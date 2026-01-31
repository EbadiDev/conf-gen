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

# Install GOST using official script
install_gost() {
    if command -v gost &>/dev/null; then
        print_info "GOST already installed at $(which gost)"
        return 0
    fi
    
    print_info "Installing GOST..."
    bash <(curl -fsSL https://github.com/go-gost/gost/raw/master/install.sh) --install
    print_success "GOST installed"
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
    echo "  -go, --gost            GOST port range (e.g., 20000-30000) for port forwarding"
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
    echo "  -go, --gost            GOST port range (e.g., 20000-30000) - disables Nodepass proxy"
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
    local gost_range=""

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
            -go|--gost)
                gost_range="$2"
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
                  "$protocol" "$nodepass_port" "$target_port" "$password" "$gaming" "$udp_protocol" "$gost_range"
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
    local gost_range=""

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
            -go|--gost)
                gost_range="$2"
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
                  "$protocol" "$nodepass_port" "$local_port" "$password" "$gaming" "$udp_protocol" "$gost_range"
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
    # Build nodepass URL parameters
    local mode="1"
    local tls="1"
    local proxy="1"
    # When GOST is enabled, disable Nodepass proxy protocol to avoid double headers
    [ -n "$gost_range" ] && proxy="0"
    
    local log="info"
    local max="16384"
    local rate="0"
    local slot="20000"
    
    # Gaming mode: low-latency profile
    if [ "$gaming" = "true" ]; then
        max="4096"
        slot="3000"
    fi
    
    local nodepass_url="server://${password}@0.0.0.0:${nodepass_port}/0.0.0.0:${target_port}?mode=${mode}&tls=${tls}&proxy=${proxy}&max=${max}&rate=${rate}&slot=${slot}&log=${log}"
    
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

    # Step 3: Configure GOST if requested
    if [ -n "$gost_range" ]; then
        print_info "Step 3/3: Setting up GOST port forwarding ($gost_range -> $target_port)..."
        install_gost
        
        # Create systemd service for GOST
        local gost_service_file="/etc/systemd/system/gost-${name}.service"
        cat << EOF > "$gost_service_file"
[Unit]
Description=GOST Forwarder - ${name}
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/gost -L tcp://:${gost_range}/127.0.0.1:${target_port}?proxyprotocol=2&nodelay=true&keepalive=true
Restart=always
RestartSec=3
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable "gost-${name}"
        systemctl restart "gost-${name}"
        
        print_success "GOST service started!"
        echo "  Traffic flow (GOST): Internet:${gost_range} -> GOST -> Target:${target_port}"
        
        systemctl is-active "gost-${name}" >/dev/null 2>&1 && echo "  ✅ GOST: Running" || echo "  ❌ GOST: Not running"
    fi
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
    local gost_range="${11:-}"

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
    local proxy="1"
    # When GOST is enabled (signaled by -go), disable Nodepass proxy protocol
    [ -n "$gost_range" ] && proxy="0"

    local log="info"
    local rate="0"
    local slot="10000"
    local min="512"
    
    # Gaming mode: low-latency profile
    if [ "$gaming" = "true" ]; then
        slot="2000"
        min="256"
    fi
    
    local nodepass_url="client://${password}@${nodepass_server_ip}:${nodepass_port}/127.0.0.1:${local_port}?min=${min}&proxy=${proxy}&rate=${rate}&slot=${slot}&log=${log}"
    
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

# --- Service Management ---

get_service_list() {
    ls /etc/systemd/system/nodepass-*.service 2>/dev/null | sed 's/.*nodepass-\(.*\)\.service/\1/'
}

perform_restart() {
    local name="$1"
    print_info "Restarting services for '$name'..."
    systemctl restart "nodepass-$name" 2>/dev/null && echo "  ✅ Nodepass restarted" || echo "  ⚠️ Nodepass not found/failed"
    systemctl restart "gost-$name" 2>/dev/null && echo "  ✅ GOST restarted" || echo "  ⚠️ GOST not found (optional)"
    systemctl restart waterwall 2>/dev/null && echo "  ✅ Waterwall Service restarted" || echo "  ⚠️ Waterwall service not found (if manual, restart manually)"
}

perform_stop() {
    local name="$1"
    print_info "Stopping services for '$name'..."
    systemctl stop "nodepass-$name" 2>/dev/null
    systemctl stop "gost-$name" 2>/dev/null
    echo "  ✅ Services stopped"
}

perform_remove() {
    local name="$1"
    echo
    read -p "⚠️  Are you sure you want to COMPLETELY REMOVE '$name' (Services + Configs)? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then echo "Aborted."; return; fi

    perform_stop "$name"
    
    # Disable and remove units
    systemctl disable "nodepass-$name" "gost-$name" 2>/dev/null
    rm -f "/etc/systemd/system/nodepass-$name.service"
    rm -f "/etc/systemd/system/gost-$name.service"
    systemctl daemon-reload
    echo "  ✅ Systemd services removed"
    
    # Remove Waterwall Config
    if [ -f "/root/tunnel/$name.json" ]; then
        rm -f "/root/tunnel/$name.json"
        echo "  ✅ Removed /root/tunnel/$name.json"
        
        # Remove from core.json
        if [ -f "/root/tunnel/core.json" ] && command -v jq >/dev/null; then
             jq --arg n "$name.json" '.configs -= [$n]' /root/tunnel/core.json > /tmp/core.json.tmp && mv /tmp/core.json.tmp /root/tunnel/core.json
             echo "  ✅ Removed from core.json"
        fi
    fi

    print_success "Removal complete for '$name'"
    print_warning "Note: Waterwall process was NOT restarted. Restart it via menu to apply removals."
}

perform_logs() {
    local name="$1"
    print_info "Tailing logs for '$name' (Ctrl+C to exit)..."
    journalctl -u "nodepass-$name" -u "gost-$name" -f -n 20
}

interactive_menu() {
    echo ""
    print_info "Interactive Service Manager"
    echo "Scanning for services..."
    services=($(get_service_list))
    
    if [ ${#services[@]} -eq 0 ]; then
        echo "  No services found."
        echo ""
        echo "Run '$0 server' or '$0 client' to create one."
        exit 0
    fi
    
    for i in "${!services[@]}"; do
        echo "  $((i+1)). ${services[$i]}"
    done
    echo ""
    read -p "Select a service number: " svc_idx
    svc_idx=$((svc_idx-1))
    
    if [ -z "${services[$svc_idx]}" ]; then
        print_error "Invalid selection."
        exit 1
    fi
    
    local name="${services[$svc_idx]}"
    echo ""
    print_info "Action for '$name':"
    echo "  1. Logs (Live)"
    echo "  2. Restart"
    echo "  3. Stop"
    echo "  4. REMOVE (Delete Config & Service)"
    echo "  5. Cancel"
    echo ""
    read -p "Select action: " act_idx
    
    case "$act_idx" in
        1) perform_logs "$name" ;;
        2) perform_restart "$name" ;;
        3) perform_stop "$name" ;;
        4) perform_remove "$name" ;;
        *) echo "Cancelled." ;;
    esac
}

# Main script logic
main() {
    show_banner

    if [ $# -lt 1 ]; then
        interactive_menu
        exit 0
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
