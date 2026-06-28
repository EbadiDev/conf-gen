#!/bin/bash

# UDP Reverse Configuration Module for Waterwall
# Supports UDP reverse tunneling using RawSocket + Obfuscator + IpOverrider + TunDevice + ReverseServer/Client.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

create_udp_reverse_config() {
    local side="$1"           # iran or kharej
    local config_name="$2"
    local iran_public_ip="$3"
    local kharej_public_ip="$4"
    local listen_port="$5"     # public_udp_port (e.g. 11040) / local target port on kharej
    local tunnel_port="${6:-443}"
    local tun_ip_iran="${7:-10.20.1.1}"
    local tun_ip_kharej="${8:-10.20.1.2}"
    local xor_key="${9:-153}"
    local reverse_secret="${10:-begapour}"

    local tun_name="${config_name}"

    if [ "$side" = "iran" ]; then
        cat << EOF > "${config_name}.json"
{
  "name": "${config_name}",
  "variables": {
    "ip_kharej_public": "${kharej_public_ip}",
    "ip_iran_public": "${iran_public_ip}",
    "tun_ip_kharej": "${tun_ip_kharej}",
    "tun_ip_iran": "${tun_ip_iran}",
    "xor_key": ${xor_key},
    "reverse_secret": "${reverse_secret}"
  },
  "nodes": [
    {
      "name": "tun_device",
      "type": "TunDevice",
      "settings": {
        "device-name": "${tun_name}",
        "device-ip": "${tun_ip_iran}/24"
      },
      "next": "ip_rewrite"
    },
    {
      "name": "ip_rewrite",
      "type": "IpOverrider",
      "settings": {
        "up": {
          "source-ip": {
            "ipv4": \$ip_iran_public\$
          },
          "dest-ip": {
            "ipv4": \$ip_kharej_public\$
          }
        },
        "down": {
          "source-ip": {
            "ipv4": \$tun_ip_kharej\$
          },
          "dest-ip": {
            "ipv4": \$tun_ip_iran\$
          }
        }
      },
      "next": "obfuscator_client"
    },
    {
      "name": "obfuscator_client",
      "type": "ObfuscatorClient",
      "settings": {
        "method": "xor",
        "xor_key": \$xor_key\$,
        "skip": "transport",
        "tls_record_header": false
      },
      "next": "raw_out"
    },
    {
      "name": "raw_out",
      "type": "RawSocket",
      "settings": {
        "capture-filter-mode": "source-ip",
        "capture-ips": [
          \$ip_kharej_public\$
        ]
      }
    },
    {
      "name": "reverse_udp_listener",
      "type": "UdpListener",
      "settings": {
        "address": \$tun_ip_iran\$,
        "port": ${tunnel_port}
      },
      "next": "reverse_server"
    },
    {
      "name": "reverse_server",
      "type": "ReverseServer",
      "settings": {
        "reverse-secret": \$reverse_secret\$
      },
      "next": "reverse_bridge_a"
    },
    {
      "name": "reverse_bridge_a",
      "type": "Bridge",
      "settings": {
        "pair": "reverse_bridge_b"
      }
    },
    {
      "name": "reverse_bridge_b",
      "type": "Bridge",
      "settings": {
        "pair": "reverse_bridge_a"
      }
    },
    {
      "name": "public_udp_inbound",
      "type": "UdpListener",
      "settings": {
        "address": "0.0.0.0",
        "port": ${listen_port}
      },
      "next": "reverse_bridge_b"
    }
  ]
}
EOF
    else # kharej
        cat << EOF > "${config_name}.json"
{
  "name": "${config_name}",
  "variables": {
    "ip_kharej_public": "${kharej_public_ip}",
    "ip_iran_public": "${iran_public_ip}",
    "tun_ip_kharej": "${tun_ip_kharej}",
    "tun_ip_iran": "${tun_ip_iran}",
    "xor_key": ${xor_key},
    "reverse_secret": "${reverse_secret}"
  },
  "nodes": [
    {
      "name": "raw_in",
      "type": "RawSocket",
      "settings": {
        "capture-filter-mode": "source-ip",
        "capture-ips": [
          \$ip_iran_public\$
        ]
      },
      "next": "obfuscator_server"
    },
    {
      "name": "obfuscator_server",
      "type": "ObfuscatorServer",
      "settings": {
        "method": "xor",
        "xor_key": \$xor_key\$,
        "skip": "transport",
        "tls_record_header": false
      },
      "next": "ip_rewrite"
    },
    {
      "name": "ip_rewrite",
      "type": "IpOverrider",
      "settings": {
        "up": {
          "source-ip": {
            "ipv4": \$tun_ip_iran\$
          },
          "dest-ip": {
            "ipv4": \$tun_ip_kharej\$
          }
        },
        "down": {
          "source-ip": {
            "ipv4": \$ip_kharej_public\$
          },
          "dest-ip": {
            "ipv4": \$ip_iran_public\$
          }
        }
      },
      "next": "tun_device"
    },
    {
      "name": "tun_device",
      "type": "TunDevice",
      "settings": {
        "device-name": "${tun_name}",
        "device-ip": "${tun_ip_kharej}/24"
      }
    },
    {
      "name": "reverse_bridge_a",
      "type": "Bridge",
      "settings": {
        "pair": "reverse_bridge_b"
      },
      "next": "reverse_client"
    },
    {
      "name": "reverse_bridge_b",
      "type": "Bridge",
      "settings": {
        "pair": "reverse_bridge_a"
      },
      "next": "udp_to_local_service"
    },
    {
      "name": "reverse_client",
      "type": "ReverseClient",
      "settings": {
        "minimum-unused": 8,
        "reverse-secret": \$reverse_secret\$
      },
      "next": "udp_to_iran"
    },
    {
      "name": "udp_to_iran",
      "type": "UdpConnector",
      "settings": {
        "address": \$tun_ip_iran\$,
        "port": ${tunnel_port}
      }
    },
    {
      "name": "udp_to_local_service",
      "type": "UdpConnector",
      "settings": {
        "address": "127.0.0.1",
        "port": ${listen_port}
      }
    }
  ]
}
EOF
    fi

    if [ $? -eq 0 ]; then
        add_to_core_json "$config_name" "udp-reverse"
        print_success "UDP Reverse configuration file ${config_name}.json created successfully!"
    else
        print_error "Failed to create UDP Reverse configuration file."
        exit 1
    fi
}

handle_udp_reverse_config() {
    shift 1 # remove udp-reverse
    local side="${1:-iran}"
    local config_name="${2}"
    local iran_public_ip="${3}"
    local kharej_public_ip="${4}"
    local listen_port="${5}"
    local tunnel_port="${6:-443}"
    local tun_ip_iran="${7:-10.20.1.1}"
    local tun_ip_kharej="${8:-10.20.1.2}"
    local xor_key="${9:-153}"
    local reverse_secret="${10:-begapour}"

    if [ -z "$listen_port" ]; then
        echo "Usage: $0 udp-reverse <iran|kharej> <config_name> <iran_public_ip> <kharej_public_ip> <listen_port> [tunnel_port] [tun_ip_iran] [tun_ip_kharej] [xor_key] [reverse_secret]"
        echo "Example: $0 udp-reverse iran udp-rev-iran 1.1.1.1 2.2.2.2 11040"
        exit 1
    fi

    create_udp_reverse_config "$side" "$config_name" "$iran_public_ip" "$kharej_public_ip" "$listen_port" "$tunnel_port" "$tun_ip_iran" "$tun_ip_kharej" "$xor_key" "$reverse_secret"
}
