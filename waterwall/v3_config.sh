#!/bin/bash

# V3 Configuration Module for Waterwall
# Optimized for UDP support - includes protoswap-tcp AND protoswap-udp
# Modern variable syntax and consolidated IpOverrider configuration
# Best for: Gaming, VPN, QUIC, WireGuard, L2TP

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

    local protoswap_udp=""
    if [ -n "$custom_udp" ] && [[ "$custom_udp" =~ ^[0-9]+$ ]]; then
        protoswap_udp="$custom_udp"
    else
        protoswap_udp=$((protoswap_tcp + 1))
    fi

    if [ "$protoswap_tcp" -eq "$protoswap_udp" ]; then
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

    exec 3> "${config_name}.json"
    cat << EOF >&3
{
    "name": "${config_name}",
    "variables": {
        "ip_server_kharej": "${non_iran_ip}",
        "ip_server_iran": "${iran_ip}",
        "private_ip": "${private_ip}",
        "private_ip_endpoint": "${ip_plus1}",
        "protoswap_tcp": ${protoswap_tcp},
        "protoswap_udp": ${protoswap_udp}
EOF
    if [ "$has_listener" = true ]; then
        cat << EOF >&3
        ,"port_to_listen": ${listen_port},
        "port_to_forward": ${target_port}
EOF
        if [ "$use_tls" = true ]; then
            cat << EOF >&3
        ,"certificate_path": "${cert_path}",
        "key_path": "${key_path}"
EOF
        fi
        if [ "$use_mux" = true ]; then
            cat << EOF >&3
        ,"each_worker_mux_connections_count": ${mux_count}
EOF
        fi
    fi
    cat << EOF >&3
    },
    "nodes": [
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
                "direction": "up",
                "mode": "source-ip",
                "ipv4": \$ip_server_kharej\$
            },
            "next": "ipovdest"
        },
        {
            "name": "ipovdest",
            "type": "IpOverrider",
            "settings": {
                "direction": "up",
                "mode": "dest-ip",
                "ipv4": \$ip_server_iran\$
            },
            "next": "manip"
        },
        {
            "name": "manip",
            "type": "IpManipulator",
            "settings": {
                "protoswap": \$protoswap_tcp\$,
                "protoswap-tcp": \$protoswap_tcp\$,
                "protoswap-udp": \$protoswap_udp\$
            },
            "next": "ipovsrc2"
        },
        {
            "name": "ipovsrc2",
            "type": "IpOverrider",
            "settings": {
                "direction": "down",
                "mode": "source-ip",
                "ipv4": \$private_ip_endpoint\$
            },
            "next": "ipovdest2"
        },
        {
            "name": "ipovdest2",
            "type": "IpOverrider",
            "settings": {
                "direction": "down",
                "mode": "dest-ip",
                "ipv4": \$private_ip\$
            },
            "next": "rd"
        },
        {
            "name": "rd",
            "type": "RawSocket",
            "settings": {
                "capture-filter-mode": "source-ip",
                "capture-ip": \$ip_server_iran\$
            }
        }
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
        ,
        {
            "name": "users_inbound",
            "type": "TcpListener",
            "settings": {
                "address": "0.0.0.0",
                "port": \$port_to_listen\$,
                "nodelay": true
            },
            "next": "${first_tcp_node}"
        }
EOF
        if [ "$use_tls" = true ]; then
            local next_after_tls="tcp-out"
            if [ "$use_proxy_protocol" = true ]; then
                next_after_tls="proxy-header"
            elif [ "$use_mux" = true ]; then
                next_after_tls="mux-client"
            fi
            cat << EOF >&3
        ,
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
        }
EOF
        fi

        if [ "$use_proxy_protocol" = true ]; then
            local next_after_proxy="tcp-out"
            if [ "$use_mux" = true ]; then
                next_after_proxy="mux-client"
            fi
            cat << EOF >&3
        ,
        {
            "name": "proxy-header",
            "type": "HeaderClient",
            "settings": {
                "data": "proxy-protocol",
                "frontend-ipv4": \$ip_server_iran\$
            },
            "next": "${next_after_proxy}"
        }
EOF
        fi

        if [ "$use_mux" = true ]; then
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
        fi

        cat << EOF >&3
        ,
        {
            "name": "tcp-out",
            "type": "TcpConnector",
            "settings": {
                "address": \$private_ip_endpoint\$,
                "port": \$port_to_forward\$,
                "nodelay": true
            }
        }
EOF
    fi

    cat << EOF >&3
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
        print_info "- Protoswap TCP: ${protoswap_tcp}"
        print_info "- Protoswap UDP: ${protoswap_udp}"
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
        print_info "Traffic flow: TUN -> IP Override -> Protocol Swap -> RawSocket -> Internet"
    else
        print_error "Failed to create V3 server configuration"
        exit 1
    fi
}

# V3 Client Configuration (Non-Iran side)
create_v3_client_config() {
    local config_name="$1"
    local non_iran_ip="$2"
    local iran_ip="$3"
    local private_ip="$4"
    local protoswap_tcp="$5"
    local custom_udp="$6"
    local use_proxy_protocol="${7:-false}"
    local listen_port="${8:-443}"
    local target_port="${9:-2059}"
    local final_ip="${10:-127.0.0.1}"
    local explicit_listener="${11:-true}"
    local use_mux="${12:-false}"

    local protoswap_udp=""
    if [ -n "$custom_udp" ] && [[ "$custom_udp" =~ ^[0-9]+$ ]]; then
        protoswap_udp="$custom_udp"
    else
        protoswap_udp=$((protoswap_tcp + 1))
    fi

    if [ "$protoswap_tcp" -eq "$protoswap_udp" ]; then
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

    cat << EOF > "${config_name}.json"
{
    "name": "${config_name}",
    "variables": {
        "ip_server_kharej": "${non_iran_ip}",
        "ip_server_iran": "${iran_ip}",
        "private_ip": "${private_ip}",
        "private_ip_endpoint": "${ip_plus1}",
        "protoswap_tcp": ${protoswap_tcp},
        "protoswap_udp": ${protoswap_udp}
EOF
    if [ "$has_listener" = true ]; then
        cat << EOF >> "${config_name}.json"
        ,"port_to_listen": ${listen_port},
        "port_to_forward": ${target_port}
EOF
    fi
    cat << EOF >> "${config_name}.json"
    },
    "nodes": [
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
                "direction": "up",
                "mode": "source-ip",
                "ipv4": \$ip_server_iran\$
            },
            "next": "ipovdest"
        },
        {
            "name": "ipovdest",
            "type": "IpOverrider",
            "settings": {
                "direction": "up",
                "mode": "dest-ip",
                "ipv4": \$ip_server_kharej\$
            },
            "next": "manip"
        },
        {
            "name": "manip",
            "type": "IpManipulator",
            "settings": {
                "protoswap": \$protoswap_tcp\$,
                "protoswap-tcp": \$protoswap_tcp\$,
                "protoswap-udp": \$protoswap_udp\$
            },
            "next": "ipovsrc2"
        },
        {
            "name": "ipovsrc2",
            "type": "IpOverrider",
            "settings": {
                "direction": "down",
                "mode": "source-ip",
                "ipv4": \$private_ip_endpoint\$
            },
            "next": "ipovdest2"
        },
        {
            "name": "ipovdest2",
            "type": "IpOverrider",
            "settings": {
                "direction": "down",
                "mode": "dest-ip",
                "ipv4": \$private_ip\$
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
EOF

    if [ "$has_listener" = true ]; then
        local first_tcp_node="tcp-out"
        if [ "$use_proxy_protocol" = true ]; then
            first_tcp_node="proxy-source-reader"
        elif [ "$use_mux" = true ]; then
            first_tcp_node="mux-s"
        fi

        cat << EOF >> "${config_name}.json"
        ,
        {
            "name": "users_inbound",
            "type": "TcpListener",
            "settings": {
                "address": "0.0.0.0",
                "port": \$port_to_listen\$,
                "nodelay": true
            },
            "next": "${first_tcp_node}"
        }
EOF
        if [ "$use_proxy_protocol" = true ]; then
            local next_after_proxy="tcp-out"
            if [ "$use_mux" = true ]; then
                next_after_proxy="mux-s"
            fi
            cat << EOF >> "${config_name}.json"
        ,
        {
            "name": "proxy-source-reader",
            "type": "HeaderServer",
            "settings": {
                "override": "proxy-protocol->source-fields"
            },
            "next": "${next_after_proxy}"
        }
EOF
        fi

        if [ "$use_mux" = true ]; then
            cat << EOF >> "${config_name}.json"
        ,
        {
            "name": "mux-s",
            "type": "MuxServer",
            "settings": {},
            "next": "tcp-out"
        }
EOF
        fi

        cat << EOF >> "${config_name}.json"
        ,
        {
            "name": "tcp-out",
            "type": "TcpConnector",
            "settings": {
                "address": "${final_ip}",
                "port": \$port_to_forward\$,
                "nodelay": true
            }
        }
EOF
    fi

    cat << EOF >> "${config_name}.json"
    ]
}
EOF

    if [ $? -eq 0 ]; then
        add_to_core_json "$config_name" "v3"
        print_success "V3 Client configuration created: ${config_name}.json"
        print_info "Config details:"
        print_info "- Private network: ${private_ip}/24"
        print_info "- TUN device: ${config_name}"
        print_info "- Tunnel endpoint: ${ip_plus1}"
        print_info "- Protoswap TCP: ${protoswap_tcp}"
        print_info "- Protoswap UDP: ${protoswap_udp}"
        if [ "$use_mux" = true ]; then
            print_info "- Mux Server: Enabled"
        fi
        if [ "$has_listener" = true ]; then
            print_info "- TCP Listener: Port ${listen_port} -> ${final_ip}:${target_port}"
        fi
        print_info ""
        print_info "Traffic flow: RawSocket -> Protocol Swap -> IP Override -> TUN"
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
            echo "  --tls <cert> <key>        Enable TLS termination on Iran side"
            echo "  --proxy-protocol          Enable Proxy Protocol header"
            echo "  --mux [count]             Enable Mux multiplexing (default count: 8)"
            echo "  --listen-port, -p <port>  Listen port on Iran side (default: 443)"
            echo "  --target-port, -t <port>  Target port on Kharej side (default: 443)"
            echo ""
            echo "Examples:"
            echo "  $0 v3 server gehetz 37.152.190.113 91.107.146.112 30.6.0.1 51"
            echo "  $0 v3 server gehetz 37.152.190.113 91.107.146.112 30.6.0.1 51 --tls /etc/ssl/cert.pem /etc/ssl/key.pem --mux 8 -p 443 -t 443"
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

        while [ "$#" -gt 0 ]; do
            case "$1" in
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

        create_v3_server_config "$config_name" "$non_iran_ip" "$iran_ip" "$private_ip" "$protoswap_tcp" "$custom_udp" "$use_tls" "$cert_path" "$key_path" "$use_proxy_protocol" "$listen_port" "$target_port" "$explicit_listener" "$use_mux" "$mux_count"

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
            echo "  --proxy-protocol          Enable HeaderServer to parse Proxy Protocol"
            echo "  --mux                     Enable Mux Server demultiplexing"
            echo "  --listen-port, -p <port>  Listen port on Kharej side (default: 443)"
            echo "  --target-port, -t <port>  Final backend target port on Kharej (default: 2059)"
            echo "  --final-ip <ip>           Final target IP for Kharej backend (default: 127.0.0.1)"
            echo ""
            echo "Example:"
            echo "  $0 v3 client umberalla6 37.152.190.113 91.107.146.112 30.6.0.1 51 --mux -p 443 -t 2059"
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
        local target_port=2059
        local final_ip="127.0.0.1"
        local explicit_listener=true
        local use_mux=false

        while [ "$#" -gt 0 ]; do
            case "$1" in
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

        create_v3_client_config "$config_name" "$non_iran_ip" "$iran_ip" "$private_ip" "$protoswap_tcp" "$custom_udp" "$use_proxy_protocol" "$listen_port" "$target_port" "$final_ip" "$explicit_listener" "$use_mux"

    else
        echo "Error: v3 config type must be either 'server' or 'client'"
        echo "Usage: $0 v3 <server|client> <config_name> <non_iran_ip> <iran_ip> <private_ip> <protocol>"
        exit 1
    fi
}
