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
    local custom_private_ip_2="${17}"
    if [ "$#" -ge 17 ]; then
        shift 17
    elif [ "$#" -ge 16 ]; then
        shift 16
    fi
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
    local tun2_ip1="${custom_private_ip_2:-$b1.$((b2+10)).$b3.$b4}"

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
EOF
            if [ "$mode" = "multi" ]; then
                cat << EOF >&3
                "capture-ips": [
                    \$ip_server_kharej_main\$
EOF
                for i in "${!float_ips[@]}"; do
                    cat << EOF >&3
                    ,\$ip_server_kharej_float_$((i+1))\$
EOF
                done
                cat << EOF >&3
                ]
EOF
            else
                cat << EOF >&3
                "capture-ip": \$ip_server_kharej\$
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
EOF
            if [ "$mode" = "multi" ]; then
                cat << EOF >&3
                        "ipv4": [
                            \$ip_server_kharej_main\$
EOF
                for i in "${!float_ips[@]}"; do
                    cat << EOF >&3
                            ,\$ip_server_kharej_float_$((i+1))\$
EOF
                done
                cat << EOF >&3
                        ]
EOF
            else
                cat << EOF >&3
                        "ipv4": \$ip_server_kharej\$
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
EOF
            if [ "$mode" = "multi" ]; then
                cat << EOF >&3
                        "ipv4": [
                            \$ip_server_kharej_main\$
EOF
                for i in "${!float_ips[@]}"; do
                    cat << EOF >&3
                            ,\$ip_server_kharej_float_$((i+1))\$
EOF
                done
                cat << EOF >&3
                        ]
EOF
            else
                cat << EOF >&3
                        "ipv4": \$ip_server_kharej\$
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

prompt_bitswap_services() {
    local -n _tcp_ref=$1
    local -n _udp_ref=$2
    local term="/dev/stdin"
    if [ ! -t 0 ] && [ -e /dev/tty ]; then
        term="/dev/tty"
    fi

    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║       BitSwap Multi-Service Configuration Wizard                 ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo "Specify services to forward through the BitSwap tunnel."
    echo ""

    while true; do
        read -r -p "Enter service port (or press Enter when done): " svc_port < "$term" || break
        svc_port="$(echo "$svc_port" | tr -d '[:space:]')"
        if [ -z "$svc_port" ]; then
            if [ ${#_tcp_ref[@]} -eq 0 ] && [ ${#_udp_ref[@]} -eq 0 ]; then
                echo "Error: You must configure at least one service port."
                continue
            fi
            break
        fi

        if [[ ! "$svc_port" =~ ^[0-9]+$ ]] || [ "$svc_port" -lt 1 ] || [ "$svc_port" -gt 65535 ]; then
            echo "Invalid port: '$svc_port'. Must be an integer between 1 and 65535."
            continue
        fi

        local proto=""
        while true; do
            read -r -p "Is port $svc_port [t]cp or [u]dp? (default: tcp): " proto < "$term" || break
            proto="$(echo "$proto" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
            proto="${proto:-tcp}"
            case "$proto" in
                1|t|tcp)
                    _tcp_ref+=("$svc_port")
                    echo "✓ Added TCP service on port $svc_port"
                    break
                    ;;
                2|u|udp)
                    _udp_ref+=("$svc_port")
                    echo "✓ Added UDP service on port $svc_port"
                    break
                    ;;
                *)
                    echo "Please enter 'tcp' (or 't') or 'udp' (or 'u')."
                    ;;
            esac
        done
        echo ""
    done

    echo "Services defined:"
    [ ${#_tcp_ref[@]} -gt 0 ] && echo "  - TCP: [${_tcp_ref[*]}]"
    [ ${#_udp_ref[@]} -gt 0 ] && echo "  - UDP: [${_udp_ref[*]}]"
    echo ""
}

create_bitswap_hybrid_config() {
    local mode="$1"           # single or multi
    local side="$2"           # iran or kharej
    local config_name="$3"
    local iran_ip="$4"
    local kharej_ip="$5"      # kharej_main for multi
    local tcp_tunnel_port="${6:-8443}"
    local udp_tunnel_port="${7:-8444}"
    local final_ip="${8:-127.0.0.1}"
    local mux_count="${9:-8}"
    local use_proxy_protocol="${10:-false}"
    local use_tls="${11:-false}"
    local cert_path="${12}"
    local key_path="${13}"
    local xor_key="${14:-90}"
    local custom_private_ip="${15}"
    local custom_private_ip_2="${16}"
    local tcp_ports_str="${17}"
    local udp_ports_str="${18}"
    shift 18
    local float_ips=("$@")

    local tun_name="${config_name}"

    # Calculate internal private IPs
    local base_ip="${custom_private_ip:-10.10.0.1}"
    IFS='.' read -r b1 b2 b3 b4 <<< "$base_ip"
    local tun_ip1="$base_ip"
    local tun_ip2="$b1.$b2.$b3.$((b4+1))"
    local tun2_ip1="${custom_private_ip_2:-$b1.$((b2+10)).$b3.$b4}"

    local tcp_ports=()
    local udp_ports=()
    if [ -n "$tcp_ports_str" ]; then
        IFS=',' read -ra tcp_ports <<< "$tcp_ports_str"
    fi
    if [ -n "$udp_ports_str" ]; then
        IFS=',' read -ra udp_ports <<< "$udp_ports_str"
    fi

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

        if [ ${#tcp_ports[@]} -gt 0 ]; then
            local tcp_json_arr="["
            for idx in "${!tcp_ports[@]}"; do
                [ $idx -gt 0 ] && tcp_json_arr+=", "
                tcp_json_arr+="${tcp_ports[$idx]}"
            done
            tcp_json_arr+="]"
            cat << EOF >&3
        "ports_to_listen": ${tcp_json_arr},
        "port_to_forward_to_kharej": ${tcp_tunnel_port},
EOF
        fi

        if [ ${#udp_ports[@]} -gt 0 ]; then
            if [ ${#udp_ports[@]} -eq 1 ]; then
                cat << EOF >&3
        "udp_port_to_listen": ${udp_ports[0]},
        "udp_port_to_forward_to_kharej": ${udp_tunnel_port},
EOF
            else
                local udp_json_arr="["
                for idx in "${!udp_ports[@]}"; do
                    [ $idx -gt 0 ] && udp_json_arr+=", "
                    udp_json_arr+="${udp_ports[$idx]}"
                done
                udp_json_arr+="]"
                cat << EOF >&3
        "udp_ports_to_listen": ${udp_json_arr},
        "udp_port_to_forward_to_kharej": ${udp_tunnel_port},
EOF
            fi
        fi

        cat << EOF >&3
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
EOF
        local has_node=false

        if [ ${#tcp_ports[@]} -gt 0 ]; then
            has_node=true
            local next_after_inbound="header-client"
            if [ "$use_tls" = true ]; then
                next_after_inbound="tls_server_user_side_tls_termination"
            elif [ "$use_proxy_protocol" = true ]; then
                next_after_inbound="proxy-header"
            fi

            cat << EOF >&3
        {
            "name": "users_inbound",
            "type": "TcpListener",
            "settings": {
                "address": "0.0.0.0",
                "port": \$ports_to_listen\$,
                "nodelay": true
            },
            "next": "${next_after_inbound}"
        }
EOF
            if [ "$use_tls" = true ]; then
                local next_after_tls="$([ "$use_proxy_protocol" = true ] && echo "proxy-header" || echo "header-client")"
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
            "next": "${next_after_tls}"
        }
EOF
            fi

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
            "next": "header-client"
        }
EOF
            fi

            cat << EOF >&3
        ,
        {
            "name": "header-client",
            "type": "HeaderClient",
            "settings": {
                "data": "src_context->port"
            },
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
        }
EOF
        fi

        if [ ${#udp_ports[@]} -gt 0 ]; then
            for idx in "${!udp_ports[@]}"; do
                local u_port="${udp_ports[$idx]}"
                local u_fwd=$((udp_tunnel_port + idx))
                local u_inbound_name="udp-users-inbound"
                local u_otc_name="udp-over-tcp-client"
                local u_mux_name="udp-mux-client"
                local u_out_name="udp-tcp-out"
                local u_port_var="\$udp_port_to_listen\$"
                local u_fwd_var="\$udp_port_to_forward_to_kharej\$"

                if [ ${#udp_ports[@]} -gt 1 ]; then
                    u_inbound_name="udp-users-inbound-${u_port}"
                    u_otc_name="udp-over-tcp-client-${u_port}"
                    u_mux_name="udp-mux-client-${u_port}"
                    u_out_name="udp-tcp-out-${u_port}"
                    u_port_var="${u_port}"
                    u_fwd_var="${u_fwd}"
                fi

                [ "$has_node" = true ] && echo "        ," >&3
                has_node=true

                cat << EOF >&3
        {
            "name": "${u_inbound_name}",
            "type": "UdpListener",
            "settings": {
                "address": "0.0.0.0",
                "port": ${u_port_var}
            },
            "next": "${u_otc_name}"
        },
        {
            "name": "${u_otc_name}",
            "type": "UdpOverTcpClient",
            "settings": {},
            "next": "${u_mux_name}"
        },
        {
            "name": "${u_mux_name}",
            "type": "MuxClient",
            "settings": {
                "mode": "fixed-connections-count",
                "per-worker-connections-count": \$each_worker_mux_connections_count\$
            },
            "next": "${u_out_name}"
        },
        {
            "name": "${u_out_name}",
            "type": "TcpConnector",
            "settings": {
                "address": \$tun_ip_2\$,
                "port": ${u_fwd_var},
                "nodelay": true
            }
        }
EOF
            done
        fi

        [ "$has_node" = true ] && echo "        ," >&3
        cat << EOF >&3
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
EOF
        if [ "$mode" = "multi" ]; then
            cat << EOF >&3
                "capture-ips": [
                    \$ip_server_kharej_main\$
EOF
            for i in "${!float_ips[@]}"; do
                cat << EOF >&3
                    ,\$ip_server_kharej_float_$((i+1))\$
EOF
            done
            cat << EOF >&3
                ]
EOF
        else
            cat << EOF >&3
                "capture-ip": \$ip_server_kharej\$
EOF
        fi
        cat << EOF >&3
            }
        }
    ]
}
EOF
        exec 3>&-
    else # side == "kharej"
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

        if [ ${#tcp_ports[@]} -gt 0 ]; then
            cat << EOF >&3
        "port_to_listen": ${tcp_tunnel_port},
EOF
        fi

        if [ ${#udp_ports[@]} -gt 0 ]; then
            cat << EOF >&3
        "udp_port_to_listen": ${udp_tunnel_port},
EOF
        fi

        cat << EOF >&3
        "final_ip": "${final_ip}",
EOF
        if [ ${#tcp_ports[@]} -gt 0 ]; then
            cat << EOF >&3
        "final_port": ${tcp_ports[0]},
EOF
        fi

        if [ ${#udp_ports[@]} -gt 0 ]; then
            cat << EOF >&3
        "udp_final_port": ${udp_ports[0]},
EOF
        fi

        cat << EOF >&3
        "tun_ip_1": "${tun_ip1}",
        "tun_ip_2": "${tun_ip2}",
        "tun2_ip_1": "${tun2_ip1}"
    },
    "nodes": [
EOF
        local has_node=false

        if [ ${#tcp_ports[@]} -gt 0 ]; then
            has_node=true
            cat << EOF >&3
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
            "next": "header-server"
        },
        {
            "name": "header-server",
            "type": "HeaderServer",
            "settings": {
                "override": "dest_context->port"
            },
            "next": "tcp-out"
        },
        {
            "name": "tcp-out",
            "type": "TcpConnector",
            "settings": {
                "address": \$final_ip\$,
                "port": "dest_context->port",
                "nodelay": true
            }
        }
EOF
        fi

        if [ ${#udp_ports[@]} -gt 0 ]; then
            for idx in "${!udp_ports[@]}"; do
                local u_port="${udp_ports[$idx]}"
                local u_listen=$((udp_tunnel_port + idx))
                local u_inbound_name="udp-users-inbound"
                local u_mux_name="udp-mux-s"
                local u_ots_name="udp-over-tcp-server"
                local u_out_name="udp-out"
                local u_listen_var="\$udp_port_to_listen\$"
                local u_final_var="\$udp_final_port\$"

                if [ ${#udp_ports[@]} -gt 1 ]; then
                    u_inbound_name="udp-users-inbound-${u_port}"
                    u_mux_name="udp-mux-s-${u_port}"
                    u_ots_name="udp-over-tcp-server-${u_port}"
                    u_out_name="udp-out-${u_port}"
                    u_listen_var="${u_listen}"
                    u_final_var="${u_port}"
                fi

                [ "$has_node" = true ] && echo "        ," >&3
                has_node=true

                cat << EOF >&3
        {
            "name": "${u_inbound_name}",
            "type": "TcpListener",
            "settings": {
                "address": "0.0.0.0",
                "port": ${u_listen_var},
                "nodelay": true
            },
            "next": "${u_mux_name}"
        },
        {
            "name": "${u_mux_name}",
            "type": "MuxServer",
            "settings": {},
            "next": "${u_ots_name}"
        },
        {
            "name": "${u_ots_name}",
            "type": "UdpOverTcpServer",
            "settings": {},
            "next": "${u_out_name}"
        },
        {
            "name": "${u_out_name}",
            "type": "UdpConnector",
            "settings": {
                "address": \$final_ip\$,
                "port": ${u_final_var}
            }
        }
EOF
            done
        fi

        [ "$has_node" = true ] && echo "        ," >&3
        cat << EOF >&3
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
EOF
        if [ "$mode" = "multi" ]; then
            cat << EOF >&3
                        "ipv4": [
                            \$ip_server_kharej_main\$
EOF
            for i in "${!float_ips[@]}"; do
                cat << EOF >&3
                            ,\$ip_server_kharej_float_$((i+1))\$
EOF
            done
            cat << EOF >&3
                        ]
EOF
        else
            cat << EOF >&3
                        "ipv4": \$ip_server_kharej\$
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

    if [ $? -eq 0 ]; then
        add_to_core_json "$config_name" "bitswap"
        print_success "Bit-swapping hybrid multi-service configuration file ${config_name}.json created successfully!"
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

    if [ -z "$config_name" ]; then
        echo "Usage: $0 bitswap <tcp|udp|hybrid> <single|multi> <iran|kharej> <config_name> <iran_ip> <kharej_ip> [listen_port/tcp_fwd] [target_port/udp_fwd] [mux_count] [options]"
        echo ""
        echo "Protocols:"
        echo "  tcp                       Single TCP service port forwarding"
        echo "  udp                       Single UDP-over-TCP service port forwarding"
        echo "  hybrid                    Multi-service: port-preserving TCP + UDP-over-TCP"
        echo ""
        echo "Options:"
        echo "  --tcp <port1,port2,...>   List of TCP service ports (e.g. --tcp 2087,9444)"
        echo "  --udp <port1,port2,...>   List of UDP service ports (e.g. --udp 27015)"
        echo "  --services <spec>         Composite service list (e.g. --services 2087:tcp,9444:tcp,27015:udp)"
        echo "  --service <port>:<proto>  Individual service (e.g. --service 2087:tcp)"
        echo "  --tcp-tunnel-port <port>  Transport port for TCP services (default: 8443)"
        echo "  --udp-tunnel-port <port>  Transport port for UDP-over-TCP services (default: 8444)"
        echo "  -i, --interactive         Interactive wizard: ask for service ports and protocol (TCP/UDP)"
        echo "  --proxy-protocol          Enable Proxy Protocol header (HeaderClient node on Iran side)"
        echo "  --tls <cert> <key>        Enable TLS termination (Iran side TCP)"
        echo "  --final-ip <ip>           Final target IP for Kharej side (default: 127.0.0.1)"
        echo "  --xor-key <N>             XOR key for obfuscator (default: 90)"
        echo "  --private-ip <ip>         Base internal private IP subnet (e.g. 10.10.0.1)"
        echo "  --private-ip-2 <ip>       Secondary internal private IP for Kharej tun2 (default: base+10)"
        echo "  --float <ip1> [ip2...]    Floating IPs for Kharej server (multi mode)"
        exit 1
    fi

    local listen_port=""
    local target_port=""
    if [ "$#" -ge 8 ] && [[ ! "$7" =~ ^-- ]] && [[ ! "$8" =~ ^-- ]]; then
        listen_port="$7"
        target_port="$8"
        shift 8
    else
        shift 6
    fi

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
    local custom_private_ip_2=""
    local float_ips=()
    local tcp_ports=()
    local udp_ports=()
    local tcp_tunnel_port="${listen_port:-8443}"
    local udp_tunnel_port="${target_port:-8444}"
    local final_ip="127.0.0.1"
    local is_interactive=false

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --tcp|--tcp-ports)
                shift 1
                while [ "$#" -gt 0 ] && [[ ! "$1" =~ ^-- ]]; do
                    IFS=',' read -ra p_arr <<< "$1"
                    for p in "${p_arr[@]}"; do
                        p="$(echo "$p" | tr -d '[:space:]')"
                        [[ "$p" =~ ^[0-9]+$ ]] && tcp_ports+=("$p")
                    done
                    shift 1
                done
                ;;
            --udp|--udp-ports)
                shift 1
                while [ "$#" -gt 0 ] && [[ ! "$1" =~ ^-- ]]; do
                    IFS=',' read -ra p_arr <<< "$1"
                    for p in "${p_arr[@]}"; do
                        p="$(echo "$p" | tr -d '[:space:]')"
                        [[ "$p" =~ ^[0-9]+$ ]] && udp_ports+=("$p")
                    done
                    shift 1
                done
                ;;
            --services)
                shift 1
                IFS=',' read -ra s_arr <<< "$1"
                for entry in "${s_arr[@]}"; do
                    local port="${entry%%[:/]*}"
                    local proto="${entry##*[:/]}"
                    proto="$(echo "$proto" | tr '[:upper:]' '[:lower:]')"
                    if [[ "$port" =~ ^[0-9]+$ ]]; then
                        if [ "$proto" = "udp" ] || [ "$proto" = "u" ]; then
                            udp_ports+=("$port")
                        else
                            tcp_ports+=("$port")
                        fi
                    fi
                done
                shift 1
                ;;
            --service)
                shift 1
                while [ "$#" -gt 0 ] && [[ ! "$1" =~ ^-- ]]; do
                    local entry="$1"
                    local port="${entry%%[:/]*}"
                    local proto="${entry##*[:/]}"
                    proto="$(echo "$proto" | tr '[:upper:]' '[:lower:]')"
                    if [[ "$port" =~ ^[0-9]+$ ]]; then
                        if [ "$proto" = "udp" ] || [ "$proto" = "u" ]; then
                            udp_ports+=("$port")
                        else
                            tcp_ports+=("$port")
                        fi
                    fi
                    shift 1
                done
                ;;
            --tcp-tunnel-port|--tcp-fwd-port)
                tcp_tunnel_port="$2"
                shift 2
                ;;
            --udp-tunnel-port|--udp-fwd-port)
                udp_tunnel_port="$2"
                shift 2
                ;;
            -i|--interactive)
                is_interactive=true
                shift 1
                ;;
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
            --private-ip-2)
                custom_private_ip_2="$2"
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

    local is_hybrid=false
    if [ "$protocol" = "hybrid" ] || [ ${#tcp_ports[@]} -gt 0 ] || [ ${#udp_ports[@]} -gt 0 ] || [ "$is_interactive" = true ]; then
        is_hybrid=true
    fi

    if [ "$is_hybrid" = true ]; then
        if [ "$is_interactive" = true ] || ([ ${#tcp_ports[@]} -eq 0 ] && [ ${#udp_ports[@]} -eq 0 ]); then
            if [ -t 0 ] || [ -e /dev/tty ]; then
                prompt_bitswap_services tcp_ports udp_ports
            fi
        fi

        if [ ${#tcp_ports[@]} -eq 0 ] && [ ${#udp_ports[@]} -eq 0 ]; then
            print_error "Hybrid mode requires at least one TCP or UDP service port. Use --tcp, --udp, --services, or -i/--interactive."
            exit 1
        fi

        local tcp_ports_joined=""
        if [ ${#tcp_ports[@]} -gt 0 ]; then
            tcp_ports_joined="$(IFS=,; echo "${tcp_ports[*]}")"
        fi
        local udp_ports_joined=""
        if [ ${#udp_ports[@]} -gt 0 ]; then
            udp_ports_joined="$(IFS=,; echo "${udp_ports[*]}")"
        fi

        create_bitswap_hybrid_config "$mode" "$side" "$config_name" "$iran_ip" "$kharej_ip" "$tcp_tunnel_port" "$udp_tunnel_port" "$final_ip" "$mux_count" "$use_proxy_protocol" "$use_tls" "$cert_path" "$key_path" "$xor_key" "$custom_private_ip" "$custom_private_ip_2" "$tcp_ports_joined" "$udp_ports_joined" "${float_ips[@]}"
    else
        # Legacy single-port bitswap path
        if [ -z "$target_port" ]; then
            echo "Error: listen_port and fwd_port are required for legacy single-service bitswap mode."
            echo "Usage: $0 bitswap <tcp|udp> <single|multi> <iran|kharej> <config_name> <iran_ip> <kharej_ip> <listen_port> <fwd_or_final_port> [mux_count] [options]"
            exit 1
        fi
        create_bitswap_config "$protocol" "$mode" "$side" "$config_name" "$iran_ip" "$kharej_ip" "$listen_port" "$target_port" "$final_ip" "$mux_count" "$use_proxy_protocol" "$use_tls" "$cert_path" "$key_path" "$xor_key" "$custom_private_ip" "$custom_private_ip_2" "${float_ips[@]}"
    fi
}
