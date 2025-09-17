#!/bin/bash

# Common Functions and Utilities for Waterwall Configuration Modules

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

# Core JSON management functions
add_to_core_json() {
    local config_name="$1"
    local config_type="$2"
    local core_json_path="./core.json"
    
    # Check if core.json exists and create basic structure if not
    if [ ! -f "$core_json_path" ]; then
        echo '{"configs": []}' > "$core_json_path"
        print_info "Created new core.json at $core_json_path"
    fi
    
    # Add configuration to core.json
    local config_path="${config_name}.json"
    
    # Use jq if available, otherwise use sed
    if command -v jq >/dev/null 2>&1; then
        local temp_file=$(mktemp)
        # Check if configs array exists, if not create it
        if ! jq -e '.configs' "$core_json_path" >/dev/null 2>&1; then
            jq '. + {"configs": []}' "$core_json_path" > "$temp_file"
            mv "$temp_file" "$core_json_path"
        fi
        
        # Remove existing config with same name and add new one
        jq --arg name "$config_path" \
           '.configs = (.configs | map(select(. != $name)) + [$name])' \
           "$core_json_path" > "$temp_file" && mv "$temp_file" "$core_json_path"
        
        if [ $? -eq 0 ]; then
            print_info "Added $config_name to core.json ($core_json_path)"
        else
            print_warning "Failed to update core.json with jq, using fallback method"
            # Fallback to manual addition
            add_config_manual "$config_path" "$core_json_path"
        fi
    else
        print_warning "jq not found, using manual core.json management"
        add_config_manual "$config_path" "$core_json_path"
    fi
}

# Manual config addition fallback
add_config_manual() {
    local config_path="$1"
    local core_json_path="$2"
    
    # Check if the config already exists in the array
    if grep -q "\"$config_path\"" "$core_json_path"; then
        print_info "Configuration $config_path already exists in core.json"
        return
    fi
    
    # Add to configs array before the closing bracket
    if grep -q '"configs"' "$core_json_path"; then
        # Configs array exists, add to it
        sed -i "/\"configs\":/,/\]/{
            s/\]/        ,\"$config_path\"\
    \]/
        }" "$core_json_path"
    else
        # No configs array, add it
        sed -i 's/}$/    ,\"configs\": [\
        \"'$config_path'\"\
    ]\
}/' "$core_json_path"
    fi
    
    print_info "Added $config_path to core.json manually"
}

# Firewall management
open_firewall_ports() {
    local start_port="$1"
    local end_port="$2"
    
    print_info "Opening firewall ports: $start_port-$end_port"
    
    # UFW (Ubuntu/Debian)
    if command -v ufw >/dev/null 2>&1; then
        if [ "$start_port" = "$end_port" ]; then
            ufw allow "$start_port" >/dev/null 2>&1
        else
            ufw allow "${start_port}:${end_port}/tcp" >/dev/null 2>&1
        fi
        print_info "UFW: Opened ports $start_port-$end_port"
        return
    fi
    
    # firewalld (CentOS/RHEL/Fedora)
    if command -v firewall-cmd >/dev/null 2>&1; then
        if [ "$start_port" = "$end_port" ]; then
            firewall-cmd --permanent --add-port="$start_port/tcp" >/dev/null 2>&1
        else
            firewall-cmd --permanent --add-port="${start_port}-${end_port}/tcp" >/dev/null 2>&1
        fi
        firewall-cmd --reload >/dev/null 2>&1
        print_info "firewalld: Opened ports $start_port-$end_port"
        return
    fi
    
    # iptables (Generic Linux)
    if command -v iptables >/dev/null 2>&1; then
        if [ "$start_port" = "$end_port" ]; then
            iptables -A INPUT -p tcp --dport "$start_port" -j ACCEPT >/dev/null 2>&1
        else
            iptables -A INPUT -p tcp --dport "${start_port}:${end_port}" -j ACCEPT >/dev/null 2>&1
        fi
        # Try to save iptables rules
        if command -v iptables-save >/dev/null 2>&1; then
            iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
        fi
        print_info "iptables: Opened ports $start_port-$end_port"
        return
    fi
    
    print_warning "No supported firewall found. Please manually open ports $start_port-$end_port"
}

# Validate IP address
validate_ip() {
    local ip="$1"
    local type="unknown"
    
    # IPv4 validation
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -r i1 i2 i3 i4 <<< "$ip"
        if [[ $i1 -le 255 && $i2 -le 255 && $i3 -le 255 && $i4 -le 255 ]]; then
            type="ipv4"
        fi
    fi
    
    # IPv6 validation (basic)
    if [[ $ip =~ .*:.* ]]; then
        type="ipv6"
    fi
    
    echo "$type"
}

# Validate port number
validate_port() {
    local port="$1"
    if [[ $port =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
        return 0
    else
        return 1
    fi
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This script requires root privileges for system configuration"
        print_info "Please run with sudo: sudo $0 $*"
        exit 1
    fi
}

# Create directory if it doesn't exist
ensure_directory() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        print_info "Created directory: $dir"
    fi
}

# Backup existing file
backup_file() {
    local file="$1"
    if [ -f "$file" ]; then
        local backup="${file}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$file" "$backup"
        print_info "Created backup: $backup"
    fi
}

# Display usage help
show_help() {
    cat << EOF
Waterwall Configuration Generator

Usage: $0 <type> [options] <parameters...>

Configuration Types:
  server          - Load-balanced server setups
  client          - Client-side reverse proxy setups  
  simple          - Direct port-to-port forwarding
  half            - Reality/gRPC tunneling
  v2              - Advanced TUN device with IP manipulation

Proxy Integration:
    Add 'haproxy', 'caddy', or 'gost' flags with supported types:
    - HAProxy:   $0 haproxy <type> <protocol> <config_name> [parameters...]
    - Caddy:     $0 caddy <type> <protocol> <config_name> [parameters...]
    - GOST (SS aes-128-cfb + Proxy Protocol). Optional password after 'gost' (default apple123ApPle or env GOST_SS_PASSWORD):
            $0 v2 gost [<ss_password>] server <config_name> <start_port> <end_port> <non_iran_ip> <iran_ip> <private_ip> <haproxy_port> <protocol>
            $0 v2 gost [<ss_password>] client <config_name> <non_iran_ip> <iran_ip> <private_ip> <haproxy_port> <protocol> <app_port>
            $0 half <website> <password> gost [<ss_password>] [tcp|udp] <server|client> <config_name> [...]
            $0 simple gost [<ss_password>] [tcp|udp] <type> <config_name> <start_port> <end_port> <dest_ip> <dest_port> [internal_port]

Examples:
  $0 server myconfig -p 8080 192.168.1.100
  $0 haproxy server tcp myconfig -p 8080 192.168.1.100
  $0 client myconfig 14000 14999 192.168.1.100 13787
  $0 simple tcp server myconfig 300 399 192.168.1.100 8080
  $0 half web-cdn.snapp.ir mypass tcp server myconfig -p 8080 192.168.1.100
  $0 v2 server myconfig 100 199 203.0.113.100 10.80.0.1 10.80.0.2 10311 146
    $0 v2 gost server geovh 450 499 37.230.48.160 188.213.197.166 10.110.0.1 10311 142

For detailed help: $0 --help <type>
EOF
}

# Detailed help for specific configuration type
show_detailed_help() {
    local config_type="$1"
    
    case "$config_type" in
        "server")
            cat << EOF
Server Configuration Help

Creates a load-balanced server setup that distributes traffic across multiple backend servers.

Usage:
  $0 server <config_name> [-p <port>] <server1> [<port1>] [<server2> <port2>] ...
  $0 haproxy server tcp <config_name> [-p <port>] <server1> [haproxy_port]

Parameters:
  config_name     - Name for the configuration file
  -p <port>       - Common port for all servers (optional)
  server1, etc.   - Server IP addresses
  port1, etc.     - Port for each server (if not using -p flag)
  haproxy_port    - Internal HAProxy port (optional, defaults to port+1000)

Examples:
  $0 server myapp -p 8080 192.168.1.100 10.0.0.50
  $0 server myapp 192.168.1.100 8080 10.0.0.50 8081
  $0 haproxy server tcp myapp -p 8080 192.168.1.100 9080
EOF
            ;;
        "client")
            cat << EOF
Client Configuration Help

Creates a client-side reverse proxy setup for connecting to a remote server.

Usage:
  $0 client <config_name> <start_port> <end_port> <kharej_ip> <kharej_port> [haproxy_port]
  $0 haproxy client tcp <config_name> <start_port> <end_port> <kharej_ip> <kharej_port> [haproxy_port]

Parameters:
  config_name     - Name for the configuration file
  start_port      - Starting port of the range
  end_port        - Ending port of the range
  kharej_ip       - Remote server IP address
  kharej_port     - Remote server port
  haproxy_port    - Internal HAProxy port (optional, defaults to start_port+1000)

Examples:
  $0 client myconfig 14000 14999 192.168.1.100 13787
  $0 haproxy client tcp myconfig 14000 14999 192.168.1.100 13787 15000
EOF
            ;;
        *)
            print_error "Unknown configuration type: $config_type"
            show_help
            ;;
    esac
}
