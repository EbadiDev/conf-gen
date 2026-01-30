#!/bin/bash

# Nodepass Tunnel Configuration Script
# Standalone script for Nodepass tunnel with TLS and Proxy Protocol support

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
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

# Nodepass version and download URL
NODEPASS_VERSION="${NODEPASS_VERSION:-1.15.0}"
NODEPASS_DOWNLOAD_URL="https://github.com/NodePassProject/nodepass/releases/download/v${NODEPASS_VERSION}/nodepass_${NODEPASS_VERSION}_linux_amd64.tar.gz"
NODEPASS_INSTALL_DIR="/root/nodepass"
NODEPASS_BIN="$NODEPASS_INSTALL_DIR/nodepass"
NODEPASS_SERVICE_DIR="/usr/lib/systemd/system"
NODEPASS_LOG="/var/log/nodepass.log"
NODEPASS_ERROR_LOG="/var/log/nodepass.error.log"

# Display banner
show_banner() {
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════════╗
║                         Nodepass Tunnel Manager                              ║
║                              v1.0.0                                          ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
}

# Install nodepass binary
install_nodepass() {
    print_info "Installing Nodepass v${NODEPASS_VERSION}..."
    
    # Create install directory
    mkdir -p "$NODEPASS_INSTALL_DIR"
    cd "$NODEPASS_INSTALL_DIR" || exit 1
    
    # Download and extract
    if ! wget --inet4-only -q "$NODEPASS_DOWNLOAD_URL" -O nodepass.tar.gz; then
        print_error "Failed to download Nodepass"
        return 1
    fi
    
    tar -xzf nodepass.tar.gz
    chmod +x nodepass
    rm -f nodepass.tar.gz README.md LICENSE 2>/dev/null
    
    if [ -x "$NODEPASS_BIN" ]; then
        print_success "Nodepass installed successfully at $NODEPASS_BIN"
        return 0
    else
        print_error "Nodepass installation failed"
        return 1
    fi
}

# Check if nodepass is installed
check_nodepass_installed() {
    if [ -x "$NODEPASS_BIN" ]; then
        return 0
    else
        return 1
    fi
}

# Open firewall ports
open_firewall_ports() {
    local port="$1"
    
    print_info "Opening firewall port: $port"
    
    # UFW (Ubuntu/Debian)
    if command -v ufw >/dev/null 2>&1; then
        ufw allow "$port" >/dev/null 2>&1
        print_info "UFW: Opened port $port"
        return
    fi
    
    # firewalld (CentOS/RHEL/Fedora)
    if command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port="$port/tcp" >/dev/null 2>&1
        firewall-cmd --permanent --add-port="$port/udp" >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
        print_info "firewalld: Opened port $port"
        return
    fi
    
    # iptables (Generic Linux)
    if command -v iptables >/dev/null 2>&1; then
        iptables -A INPUT -p tcp --dport "$port" -j ACCEPT >/dev/null 2>&1
        iptables -A INPUT -p udp --dport "$port" -j ACCEPT >/dev/null 2>&1
        print_info "iptables: Opened port $port"
        return
    fi
    
    print_warning "No supported firewall found. Please manually open port $port"
}

# Create systemd service for nodepass
_nodepass_write_service() {
    local service_name="$1"
    local nodepass_url="$2"
    
    local unit_path="$NODEPASS_SERVICE_DIR/nodepass-${service_name}.service"
    
    # Ensure systemd directory exists
    mkdir -p "$NODEPASS_SERVICE_DIR"
    
    cat > "$unit_path" <<EOF
[Unit]
Description=Nodepass Tunnel - ${service_name}
After=network.target
Wants=network.target

[Service]
Type=simple
WorkingDirectory=/root/
ExecStart=${NODEPASS_BIN} "${nodepass_url}"
Restart=always
RestartSec=5
LimitNOFILE=infinity

# Logging configuration
StandardOutput=append:${NODEPASS_LOG}
StandardError=append:${NODEPASS_ERROR_LOG}

# Log rotation
LogRateLimitIntervalSec=0
LogRateLimitBurst=0

[Install]
WantedBy=multi-user.target
EOF
    
    echo "$unit_path"
}

# Manage Nodepass service lifecycle
manage_nodepass_service() {
    local service_name="$1"
    
    # Validate nodepass binary exists
    if ! check_nodepass_installed; then
        print_warning "Nodepass not found, installing..."
        if ! install_nodepass; then
            print_error "Failed to install Nodepass. Please install manually."
            return 1
        fi
    fi
    
    systemctl daemon-reload
    systemctl enable "nodepass-${service_name}.service" >/dev/null 2>&1 || true
    if systemctl is-active --quiet "nodepass-${service_name}.service"; then
        systemctl restart "nodepass-${service_name}.service"
    else
        systemctl start "nodepass-${service_name}.service"
    fi
    
    print_success "Nodepass service 'nodepass-${service_name}' started"
}

# Remove existing Nodepass service
remove_nodepass_service() {
    local service_name="$1"
    local unit_path="$NODEPASS_SERVICE_DIR/nodepass-${service_name}.service"
    
    if [ -f "$unit_path" ]; then
        systemctl stop "nodepass-${service_name}.service" >/dev/null 2>&1 || true
        systemctl disable "nodepass-${service_name}.service" >/dev/null 2>&1 || true
        rm -f "$unit_path"
        systemctl daemon-reload
        print_info "Removed Nodepass service: ${service_name}"
    fi
}

# Build nodepass URL with options
# Mode: 0=auto, 1=tcp+udp (recommended)
# TLS: 0=plain, 1=TLS (recommended for server)
build_nodepass_url() {
    local type="$1"          # server or client
    local password="$2"
    local bind_addr="$3"
    local bind_port="$4"
    local target_addr="$5"
    local target_port="$6"
    
    # Default options (can be overridden via environment)
    local mode="${NODEPASS_MODE:-1}"
    local tls="${NODEPASS_TLS:-1}"
    local notcp="${NODEPASS_NOTCP:-0}"
    local noudp="${NODEPASS_NOUDP:-0}"
    local proxy="${NODEPASS_PROXY:-1}"
    local max="${NODEPASS_MAX:-8192}"
    local rate="${NODEPASS_RATE:-1000}"
    local slot="${NODEPASS_SLOT:-10000}"
    local min="${NODEPASS_MIN:-128}"
    local log_level="${NODEPASS_LOG_LEVEL:-info}"
    
    local url=""
    if [ "$type" = "server" ]; then
        # Server: server://password@bind:port/target:port?options
        url="server://${password}@${bind_addr}:${bind_port}/${target_addr}:${target_port}?mode=${mode}&tls=${tls}&notcp=${notcp}&noudp=${noudp}&proxy=${proxy}&max=${max}&rate=${rate}&slot=${slot}&log=${log_level}"
    else
        # Client: client://password@server:port/local:port?options
        url="client://${password}@${bind_addr}:${bind_port}/${target_addr}:${target_port}?min=${min}&notcp=${notcp}&noudp=${noudp}&proxy=${proxy}&rate=${rate}&slot=${slot}&log=${log_level}"
    fi
    
    echo "$url"
}

# Create Nodepass Server Configuration
create_nodepass_server_config() {
    local config_name="$1"
    local password="$2"
    local tunnel_port="$3"      # Port for tunnel connections from clients
    local target_port="$4"      # Port to forward traffic to (local app)
    local bind_addr="${5:-0.0.0.0}"
    local target_addr="${6:-0.0.0.0}"
    
    print_info "Creating Nodepass Server configuration: $config_name"
    
    local nodepass_url
    nodepass_url=$(build_nodepass_url "server" "$password" "$bind_addr" "$tunnel_port" "$target_addr" "$target_port")
    
    # Remove existing service and create new one
    remove_nodepass_service "$config_name"
    local unit_path
    unit_path=$(_nodepass_write_service "$config_name" "$nodepass_url")
    
    # Open firewall ports
    open_firewall_ports "$tunnel_port"
    open_firewall_ports "$target_port"
    
    print_success "Nodepass Server configuration created!"
    print_info "Service file: $unit_path"
    print_info "Tunnel port: $tunnel_port (clients connect here)"
    print_info "Target port: $target_port (traffic forwarded here)"
    print_info "Connection URL: $nodepass_url"
    
    echo "$unit_path"
}

# Create Nodepass Client Configuration
create_nodepass_client_config() {
    local config_name="$1"
    local password="$2"
    local server_ip="$3"        # Remote server IP
    local server_port="$4"      # Remote server tunnel port
    local local_addr="$5"       # Local address to forward to
    local local_port="$6"       # Local port to forward to (app port)
    
    print_info "Creating Nodepass Client configuration: $config_name"
    
    local nodepass_url
    nodepass_url=$(build_nodepass_url "client" "$password" "$server_ip" "$server_port" "$local_addr" "$local_port")
    
    # Remove existing service and create new one
    remove_nodepass_service "$config_name"
    local unit_path
    unit_path=$(_nodepass_write_service "$config_name" "$nodepass_url")
    
    print_success "Nodepass Client configuration created!"
    print_info "Service file: $unit_path"
    print_info "Server: ${server_ip}:${server_port}"
    print_info "Local forward: ${local_addr}:${local_port}"
    print_info "Connection URL: $nodepass_url"
    
    echo "$unit_path"
}

# Parse server arguments
parse_server_args() {
    local config_name=""
    local password=""
    local tunnel_port=""
    local target_port=""
    local bind_addr="0.0.0.0"
    local target_addr="0.0.0.0"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name|-n)
                config_name="$2"
                shift 2
                ;;
            --pass|-p)
                password="$2"
                shift 2
                ;;
            --tunnel-port|-t)
                tunnel_port="$2"
                shift 2
                ;;
            --target-port|-T)
                target_port="$2"
                shift 2
                ;;
            --bind|-b)
                bind_addr="$2"
                shift 2
                ;;
            --target-addr|-a)
                target_addr="$2"
                shift 2
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Validate required args
    if [ -z "$config_name" ] || [ -z "$password" ] || [ -z "$tunnel_port" ] || [ -z "$target_port" ]; then
        echo "Usage: $0 server --name <name> --pass <password> --tunnel-port <port> --target-port <port> [--bind <addr>] [--target-addr <addr>]"
        echo ""
        echo "Required:"
        echo "  --name, -n          Config/service name"
        echo "  --pass, -p          Password for tunnel"
        echo "  --tunnel-port, -t   Port for tunnel connections (clients connect here)"
        echo "  --target-port, -T   Port to forward traffic to (local app)"
        echo ""
        echo "Optional:"
        echo "  --bind, -b          Bind address (default: 0.0.0.0)"
        echo "  --target-addr, -a   Target address (default: 0.0.0.0)"
        echo ""
        echo "Example:"
        echo "  $0 server --name sweden --pass mypassword --tunnel-port 5009 --target-port 10010"
        exit 1
    fi
    
    create_nodepass_server_config "$config_name" "$password" "$tunnel_port" "$target_port" "$bind_addr" "$target_addr"
    manage_nodepass_service "$config_name"
}

# Parse client arguments
parse_client_args() {
    local config_name=""
    local password=""
    local server_ip=""
    local server_port=""
    local local_port=""
    local local_addr="127.0.0.1"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name|-n)
                config_name="$2"
                shift 2
                ;;
            --pass|-p)
                password="$2"
                shift 2
                ;;
            --server|-s)
                server_ip="$2"
                shift 2
                ;;
            --server-port|-S)
                server_port="$2"
                shift 2
                ;;
            --local-port|-l)
                local_port="$2"
                shift 2
                ;;
            --local-addr|-a)
                local_addr="$2"
                shift 2
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Validate required args
    if [ -z "$config_name" ] || [ -z "$password" ] || [ -z "$server_ip" ] || [ -z "$server_port" ] || [ -z "$local_port" ]; then
        echo "Usage: $0 client --name <name> --pass <password> --server <ip> --server-port <port> --local-port <port> [--local-addr <addr>]"
        echo ""
        echo "Required:"
        echo "  --name, -n          Config/service name"
        echo "  --pass, -p          Password for tunnel"
        echo "  --server, -s        Remote server IP"
        echo "  --server-port, -S   Remote server tunnel port"
        echo "  --local-port, -l    Local port to forward to (app port)"
        echo ""
        echo "Optional:"
        echo "  --local-addr, -a    Local address (default: 127.0.0.1)"
        echo ""
        echo "Example:"
        echo "  $0 client --name sweden --pass mypassword --server 213.176.7.229 --server-port 5009 --local-port 18081"
        exit 1
    fi
    
    create_nodepass_client_config "$config_name" "$password" "$server_ip" "$server_port" "$local_addr" "$local_port"
    manage_nodepass_service "$config_name"
}

# Show help
show_help() {
    echo "Nodepass Tunnel Configuration"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  install              Install Nodepass binary"
    echo "  server [options]     Create server config"
    echo "  client [options]     Create client config"
    echo "  stop <name>          Stop a Nodepass service"
    echo "  remove <name>        Remove a Nodepass service"
    echo "  status [name]        Show service status"  
    echo "  logs [--error]       View logs"
    echo ""
    echo "Server Options:"
    echo "  --name, -n          Config/service name"
    echo "  --pass, -p          Password for tunnel"
    echo "  --tunnel-port, -t   Port for tunnel connections"
    echo "  --target-port, -T   Port to forward traffic to"
    echo "  --bind, -b          Bind address (default: 0.0.0.0)"
    echo "  --target-addr, -a   Target address (default: 0.0.0.0)"
    echo ""
    echo "Client Options:"
    echo "  --name, -n          Config/service name"
    echo "  --pass, -p          Password for tunnel"
    echo "  --server, -s        Remote server IP"
    echo "  --server-port, -S   Remote server tunnel port"
    echo "  --local-port, -l    Local port to forward to"
    echo "  --local-addr, -a    Local address (default: 127.0.0.1)"
    echo ""
    echo "Environment Variables (optional):"
    echo "  NODEPASS_VERSION     Version to install (default: 1.15.0)"
    echo "  NODEPASS_MODE        Mode: 0=auto, 1=tcp+udp (default: 1)"
    echo "  NODEPASS_TLS         TLS: 0=plain, 1=TLS (default: 1)"
    echo "  NODEPASS_PROXY       Proxy Protocol: 0=off, 1=on (default: 1)"
    echo "  NODEPASS_LOG_LEVEL   Log level: debug|info|warn|error (default: info)"
    echo ""
    echo "Examples:"
    echo "  # Install Nodepass"
    echo "  $0 install"
    echo ""
    echo "  # Create server"
    echo "  $0 server --name sweden --pass mypassword --tunnel-port 5009 --target-port 10010"
    echo ""
    echo "  # Create client"
    echo "  $0 client --name sweden --pass mypassword --server 213.176.7.229 --server-port 5009 --local-port 18081"
}

# Main function
main() {
    show_banner
    
    local subcommand="$1"
    shift || true
    
    case "$subcommand" in
        "install")
            install_nodepass
            ;;
        "server")
            parse_server_args "$@"
            ;;
        "client")
            parse_client_args "$@"
            ;;
        "stop")
            if [ -z "$1" ]; then
                echo "Usage: $0 stop <config_name>"
                exit 1
            fi
            systemctl stop "nodepass-${1}.service" 2>/dev/null || true
            print_info "Stopped Nodepass service: ${1}"
            ;;
        "remove")
            if [ -z "$1" ]; then
                echo "Usage: $0 remove <config_name>"
                exit 1
            fi
            remove_nodepass_service "$1"
            ;;
        "status")
            if [ -n "$1" ]; then
                systemctl status "nodepass-${1}.service"
            else
                systemctl list-units --type=service --all | grep nodepass || echo "No nodepass services found"
            fi
            ;;
        "logs")
            if [ "$1" = "--error" ]; then
                less +G "$NODEPASS_ERROR_LOG"
            else
                less +G "$NODEPASS_LOG"
            fi
            ;;
        *)
            show_help
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
