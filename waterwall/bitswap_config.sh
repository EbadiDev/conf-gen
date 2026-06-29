#!/bin/bash

# Bit-Swapping MUX Configuration Module for Waterwall
# Supports single and multi floating IP modes, TCP and UDP protocols, native Proxy Protocol (HeaderClient), and TLS termination.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

create_bitswap_config() {
    local protocol="$1"       # tcp or udp
    local mode="$2"           # single or multi
    local side="$3"           # iran or kharej
    local config_name="$4"
    local iran_ip="$5"
    local kharej_ip="$6"      # kharej_main for multi
    local listen_port="$7"
    local target_port="$8"    # fwd_port for iran, final_port for kharej
    local final_ip="${9:-127.0.0.1}" # for kharej side
    local mux_count="${10:-8}"
    local use_proxy_protocol="${11:-false}"
    local use_tls="${12:-false}"
    local cert_path="${13}"
    local key_path="${14}"
    local xor_key="${15:-90}"
    local custom_private_ip="${16}"
    shift 16
    local float_ips=("$@")

    local tun_name="${config_name}"

    # Calculate internal private IPs
    local base_ip="${custom_private_ip}"
    if [ -z "$base_ip" ]; then
        if [ "$protocol" = "tcp" ]; then
            base_ip="10.10.0.1"
        else
            base_ip="10.30.0.1"
        fi
    fi

    IFS='.' read -r b1 b2 b3 b4 <<< "$base_ip"
    local tun_ip1="$base_ip"
    local tun_ip2="$b1.$b2.$b3.$((b4+1))"
    local tun2_ip1="$b1.$((b2+10)).$b3.$b4"

    if [ "$protocol" = "tcp" ]; then
        if [ "$side" = "iran" ]; then
            exec 3> "${config_name}.json"
            cat << EOF >&3
{
    "name": "${config_name}",
    "variables": {
        "ip_server_iran": "${iran_ip}",
EOF
            if [ "$mode" = "multi" ]; then
                cat << EOF >&3
        "ip_server_kharej_main": "${kharej_ip}",
EOF
                for i in "${!float_ips[@]}"; do
                    cat << EOF >&3
        "ip_server_kharej_float_$((i+1))": "${float_ips[$i]}",
EOF
                done
            else
                cat << EOF >&3
        "ip_server_kharej": "${kharej_ip}",
EOF
            fi
            cat << EOF >&3
        "port_to_listen": ${listen_port},
        "port_to_forward_to_kharej": ${target_port},
        "each_worker_mux_connections_count": ${mux_count},
        "tun_ip_1": "${tun_ip1}",
        "tun_ip_2": "${tun_ip2}"
EOF
            if [ "$use_tls" = true ]; then
                cat << EOF >&3
        ,"certificate_path": "${cert_path}",
        "key_path": "${key_path}"
EOF
            fi
            cat << EOF >&3
    },
    "nodes": [
        {
            "name": "users_inbound",
            "type": "TcpListener",
            "settings": {
                "address": "0.0.0.0",
                "port": \$port_to_listen\$,
                "nodelay": true
            },
            "next": "$(if [ "$use_tls" = true ]; then echo "tls_server_user_side_tls_termination"; elif [ "$use_proxy_protocol" = true ]; then echo "proxy-header"; else echo "mux-client"; fi)"
        }
EOF
            if [ "$use_tls" = true ]; then
                cat << EOF >&3
        ,
        {
            "name": "tls_server_user_side_tls_termination",
            "type": "TlsServer",
            "settings": {
                "cert-file": \$certificate_path\$,
                "key-file": \$key_path\$,
                "min-version": "TLSv1.2",
                "max-version": "TLSv1.3",
                "ciphers": "HIGH:!aNULL:!MD5",
                "session-cache": "none",
                "session-tickets": true,
                "verbose": false
            },
            "next": "$([ "$use_proxy_protocol" = true ] && echo "proxy-header" || echo "mux-client")"
        }
EOF
            fi
            cat << EOF >&3
        ,
        {
            "name": "mux-client",
            "type": "MuxClient",
            "settings": {
                "mode": "fixed-connections-count",
                "per-worker-connections-count": \$each_worker_mux_connections_count\$
            },
            "next": "tcp-out"
        }
EOF
            if [ "$use_proxy_protocol" = true ]; then
                cat << EOF >&3
        ,
        {
            "name": "proxy-header",
            "type": "HeaderClient",
            "settings": {
                "data": "proxy-protocol",
                "frontend-ipv4": \$ip_server_iran\$
            },
            "next": "mux-client"
        }
EOF
            fi
            cat << EOF >&3
        ,
        {
            "name": "tcp-out",
            "type": "TcpConnector",
            "settings": {
                "address": \$tun_ip_2\$,
                "port": \$port_to_forward_to_kharej\$,
                "nodelay": true
            }
        },
        {
            "name": "my tun",
            "type": "TunDevice",
            "settings": {
                "device-name": "${tun_name}",
                "device-ip": "${tun_ip1}/24"
            },
            "next": "ipovsrc"
        },
        {
            "name": "ipovsrc",
            "type": "IpOverrider",
            "settings": {
                "up": {
                    "source-ip": {
                        "ipv4": \$ip_server_iran\$
                    },
                    "dest-ip": {
                        "ipv4": $([ "$mode" = "multi" ] && echo "\$ip_server_kharej_main\$" || echo "\$ip_server_kharej\$")
                    }
                },
                "down": {
                    "source-ip": {
                        "ipv4": \$tun_ip_2\$
                    },
                    "dest-ip": {
                        "ipv4": \$tun_ip_1\$
                    }
                }
            },
            "next": "splitter"
        },
        {
            "name": "splitter",
            "type": "PacketSplitStream",
            "settings": {
                "up": "obfuscator-c",
                "down": "obfuscator-s"
            }
        },
        {
            "name": "obfuscator-c",
            "type": "ObfuscatorClient",
            "settings": {
                "method": "xor",
                "xor_key": ${xor_key},
                "skip": "transport"
            },
            "next": "ip-manipulator-up"
        },
        {
            "name": "ip-manipulator-up",
            "type": "IpManipulator",
            "settings": {
                "up-tcp-bit-psh": "packet->cwr",
                "up-tcp-bit-cwr": "packet->psh"
            },
            "next": "rd"
        },
        {
            "name": "rd",
            "type": "RawSocket",
            "settings": {
                "capture-filter-mode": "source-ip",
                "capture-ip": "12.12.12.12/32"
            }
        },
        {
            "name": "obfuscator-s",
            "type": "ObfuscatorServer",
            "settings": {
                "method": "xor",
                "xor_key": ${xor_key},
                "skip": "transport"
            },
            "next": "ip-manipulator"
        },
        {
            "name": "ip-manipulator",
            "type": "IpManipulator",
            "settings": {
                "dw-tcp-bit-psh": "packet->rst",
                "dw-tcp-bit-rst": "packet->psh"
            },
            "next": "rd2"
        },
        {
            "name": "rd2",
            "type": "RawSocket",
            "settings": {
                "capture-filter-mode": "source-ip",
                "capture-ip": $([ "$mode" = "multi" ] && echo "[\n                    \$ip_server_kharej_main\$" || echo "\$ip_server_kharej\$")
EOF
            if [ "$mode" = "multi" ]; then
                for i in "${!float_ips[@]}"; do
                    cat << EOF >&3
                    ,\$ip_server_kharej_float_$((i+1))\$
EOF
                done
                cat << EOF >&3
                ]
EOF
            fi
            cat << EOF >&3
            }
        }
    ]
}
EOF
            exec 3>&-
        else # tcp kharej
            exec 3> "${config_name}.json"
            cat << EOF >&3
{
    "name": "${config_name}",
    "variables": {
        "ip_server_iran": "${iran_ip}",
EOF
            if [ "$mode" = "multi" ]; then
                cat << EOF >&3
        "ip_server_kharej_main": "${kharej_ip}",
EOF
                for i in "${!float_ips[@]}"; do
                    cat << EOF >&3
        "ip_server_kharej_float_$((i+1))": "${float_ips[$i]}",
EOF
                done
            else
                cat << EOF >&3
        "ip_server_kharej": "${kharej_ip}",
EOF
            fi
            cat << EOF >&3
        "port_to_listen": ${listen_port},
        "final_ip": "${final_ip}",
        "final_port": ${target_port},
        "tun_ip_1": "${tun_ip1}",
        "tun_ip_2": "${tun_ip2}",
        "tun2_ip_1": "${tun2_ip1}"
    },
    "nodes": [
        {
            "name": "users_inbound",
            "type": "TcpListener",
            "settings": {
                "address": "0.0.0.0",
                "port": \$port_to_listen\$,
                "nodelay": true
            },
            "next": "mux-s"
        },
        {
            "name": "mux-s",
            "type": "MuxServer",
            "settings": {},
            "next": "tcp-out"
        },
        {
            "name": "tcp-out",
            "type": "TcpConnector",
            "settings": {
                "address": \$final_ip\$,
                "port": \$final_port\$,
                "nodelay": true
            }
        },
        {
            "name": "my tun2",
            "type": "TunDevice",
            "settings": {
                "device-name": "${tun_name}2",
                "device-ip": "${tun2_ip1}/24"
            },
            "next": "ipcorrect"
        },
        {
            "name": "ipcorrect",
            "type": "IpOverrider",
            "settings": {
                "up": {
                    "source-ip": {
                        "ipv4": \$tun_ip_2\$
                    },
                    "dest-ip": {
                        "ipv4": \$tun_ip_1\$
                    }
                },
                "down": {
                    "source-ip": {
                        "ipv4": \$tun_ip_2\$
                    },
                    "dest-ip": {
                        "ipv4": \$tun_ip_1\$
                    }
                }
            },
            "next": "obfuscator-s"
        },
        {
            "name": "obfuscator-s",
            "type": "ObfuscatorServer",
            "settings": {
                "method": "xor",
                "xor_key": ${xor_key},
                "skip": "transport"
            },
            "next": "ip-manipulator-in"
        },
        {
            "name": "ip-manipulator-in",
            "type": "IpManipulator",
            "settings": {
                "dw-tcp-bit-psh": "packet->cwr",
                "dw-tcp-bit-cwr": "packet->psh"
            },
            "next": "rdin"
        },
        {
            "name": "rdin",
            "type": "RawSocket",
            "settings": {
                "capture-filter-mode": "source-ip",
                "capture-ip": \$ip_server_iran\$
            }
        },
        {
            "name": "my tun",
            "type": "TunDevice",
            "settings": {
                "device-name": "${tun_name}",
                "device-ip": "${tun_ip1}/24"
            },
            "next": "ipovsrc"
        },
        {
            "name": "ipovsrc",
            "type": "IpOverrider",
            "settings": {
                "up": {
                    "source-ip": {
                        "ipv4": $([ "$mode" = "multi" ] && echo "[\n                            \$ip_server_kharej_main\$" || echo "\$ip_server_kharej\$")
EOF
            if [ "$mode" = "multi" ]; then
                for i in "${!float_ips[@]}"; do
                    cat << EOF >&3
                            ,\$ip_server_kharej_float_$((i+1))\$
EOF
                done
                cat << EOF >&3
                        ]
EOF
            fi
            cat << EOF >&3
                    },
                    "dest-ip": {
                        "ipv4": \$ip_server_iran\$
                    }
                },
                "down": {
                    "source-ip": {
                        "ipv4": \$tun_ip_2\$
                    },
                    "dest-ip": {
                        "ipv4": \$tun_ip_1\$
                    }
                }
            },
            "next": "obfuscator-c"
        },
        {
            "name": "obfuscator-c",
            "type": "ObfuscatorClient",
            "settings": {
                "method": "xor",
                "xor_key": ${xor_key},
                "skip": "transport"
            },
            "next": "ip-manipulator"
        },
        {
            "name": "ip-manipulator",
            "type": "IpManipulator",
            "settings": {
                "up-tcp-bit-psh": "packet->rst",
                "up-tcp-bit-rst": "packet->psh"
            },
            "next": "rd"
        },
        {
            "name": "rd",
            "type": "RawSocket",
            "settings": {
                "capture-filter-mode": "source-ip",
                "capture-ip": "12.13.12.13"
            }
        }
    ]
}
EOF
            exec 3>&-
        fi
    else # UDP
        if [ "$side" = "iran" ]; then
            exec 3> "${config_name}.json"
            cat << EOF >&3
{
    "name": "${config_name}",
    "variables": {
        "ip_server_iran": "${iran_ip}",
        "ip_server_kharej_main": "${kharej_ip}",
EOF
            if [ "$mode" = "multi" ]; then
                for i in "${!float_ips[@]}"; do
                    cat << EOF >&3
        "ip_server_kharej_float_$((i+1))": "${float_ips[$i]}",
EOF
                done
            fi
            cat << EOF >&3
        "port_to_listen": ${listen_port},
        "port_to_forward_to_kharej": ${target_port},
        "each_worker_mux_connections_count": ${mux_count},
        "tun_ip_1": "${tun_ip1}",
        "tun_ip_2": "${tun_ip2}"
    },
    "nodes": [
        {
            "name": "users_inbound",
            "type": "UdpListener",
            "settings": {
                "address": "0.0.0.0",
                "port": \$port_to_listen\$
            },
            "next": "udpovertcp_client"
        },
        {
            "name": "udpovertcp_client",
            "type": "UdpOverTcpClient",
            "settings": {},
            "next": "mux-client"
        },
        {
            "name": "mux-client",
            "type": "MuxClient",
            "settings": {
                "mode": "fixed-connections-count",
                "per-worker-connections-count": \$each_worker_mux_connections_count\$
            },
            "next": "tcp-out"
        },
        {
            "name": "tcp-out",
            "type": "TcpConnector",
            "settings": {
                "address": \$tun_ip_2\$,
                "port": \$port_to_forward_to_kharej\$,
                "nodelay": true
            }
        },
        {
            "name": "my tun",
            "type": "TunDevice",
            "settings": {
                "device-name": "${tun_name}",
                "device-ip": "${tun_ip1}/24"
            },
            "next": "ipovsrc"
        },
        {
            "name": "ipovsrc",
            "type": "IpOverrider",
            "settings": {
                "up": {
                    "source-ip": {
                        "ipv4": \$ip_server_iran\$
                    },
                    "dest-ip": {
                        "ipv4": \$ip_server_kharej_main\$
                    }
                },
                "down": {
                    "source-ip": {
                        "ipv4": \$tun_ip_2\$
                    },
                    "dest-ip": {
                        "ipv4": \$tun_ip_1\$
                    }
                }
            },
            "next": "splitter"
        },
        {
            "name": "splitter",
            "type": "PacketSplitStream",
            "settings": {
                "up": "obfuscator-c",
                "down": "obfuscator-s"
            }
        },
        {
            "name": "obfuscator-c",
            "type": "ObfuscatorClient",
            "settings": {
                "method": "xor",
                "xor_key": ${xor_key},
                "skip": "transport"
            },
            "next": "ip-manipulator-up"
        },
        {
            "name": "ip-manipulator-up",
            "type": "IpManipulator",
            "settings": {
                "up-tcp-bit-psh": "packet->cwr",
                "up-tcp-bit-cwr": "packet->psh"
            },
            "next": "rd"
        },
        {
            "name": "rd",
            "type": "RawSocket",
            "settings": {
                "capture-filter-mode": "source-ip",
                "capture-ip": "12.12.12.12/32"
            }
        },
        {
            "name": "obfuscator-s",
            "type": "ObfuscatorServer",
            "settings": {
                "method": "xor",
                "xor_key": ${xor_key},
                "skip": "transport"
            },
            "next": "ip-manipulator"
        },
        {
            "name": "ip-manipulator",
            "type": "IpManipulator",
            "settings": {
                "dw-tcp-bit-psh": "packet->rst",
                "dw-tcp-bit-rst": "packet->psh"
            },
            "next": "rd2"
        },
        {
            "name": "rd2",
            "type": "RawSocket",
            "settings": {
                "capture-filter-mode": "source-ip",
                "capture-ips": [
                    \$ip_server_kharej_main\$
EOF
            if [ "$mode" = "multi" ]; then
                for i in "${!float_ips[@]}"; do
                    cat << EOF >&3
                    ,\$ip_server_kharej_float_$((i+1))\$
EOF
                done
            fi
            cat << EOF >&3
                ]
            }
        }
    ]
}
EOF
            exec 3>&-
        else # udp kharej
            exec 3> "${config_name}.json"
            cat << EOF >&3
{
    "name": "${config_name}",
    "variables": {
        "ip_server_iran": "${iran_ip}",
EOF
            if [ "$mode" = "multi" ]; then
                cat << EOF >&3
        "ip_server_kharej_main": "${kharej_ip}",
EOF
                for i in "${!float_ips[@]}"; do
                    cat << EOF >&3
        "ip_server_kharej_float_$((i+1))": "${float_ips[$i]}",
EOF
                done
            else
                cat << EOF >&3
        "ip_server_kharej": "${kharej_ip}",
EOF
            fi
            cat << EOF >&3
        "port_to_listen": ${listen_port},
        "final_ip": "${final_ip}",
        "final_port": ${target_port},
        "tun_ip_1": "${tun_ip1}",
        "tun_ip_2": "${tun_ip2}",
        "tun2_ip_1": "${tun2_ip1}"
    },
    "nodes": [
        {
            "name": "users_inbound",
            "type": "TcpListener",
            "settings": {
                "address": "0.0.0.0",
                "port": \$port_to_listen\$,
                "nodelay": true
            },
            "next": "mux-s"
        },
        {
            "name": "mux-s",
            "type": "MuxServer",
            "settings": {},
            "next": "udpovertcp_server"
        },
        {
            "name": "udpovertcp_server",
            "type": "UdpOverTcpServer",
            "settings": {},
            "next": "udp-out"
        },
        {
            "name": "udp-out",
            "type": "UdpConnector",
            "settings": {
                "address": \$final_ip\$,
                "port": \$final_port\$
            }
        },
        {
            "name": "my tun2",
            "type": "TunDevice",
            "settings": {
                "device-name": "${tun_name}2",
                "device-ip": "${tun2_ip1}/24"
            },
            "next": "ipcorrect"
        },
        {
            "name": "ipcorrect",
            "type": "IpOverrider",
            "settings": {
                "up": {
                    "source-ip": {
                        "ipv4": \$tun_ip_2\$
                    },
                    "dest-ip": {
                        "ipv4": \$tun_ip_1\$
                    }
                },
                "down": {
                    "source-ip": {
                        "ipv4": \$tun_ip_2\$
                    },
                    "dest-ip": {
                        "ipv4": \$tun_ip_1\$
                    }
                }
            },
            "next": "obfuscator-s"
        },
        {
            "name": "obfuscator-s",
            "type": "ObfuscatorServer",
            "settings": {
                "method": "xor",
                "xor_key": ${xor_key},
                "skip": "transport"
            },
            "next": "ip-manipulator-in"
        },
        {
            "name": "ip-manipulator-in",
            "type": "IpManipulator",
            "settings": {
                "dw-tcp-bit-psh": "packet->cwr",
                "dw-tcp-bit-cwr": "packet->psh"
            },
            "next": "rdin"
        },
        {
            "name": "rdin",
            "type": "RawSocket",
            "settings": {
                "capture-filter-mode": "source-ip",
                "capture-ip": \$ip_server_iran\$
            }
        },
        {
            "name": "my tun",
            "type": "TunDevice",
            "settings": {
                "device-name": "${tun_name}",
                "device-ip": "${tun_ip1}/24"
            },
            "next": "ipovsrc"
        },
        {
            "name": "ipovsrc",
            "type": "IpOverrider",
            "settings": {
                "up": {
                    "source-ip": {
                        "ipv4": $([ "$mode" = "multi" ] && echo "[\n                            \$ip_server_kharej_main\$" || echo "\$ip_server_kharej\$")
EOF
            if [ "$mode" = "multi" ]; then
                for i in "${!float_ips[@]}"; do
                    cat << EOF >&3
                            ,\$ip_server_kharej_float_$((i+1))\$
EOF
                done
                cat << EOF >&3
                        ]
EOF
            fi
            cat << EOF >&3
                    },
                    "dest-ip": {
                        "ipv4": \$ip_server_iran\$
                    }
                },
                "down": {
                    "source-ip": {
                        "ipv4": \$tun_ip_2\$
                    },
                    "dest-ip": {
                        "ipv4": \$tun_ip_1\$
                    }
                }
            },
            "next": "obfuscator-c"
        },
        {
            "name": "obfuscator-c",
            "type": "ObfuscatorClient",
            "settings": {
                "method": "xor",
                "xor_key": ${xor_key},
                "skip": "transport"
            },
            "next": "ip-manipulator"
        },
        {
            "name": "ip-manipulator",
            "type": "IpManipulator",
            "settings": {
                "up-tcp-bit-psh": "packet->rst",
                "up-tcp-bit-rst": "packet->psh"
            },
            "next": "rd"
        },
        {
            "name": "rd",
            "type": "RawSocket",
            "settings": {
                "capture-filter-mode": "source-ip",
                "capture-ip": "12.13.12.13"
            }
        }
    ]
}
EOF
            exec 3>&-
        fi
    fi

    if [ $? -eq 0 ]; then
        add_to_core_json "$config_name" "bitswap"
        print_success "Bit-swapping MUX configuration file ${config_name}.json created successfully!"
    else
        print_error "Failed to create bit-swapping configuration file."
        exit 1
    fi
}

handle_bitswap_config() {
    shift 1 # remove bitswap
    local protocol="${1:-tcp}"
    local mode="${2:-single}"
    local side="${3:-iran}"
    local config_name="${4}"
    local iran_ip="${5}"
    local kharej_ip="${6}"
    local listen_port="${7}"
    local target_port="${8}"
    local final_ip="127.0.0.1"

    if [ -z "$target_port" ]; then
        echo "Usage: $0 bitswap <tcp|udp> <single|multi> <iran|kharej> <config_name> <iran_ip> <kharej_ip> <listen_port> <fwd_or_final_port> [mux_count] [options]"
        echo "Options:"
        echo "  --proxy-protocol          Enable Proxy Protocol header (HeaderClient node on Iran side)"
        echo "  --tls <cert> <key>        Enable TLS termination (Iran side TCP)"
        echo "  --final-ip <ip>           Final target IP for Kharej side (default: 127.0.0.1)"
        echo "  --xor-key <N>             XOR key for obfuscator (default: 90)"
        echo "  --private-ip <ip>         Base internal private IP subnet (e.g. 10.10.0.1 for TCP, 10.30.0.1 for UDP)"
        echo "  --float <ip1> [ip2...]    Floating IPs for Kharej server (multi mode)"
        exit 1
    fi

    shift 8

    local mux_count=8
    if [ "$#" -gt 0 ] && [[ "$1" =~ ^[0-9]+$ ]]; then
        mux_count="$1"
        shift 1
    fi

    local use_proxy_protocol=false
    local use_tls=false
    local cert_path=""
    local key_path=""
    local xor_key=90
    local custom_private_ip=""
    local float_ips=()

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --proxy-protocol)
                use_proxy_protocol=true
                shift 1
                ;;
            --tls)
                use_tls=true
                cert_path="$2"
                key_path="$3"
                shift 3
                ;;
            --final-ip)
                final_ip="$2"
                shift 2
                ;;
            --xor-key)
                xor_key="$2"
                shift 2
                ;;
            --private-ip)
                custom_private_ip="$2"
                shift 2
                ;;
            --float)
                shift 1
                while [ "$#" -gt 0 ] && [[ ! "$1" =~ ^-- ]]; do
                    float_ips+=("$1")
                    shift 1
                done
                ;;
            *)
                shift 1
                ;;
        esac
    done

    create_bitswap_config "$protocol" "$mode" "$side" "$config_name" "$iran_ip" "$kharej_ip" "$listen_port" "$target_port" "$final_ip" "$mux_count" "$use_proxy_protocol" "$use_tls" "$cert_path" "$key_path" "$xor_key" "$custom_private_ip" "${float_ips[@]}"
}
