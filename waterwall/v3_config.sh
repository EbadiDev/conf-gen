#!/bin/bash

# V3 Configuration Module for Waterwall
# Aligned with standard Waterwall PROTOSWAP architecture
# Features:
# - Consolidated IpOverrider node schema (up/down sub-objects)
# - ObfuscatorServer (Kharej) / ObfuscatorClient (Iran) with XOR obfuscation
# - Protoswap TCP / UDP protocol swapping (protoswap-tcp / protoswap-udp)
# - TUN Device + RawSocket capture pipeline

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# V3 Server Configuration (Iran-side)
create_v3_server_config() {
    local config_name="$1"
    local non_iran_ip="$2"
    local iran_ip="$3"
    local private_ip="$4"
    local protoswap_tcp="$5"
    local custom_udp="$6"
    local use_tls="${7:-false}"
    local cert_path="$8"
    local key_path="$9"
    local use_proxy_protocol="${10:-false}"
    local listen_port="${11:-443}"
    local target_port="${12:-443}"
    local explicit_listener="${13:-true}"
    local use_mux="${14:-false}"
    local mux_count="${15:-8}"
    local xor_key="${16:-90}"

    local protoswap_udp=""
    if [ -n "$custom_udp" ] && [[ "$custom_udp" =~ ^[0-9]+$ ]]; then
        protoswap_udp="$custom_udp"
    fi

    if [ -n "$protoswap_tcp" ] && [ -n "$protoswap_udp" ] && [ "$protoswap_tcp" -eq "$protoswap_udp" ]; then
        print_error "Error: TCP Protocol ($protoswap_tcp) and UDP Protocol ($protoswap_udp) CANNOT be the same."
        print_error "Traffic would be indistinguishable. Please use different values."
        exit 1
    fi

    IFS='.' read -r ip1 ip2 ip3 ip4 <<< "$private_ip"
    local ip_plus1="$ip1.$ip2.$ip3.$((ip4+1))"

    local has_listener=false
    if [ "$use_tls" = true ] || [ "$use_proxy_protocol" = true ] || [ "$explicit_listener" = true ] || [ "$use_mux" = true ]; then
        has_listener=true
    fi

    local var_entries=()
    var_entries+=("        \"ip_server_iran\": \"${iran_ip}\"")
    var_entries+=("        \"ip_server_kharej\": \"${non_iran_ip}\"")
    var_entries+=("        \"private_ip\": \"${private_ip}\"")
    var_entries+=("        \"private_ip_endpoint\": \"${ip_plus1}\"")

    if [ -n "$protoswap_tcp" ]; then
        var_entries+=("        \"protoswap_tcp_to_number\": ${protoswap_tcp}")
    fi
    if [ -n "$protoswap_udp" ]; then
        var_entries+=("        \"protoswap_udp_to_number\": ${protoswap_udp}")
    fi
    if [ "$has_listener" = true ]; then
        var_entries+=("        \"port_listen_iran\": ${listen_port}")
        var_entries+=("        \"port_service_kharej\": ${target_port}")
        if [ "$use_tls" = true ]; then
            var_entries+=("        \"certificate_path\": \"${cert_path}\"")
            var_entries+=("        \"key_path\": \"${key_path}\"")
        fi
        if [ "$use_mux" = true ]; then
            var_entries+=("        \"each_worker_mux_connections_count\": ${mux_count}")
        fi
    fi

    exec 3> "${config_name}.json"
    cat << EOF >&3
{
    "name": "${config_name}",
    "variables": {
EOF
    local total_vars=${#var_entries[@]}
    for ((i=0; i<total_vars; i++)); do
        if [ $((i + 1)) -lt "$total_vars" ]; then
            echo "${var_entries[i]}," >&3
        else
            echo "${var_entries[i]}" >&3
        fi
    done
    cat << EOF >&3
    },
    "nodes": [
EOF

    if [ "$has_listener" = true ]; then
        local first_tcp_node="tcp-out"
        if [ "$use_tls" = true ]; then
            first_tcp_node="tls_server"
        elif [ "$use_proxy_protocol" = true ]; then
            first_tcp_node="proxy-header"
        elif [ "$use_mux" = true ]; then
            first_tcp_node="mux-client"
        fi

        cat << EOF >&3
        {
            "name": "users_inbound",
            "type": "TcpListener",
            "settings": {
                "address": "0.0.0.0",
                "port": \$port_listen_iran\$,
                "nodelay": true
            },
            "next": "${first_tcp_node}"
        },
EOF
        if [ "$use_tls" = true ]; then
            local next_after_tls="tcp-out"
            if [ "$use_proxy_protocol" = true ]; then
                next_after_tls="proxy-header"
            elif [ "$use_mux" = true ]; then
                next_after_tls="mux-client"
            fi
            cat << EOF >&3
        {
            "name": "tls_server",
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
        },
EOF
        fi

        if [ "$use_proxy_protocol" = true ]; then
            local next_after_proxy="tcp-out"
            if [ "$use_mux" = true ]; then
                next_after_proxy="mux-client"
            fi
            cat << EOF >&3
        {
            "name": "proxy-header",
            "type": "HeaderClient",
            "settings": {
                "data": "proxy-protocol",
                "frontend-ipv4": \$ip_server_iran\$
            },
            "next": "${next_after_proxy}"
        },
EOF
        fi

        if [ "$use_mux" = true ]; then
            cat << EOF >&3
        {
            "name": "mux-client",
            "type": "MuxClient",
            "settings": {
                "mode": "fixed-connections-count",
                "per-worker-connections-count": \$each_worker_mux_connections_count\$
            },
            "next": "tcp-out"
        },
EOF
        fi

        cat << EOF >&3
        {
            "name": "tcp-out",
            "type": "TcpConnector",
            "settings": {
                "address": \$private_ip_endpoint\$,
                "port": \$port_service_kharej\$,
                "nodelay": true
            }
        },
EOF
    fi

    cat << EOF >&3
        {
            "name": "my tun",
            "type": "TunDevice",
            "settings": {
                "device-name": "${config_name}",
                "device-ip": "${private_ip}/24"
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
                        "ipv4": \$ip_server_kharej\$
                    }
                },
                "down": {
                    "source-ip": {
                        "ipv4": \$private_ip_endpoint\$
                    },
                    "dest-ip": {
                        "ipv4": \$private_ip\$
                    }
                }
            },
            "next": "ip-manipulator"
        },
        {
            "name": "ip-manipulator",
            "type": "IpManipulator",
            "settings": {
EOF
    if [ -n "$protoswap_tcp" ] && [ -n "$protoswap_udp" ]; then
        cat << EOF >&3
                "protoswap-tcp": \$protoswap_tcp_to_number\$,
                "protoswap-udp": \$protoswap_udp_to_number\$
EOF
    elif [ -n "$protoswap_tcp" ]; then
        cat << EOF >&3
                "protoswap-tcp": \$protoswap_tcp_to_number\$
EOF
    elif [ -n "$protoswap_udp" ]; then
        cat << EOF >&3
                "protoswap-udp": \$protoswap_udp_to_number\$
EOF
    fi

    cat << EOF >&3
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
            "next": "rd"
        },
        {
            "name": "rd",
            "type": "RawSocket",
            "settings": {
                "capture-filter-mode": "source-ip",
                "capture-ip": \$ip_server_kharej\$
            }
        }
    ]
}
EOF
    exec 3>&-

    if [ $? -eq 0 ]; then
        add_to_core_json "$config_name" "v3"
        print_success "V3 Server configuration created: ${config_name}.json"
        print_info "Config details:"
        print_info "- Private network: ${private_ip}/24"
        print_info "- TUN device: ${config_name}"
        print_info "- Tunnel endpoint: ${ip_plus1}"
        print_info "- Protoswap TCP: ${protoswap_tcp:-N/A}"
        print_info "- Protoswap UDP: ${protoswap_udp:-N/A}"
        print_info "- XOR key: ${xor_key}"
        if [ "$use_tls" = true ]; then
            print_info "- TLS Termination: Enabled (${cert_path})"
        fi
        if [ "$use_proxy_protocol" = true ]; then
            print_info "- Proxy Protocol: Enabled"
        fi
        if [ "$use_mux" = true ]; then
            print_info "- Mux Client: Enabled (${mux_count} connections)"
        fi
        if [ "$has_listener" = true ]; then
            print_info "- TCP Listener: Port ${listen_port} -> ${ip_plus1}:${target_port}"
        fi
        print_info ""
        print_info "Traffic flow: TUN -> IpOverrider (Up/Down) -> IpManipulator -> ObfuscatorClient -> RawSocket"
    else
        print_error "Failed to create V3 server configuration"
        exit 1
    fi
}

# V3 Client Configuration (Non-Iran side / Kharej)
create_v3_client_config() {
    local config_name="$1"
    local non_iran_ip="$2"
    local iran_ip="$3"
    local private_ip="$4"
    local protoswap_tcp="$5"
    local custom_udp="$6"
    local use_proxy_protocol="${7:-false}"
    local listen_port="${8:-443}"
    local target_port="${9:-443}"
    local final_ip="${10:-127.0.0.1}"
    local explicit_listener="${11:-false}"
    local use_mux="${12:-false}"
    local xor_key="${13:-90}"

    local protoswap_udp=""
    if [ -n "$custom_udp" ] && [[ "$custom_udp" =~ ^[0-9]+$ ]]; then
        protoswap_udp="$custom_udp"
    fi

    if [ -n "$protoswap_tcp" ] && [ -n "$protoswap_udp" ] && [ "$protoswap_tcp" -eq "$protoswap_udp" ]; then
        print_error "Error: TCP Protocol ($protoswap_tcp) and UDP Protocol ($protoswap_udp) CANNOT be the same."
        print_error "Traffic would be indistinguishable. Please use different values."
        exit 1
    fi

    IFS='.' read -r ip1 ip2 ip3 ip4 <<< "$private_ip"
    local ip_plus1="$ip1.$ip2.$ip3.$((ip4+1))"

    local has_listener=false
    if [ "$use_proxy_protocol" = true ] || [ "$explicit_listener" = true ] || [ "$use_mux" = true ]; then
        has_listener=true
    fi

    local var_entries=()
    var_entries+=("        \"ip_server_iran\": \"${iran_ip}\"")
    var_entries+=("        \"ip_server_kharej\": \"${non_iran_ip}\"")
    var_entries+=("        \"private_ip\": \"${private_ip}\"")
    var_entries+=("        \"private_ip_endpoint\": \"${ip_plus1}\"")

    if [ -n "$protoswap_tcp" ]; then
        var_entries+=("        \"protoswap_tcp_to_number\": ${protoswap_tcp}")
    fi
    if [ -n "$protoswap_udp" ]; then
        var_entries+=("        \"protoswap_udp_to_number\": ${protoswap_udp}")
    fi
    if [ "$has_listener" = true ]; then
        var_entries+=("        \"port_to_listen\": ${listen_port}")
        var_entries+=("        \"port_to_forward\": ${target_port}")
    fi

    exec 3> "${config_name}.json"
    cat << EOF >&3
{
    "name": "${config_name}",
    "variables": {
EOF
    local total_vars=${#var_entries[@]}
    for ((i=0; i<total_vars; i++)); do
        if [ $((i + 1)) -lt "$total_vars" ]; then
            echo "${var_entries[i]}," >&3
        else
            echo "${var_entries[i]}" >&3
        fi
    done
    cat << EOF >&3
    },
    "nodes": [
EOF

    if [ "$has_listener" = true ]; then
        local first_tcp_node="tcp-out"
        if [ "$use_proxy_protocol" = true ]; then
            first_tcp_node="proxy-source-reader"
        elif [ "$use_mux" = true ]; then
            first_tcp_node="mux-s"
        fi

        cat << EOF >&3
        {
            "name": "users_inbound",
            "type": "TcpListener",
            "settings": {
                "address": "0.0.0.0",
                "port": \$port_to_listen\$,
                "nodelay": true
            },
            "next": "${first_tcp_node}"
        },
EOF
        if [ "$use_proxy_protocol" = true ]; then
            local next_after_proxy="tcp-out"
            if [ "$use_mux" = true ]; then
                next_after_proxy="mux-s"
            fi
            cat << EOF >&3
        {
            "name": "proxy-source-reader",
            "type": "HeaderServer",
            "settings": {
                "override": "proxy-protocol->source-fields"
            },
            "next": "${next_after_proxy}"
        },
EOF
        fi

        if [ "$use_mux" = true ]; then
            cat << EOF >&3
        {
            "name": "mux-s",
            "type": "MuxServer",
            "settings": {},
            "next": "tcp-out"
        },
EOF
        fi

        cat << EOF >&3
        {
            "name": "tcp-out",
            "type": "TcpConnector",
            "settings": {
                "address": "${final_ip}",
                "port": \$port_to_forward\$,
                "nodelay": true
            }
        },
EOF
    fi

    cat << EOF >&3
        {
            "name": "my tun2",
            "type": "TunDevice",
            "settings": {
                "device-name": "${config_name}",
                "device-ip": "${private_ip}/24"
            },
            "next": "ipcorrect"
        },
        {
            "name": "ipcorrect",
            "type": "IpOverrider",
            "settings": {
                "up": {
                    "source-ip": {
                        "ipv4": \$ip_server_kharej\$
                    },
                    "dest-ip": {
                        "ipv4": \$ip_server_iran\$
                    }
                },
                "down": {
                    "source-ip": {
                        "ipv4": \$private_ip_endpoint\$
                    },
                    "dest-ip": {
                        "ipv4": \$private_ip\$
                    }
                }
            },
            "next": "ip-manipulator"
        },
        {
            "name": "ip-manipulator",
            "type": "IpManipulator",
            "settings": {
EOF
    if [ -n "$protoswap_tcp" ] && [ -n "$protoswap_udp" ]; then
        cat << EOF >&3
                "protoswap-tcp": \$protoswap_tcp_to_number\$,
                "protoswap-udp": \$protoswap_udp_to_number\$
EOF
    elif [ -n "$protoswap_tcp" ]; then
        cat << EOF >&3
                "protoswap-tcp": \$protoswap_tcp_to_number\$
EOF
    elif [ -n "$protoswap_udp" ]; then
        cat << EOF >&3
                "protoswap-udp": \$protoswap_udp_to_number\$
EOF
    fi

    cat << EOF >&3
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
            "next": "rdin"
        },
        {
            "name": "rdin",
            "type": "RawSocket",
            "settings": {
                "capture-filter-mode": "source-ip",
                "capture-ip": \$ip_server_iran\$
            }
        }
    ]
}
EOF
    exec 3>&-

    if [ $? -eq 0 ]; then
        add_to_core_json "$config_name" "v3"
        print_success "V3 Client configuration created: ${config_name}.json"
        print_info "Config details:"
        print_info "- Private network: ${private_ip}/24"
        print_info "- TUN device: ${config_name}"
        print_info "- Tunnel endpoint: ${ip_plus1}"
        print_info "- Protoswap TCP: ${protoswap_tcp:-N/A}"
        print_info "- Protoswap UDP: ${protoswap_udp:-N/A}"
        print_info "- XOR key: ${xor_key}"
        if [ "$use_mux" = true ]; then
            print_info "- Mux Server: Enabled"
        fi
        if [ "$has_listener" = true ]; then
            print_info "- TCP Listener: Port ${listen_port} -> ${final_ip}:${target_port}"
        fi
        print_info ""
        print_info "Traffic flow: TUN -> IpOverrider (Up/Down) -> IpManipulator -> ObfuscatorServer -> RawSocket"
    else
        print_error "Failed to create V3 client configuration"
        exit 1
    fi
}

# Handle V3 configuration CLI
handle_v3_config() {
    shift 1 # remove v3
    local config_type="$1"  # server or client
    shift 1

    if [ "$config_type" = "server" ]; then
        if [ "$#" -lt 5 ]; then
            echo "Usage: $0 v3 server <config_name> <non_iran_ip> <iran_ip> <private_ip> <protocol> [udp_protocol] [options]"
            echo ""
            echo "Arguments:"
            echo "  config_name   - Name for the tunnel configuration"
            echo "  non_iran_ip   - IP of the foreign server (e.g., Sweden)"
            echo "  iran_ip       - IP of the Iran server"
            echo "  private_ip    - Private network IP (e.g., 30.6.0.1)"
            echo "  protocol      - Protocol number for TCP swap"
            echo "  udp_protocol  - Protocol number for UDP swap (default: tcp + 1)"
            echo ""
            echo "Options:"
            echo "  --xor-key N               Obfuscator XOR key (default: 90)"
            echo "  --tls <cert> <key>        Enable TLS termination on Iran side"
            echo "  --proxy-protocol          Enable Proxy Protocol header"
            echo "  --mux [count]             Enable Mux multiplexing (default count: 8)"
            echo "  --listen-port, -p <port>  Listen port on Iran side (default: 443)"
            echo "  --target-port, -t <port>  Target port on Kharej side (default: 443)"
            echo ""
            echo "Examples:"
            echo "  $0 v3 server gehetz 37.152.190.113 91.107.146.112 30.6.0.1 50"
            echo "  $0 v3 server gehetz 37.152.190.113 91.107.146.112 30.6.0.1 50 --xor-key 90 --tls /etc/ssl/cert.pem /etc/ssl/key.pem --mux 8 -p 443 -t 443"
            exit 1
        fi

        local config_name="$1"
        local non_iran_ip="$2"
        local iran_ip="$3"
        local private_ip="$4"
        local protoswap_tcp="$5"
        shift 5

        local custom_udp=""
        if [ "$#" -gt 0 ] && [[ "$1" =~ ^[0-9]+$ ]]; then
            custom_udp="$1"
            shift 1
        fi

        local use_tls=false
        local cert_path=""
        local key_path=""
        local use_proxy_protocol=false
        local listen_port=443
        local target_port=443
        local explicit_listener=true
        local use_mux=false
        local mux_count=8
        local xor_key=90

        while [ "$#" -gt 0 ]; do
            case "$1" in
                --xor-key)
                    xor_key="$2"
                    shift 2
                    ;;
                --tls)
                    use_tls=true
                    cert_path="$2"
                    key_path="$3"
                    shift 3
                    ;;
                --proxy-protocol)
                    use_proxy_protocol=true
                    shift 1
                    ;;
                --mux)
                    use_mux=true
                    if [ "$#" -gt 1 ] && [[ "$2" =~ ^[0-9]+$ ]]; then
                        mux_count="$2"
                        shift 2
                    else
                        mux_count=8
                        shift 1
                    fi
                    ;;
                --listen-port|--listen|-p|-l)
                    listen_port="$2"
                    explicit_listener=true
                    shift 2
                    ;;
                --target-port|--forward|-t|-f)
                    target_port="$2"
                    explicit_listener=true
                    shift 2
                    ;;
                *)
                    shift 1
                    ;;
            esac
        done

        create_v3_server_config "$config_name" "$non_iran_ip" "$iran_ip" "$private_ip" "$protoswap_tcp" "$custom_udp" "$use_tls" "$cert_path" "$key_path" "$use_proxy_protocol" "$listen_port" "$target_port" "$explicit_listener" "$use_mux" "$mux_count" "$xor_key"

    elif [ "$config_type" = "client" ]; then
        if [ "$#" -lt 5 ]; then
            echo "Usage: $0 v3 client <config_name> <non_iran_ip> <iran_ip> <private_ip> <protocol> [udp_protocol] [options]"
            echo ""
            echo "Arguments:"
            echo "  config_name   - Name for the tunnel configuration"
            echo "  non_iran_ip   - IP of the foreign server (e.g., Sweden)"
            echo "  iran_ip       - IP of the Iran server"
            echo "  private_ip    - Private network IP (e.g., 30.6.0.1)"
            echo "  protocol      - Protocol number for TCP swap"
            echo "  udp_protocol  - Protocol number for UDP swap (default: tcp + 1)"
            echo ""
            echo "Options:"
            echo "  --xor-key N               Obfuscator XOR key (default: 90)"
            echo "  --proxy-protocol          Enable HeaderServer to parse Proxy Protocol"
            echo "  --mux                     Enable Mux Server demultiplexing"
            echo "  --listen-port, -p <port>  Listen port on Kharej side (default: 443)"
            echo "  --target-port, -t <port>  Final backend target port on Kharej (default: 443)"
            echo "  --final-ip <ip>           Final target IP for Kharej backend (default: 127.0.0.1)"
            echo ""
            echo "Example:"
            echo "  $0 v3 client umberalla6 37.152.190.113 91.107.146.112 30.6.0.1 50 --mux -p 443 -t 443"
            exit 1
        fi

        local config_name="$1"
        local non_iran_ip="$2"
        local iran_ip="$3"
        local private_ip="$4"
        local protoswap_tcp="$5"
        shift 5

        local custom_udp=""
        if [ "$#" -gt 0 ] && [[ "$1" =~ ^[0-9]+$ ]]; then
            custom_udp="$1"
            shift 1
        fi

        local use_proxy_protocol=false
        local listen_port=443
        local target_port=443
        local final_ip="127.0.0.1"
        local explicit_listener=false
        local use_mux=false
        local xor_key=90

        while [ "$#" -gt 0 ]; do
            case "$1" in
                --xor-key)
                    xor_key="$2"
                    shift 2
                    ;;
                --proxy-protocol)
                    use_proxy_protocol=true
                    shift 1
                    ;;
                --mux)
                    use_mux=true
                    if [ "$#" -gt 1 ] && [[ "$2" =~ ^[0-9]+$ ]]; then
                        shift 2
                    else
                        shift 1
                    fi
                    ;;
                --listen-port|--listen|-p|-l)
                    listen_port="$2"
                    explicit_listener=true
                    shift 2
                    ;;
                --target-port|--forward|-t|-f)
                    target_port="$2"
                    explicit_listener=true
                    shift 2
                    ;;
                --final-ip)
                    final_ip="$2"
                    shift 2
                    ;;
                *)
                    shift 1
                    ;;
            esac
        done

        create_v3_client_config "$config_name" "$non_iran_ip" "$iran_ip" "$private_ip" "$protoswap_tcp" "$custom_udp" "$use_proxy_protocol" "$listen_port" "$target_port" "$final_ip" "$explicit_listener" "$use_mux" "$xor_key"

    else
        echo "Error: v3 config type must be either 'server' or 'client'"
        echo "Usage: $0 v3 <server|client> <config_name> <non_iran_ip> <iran_ip> <private_ip> <protocol>"
        exit 1
    fi
}

