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
    echo "  -np, --nodepass-port   Nodepass tunnel port"
    echo "  -tp, --target-port     Target port for forwarded traffic"
    echo "  -ps, --password        Nodepass password"
    echo ""
    echo "Client Options:"
    echo "  -n,  --name            Configuration name"
    echo "  -ni, --non-iran-ip     Non-Iran server IP (Sweden/etc)"
    echo "  -ii, --iran-ip         Iran server IP"
    echo "  -pi, --private-ip      Private network IP (e.g., 30.6.0.1)"
    echo "  -wp, --waterwall-port  Waterwall internal port"
    echo "  -pt, --protocol        Protocol number for waterwall"
    echo "  -np, --nodepass-port   Nodepass server's tunnel port"
    echo "  -lp, --local-port      Local port for apps to connect"
    echo "  -ps, --password        Nodepass password"
    echo ""
    echo "Examples:"
    echo "  Server (External 443 -> Waterwall 30111 -> Nodepass 5009 -> Target 10010):"
    echo "    $0 server -n sweden -ep 443 -ni 87.121.105.148 -ii 213.176.7.229 \\"
    echo "              -pi 30.5.0.1 -wp 30111 -pt 26 -np 5009 -tp 10010 -ps mypassword"
    echo ""
    echo "  Client (App -> Local 18081 -> Nodepass -> Waterwall -> Internet):"
    echo "    $0 client -n iran -ni 87.121.105.148 -ii 213.176.7.229 \\"
    echo "              -pi 30.5.0.1 -wp 30111 -pt 26 -np 5009 -lp 18081 -ps mypassword"
}

# Parse server arguments
parse_server_args() {
    local name=""
    local external_port=""
    local non_iran_ip=""
    local iran_ip=""
    local private_ip=""
    local waterwall_port=""
    local protocol=""
    local nodepass_port=""
    local target_port=""
    local password=""

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
            -wp|--waterwall-port)
                waterwall_port="$2"
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
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    # Validate required parameters
    if [ -z "$name" ] || [ -z "$external_port" ] || [ -z "$non_iran_ip" ] || [ -z "$iran_ip" ] || \
       [ -z "$private_ip" ] || [ -z "$waterwall_port" ] || [ -z "$protocol" ] || \
       [ -z "$nodepass_port" ] || [ -z "$target_port" ] || [ -z "$password" ]; then
        print_error "Missing required server parameters"
        show_usage
        exit 1
    fi

    create_server "$name" "$external_port" "$non_iran_ip" "$iran_ip" "$private_ip" \
                  "$waterwall_port" "$protocol" "$nodepass_port" "$target_port" "$password"
}

# Parse client arguments
parse_client_args() {
    local name=""
    local non_iran_ip=""
    local iran_ip=""
    local private_ip=""
    local waterwall_port=""
    local protocol=""
    local nodepass_port=""
    local local_port=""
    local password=""

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
            -wp|--waterwall-port)
                waterwall_port="$2"
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
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    # Validate required parameters
    if [ -z "$name" ] || [ -z "$non_iran_ip" ] || [ -z "$iran_ip" ] || [ -z "$private_ip" ] || \
       [ -z "$waterwall_port" ] || [ -z "$protocol" ] || [ -z "$nodepass_port" ] || \
       [ -z "$local_port" ] || [ -z "$password" ]; then
        print_error "Missing required client parameters"
        show_usage
        exit 1
    fi

    create_client "$name" "$non_iran_ip" "$iran_ip" "$private_ip" "$waterwall_port" \
                  "$protocol" "$nodepass_port" "$local_port" "$password"
}

# Create server configuration
create_server() {
    local name="$1"
    local external_port="$2"
    local non_iran_ip="$3"
    local iran_ip="$4"
    local private_ip="$5"
    local waterwall_port="$6"
    local protocol="$7"
    local nodepass_port="$8"
    local target_port="$9"
    local password="${10}"

    # Calculate private IP + 1 for TUN device
    IFS='.' read -r ip1 ip2 ip3 ip4 <<< "$private_ip"
    local private_ip_plus1="$ip1.$ip2.$ip3.$((ip4+1))"

    print_info "Setting up Waterwall V2 + Nodepass Server: $name"
    echo ""

    # Step 1: Create Waterwall V2 configuration
    print_info "Step 1/2: Creating Waterwall V2 tunnel..."
    mkdir -p /root/tunnel
    cd /root/tunnel

    bash <(curl -4 -Ls https://raw.githubusercontent.com/EbadiDev/conf-gen/main/main.sh) v2 server "$name" --port "$external_port" "$non_iran_ip" "$iran_ip" "$private_ip" "$waterwall_port" "$protocol"

    # Step 2: Create Nodepass server configuration
    print_info "Step 2/2: Creating Nodepass tunnel server..."
    
    # Download nodepass script if not present
    if [ ! -f /root/nodepass.sh ]; then
        curl -4 -Ls https://raw.githubusercontent.com/EbadiDev/conf-gen/main/nodepass.sh -o /root/nodepass.sh
        chmod +x /root/nodepass.sh
    fi

    # Create Nodepass server: listens on private_ip+1 for tunnel, forwards to target
    /root/nodepass.sh server \
        --name "$name" \
        --pass "$password" \
        --tunnel-port "$nodepass_port" \
        --target-port "$target_port" \
        --bind "$private_ip_plus1" \
        --target-addr "0.0.0.0"

    # Verify and display status
    sleep 2
    echo ""
    print_success "Server setup completed!"
    echo ""
    print_info "Configuration summary:"
    print_info "  External port: $external_port"
    print_info "  Waterwall internal port: $waterwall_port"
    print_info "  Private network: $private_ip (TUN: $private_ip_plus1)"
    print_info "  Nodepass tunnel: ${private_ip_plus1}:${nodepass_port}"
    print_info "  Target port: $target_port"
    echo ""
    print_info "Traffic flow:"
    print_info "  Internet:$external_port -> Waterwall V2 -> Nodepass:$nodepass_port -> :$target_port"
    echo ""
    print_info "Service status:"
    systemctl is-active waterwall >/dev/null 2>&1 && echo "  ✅ Waterwall: Running" || echo "  ❌ Waterwall: Not running"
    systemctl is-active "nodepass-${name}" >/dev/null 2>&1 && echo "  ✅ Nodepass: Running" || echo "  ❌ Nodepass: Not running"
}

# Create client configuration
create_client() {
    local name="$1"
    local non_iran_ip="$2"
    local iran_ip="$3"
    local private_ip="$4"
    local waterwall_port="$5"
    local protocol="$6"
    local nodepass_port="$7"
    local local_port="$8"
    local password="$9"

    # Calculate private IP + 1 for nodepass server connection
    IFS='.' read -r ip1 ip2 ip3 ip4 <<< "$private_ip"
    local nodepass_server_ip="$ip1.$ip2.$ip3.$((ip4+1))"

    print_info "Setting up Waterwall V2 + Nodepass Client: $name"
    echo ""

    # Step 1: Create Waterwall V2 client configuration
    print_info "Step 1/2: Creating Waterwall V2 tunnel..."
    mkdir -p /root/tunnel
    cd /root/tunnel

    bash <(curl -4 -Ls https://raw.githubusercontent.com/EbadiDev/conf-gen/main/main.sh) v2 client "$name" "$non_iran_ip" "$iran_ip" "$private_ip" "$waterwall_port" "$protocol"

    # Step 2: Create Nodepass client configuration
    print_info "Step 2/2: Creating Nodepass tunnel client..."
    
    # Download nodepass script if not present
    if [ ! -f /root/nodepass.sh ]; then
        curl -4 -Ls https://raw.githubusercontent.com/EbadiDev/conf-gen/main/nodepass.sh -o /root/nodepass.sh
        chmod +x /root/nodepass.sh
    fi

    # Create Nodepass client: connects to server via private IP, forwards to local app port
    /root/nodepass.sh client \
        --name "$name" \
        --pass "$password" \
        --server "$nodepass_server_ip" \
        --server-port "$nodepass_port" \
        --local-port "$local_port"

    # Verify and display status
    sleep 2
    echo ""
    print_success "Client setup completed!"
    echo ""
    print_info "Configuration summary:"
    print_info "  Private network: $private_ip"
    print_info "  Nodepass server: ${nodepass_server_ip}:${nodepass_port}"
    print_info "  Waterwall port: $waterwall_port"
    print_info "  Local port: 127.0.0.1:$local_port"
    echo ""
    print_info "Traffic flow:"
    print_info "  App -> 127.0.0.1:$local_port -> Nodepass -> ${nodepass_server_ip}:${nodepass_port} -> Waterwall V2 -> Internet"
    echo ""
    print_info "Service status:"
    systemctl is-active waterwall >/dev/null 2>&1 && echo "  ✅ Waterwall: Running" || echo "  ❌ Waterwall: Not running"
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
