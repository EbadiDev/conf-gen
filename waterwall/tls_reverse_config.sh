#!/bin/bash

# TLS Reverse Configuration Module for Waterwall
# Supports reverse TLS tunneling with multi-kharej IP whitelist on Iran server and optional user-side TLS termination.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

create_tls_reverse_config() {
    local side="$1"           # iran, kharej, or helper
    local config_name="$2"
    local iran_ip="$3"
    local port="$4"           # user_and_server_kharej_port / connect_to_iran_port
    local use_proxy_protocol="$5"
    shift 5

    if [ "$side" = "iran" ]; then
        local cert_path="$1"
        local key_path="$2"
        shift 2
        local kharej_ips=("$@")

        exec 3> "${config_name}.json"
        cat << EOF >&3
{
    "name": "${config_name}",
    "variables": {
        "ip_server_iran": "${iran_ip}",
        "certificate_path": "${cert_path}",
        "key_path": "${key_path}",
EOF
        for i in "${!kharej_ips[@]}"; do
            local ip_clean="${kharej_ips[$i]}"
            if [[ "$ip_clean" != */* ]]; then
                ip_clean="${ip_clean}/32"
            fi
            if [ $i -eq 0 ]; then
                cat << EOF >&3
        "ip_server_kharej": "${ip_clean}",
EOF
            else
                cat << EOF >&3
        "ip_server_kharej_$((i+1))": "${ip_clean}",
EOF
            fi
        done
        cat << EOF >&3
        "user_and_server_kharej_port": ${port}
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
            "next": "reverse_server"
        },
        {
            "name": "germany_reverse_tls_inbound",
            "type": "TcpListener",
            "settings": {
                "address": "0.0.0.0",
                "port": \$user_and_server_kharej_port\$,
                "nodelay": true,
                "whitelist": [
EOF
        for i in "${!kharej_ips[@]}"; do
            if [ $i -eq 0 ]; then
                cat << EOF >&3
                    \$ip_server_kharej\$
EOF
            else
                cat << EOF >&3
                    ,\$ip_server_kharej_$((i+1))\$
EOF
            fi
        done
        cat << EOF >&3
                ]
            },
            "next": "tls_server"
        }
    ]
}
EOF
        exec 3>&-
    else # kharej or helper
        local sni="$1"
        local final_port="$2"
        local final_ip="${3:-127.0.0.1}"
        local min_held="${4:-8}"

        cat << EOF > "${config_name}.json"
{
    "name": "${config_name}",
    "variables": {
        "ip_server_iran": "${iran_ip}",
        "connect_to_iran_port": ${port},
        "domain_to_handshake_tls": "${sni}",
        "final_port": ${final_port},
        "min_held_connections": ${min_held}
    },
    "nodes": [
        {
            "name": "outbound_to_local_service",
            "type": "TcpConnector",
            "settings": {
                "address": "${final_ip}",
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
            "next": "tls_client"
        },
        {
            "name": "tls_client",
            "type": "TlsClient",
            "settings": {
                "sni": \$domain_to_handshake_tls\$,
                "verify": true
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

    if [ $? -eq 0 ]; then
        add_to_core_json "$config_name" "tls-reverse"
        print_success "TLS Reverse configuration file ${config_name}.json created successfully!"
    else
        print_error "Failed to create TLS Reverse configuration file."
        exit 1
    fi
}

handle_tls_reverse_config() {
    shift 1 # remove tls-reverse
    local side="${1:-iran}"
    local config_name="${2}"
    local iran_ip="${3}"
    local port="${4}"
    shift 4

    if [ -z "$port" ]; then
        echo "Usage (Iran):   $0 tls-reverse iran <config_name> <iran_ip> <port> <cert_path> <key_path> <kharej_ip1> [kharej_ip2...] [--proxy-protocol]"
        echo "Usage (Kharej): $0 tls-reverse kharej <config_name> <iran_ip> <port> <sni> <final_port> [final_ip] [min_held]"
        exit 1
    fi

    local use_proxy_protocol=false
    local remaining_args=()

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --proxy-protocol)
                use_proxy_protocol=true
                shift 1
                ;;
            *)
                remaining_args+=("$1")
                shift 1
                ;;
        esac
    done

    create_tls_reverse_config "$side" "$config_name" "$iran_ip" "$port" "$use_proxy_protocol" "${remaining_args[@]}"
}
