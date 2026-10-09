#!/bin/bash

# Xray Reverse Tunnel Configuration Module
# Generates Xray VLESS Reverse configurations for Iran (Portal) and Kharej (Bridge).
# Supports plain WebSocket (WS) or WebSocket + TLS, with multi-port TCP & UDP tunneling.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

create_xray_reverse_config() {
    local side="$1"             # iran or kharej
    local config_name="$2"
    shift 2

    local default_uuid="e3b0c442-98fc-1c14-9afb-f4c8996fb924"
    local uuid="$default_uuid"
    local ws_path="/api/v3/live"
    local ed="2560"
    local tls_enabled=false
    local cert_file=""
    local key_file=""
    local sni=""
    local output_file="${config_name}.json"

    if [ "$side" = "iran" ]; then
        local listen_port="$1"
        shift 1

        local tcp_ports=()
        local udp_ports=()

        while [ "$#" -gt 0 ]; do
            case "$1" in
                --ports|--tcp)
                    IFS=',' read -ra ADDR <<< "$2"
                    tcp_ports+=("${ADDR[@]}")
                    shift 2
                    ;;
                --udp)
                    IFS=',' read -ra ADDR <<< "$2"
                    udp_ports+=("${ADDR[@]}")
                    shift 2
                    ;;
                --uuid)
                    uuid="$2"
                    shift 2
                    ;;
                --path)
                    ws_path="$2"
                    shift 2
                    ;;
                --tls)
                    tls_enabled=true
                    cert_file="$2"
                    key_file="$3"
                    shift 3
                    ;;
                --output|-o)
                    output_file="$2"
                    shift 2
                    ;;
                *)
                    # Treat positional arguments as TCP ports
                    tcp_ports+=("$1")
                    shift 1
                    ;;
            esac
        done

        # Fallback default ports if none provided
        if [ ${#tcp_ports[@]} -eq 0 ] && [ ${#udp_ports[@]} -eq 0 ]; then
            tcp_ports=("8085" "8086")
        fi

        exec 3> "$output_file"
        cat << EOF >&3
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "portal",
      "listen": "0.0.0.0",
      "port": ${listen_port},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "reverse": {
              "tag": "reverse-portal"
            }
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
EOF
        if [ "$tls_enabled" = true ]; then
            cat << EOF >&3
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "${cert_file}",
              "keyFile": "${key_file}"
            }
          ]
        },
EOF
        fi
        cat << EOF >&3
        "wsSettings": {
          "path": "${ws_path}"
        }
      }
    }
EOF

        local all_tags=()
        # Add TCP tunnel inbounds
        for p in "${tcp_ports[@]}"; do
            all_tags+=("\"tunnel-${p}\"")
            cat << EOF >&3
    ,
    {
      "tag": "tunnel-${p}",
      "listen": "0.0.0.0",
      "port": ${p},
      "protocol": "tunnel",
      "settings": {
        "allowedNetwork": "tcp",
        "rewriteAddress": "127.0.0.1",
        "rewritePort": ${p}
      }
    }
EOF
        done

        # Add UDP tunnel inbounds
        for p in "${udp_ports[@]}"; do
            all_tags+=("\"tunnel-${p}-udp\"")
            cat << EOF >&3
    ,
    {
      "tag": "tunnel-${p}-udp",
      "listen": "0.0.0.0",
      "port": ${p},
      "protocol": "tunnel",
      "settings": {
        "allowedNetwork": "udp",
        "rewriteAddress": "127.0.0.1",
        "rewritePort": ${p}
      }
    }
EOF
        done

        local inbound_tags_joined
        inbound_tags_joined=$(IFS=,; echo "${all_tags[*]}")

        cat << EOF >&3
  ],
  "routing": {
    "rules": [
      {
        "inboundTag": [
          ${inbound_tags_joined}
        ],
        "outboundTag": "reverse-portal"
      }
    ]
  },
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    }
  ]
}
EOF
        exec 3>&-

    elif [ "$side" = "kharej" ]; then
        local iran_ip="$1"
        local connect_port="$2"
        shift 2

        while [ "$#" -gt 0 ]; do
            case "$1" in
                --uuid)
                    uuid="$2"
                    shift 2
                    ;;
                --path)
                    ws_path="$2"
                    shift 2
                    ;;
                --ed)
                    ed="$2"
                    shift 2
                    ;;
                --tls|--sni)
                    tls_enabled=true
                    sni="$2"
                    shift 2
                    ;;
                --output|-o)
                    output_file="$2"
                    shift 2
                    ;;
                *)
                    shift 1
                    ;;
            esac
        done

        local client_ws_path="${ws_path}"
        if [ -n "$ed" ]; then
            client_ws_path="${ws_path}?ed=${ed}"
        fi

        exec 3> "$output_file"
        cat << EOF >&3
{
  "log": {
    "loglevel": "warning"
  },
  "routing": {
    "rules": [
      {
        "inboundTag": [
          "reverse-bridge"
        ],
        "outboundTag": "direct"
      }
    ]
  },
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct",
      "settings": {
        "finalRules": [
          {
            "action": "allow",
            "ip": [
              "127.0.0.1",
              "::1"
            ]
          }
        ]
      }
    },
    {
      "tag": "bridge-out",
      "protocol": "vless",
      "settings": {
        "address": "${iran_ip}",
        "port": ${connect_port},
        "id": "${uuid}",
        "encryption": "none",
        "reverse": {
          "tag": "reverse-bridge"
        }
      },
      "streamSettings": {
        "network": "ws",
EOF
        if [ "$tls_enabled" = true ]; then
            cat << EOF >&3
        "security": "tls",
        "tlsSettings": {
          "serverName": "${sni}",
          "allowInsecure": false
        },
        "wsSettings": {
          "path": "${client_ws_path}",
          "headers": {
            "Host": "${sni}"
          }
        }
EOF
        else
            cat << EOF >&3
        "wsSettings": {
          "path": "${client_ws_path}"
        }
EOF
        fi
        cat << EOF >&3
      }
    }
  ]
}
EOF
        exec 3>&-
    else
        print_error "Invalid side: $side (must be 'iran' or 'kharej')"
        exit 1
    fi

    if [ $? -eq 0 ]; then
        print_success "Xray reverse configuration generated: $output_file"
    else
        print_error "Failed to generate Xray reverse configuration."
        exit 1
    fi
}

handle_xray_reverse_config() {
    shift 1 # remove xray-reverse
    local side="${1}"
    local config_name="${2}"

    if [ -z "$side" ] || [ -z "$config_name" ]; then
        echo "Usage:"
        echo "  $0 xray-reverse iran <config_name> <listen_port> [--tcp <ports>] [--udp <ports>] [options]"
        echo "  $0 xray-reverse kharej <config_name> <iran_ip> <connect_port> [options]"
        echo ""
        echo "Iran Options:"
        echo "  --tcp <ports>             Comma-separated TCP ports to forward (e.g. 8085,8086)"
        echo "  --udp <ports>             Comma-separated UDP ports to forward (e.g. 8087)"
        echo "  --uuid <uuid>             VLESS user UUID (default: e3b0c442-98fc-1c14-9afb-f4c8996fb924)"
        echo "  --path <path>             WebSocket path (default: /api/v3/live)"
        echo "  --tls <cert> <key>        Enable TLS with certificate and private key paths"
        echo "  -o, --output <file>       Custom output file (default: <config_name>.json)"
        echo ""
        echo "Kharej Options:"
        echo "  --uuid <uuid>             VLESS user UUID"
        echo "  --path <path>             WebSocket path (default: /api/v3/live)"
        echo "  --ed <threshold>          Early data length threshold (default: 2560)"
        echo "  --tls, --sni <domain>     Enable TLS with SNI / Host header"
        echo "  -o, --output <file>       Custom output file (default: <config_name>.json)"
        echo ""
        echo "Examples:"
        echo "  # Iran (Portal) - Plain WS:"
        echo "  $0 xray-reverse iran xray-iran 8443 --tcp 8085,8086 --udp 8087"
        echo ""
        echo "  # Kharej (Bridge) - Plain WS:"
        echo "  $0 xray-reverse kharej xray-kharej 109.94.164.214 8443"
        echo ""
        echo "  # Iran (Portal) - With TLS:"
        echo "  $0 xray-reverse iran xray-iran 8443 --tcp 8085,8086 --tls /etc/xray/cert/fullchain.pem /etc/xray/cert/privkey.pem"
        echo ""
        echo "  # Kharej (Bridge) - With TLS:"
        echo "  $0 xray-reverse kharej xray-kharej 109.94.164.214 8443 --tls france.archlix.com"
        exit 1
    fi

    shift 2
    create_xray_reverse_config "$side" "$config_name" "$@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    handle_xray_reverse_config "$@"
fi
