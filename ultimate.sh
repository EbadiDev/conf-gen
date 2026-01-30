#!/bin/bash

# Ultimate Configuration Generator
# Combines Waterwall V2 + Rathole with GOST for complete tunnel solution

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[ULTIMATE]${NC} $1"
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
║                        Ultimate Configuration Generator                      ║
║                       Waterwall V2 + Rathole + GOST                         ║
║                                v1.0.0                                        ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
}

show_usage() {
    echo "Ultimate Configuration Generator - Complete Tunnel Solution"
    echo ""
    echo "Usage:"
    echo "  Server: $0 server --name <name> --port-range <start-end> --non-iran-ip <ip> --iran-ip <ip> --private-ip <ip> --rathole-port <port> --protocol <num> --token <token> --gost-range <start-end> --gost-port <port> [--password <pass>] [--service <name>]"
    echo "  Client: $0 client --name <name> --non-iran-ip <ip> --iran-ip <ip> --private-ip <ip> --waterwall-port <port> --protocol <num> --app-port <port> --token <token> --gost-port <port> [--password <pass>] [--service <name>]"
    echo ""
    echo "Short options:"
    echo "  -n, --name           Configuration name"
    echo "  -pr, --port-range    External port range (e.g., 801-802) - server only"
    echo "  -ni, --non-iran-ip   Non-Iran server IP"
    echo "  -ii, --iran-ip       Iran server IP" 
    echo "  -pi, --private-ip    Private network IP (e.g., 30.6.0.1)"
    echo "  -rp, --rathole-port  Port for rathole communication - server only"
    echo "  -wp, --waterwall-port Waterwall internal port - client only"
    echo "  -p, --protocol       Protocol number for waterwall"
    echo "  -ap, --app-port      Application port - client only"
    echo "  -t, --token          Rathole authentication token"
    echo "  -gr, --gost-range    GOST port range (e.g., 1200-1299) - server only"
    echo "  -gp, --gost-port     GOST port (server: bind port, client: local port)"
    echo "  -ps, --password      Optional Shadowsocks password"
    echo "  -s, --service        Optional service name"
    echo ""
    echo "Examples:"
    echo "  Server:"
    echo "    $0 server -n gehetz -pr 801-802 -ni 203.0.113.50 -ii 198.51.100.20 -pi 30.6.0.1 -rp 800 -p 27 -t strongpass -gr 1200-1299 -gp 30121"
    echo "    $0 server --name gehetz --port-range 801-802 --non-iran-ip 203.0.113.50 --iran-ip 198.51.100.20 --private-ip 30.6.0.1 --rathole-port 800 --protocol 27 --token strongpass --gost-range 1200-1299 --gost-port 30121 --password mySSpass"
    echo ""
    echo "  Client:"
    echo "    $0 client -n mahannet -ni 203.0.113.50 -ii 198.51.100.20 -pi 30.6.0.1 -wp 30122 -p 27 -ap 800 -t strongpass -gp 30120"
    echo "    $0 client --name mahannet --non-iran-ip 203.0.113.50 --iran-ip 198.51.100.20 --private-ip 30.6.0.1 --waterwall-port 30122 --protocol 27 --app-port 800 --token strongpass --gost-port 30120 --password mySSpass"
}

# Function to parse command line arguments
parse_args() {
    local config_type="$1"
    shift
    
    # Initialize variables
    name=""
    port_range=""
    non_iran_ip=""
    iran_ip=""
    private_ip=""
    rathole_port=""
    waterwall_port=""
    protocol=""
    app_port=""
    token=""
    gost_range=""
    gost_port=""
    ss_password="strongpass"
    service_name=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--name)
                name="$2"
                shift 2
                ;;
            -pr|--port-range)
                port_range="$2"
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
            -rp|--rathole-port)
                rathole_port="$2"
                shift 2
                ;;
            -wp|--waterwall-port)
                waterwall_port="$2"
                shift 2
                ;;
            -p|--protocol)
                protocol="$2"
                shift 2
                ;;
            -ap|--app-port)
                app_port="$2"
                shift 2
                ;;
            -t|--token)
                token="$2"
                shift 2
                ;;
            -gr|--gost-range)
                gost_range="$2"
                shift 2
                ;;
            -gp|--gost-port)
                gost_port="$2"
                shift 2
                ;;
            -ps|--password)
                ss_password="$2"
                shift 2
                ;;
            -s|--service)
                service_name="$2"
                shift 2
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Validate required parameters based on config type
    if [ "$config_type" = "server" ]; then
        if [ -z "$name" ] || [ -z "$port_range" ] || [ -z "$non_iran_ip" ] || [ -z "$iran_ip" ] || [ -z "$private_ip" ] || [ -z "$rathole_port" ] || [ -z "$protocol" ] || [ -z "$token" ] || [ -z "$gost_range" ] || [ -z "$gost_port" ]; then
            print_error "Missing required server parameters"
            show_usage
            exit 1
        fi
        
        # Parse port ranges
        if [[ "$port_range" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            external_port_start="${BASH_REMATCH[1]}"
            external_port_end="${BASH_REMATCH[2]}"
        else
            print_error "Invalid port range format: $port_range (use format: 801-802)"
            exit 1
        fi
        
        if [[ "$gost_range" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            gost_port_start="${BASH_REMATCH[1]}"
            gost_port_end="${BASH_REMATCH[2]}"
        else
            print_error "Invalid GOST range format: $gost_range (use format: 1200-1299)"
            exit 1
        fi
        
        # Set default service name
        [ -z "$service_name" ] && service_name="$token"
        
        # Call server function
        create_ultimate_server "$name" "$external_port_start" "$external_port_end" "$non_iran_ip" "$iran_ip" "$private_ip" "$rathole_port" "$protocol" "$token" "$gost_port_start" "$gost_port_end" "$ss_password" "$service_name" "$gost_port"
        
    elif [ "$config_type" = "client" ]; then
        if [ -z "$name" ] || [ -z "$non_iran_ip" ] || [ -z "$iran_ip" ] || [ -z "$private_ip" ] || [ -z "$waterwall_port" ] || [ -z "$protocol" ] || [ -z "$app_port" ] || [ -z "$token" ] || [ -z "$gost_port" ]; then
            print_error "Missing required client parameters"
            show_usage
            exit 1
        fi
        
        # Set default service name
        [ -z "$service_name" ] && service_name="$token"
        
        # Call client function
        create_ultimate_client "$name" "$non_iran_ip" "$iran_ip" "$private_ip" "$waterwall_port" "$protocol" "$app_port" "$token" "$gost_port" "$ss_password" "$service_name"
    fi
}
create_ultimate_server() {
    local name="$1"
    local external_port_start="$2"
    local external_port_end="$3"
    local non_iran_ip="$4"
    local iran_ip="$5"
    local private_ip="$6"
    local rathole_port="$7"
    local protocol="$8"
    local rathole_token="$9"
    local gost_port_start="${10}"
    local gost_port_end="${11}"
    local ss_password="${12:-strongpass}"
    local service_name="${13:-$rathole_token}"
    local gost_port="${14}"

    print_info "Setting up Ultimate Server configuration: $name"
    
    # Step 1: Create Waterwall V2 configuration
    print_info "Step 1/3: Creating Waterwall V2 tunnel..."
    cd /root/tunnel
    bash <(curl -4 -Ls https://raw.githubusercontent.com/EbadiDev/conf-gen/main/main.sh) v2 server "$name" "$external_port_start" "$external_port_end" "$non_iran_ip" "$iran_ip" "$private_ip" "$rathole_port" "$protocol"
    
    # Step 2: Create Rathole configuration  
    print_info "Step 2/3: Creating Rathole server with GOST..."
    cd /root/rathole
    bash <(curl -4 -Ls https://raw.githubusercontent.com/EbadiDev/conf-gen/main/rathole.sh) server "$name" "$rathole_port" "$rathole_token" "${gost_port_start}-${gost_port_end}" tcp true gost "$ss_password" "$gost_port" "$service_name"
    
    # Step 3: Verify and display status
    print_info "Step 3/3: Verifying services..."
    sleep 3
    
    print_success "Ultimate Server setup completed!"
    print_info "Configuration summary:"
    print_info "- Waterwall V2: External ports ${external_port_start}-${external_port_end} -> Internal port ${rathole_port}"
    print_info "- Private network: ${private_ip}"
    print_info "- Rathole: Port ${rathole_port} -> GOST ports ${gost_port_start}-${gost_port_end}"
    print_info ""
    print_info "Service status check:"
    systemctl is-active waterwall >/dev/null 2>&1 && echo "✅ Waterwall: Running" || echo "❌ Waterwall: Not running"
    systemctl is-active "ratholes@${name}" >/dev/null 2>&1 && echo "✅ Rathole Server: Running" || echo "❌ Rathole Server: Not running" 
    systemctl is-active "gost-${name}" >/dev/null 2>&1 && echo "✅ GOST: Running" || echo "❌ GOST: Not running"
}

# Function to create ultimate client configuration
create_ultimate_client() {
    local name="$1"
    local non_iran_ip="$2" 
    local iran_ip="$3"
    local private_ip="$4"
    local waterwall_port="$5"
    local protocol="$6"
    local app_port="$7"
    local rathole_token="$8"
    local gost_local_port="$9"
    local ss_password="${10:-strongpass}"
    local service_name="${11:-$rathole_token}"

    # Calculate private IP + 1 for rathole connection
    IFS='.' read -r ip1 ip2 ip3 ip4 <<< "$private_ip"
    local rathole_server_ip="$ip1.$ip2.$ip3.$((ip4+1))"

    print_info "Setting up Ultimate Client configuration: $name"
    
    # Step 1: Create Waterwall V2 configuration
    print_info "Step 1/4: Creating Waterwall V2 tunnel..."
    cd /root/tunnel
    bash <(curl -4 -Ls https://raw.githubusercontent.com/EbadiDev/conf-gen/main/main.sh) v2 client "$name" "$non_iran_ip" "$iran_ip" "$private_ip" "$waterwall_port" "$protocol" "$app_port"
    
    # Step 2: Create Rathole configuration
    print_info "Step 2/4: Creating Rathole client with GOST..."
    cd /root/rathole  
    bash <(curl -4 -Ls https://raw.githubusercontent.com/EbadiDev/conf-gen/main/rathole.sh) client "$name" "${rathole_server_ip}:${app_port}" "$rathole_token" "$gost_local_port" tcp true gost "$ss_password" "$gost_local_port" "$service_name"
    
    # Step 3: Fix rathole client config (add 127.0.0.1 to local_addr)
    print_info "Step 3/4: Fixing rathole client configuration..."
    local rathole_config="/etc/rathole/${name}_client.toml"
    if [ -f "$rathole_config" ]; then
        # Fix the local_addr to include 127.0.0.1
        sed -i "s/local_addr = \":${gost_local_port}\"/local_addr = \"127.0.0.1:${gost_local_port}\"/" "$rathole_config"
        print_success "Fixed rathole client local_addr configuration"
        
        # Restart rathole client service
        systemctl restart "ratholec@${name}"
        print_success "Restarted rathole client service"
    else
        print_warning "Rathole config not found at: $rathole_config"
    fi
    
    # Step 4: Verify and display status  
    print_info "Step 4/4: Verifying services..."
    sleep 3
    
    print_success "Ultimate Client setup completed!"
    print_info "Configuration summary:"
    print_info "- Waterwall V2: App port ${app_port} -> Private network ${private_ip}"
    print_info "- Rathole: Connects to ${rathole_server_ip}:${app_port} -> Local GOST port ${gost_local_port}"
    print_info "- Local application port: ${gost_local_port}"
    print_info ""
    print_info "Service status check:"
    systemctl is-active waterwall >/dev/null 2>&1 && echo "✅ Waterwall: Running" || echo "❌ Waterwall: Not running"
    systemctl is-active "ratholec@${name}" >/dev/null 2>&1 && echo "✅ Rathole Client: Running" || echo "❌ Rathole Client: Not running"
    systemctl is-active "gost-${name}" >/dev/null 2>&1 && echo "✅ GOST: Running" || echo "❌ GOST: Not running"
    
    print_info ""
    print_info "Test your setup:"
    print_info "  Your application should connect to: 127.0.0.1:${gost_local_port}"
}

# Main script logic
main() {
    show_banner
    
    if [ $# -lt 2 ]; then
        show_usage
        exit 1
    fi
    
    local type="$1"
    shift
    
    case "$type" in
        "server")
            parse_args "server" "$@"
            ;;
            
        "client")
            parse_args "client" "$@"
            ;;
            
        *)
            print_error "Invalid type: $type. Must be 'server' or 'client'"
            show_usage
            exit 1
            ;;
    esac
}

# Run the main function with all arguments
main "$@"