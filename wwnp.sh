#!/bin/bash

# Waterwall V2 + Nodepass Configuration Generator
# Combines Waterwall V2 tunnel with Nodepass for complete tunnel solution
# Uses Proxy Protocol natively - no GOST needed

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[WW+NP]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ============================================================================
# Waterwall V3 Configuration Generation (embedded)
# Optimized for UDP support - includes protoswap-tcp AND protoswap-udp
# ============================================================================

# Add config to core.json
add_to_core_json() {
    local config_name="$1"
    local core_file="core.json"
    
    # Create core.json if it doesn't exist
    if [ ! -f "$core_file" ]; then
        echo '{"configs": []}' > "$core_file"
    fi
    
    # Add new config and ensure uniqueness
    local tmp_file=$(mktemp)
    # Add if not exists, then unique
    jq --arg cfg "${config_name}.json" '.configs += [$cfg] | .configs |= unique' "$core_file" > "$tmp_file" 2>/dev/null && mv "$tmp_file" "$core_file"
}

# Create V3 Server Waterwall Config (Iran-side)
create_waterwall_v3_server_config() {
    local config_name="$1"
    local non_iran_ip="$2"
    local iran_ip="$3"
    local private_ip="$4"
    local protoswap_tcp="$5"
    local custom_udp="$6"

    # Use custom UDP protocol if provided, otherwise calculate as tcp + 1
    local protoswap_udp=""
    if [ -n "$custom_udp" ]; then
        protoswap_udp="$custom_udp"
    else
        protoswap_udp=$((protoswap_tcp + 1))
    fi

    # Validation: Protocols must be different
    if [ "$protoswap_tcp" -eq "$protoswap_udp" ]; then
        print_error "Error: TCP Protocol ($protoswap_tcp) and UDP Protocol ($protoswap_udp) CANNOT be the same."
        print_error "Traffic would be indistinguishable. Please use different values."
        exit 1
    fi

    # Calculate PRIVATE_IP+1 for ipovsrc2
    IFS='.' read -r ip1 ip2 ip3 ip4 <<< "$private_ip"
    local ip_plus1="$ip1.$ip2.$ip3.$((ip4+1))"

    cat << EOF > "${config_name}.json"
{
    "name": "${config_name}",
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
                "ipv4": "${iran_ip}"
            },
            "next": "ipovdest"
        },
        {
            "name": "ipovdest",
            "type": "IpOverrider",
            "settings": {
                "direction": "up",
                "mode": "dest-ip",
                "ipv4": "${non_iran_ip}"
            },
            "next": "manip"
        },
        {
            "name": "manip",
            "type": "IpManipulator",
            "settings": {
                "protoswap-tcp": ${protoswap_tcp},
                "protoswap-udp": ${protoswap_udp}
            },
            "next": "ipovsrc2"
        },
        {
            "name": "ipovsrc2",
            "type": "IpOverrider",
            "settings": {
                "direction": "down",
                "mode": "source-ip",
                "ipv4": "${ip_plus1}"
            },
            "next": "ipovdest2"
        },
        {
            "name": "ipovdest2",
            "type": "IpOverrider",
            "settings": {
                "direction": "down",
                "mode": "dest-ip",
                "ipv4": "${private_ip}"
            },
            "next": "rd"
        },
        {
            "name": "rd",
            "type": "RawSocket",
            "settings": {
                "capture-filter-mode": "source-ip",
                "capture-ip": "${non_iran_ip}"
            }
        }
    ]
}
EOF

    if [ $? -eq 0 ]; then
        add_to_core_json "$config_name"
        print_success "V3 Server configuration created: ${config_name}.json"
        print_info "- Protoswap TCP: ${protoswap_tcp}, UDP: ${protoswap_udp}"
    else
        print_error "Failed to create V3 server configuration"
        exit 1
    fi
}

# Create V3 Client Waterwall Config (Non-Iran side)
create_waterwall_v3_client_config() {
    local config_name="$1"
    local non_iran_ip="$2"
    local iran_ip="$3"
    local private_ip="$4"
    local protoswap_tcp="$5"
    local custom_udp="$6"

    # Use custom UDP protocol if provided, otherwise calculate as tcp + 1
    local protoswap_udp=""
    if [ -n "$custom_udp" ]; then
        protoswap_udp="$custom_udp"
    else
        protoswap_udp=$((protoswap_tcp + 1))
    fi

    # Validation: Protocols must be different
    if [ "$protoswap_tcp" -eq "$protoswap_udp" ]; then
        print_error "Error: TCP Protocol ($protoswap_tcp) and UDP Protocol ($protoswap_udp) CANNOT be the same."
        print_error "Traffic would be indistinguishable. Please use different values."
        exit 1
    fi

    # Calculate PRIVATE_IP+1 for ipovsrc2
    IFS='.' read -r ip1 ip2 ip3 ip4 <<< "$private_ip"
    local ip_plus1="$ip1.$ip2.$ip3.$((ip4+1))"

    cat << EOF > "${config_name}.json"
{
    "name": "${config_name}",
    "nodes": [
        {
            "name": "rd",
            "type": "RawSocket",
            "settings": {
                "capture-filter-mode": "source-ip",
                "capture-ip": "${iran_ip}"
            },
            "next": "ipovsrc"
        },
        {
            "name": "ipovsrc",
            "type": "IpOverrider",
            "settings": {
                "direction": "down",
                "mode": "source-ip",
                "ipv4": "${non_iran_ip}"
            },
            "next": "ipovdest"
        },
        {
            "name": "ipovdest",
            "type": "IpOverrider",
            "settings": {
                "direction": "down",
                "mode": "dest-ip",
                "ipv4": "${iran_ip}"
            },
            "next": "manip"
        },
        {
            "name": "manip",
            "type": "IpManipulator",
            "settings": {
                "protoswap-tcp": ${protoswap_tcp},
                "protoswap-udp": ${protoswap_udp}
            },
            "next": "ipovsrc2"
        },
        {
            "name": "ipovsrc2",
            "type": "IpOverrider",
            "settings": {
                "direction": "up",
                "mode": "source-ip",
                "ipv4": "${ip_plus1}"
            },
            "next": "ipovdest2"
        },
        {
            "name": "ipovdest2",
            "type": "IpOverrider",
            "settings": {
                "direction": "up",
                "mode": "dest-ip",
                "ipv4": "${private_ip}"
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
        add_to_core_json "$config_name"
        print_success "V3 Client configuration created: ${config_name}.json"
        print_info "- Protoswap TCP: ${protoswap_tcp}, UDP: ${protoswap_udp}"
    else
        print_error "Failed to create V3 client configuration"
        exit 1
    fi
}

# Download and install Nodepass binary to /usr/local/bin
install_nodepass() {
    local version="${NODEPASS_VERSION:-v1.15.0}"
    
    # Check if already installed
    if command -v nodepass &>/dev/null; then
        print_info "Nodepass already installed at $(which nodepass)"
        return 0
    fi
    
    print_info "Installing Nodepass ${version}..."
    
    cd /tmp
    rm -f nodepass nodepass_*.tar.gz
    
    local version_num="${version#v}"  # Remove 'v' prefix
    wget --inet4-only -q -O nodepass.tar.gz "https://github.com/NodePassProject/nodepass/releases/download/${version}/nodepass_${version_num}_linux_amd64.tar.gz"
    
    tar -xzf nodepass.tar.gz
    chmod +x nodepass
    mv nodepass /usr/local/bin/nodepass
    rm -f nodepass.tar.gz README.md LICENSE
    
    print_success "Nodepass installed to /usr/local/bin/nodepass"
}


# Display banner
show_banner() {
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════════╗
║                    Waterwall V2 + Nodepass Configuration                     ║
║                        TLS Tunnel with Proxy Protocol                        ║
║                                v1.0.0                                        ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
}

show_usage() {
    echo "Waterwall V2 + Nodepass - Complete Tunnel Solution"
    echo ""
    echo "Usage:"
    echo "  Server: $0 server [options]"
    echo "  Client: $0 client [options]"
    echo ""
    echo "Server Options:"
    echo "  -n,  --name            Configuration name"
    echo "  -ep, --external-port   External port for incoming connections"
    echo "  -ni, --non-iran-ip     Non-Iran server IP (Sweden/etc)"
    echo "  -ii, --iran-ip         Iran server IP"
    echo "  -pi, --private-ip      Private network IP (e.g., 30.6.0.1)"
    echo "  -wp, --waterwall-port  Waterwall internal port"
    echo "  -pt, --protocol        Protocol number for waterwall"
    echo "  -pu, --udp-protocol    UDP Protocol number (default: tcp + 1)"
    echo "  -np, --nodepass-port   Nodepass tunnel port"
    echo "  -tp, --target-port     Target port for forwarded traffic"
    echo "  -ps, --password        Nodepass password"
    echo "  -g,  --gaming          Enable gaming mode (low-latency profile)"
    echo ""
    echo "Client Options:"
    echo "  -n,  --name            Configuration name"
    echo "  -ni, --non-iran-ip     Non-Iran server IP (Sweden/etc)"
    echo "  -ii, --iran-ip         Iran server IP"
    echo "  -pi, --private-ip      Private network IP (e.g., 30.6.0.1)"
    echo "  -pt, --protocol        Protocol number for waterwall"
    echo "  -pu, --udp-protocol    UDP Protocol number (default: tcp + 1)"
    echo "  -np, --nodepass-port   Nodepass server's tunnel port"
    echo "  -lp, --local-port      Local port for apps to connect"
    echo "  -ps, --password        Nodepass password"
    echo "  -g,  --gaming          Enable gaming mode (low-latency profile)"
    echo ""
    echo "Examples:"
    echo "  Server (External 443 -> Waterwall -> Nodepass 5009 -> Target 10010):"
    echo "    $0 server -n sweden -ep 443 -ni 1.2.3.4 -ii 5.6.7.8 \\"
    echo "              -pi 30.5.0.1 -pt 26 -np 5009 -tp 10010 -ps mypassword"
    echo ""
    echo "  Server with gaming mode (low-latency):"
    echo "    $0 server -n gameserver -ep 443 -ni 1.2.3.4 -ii 5.6.7.8 \\"
    echo "              -pi 30.5.0.1 -pt 26 -np 5009 -tp 10010 -ps mypassword --gaming"
    echo ""
    echo "  Client (App -> Local 18081 -> Nodepass -> Waterwall -> Internet):"
    echo "    $0 client -n iran -ni 1.2.3.4 -ii 5.6.7.8 \\"
    echo "              -pi 30.5.0.1 -pt 26 -np 5009 -lp 18081 -ps mypassword"
}

# Parse server arguments
parse_server_args() {
    local name=""
    local external_port=""
    local non_iran_ip=""
    local iran_ip=""
    local private_ip=""
    local protocol=""
    local nodepass_port=""
    local target_port=""
    local password=""
    local gaming="false"
    local udp_protocol=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--name)
                name="$2"
                shift 2
                ;;
            -ep|--external-port)
                external_port="$2"
                shift 2
                ;;
            -ni|--non-iran-ip)
                non_iran_ip="$2"
                shift 2
                ;;
            -ii|--iran-ip)
                iran_ip="$2"
                shift 2
                ;;
            -pi|--private-ip)
                private_ip="$2"
                shift 2
                ;;
            -pt|--protocol)
                protocol="$2"
                shift 2
                ;;
            -np|--nodepass-port)
                nodepass_port="$2"
                shift 2
                ;;
            -tp|--target-port)
                target_port="$2"
                shift 2
                ;;
            -ps|--password)
                password="$2"
                shift 2
                ;;
            -g|--gaming)
                gaming="true"
                shift
                ;;
            -pu|--udp-protocol)
                udp_protocol="$2"
                shift 2
                ;;
            "")
                # Skip empty arguments (caused by trailing whitespace in multiline commands)
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    # Validate required parameters
    if [ -z "$name" ] || [ -z "$external_port" ] || [ -z "$non_iran_ip" ] || [ -z "$iran_ip" ] || \
       [ -z "$private_ip" ] || [ -z "$protocol" ] || \
       [ -z "$nodepass_port" ] || [ -z "$target_port" ] || [ -z "$password" ]; then
        print_error "Missing required server parameters"
        show_usage
        exit 1
    fi

    create_server "$name" "$external_port" "$non_iran_ip" "$iran_ip" "$private_ip" \
                  "$protocol" "$nodepass_port" "$target_port" "$password" "$gaming" "$udp_protocol"
}

# Parse client arguments
parse_client_args() {
    local name=""
    local non_iran_ip=""
    local iran_ip=""
    local private_ip=""
    local protocol=""
    local nodepass_port=""
    local local_port=""
    local password=""
    local gaming="false"
    local udp_protocol=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--name)
                name="$2"
                shift 2
                ;;
            -ni|--non-iran-ip)
                non_iran_ip="$2"
                shift 2
                ;;
            -ii|--iran-ip)
                iran_ip="$2"
                shift 2
                ;;
            -pi|--private-ip)
                private_ip="$2"
                shift 2
                ;;
            -pt|--protocol)
                protocol="$2"
                shift 2
                ;;
            -np|--nodepass-port)
                nodepass_port="$2"
                shift 2
                ;;
            -lp|--local-port)
                local_port="$2"
                shift 2
                ;;
            -ps|--password)
                password="$2"
                shift 2
                ;;
            -g|--gaming)
                gaming="true"
                shift
                ;;
            -pu|--udp-protocol)
                udp_protocol="$2"
                shift 2
                ;;
            "")
                # Skip empty arguments (caused by trailing whitespace in multiline commands)
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    # Validate required parameters
    if [ -z "$name" ] || [ -z "$non_iran_ip" ] || [ -z "$iran_ip" ] || [ -z "$private_ip" ] || \
       [ -z "$protocol" ] || [ -z "$nodepass_port" ] || \
       [ -z "$local_port" ] || [ -z "$password" ]; then
        print_error "Missing required client parameters"
        show_usage
        exit 1
    fi

    create_client "$name" "$non_iran_ip" "$iran_ip" "$private_ip" \
                  "$protocol" "$nodepass_port" "$local_port" "$password" "$gaming" "$udp_protocol"
}

# Create server configuration
create_server() {
    local name="$1"
    local external_port="$2"
    local non_iran_ip="$3"
    local iran_ip="$4"
    local private_ip="$5"
    local protocol="$6"
    local nodepass_port="$7"
    local target_port="$8"
    local password="$9"
    local gaming="${10:-false}"
    local udp_protocol="${11:-}"

    # Calculate private IP + 1 for TUN device
    IFS='.' read -r ip1 ip2 ip3 ip4 <<< "$private_ip"
    local private_ip_plus1="$ip1.$ip2.$ip3.$((ip4+1))"

    print_info "Setting up Waterwall V2 + Nodepass Server: $name"
    [ "$gaming" = "true" ] && print_info "Gaming mode: ENABLED (low-latency profile)"
    echo ""

    # Step 1: Create Waterwall V3 configuration (with UDP support)
    print_info "Step 1/2: Creating Waterwall V3 tunnel..."
    mkdir -p /root/tunnel
    cd /root/tunnel
    create_waterwall_v3_server_config "$name" "$non_iran_ip" "$iran_ip" "$private_ip" "$protocol" "$udp_protocol"

    # Step 2: Create Nodepass server configuration
    print_info "Step 2/2: Creating Nodepass tunnel server..."
    
    # Install nodepass binary if not present
    install_nodepass

    # Build nodepass URL parameters
    local mode="1"  # server mode
    local tls="1"
    local proxy="1"
    local log="1"
    local max="16384"
    local rate="0"
    local slot="20000"
    local min="256"
    
    # Gaming mode: low-latency profile
    if [ "$gaming" = "true" ]; then
        max="4096"
        slot="3000"
    fi
    
    local nodepass_url="server://${password}@0.0.0.0:${nodepass_port}/0.0.0.0:${target_port}?mode=${mode}&tls=${tls}&proxy=${proxy}&log=${log}&max=${max}&rate=${rate}&slot=${slot}&min=${min}"
    
    # Create systemd service for nodepass
    local service_file="/etc/systemd/system/nodepass-${name}.service"
    cat << EOF > "$service_file"
[Unit]
Description=Nodepass Server - ${name}
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/nodepass "${nodepass_url}"
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable "nodepass-${name}"
    systemctl restart "nodepass-${name}"

    # Verify and display status
    sleep 2
    echo ""
    print_success "Server setup completed!"
    echo ""
    print_info "Configuration summary:"
    print_info "  External port: $external_port"
    print_info "  Private network: $private_ip (TUN: $private_ip_plus1)"
    print_info "  Nodepass tunnel: ${private_ip_plus1}:${nodepass_port}"
    print_info "  Target port: $target_port"
    echo ""
    print_info "Traffic flow:"
    print_info "  Internet:$external_port -> Waterwall V2 -> Nodepass:$nodepass_port -> :$target_port"
    echo ""
    print_info "Service status:"
    pgrep -f "Waterwall" >/dev/null && echo "  ✅ Waterwall: Running" || echo "  ❌ Waterwall: Not running"
    systemctl is-active "nodepass-${name}" >/dev/null 2>&1 && echo "  ✅ Nodepass: Running" || echo "  ❌ Nodepass: Not running"
}

# Create client configuration
create_client() {
    local name="$1"
    local non_iran_ip="$2"
    local iran_ip="$3"
    local private_ip="$4"
    local protocol="$5"
    local nodepass_port="$6"
    local local_port="$7"
    local password="$8"
    local gaming="${9:-false}"
    local udp_protocol="${10:-}"

    # Calculate private IP + 1 for nodepass server connection
    IFS='.' read -r ip1 ip2 ip3 ip4 <<< "$private_ip"
    local nodepass_server_ip="$ip1.$ip2.$ip3.$((ip4+1))"

    print_info "Setting up Waterwall V2 + Nodepass Client: $name"
    [ "$gaming" = "true" ] && print_info "Gaming mode: ENABLED (low-latency profile)"
    echo ""

    # Step 1: Create Waterwall V3 configuration (with UDP support)
    print_info "Step 1/2: Creating Waterwall V3 tunnel..."
    mkdir -p /root/tunnel
    cd /root/tunnel
    create_waterwall_v3_client_config "$name" "$non_iran_ip" "$iran_ip" "$private_ip" "$protocol" "$udp_protocol"

    # Step 2: Create Nodepass client configuration
    print_info "Step 2/2: Creating Nodepass tunnel client..."
    
    # Install nodepass binary if not present
    install_nodepass

    # Build nodepass URL parameters
    local mode="1"  # tcp mode
    local tls="1"
    local proxy="1"
    local log="1"
    local max="16384"
    local rate="0"
    local slot="20000"
    local min="256"
    
    # Gaming mode: low-latency profile
    if [ "$gaming" = "true" ]; then
        max="4096"
        slot="2000"
    fi
    
    local nodepass_url="client://${password}@${nodepass_server_ip}:${nodepass_port}/127.0.0.1:${local_port}?mode=${mode}&tls=${tls}&proxy=${proxy}&log=${log}&max=${max}&rate=${rate}&slot=${slot}&min=${min}"
    
    # Create systemd service for nodepass
    local service_file="/etc/systemd/system/nodepass-${name}.service"
    cat << EOF > "$service_file"
[Unit]
Description=Nodepass Client - ${name}
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/nodepass "${nodepass_url}"
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable "nodepass-${name}"
    systemctl restart "nodepass-${name}"

    # Verify and display status
    sleep 2
    echo ""
    print_success "Client setup completed!"
    echo ""
    print_info "Configuration summary:"
    print_info "  Private network: $private_ip"
    print_info "  Nodepass server: ${nodepass_server_ip}:${nodepass_port}"
    print_info "  Local port: 127.0.0.1:$local_port"
    echo ""
    print_info "Traffic flow:"
    print_info "  App -> 127.0.0.1:$local_port -> Nodepass -> ${nodepass_server_ip}:${nodepass_port} -> Waterwall V2 -> Internet"
    echo ""
    print_info "Service status:"
    pgrep -f "Waterwall" >/dev/null && echo "  ✅ Waterwall: Running" || echo "  ❌ Waterwall: Not running"
    systemctl is-active "nodepass-${name}" >/dev/null 2>&1 && echo "  ✅ Nodepass: Running" || echo "  ❌ Nodepass: Not running"
    echo ""
    print_info "Your application should connect to: 127.0.0.1:${local_port}"
}

# Main script logic
main() {
    show_banner

    if [ $# -lt 1 ]; then
        show_usage
        exit 1
    fi

    local type="$1"
    shift

    case "$type" in
        "server")
            parse_server_args "$@"
            ;;
        "client")
            parse_client_args "$@"
            ;;
        "-h"|"--help"|"help")
            show_usage
            ;;
        *)
            print_error "Invalid type: $type. Must be 'server' or 'client'"
            show_usage
            exit 1
            ;;
    esac
}

# Run the main function
main "$@"
