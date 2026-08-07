#!/bin/bash

# Reverse Reality Configuration Module for Waterwall
# Supports TCP and UDP reverse tunneling with Reality encryption and ConnectionFisher for UDP.
# Supports floating IPs via --float flag for multi-IP load balancing.

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
    local cert_path="${12:-}"
    local key_path="${13:-}"
    local use_halfduplex="${14:-false}"
    local use_fisher="${15:-false}"
    local reverse_secret_length="${16:-}"
    local reverse_secret="${17:-}"
    shift 17 2>/dev/null
    local float_ips=("$@")

    # --- Shared routing decisions (order matters) ---
    # Users/local entry side: HalfDuplex (if enabled) sits closest to the
    # user-facing entry, splitting the line before it reaches the Bridge/
    # Reverse/Reality chain.
    local user_side_entry="bridge_user_side"
    [ "$use_halfduplex" = true ] && user_side_entry="halfduplex_client"

    # Kharej-facing reverse-link listener (iran side): ConnectionFisher (if
    # enabled) sits right after the raw listener, before Reality.
    local kharej_listener_next="reality-server"
    [ "$use_fisher" = true ] && kharej_listener_next="fisher_server"

    # Optional ReverseClient/ReverseServer handshake settings. Both peers
    # (and any SniffRouter reverse detector in front of them) must match.
    local -a _revparts=()
    [ -n "$reverse_secret_length" ] && _revparts+=("\"reverse-secret-length\": ${reverse_secret_length}")
    [ -n "$reverse_secret" ] && _revparts+=("\"reverse-secret\": \"${reverse_secret}\"")
    local reverse_extra_settings=""
    if [ ${#_revparts[@]} -gt 0 ]; then
        reverse_extra_settings=$(IFS=,; echo "${_revparts[*]}")
    fi

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
EOF
            for i in "${!float_ips[@]}"; do
                cat << EOF >&3
        "ip_server_kharej_float_$((i+1))": "${float_ips[$i]}/32",
EOF
            done
            # Add TLS variables if enabled
            if [ -n "$cert_path" ]; then
                cat << EOF >&3
        "certificate_path": "${cert_path}",
        "key_path": "${key_path}",
EOF
            fi
            cat << EOF >&3
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
            "next": "$(if [ -n "$cert_path" ]; then echo "tls_termination"; elif [ "$use_proxy_protocol" = true ]; then echo "proxy-header"; else echo "$user_side_entry"; fi)"
        }
EOF
            # Determine next node after TLS termination
            local _after_tls="$([ "$use_proxy_protocol" = true ] && echo "proxy-header" || echo "$user_side_entry")"
            if [ -n "$cert_path" ]; then
                cat << EOF >&3
        ,
        {
            "name": "tls_termination",
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
            "next": "${_after_tls}"
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
            "next": "${user_side_entry}"
        }
EOF
            fi
            if [ "$use_halfduplex" = true ]; then
                cat << EOF >&3
        ,
        {
            "name": "halfduplex_client",
            "type": "HalfDuplexClient",
            "settings": {},
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
            "settings": { ${reverse_extra_settings} },
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
EOF
            for i in "${!float_ips[@]}"; do
                cat << EOF >&3
                    ,\$ip_server_kharej_float_$((i+1))\$
EOF
            done
            cat << EOF >&3
                ]
            },
            "next": "${kharej_listener_next}"
        }
EOF
            if [ "$use_fisher" = true ]; then
                cat << EOF >&3
        ,
        {
            "name": "fisher_server",
            "type": "ConnectionFisherServer",
            "settings": {},
            "next": "reality-server"
        }
EOF
            fi
            cat << EOF >&3
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
        "ip_server_kharej": "${kharej_ip}",
EOF
            for i in "${!float_ips[@]}"; do
                cat << VAREOF >> "${config_name}.json"
        "ip_server_kharej_float_$((i+1))": "${float_ips[$i]}",
VAREOF
            done
            cat << EOF >> "${config_name}.json"
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
            "next": "$([ "$use_halfduplex" = true ] && echo "halfduplex_server" || echo "outbound_to_local_service")"
        },
EOF
            if [ "$use_halfduplex" = true ]; then
                cat << EOF >> "${config_name}.json"
        {
            "name": "halfduplex_server",
            "type": "HalfDuplexServer",
            "settings": {},
            "next": "outbound_to_local_service"
        },
EOF
            fi
            cat << EOF >> "${config_name}.json"
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
                "minimum-unused": \$min_held_connections\$${reverse_extra_settings:+, ${reverse_extra_settings}}
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
            "next": "$([ "$use_fisher" = true ] && echo "fisher_client" || echo "tcp_to_iran")"
        },
EOF
            if [ "$use_fisher" = true ]; then
                cat << EOF >> "${config_name}.json"
        {
            "name": "fisher_client",
            "type": "ConnectionFisherClient",
            "settings": {
                "simultaneous-tries-perline": 3
            },
            "next": "tcp_to_iran"
        },
EOF
            fi
            cat << EOF >> "${config_name}.json"
        {
            "name": "tcp_to_iran",
            "type": "TcpConnector",
            "settings": {
EOF
            if [ ${#float_ips[@]} -gt 0 ]; then
                cat << EOF >> "${config_name}.json"
                "addresses": [
                    {
                        "address": \$ip_server_iran\$,
                        "port": \$connect_to_iran_port\$,
                        "weight": 1,
                        "source_ip": \$ip_server_kharej\$
                    }
EOF
                for i in "${!float_ips[@]}"; do
                    cat << EOF >> "${config_name}.json"
                    ,{
                        "address": \$ip_server_iran\$,
                        "port": \$connect_to_iran_port\$,
                        "weight": 1,
                        "source_ip": \$ip_server_kharej_float_$((i+1))\$
                    }
EOF
                done
                cat << EOF >> "${config_name}.json"
                ],
                "nodelay": true
            }
        }
    ]
}
EOF
            else
                cat << EOF >> "${config_name}.json"
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
    else # UDP
        if [ "$side" = "iran" ]; then
            exec 3> "${config_name}.json"
            cat << EOF >&3
{
    "name": "${config_name}",
    "variables": {
        "domain_white": "${domain}",
        "ip_behind_domain_white": "${white_ip}",
        "ip_server_kharej": "${kharej_ip}/32",
EOF
            for i in "${!float_ips[@]}"; do
                cat << EOF >&3
        "ip_server_kharej_float_$((i+1))": "${float_ips[$i]}/32",
EOF
            done
            cat << EOF >&3
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
            "next": "${user_side_entry}"
        }
EOF
            if [ "$use_halfduplex" = true ]; then
                cat << EOF >&3
        ,
        {
            "name": "halfduplex_client",
            "type": "HalfDuplexClient",
            "settings": {},
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
            "settings": { ${reverse_extra_settings} },
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
EOF
            for i in "${!float_ips[@]}"; do
                cat << EOF >&3
                    ,\$ip_server_kharej_float_$((i+1))\$
EOF
            done
            cat << EOF >&3
                ]
            },
            "next": "${kharej_listener_next}"
        }
EOF
            if [ "$use_fisher" = true ]; then
                cat << EOF >&3
        ,
        {
            "name": "fisher_server",
            "type": "ConnectionFisherServer",
            "settings": {},
            "next": "reality-server"
        }
EOF
            fi
            cat << EOF >&3
    ]
}
EOF
            exec 3>&-
        else # udp kharej
            cat << EOF > "${config_name}.json"
{
    "name": "${config_name}",
    "variables": {
        "ip_server_iran": "${iran_ip}",
        "ip_server_kharej": "${kharej_ip}",
EOF
            for i in "${!float_ips[@]}"; do
                cat << VAREOF >> "${config_name}.json"
        "ip_server_kharej_float_$((i+1))": "${float_ips[$i]}",
VAREOF
            done
            cat << EOF >> "${config_name}.json"
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
            "next": "$([ "$use_halfduplex" = true ] && echo "halfduplex_server" || echo "udpovertcp_server")"
        },
EOF
            if [ "$use_halfduplex" = true ]; then
                cat << EOF >> "${config_name}.json"
        {
            "name": "halfduplex_server",
            "type": "HalfDuplexServer",
            "settings": {},
            "next": "udpovertcp_server"
        },
EOF
            fi
            cat << EOF >> "${config_name}.json"
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
                "minimum-unused": \$min_held_connections\$${reverse_extra_settings:+, ${reverse_extra_settings}}
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
            "next": "$([ "$use_fisher" = true ] && echo "fisher_client" || echo "tcp_to_iran")"
        },
EOF
            if [ "$use_fisher" = true ]; then
                cat << EOF >> "${config_name}.json"
        {
            "name": "fisher_client",
            "type": "ConnectionFisherClient",
            "settings": {
                "simultaneous-tries-perline": 3
            },
            "next": "tcp_to_iran"
        },
EOF
            fi
            cat << EOF >> "${config_name}.json"
        {
            "name": "tcp_to_iran",
            "type": "TcpConnector",
            "settings": {
EOF
            if [ ${#float_ips[@]} -gt 0 ]; then
                cat << EOF >> "${config_name}.json"
                "addresses": [
                    {
                        "address": \$ip_server_iran\$,
                        "port": \$connect_to_iran_port\$,
                        "weight": 1,
                        "source_ip": \$ip_server_kharej\$
                    }
EOF
                for i in "${!float_ips[@]}"; do
                    cat << EOF >> "${config_name}.json"
                    ,{
                        "address": \$ip_server_iran\$,
                        "port": \$connect_to_iran_port\$,
                        "weight": 1,
                        "source_ip": \$ip_server_kharej_float_$((i+1))\$
                    }
EOF
                done
                cat << EOF >> "${config_name}.json"
                ],
                "nodelay": true
            }
        }
    ]
}
EOF
            else
                cat << EOF >> "${config_name}.json"
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
        echo "Usage: $0 reverse-reality <tcp|udp> <iran|kharej> <config_name> <iran_ip> <kharej_ip> <port> <domain> <white_ip_or_final_port> [password] [min_held_connections] [--proxy-protocol] [--tls <cert> <key>] [--halfduplex] [--fisher] [--reverse-secret-length <n>] [--reverse-secret <secret>] [--float <ip1> ...]"
        echo "Example (Iran):   $0 reverse-reality tcp iran rev-iran 1.1.1.1 2.2.2.2 443 live.telewebion.ir 185.112.32.68 mypass --proxy-protocol"
        echo "Example (Iran+TLS): $0 reverse-reality tcp iran rev-iran 1.1.1.1 2.2.2.2 443 live.telewebion.ir 185.112.32.68 mypass --tls /etc/ssl/cert.crt /etc/ssl/key.key"
        echo "Example (Kharej): $0 reverse-reality tcp kharej rev-kharej 1.1.1.1 2.2.2.2 443 live.telewebion.ir 8081 mypass 8 --float 2.2.2.3 2.2.2.4"
        echo "Example (UDP + HalfDuplex + Fisher): $0 reverse-reality udp iran rev-iran 1.1.1.1 2.2.2.2 443 live.telewebion.ir 185.112.32.68 mypass 8 --halfduplex --fisher"
        echo "Example (Reverse handshake secret): $0 reverse-reality tcp kharej rev-kharej 1.1.1.1 2.2.2.2 443 live.telewebion.ir 8081 mypass 8 --reverse-secret-length 900 --reverse-secret mysecret"
        echo ""
        echo "  --halfduplex             Split each logical line into separate upload/download transport lines (HalfDuplexClient/Server)."
        echo "  --fisher                 Race multiple candidate outbound lines and keep the first that proves it reached the peer (ConnectionFisherClient/Server)."
        echo "  --reverse-secret-length  Length in bytes of the ReverseClient/ReverseServer handshake. Must be 1-1024 (default 640)."
        echo "  --reverse-secret         ASCII secret that XORs the reverse-link handshake. Must match on both iran and kharej."
        exit 1
    fi

    shift 8
    local password="arch1234net"
    local min_held=8
    local use_proxy_protocol=false
    local cert_path=""
    local key_path=""
    local use_halfduplex=false
    local use_fisher=false
    local reverse_secret_length=""
    local reverse_secret=""
    local float_ips=()

    if [ "$#" -gt 0 ] && [[ ! "$1" =~ ^- ]]; then
        password="$1"
        shift 1
    fi
    if [ "$#" -gt 0 ] && [[ ! "$1" =~ ^- ]]; then
        min_held="$1"
        shift 1
    fi

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --proxy-protocol)
                use_proxy_protocol=true
                shift 1
                ;;
            --tls)
                shift 1
                cert_path="$1"
                key_path="$2"
                shift 2
                ;;
            --halfduplex)
                use_halfduplex=true
                shift 1
                ;;
            --fisher)
                use_fisher=true
                shift 1
                ;;
            --reverse-secret-length)
                shift 1
                reverse_secret_length="$1"
                if ! [[ "$reverse_secret_length" =~ ^[0-9]+$ ]] || [ "$reverse_secret_length" -lt 1 ] || [ "$reverse_secret_length" -gt 1024 ]; then
                    print_error "--reverse-secret-length must be an integer between 1 and 1024"
                    exit 1
                fi
                shift 1
                ;;
            --reverse-secret)
                shift 1
                reverse_secret="$1"
                shift 1
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

    create_reverse_reality_config "$protocol" "$side" "$config_name" "$iran_ip" "$kharej_ip" "$port" "$domain" "$white_ip_or_final_port" "$password" "$min_held" "$use_proxy_protocol" "$cert_path" "$key_path" "$use_halfduplex" "$use_fisher" "$reverse_secret_length" "$reverse_secret" "${float_ips[@]}"
}