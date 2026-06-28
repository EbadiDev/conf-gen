#!/bin/bash

# Reverse Reality Configuration Module for Waterwall
# Supports TCP and UDP reverse tunneling with Reality encryption and ConnectionFisher for UDP.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

create_reverse_reality_config() {
    local protocol="$1"       # tcp or udp
    local side="$2"           # iran or kharej
    local config_name="$3"
    local iran_ip="$4"
    local kharej_ip="$5"
    local port="$6"           # user_and_server_kharej_port for iran / connect_to_iran_port for kharej
    local domain="$7"         # domain_white / domain_to_handshake_reality
    local white_ip="$8"       # ip_behind_domain_white (iran) / final_port (kharej)
    local password="${9:-arch1234net}"
    local min_held="${10:-8}"
    local use_proxy_protocol="${11:-false}"

    if [ "$protocol" = "tcp" ]; then
        if [ "$side" = "iran" ]; then
            exec 3> "${config_name}.json"
            cat << EOF >&3
{
    "name": "${config_name}",
    "variables": {
        "ip_server_iran": "${iran_ip}",
        "domain_white": "${domain}",
        "ip_behind_domain_white": "${white_ip}",
        "ip_server_kharej": "${kharej_ip}/32",
        "user_and_server_kharej_port": ${port},
        "password": "${password}"
    },
    "nodes": [
        {
            "name": "users_inbound",
            "type": "TcpListener",
            "settings": {
                "address": "0.0.0.0",
                "port": \$user_and_server_kharej_port\$,
                "nodelay": true
            },
            "next": "$([ "$use_proxy_protocol" = true ] && echo "proxy-header" || echo "bridge_user_side")"
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
            "next": "bridge_user_side"
        }
EOF
            fi
            cat << EOF >&3
        ,
        {
            "name": "bridge_user_side",
            "type": "Bridge",
            "settings": {
                "pair": "bridge_reverse_side"
            }
        },
        {
            "name": "bridge_reverse_side",
            "type": "Bridge",
            "settings": {
                "pair": "bridge_user_side"
            }
        },
        {
            "name": "reverse_server",
            "type": "ReverseServer",
            "settings": {},
            "next": "bridge_reverse_side"
        },
        {
            "name": "reality-server",
            "type": "RealityServer",
            "settings": {
                "destination": "dest-visitor",
                "password": \$password\$,
                "algorithm": "chacha20-poly1305",
                "kdf-iterations": 12000,
                "sniffing-attempts": 8
            },
            "next": "reverse_server"
        },
        {
            "name": "dest-visitor",
            "type": "TcpConnector",
            "settings": {
                "address": \$ip_behind_domain_white\$,
                "port": 443,
                "nodelay": true
            }
        },
        {
            "name": "germany_reverse_tls_inbound",
            "type": "TcpListener",
            "settings": {
                "address": "0.0.0.0",
                "port": \$user_and_server_kharej_port\$,
                "nodelay": true,
                "whitelist": [
                    \$ip_server_kharej\$
                ]
            },
            "next": "reality-server"
        }
    ]
}
EOF
            exec 3>&-
        else # tcp kharej
            cat << EOF > "${config_name}.json"
{
    "name": "${config_name}",
    "variables": {
        "ip_server_iran": "${iran_ip}",
        "connect_to_iran_port": ${port},
        "domain_to_handshake_reality": "${domain}",
        "password": "${password}",
        "final_port": ${white_ip},
        "min_held_connections": ${min_held}
    },
    "nodes": [
        {
            "name": "outbound_to_local_service",
            "type": "TcpConnector",
            "settings": {
                "address": "127.0.0.1",
                "port": \$final_port\$,
                "nodelay": true
            }
        },
        {
            "name": "bridge_local_side",
            "type": "Bridge",
            "settings": {
                "pair": "bridge_reverse_client_side"
            },
            "next": "outbound_to_local_service"
        },
        {
            "name": "bridge_reverse_client_side",
            "type": "Bridge",
            "settings": {
                "pair": "bridge_local_side"
            },
            "next": "reverse_client"
        },
        {
            "name": "reverse_client",
            "type": "ReverseClient",
            "settings": {
                "minimum-unused": \$min_held_connections\$
            },
            "next": "reality-client"
        },
        {
            "name": "reality-client",
            "type": "RealityClient",
            "settings": {
                "sni": \$domain_to_handshake_reality\$,
                "verify": true,
                "password": \$password\$,
                "algorithm": "chacha20-poly1305",
                "kdf-iterations": 12000
            },
            "next": "tcp_to_iran"
        },
        {
            "name": "tcp_to_iran",
            "type": "TcpConnector",
            "settings": {
                "address": \$ip_server_iran\$,
                "port": \$connect_to_iran_port\$,
                "nodelay": true
            }
        }
    ]
}
EOF
        fi
    else # UDP
        if [ "$side" = "iran" ]; then
            cat << EOF > "${config_name}.json"
{
    "name": "${config_name}",
    "variables": {
        "domain_white": "${domain}",
        "ip_behind_domain_white": "${white_ip}",
        "ip_server_kharej": "${kharej_ip}/32",
        "user_and_server_kharej_port": ${port},
        "password": "${password}"
    },
    "nodes": [
        {
            "name": "users_inbound",
            "type": "UdpListener",
            "settings": {
                "address": "0.0.0.0",
                "port": \$user_and_server_kharej_port\$
            },
            "next": "udpovertcp_client"
        },
        {
            "name": "udpovertcp_client",
            "type": "UdpOverTcpClient",
            "settings": {},
            "next": "halfduplex_client"
        },
        {
            "name": "halfduplex_client",
            "type": "HalfDuplexClient",
            "settings": {},
            "next": "bridge_user_side"
        },
        {
            "name": "bridge_user_side",
            "type": "Bridge",
            "settings": {
                "pair": "bridge_reverse_side"
            }
        },
        {
            "name": "bridge_reverse_side",
            "type": "Bridge",
            "settings": {
                "pair": "bridge_user_side"
            }
        },
        {
            "name": "reverse_server",
            "type": "ReverseServer",
            "settings": {},
            "next": "bridge_reverse_side"
        },
        {
            "name": "reality-server",
            "type": "RealityServer",
            "settings": {
                "destination": "dest-visitor",
                "password": \$password\$,
                "algorithm": "chacha20-poly1305",
                "kdf-iterations": 12000,
                "sniffing-attempts": 8
            },
            "next": "reverse_server"
        },
        {
            "name": "dest-visitor",
            "type": "TcpConnector",
            "settings": {
                "address": \$ip_behind_domain_white\$,
                "port": 443,
                "nodelay": true
            }
        },
        {
            "name": "germany_reverse_tls_inbound",
            "type": "TcpListener",
            "settings": {
                "address": "0.0.0.0",
                "port": \$user_and_server_kharej_port\$,
                "nodelay": true,
                "whitelist": [
                    \$ip_server_kharej\$
                ]
            },
            "next": "fisher_server"
        },
        {
            "name": "fisher_server",
            "type": "ConnectionFisherServer",
            "settings": {},
            "next": "reality-server"
        }
    ]
}
EOF
        else # udp kharej
            cat << EOF > "${config_name}.json"
{
    "name": "${config_name}",
    "variables": {
        "ip_server_iran": "${iran_ip}",
        "connect_to_iran_port": ${port},
        "domain_to_handshake_reality": "${domain}",
        "password": "${password}",
        "final_port": ${white_ip},
        "min_held_connections": ${min_held}
    },
    "nodes": [
        {
            "name": "outbound_to_local_service",
            "type": "UdpConnector",
            "settings": {
                "address": "127.0.0.1",
                "port": \$final_port\$
            }
        },
        {
            "name": "udpovertcp_server",
            "type": "UdpOverTcpServer",
            "settings": {},
            "next": "outbound_to_local_service"
        },
        {
            "name": "bridge_local_side",
            "type": "Bridge",
            "settings": {
                "pair": "bridge_reverse_client_side"
            },
            "next": "halfduplex_server"
        },
        {
            "name": "halfduplex_server",
            "type": "HalfDuplexServer",
            "settings": {},
            "next": "udpovertcp_server"
        },
        {
            "name": "bridge_reverse_client_side",
            "type": "Bridge",
            "settings": {
                "pair": "bridge_local_side"
            },
            "next": "reverse_client"
        },
        {
            "name": "reverse_client",
            "type": "ReverseClient",
            "settings": {
                "minimum-unused": \$min_held_connections\$
            },
            "next": "reality-client"
        },
        {
            "name": "reality-client",
            "type": "RealityClient",
            "settings": {
                "sni": \$domain_to_handshake_reality\$,
                "verify": true,
                "password": \$password\$,
                "algorithm": "chacha20-poly1305",
                "kdf-iterations": 12000
            },
            "next": "fisher_client"
        },
        {
            "name": "fisher_client",
            "type": "ConnectionFisherClient",
            "settings": {
                "simultaneous-tries-perline": 3
            },
            "next": "tcp_to_iran"
        },
        {
            "name": "tcp_to_iran",
            "type": "TcpConnector",
            "settings": {
                "address": \$ip_server_iran\$,
                "port": \$connect_to_iran_port\$,
                "nodelay": true
            }
        }
    ]
}
EOF
        fi
    fi

    if [ $? -eq 0 ]; then
        add_to_core_json "$config_name" "reverse-reality"
        print_success "Reverse Reality configuration file ${config_name}.json created successfully!"
    else
        print_error "Failed to create Reverse Reality configuration file."
        exit 1
    fi
}

handle_reverse_reality_config() {
    shift 1 # remove reverse-reality
    local protocol="${1:-tcp}"
    local side="${2:-iran}"
    local config_name="${3}"
    local iran_ip="${4}"
    local kharej_ip="${5}"
    local port="${6}"
    local domain="${7}"
    local white_ip_or_final_port="${8}"

    if [ -z "$white_ip_or_final_port" ]; then
        echo "Usage: $0 reverse-reality <tcp|udp> <iran|kharej> <config_name> <iran_ip> <kharej_ip> <port> <domain> <white_ip_or_final_port> [password] [min_held_connections] [--proxy-protocol]"
        echo "Example (Iran):   $0 reverse-reality tcp iran rev-iran 1.1.1.1 2.2.2.2 443 live.telewebion.ir 185.112.32.68 mypass --proxy-protocol"
        echo "Example (Kharej): $0 reverse-reality tcp kharej rev-kharej 1.1.1.1 2.2.2.2 443 live.telewebion.ir 8081 mypass 8"
        exit 1
    fi

    shift 8
    local password="arch1234net"
    local min_held=8
    local use_proxy_protocol=false

    if [ "$#" -gt 0 ] && [[ ! "$1" =~ ^-- ]]; then
        password="$1"
        shift 1
    fi
    if [ "$#" -gt 0 ] && [[ ! "$1" =~ ^-- ]]; then
        min_held="$1"
        shift 1
    fi

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --proxy-protocol)
                use_proxy_protocol=true
                shift 1
                ;;
            *)
                shift 1
                ;;
        esac
    done

    create_reverse_reality_config "$protocol" "$side" "$config_name" "$iran_ip" "$kharej_ip" "$port" "$domain" "$white_ip_or_final_port" "$password" "$min_held" "$use_proxy_protocol"
}
