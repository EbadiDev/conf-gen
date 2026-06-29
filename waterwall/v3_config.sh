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

    local protoswap_udp=""
    if [ -n "$custom_udp" ]; then
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
    },
    "nodes": [
        {
            "name": "my tun",
            "type": "TunDevice",
            "settings": {
                "device-name": "${config_name}",
                "device-ip": "${private_ip}/24"
            },
            "next": "ip_rewrite"
        },
        {
            "name": "ip_rewrite",
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
            "next": "manip"
        },
        {
            "name": "manip",
            "type": "IpManipulator",
            "settings": {
                "protoswap-tcp": \$protoswap_tcp\$,
                "protoswap-udp": \$protoswap_udp\$
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

    if [ $? -eq 0 ]; then
        add_to_core_json "$config_name" "v3"
        print_success "V3 Server configuration created: ${config_name}.json"
        print_info "Config details:"
        print_info "- Private network: ${private_ip}/24"
        print_info "- TUN device: ${config_name}"
        print_info "- Tunnel endpoint: ${ip_plus1}"
        print_info "- Protoswap TCP: ${protoswap_tcp}"
        print_info "- Protoswap UDP: ${protoswap_udp}"
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

    local protoswap_udp=""
    if [ -n "$custom_udp" ]; then
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
    },
    "nodes": [
        {
            "name": "rd",
            "type": "RawSocket",
            "settings": {
                "capture-filter-mode": "source-ip",
                "capture-ip": \$ip_server_iran\$
            },
            "next": "manip"
        },
        {
            "name": "manip",
            "type": "IpManipulator",
            "settings": {
                "protoswap-tcp": \$protoswap_tcp\$,
                "protoswap-udp": \$protoswap_udp\$
            },
            "next": "ip_rewrite"
        },
        {
            "name": "ip_rewrite",
            "type": "IpOverrider",
            "settings": {
                "up": {
                    "source-ip": {
                        "ipv4": \$private_ip_endpoint\$
                    },
                    "dest-ip": {
                        "ipv4": \$private_ip\$
                    }
                },
                "down": {
                    "source-ip": {
                        "ipv4": \$ip_server_kharej\$
                    },
                    "dest-ip": {
                        "ipv4": \$ip_server_iran\$
                    }
                }
            },
            "next": "my tun"
        },
        {
            "name": "my tun",
            "type": "TunDevice",
            "settings": {
                "device-name": "${config_name}",
                "device-ip": "${private_ip}/24"
            }
        }
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
        print_info ""
        print_info "Traffic flow: RawSocket -> Protocol Swap -> IP Override -> TUN"
    else
        print_error "Failed to create V3 client configuration"
        exit 1
    fi
}

# Handle V3 configuration CLI
handle_v3_config() {
    local config_type="$2"  # server or client
    
    if [ "$config_type" = "server" ]; then
        if [ "$#" -lt 7 ]; then
            echo "Usage: $0 v3 server <config_name> <non_iran_ip> <iran_ip> <private_ip> <protocol> [udp_protocol]"
            echo ""
            echo "Arguments:"
            echo "  config_name   - Name for the tunnel configuration"
            echo "  non_iran_ip   - IP of the foreign server (e.g., Sweden)"
            echo "  iran_ip       - IP of the Iran server"
            echo "  private_ip    - Private network IP (e.g., 30.6.0.1)"
            echo "  protocol      - Protocol number for TCP swap"
            echo "  udp_protocol  - Protocol number for UDP swap (default: tcp + 1)"
            echo ""
            echo "Example:"
            echo "  $0 v3 server sweden 1.2.3.4 5.6.7.8 30.6.0.1 27"
            exit 1
        fi
        
        create_v3_server_config "$3" "$4" "$5" "$6" "$7" "$8"
        
    elif [ "$config_type" = "client" ]; then
        if [ "$#" -lt 7 ]; then
            echo "Usage: $0 v3 client <config_name> <non_iran_ip> <iran_ip> <private_ip> <protocol> [udp_protocol]"
            echo ""
            echo "Arguments:"
            echo "  config_name   - Name for the tunnel configuration"
            echo "  non_iran_ip   - IP of the foreign server (e.g., Sweden)"
            echo "  iran_ip       - IP of the Iran server"
            echo "  private_ip    - Private network IP (e.g., 30.6.0.1)"
            echo "  protocol      - Protocol number for TCP swap"
            echo "  udp_protocol  - Protocol number for UDP swap (default: tcp + 1)"
            echo ""
            echo "Example:"
            echo "  $0 v3 client iran 1.2.3.4 5.6.7.8 30.6.0.1 27"
            exit 1
        fi
        
        create_v3_client_config "$3" "$4" "$5" "$6" "$7" "$8"
        
    else
        echo "Error: v3 config type must be either 'server' or 'client'"
        echo "Usage: $0 v3 <server|client> <config_name> <non_iran_ip> <iran_ip> <private_ip> <protocol>"
        exit 1
    fi
}
