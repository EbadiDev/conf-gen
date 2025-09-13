#!/bin/bash

# HAProxy Configuration Module
# Handles HAProxy configuration generation and management

# HAProxy Server Configuration (for external clients connecting to a port range)
create_haproxy_server_config_range() {
    local service_name="$1"
    local start_port="$2"
    local end_port="$3"
    local backend_ip="$4"
    local backend_port="$5"
    local protocol="$6"
    
    local haproxy_config="/etc/haproxy/haproxy.cfg"
    local backup_file="${haproxy_config}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Create backup if file exists
    if [ -f "$haproxy_config" ]; then
        cp "$haproxy_config" "$backup_file"
        print_info "Created backup: $backup_file"
    fi
    
    # Initialize HAProxy config if it doesn't exist
    if [ ! -f "$haproxy_config" ]; then
        create_haproxy_base_config > "$haproxy_config"
    fi
    
    # Remove existing service configuration if it exists
    remove_haproxy_service "$service_name"
    
    # Add new service configuration
    cat << EOF >> "$haproxy_config"

#---------------------------------------------------------------------
# $service_name service configuration
#---------------------------------------------------------------------
frontend ${service_name}_frontend
    bind *:${start_port}-${end_port}
    mode tcp
    option tcplog
    default_backend ${service_name}_backend

backend ${service_name}_backend
    mode tcp
    option tcp-check
    # waterwall service
    server waterwall1 ${backend_ip}:${backend_port} check send-proxy
EOF
    
    print_info "HAProxy configuration updated for service: $service_name"
}

# HAProxy Server Configuration (for single port)
create_haproxy_server_config() {
    local service_name="$1"
    local external_port="$2"
    local backend_ip="$3"
    local backend_port="$4"
    local protocol="$5"
    
    local haproxy_config="/etc/haproxy/haproxy.cfg"
    local backup_file="${haproxy_config}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Create backup if file exists
    if [ -f "$haproxy_config" ]; then
        cp "$haproxy_config" "$backup_file"
        print_info "Created backup: $backup_file"
    fi
    
    # Initialize HAProxy config if it doesn't exist
    if [ ! -f "$haproxy_config" ]; then
        create_haproxy_base_config > "$haproxy_config"
    fi
    
    # Remove existing service configuration if it exists
    remove_haproxy_service "$service_name"
    
    # Add new service configuration
    cat << EOF >> "$haproxy_config"

#---------------------------------------------------------------------
# $service_name service configuration
#---------------------------------------------------------------------
frontend ${service_name}_frontend
    bind *:${external_port}
    mode tcp
    option tcplog
    default_backend ${service_name}_backend

backend ${service_name}_backend
    mode tcp
    option tcp-check
    # waterwall service
    server waterwall1 ${backend_ip}:${backend_port} check send-proxy
EOF
    
    print_info "HAProxy configuration updated for service: $service_name"
}

# HAProxy Client Configuration (for tunnel connecting to HAProxy which forwards to application)
create_haproxy_client_config() {
    local service_name="$1"
    local bind_ip="$2"
    local tunnel_port="$3"
    local app_ip="$4"
    local app_port="$5"
    local protocol="$6"
    
    local haproxy_config="/etc/haproxy/haproxy.cfg"
    local backup_file="${haproxy_config}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Create backup if file exists
    if [ -f "$haproxy_config" ]; then
        cp "$haproxy_config" "$backup_file"
        print_info "Created backup: $backup_file"
    fi
    
    # Initialize HAProxy config if it doesn't exist
    if [ ! -f "$haproxy_config" ]; then
        create_haproxy_base_config > "$haproxy_config"
    fi
    
    # Remove existing service configuration if it exists
    remove_haproxy_service "$service_name"
    
    # Add new service configuration
    cat << EOF >> "$haproxy_config"

#---------------------------------------------------------------------
# $service_name service configuration
#---------------------------------------------------------------------
frontend ${service_name}_frontend
    bind ${bind_ip}:${tunnel_port} accept-proxy
    mode tcp
    option tcplog
    default_backend ${service_name}_backend

backend ${service_name}_backend
    mode tcp
    option tcp-check
    # application service
    server app1 ${app_ip}:${app_port} check send-proxy
EOF
    
    print_info "HAProxy configuration updated for service: $service_name"
}

# HAProxy Client Configuration with Port Range
create_haproxy_client_config_range() {
    local service_name="$1"
    local start_port="$2"
    local end_port="$3"
    local backend_ip="$4"
    local backend_port="$5"
    local protocol="$6"
    
    local haproxy_config="/etc/haproxy/haproxy.cfg"
    local backup_file="${haproxy_config}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Create backup if file exists
    if [ -f "$haproxy_config" ]; then
        cp "$haproxy_config" "$backup_file"
        print_info "Created backup: $backup_file"
    fi
    
    # Initialize HAProxy config if it doesn't exist
    if [ ! -f "$haproxy_config" ]; then
        create_haproxy_base_config > "$haproxy_config"
    fi
    
    # Remove existing service configuration if it exists
    remove_haproxy_service "$service_name"
    
    # Add new service configuration
    cat << EOF >> "$haproxy_config"

#---------------------------------------------------------------------
# $service_name service configuration
#---------------------------------------------------------------------
frontend ${service_name}_frontend
    bind *:${start_port}-${end_port}
    mode tcp
    option tcplog
    default_backend ${service_name}_backend

backend ${service_name}_backend
    mode tcp
    option tcp-check
    # waterwall service
    server waterwall1 ${backend_ip}:${backend_port} check
EOF
    
    print_info "HAProxy configuration updated for service: $service_name"
}

# Create base HAProxy configuration
create_haproxy_base_config() {
    cat << 'EOF'
global
    log stdout local0
    user haproxy
    group haproxy
    daemon
    
    # Performance optimizations
    tune.ssl.default-dh-param 2048
    tune.bufsize 32768
    tune.rcvbuf.server 256k
    tune.sndbuf.server 256k
    
    # Multi-threading
    nbthread 4
    
defaults
    mode tcp
    log global
    option tcplog
    option dontlognull
    option tcp-smart-accept
    option tcp-smart-connect
    
    # Timeouts
    timeout connect 2s
    timeout client 30s
    timeout server 30s
    timeout check 2s
    
    # Keep-alive
    option socket-stats
    
    # Load balancing
    balance roundrobin
EOF
}

# Remove existing HAProxy service configuration
remove_haproxy_service() {
    local service_name="$1"
    local haproxy_config="/etc/haproxy/haproxy.cfg"
    
    if [ -f "$haproxy_config" ]; then
        # Use Python to clean up the config
        python3 -c "
import sys
import re

service_name = '$service_name'
with open('$haproxy_config', 'r') as f:
    lines = f.readlines()

new_lines = []
skip = False
i = 0

while i < len(lines):
    line = lines[i].strip()
    
    # Check if this line is the start of our target service
    if service_name + ' service configuration' in line and '#' in line:
        skip = True
        # Skip until we find another service configuration or EOF
        i += 1
        while i < len(lines):
            next_line = lines[i].strip()
            # Stop skipping when we find another service configuration
            if 'service configuration' in next_line and service_name + ' service configuration' not in next_line and '#' in next_line:
                skip = False
                break
            i += 1
        # Don't increment i again as we want to process the line that ended our skip
        continue
    
    if not skip:
        new_lines.append(lines[i])
    
    i += 1

# Clean up orphaned comment lines (lines that are just #-----)
cleaned_lines = []
for i, line in enumerate(new_lines):
    # Skip lines that are just comment separators if they appear multiple times in a row
    if line.strip() == '#' + '-' * 69:
        # Check if the previous line was also a comment separator
        if i > 0 and cleaned_lines and cleaned_lines[-1].strip() == '#' + '-' * 69:
            continue  # Skip this duplicate
        # Check if this is at the end of file
        if i == len(new_lines) - 1:
            continue  # Skip trailing comment separator
        # Check if next non-empty line is also a comment separator
        next_non_empty = None
        for j in range(i + 1, len(new_lines)):
            if new_lines[j].strip():
                next_non_empty = new_lines[j].strip()
                break
        if next_non_empty == '#' + '-' * 69:
            continue  # Skip if next non-empty is also a separator
    
    cleaned_lines.append(line)

with open('$haproxy_config', 'w') as f:
    f.writelines(cleaned_lines)
"
    fi
}

# Manage HAProxy service (install, start, reload)
manage_haproxy_service() {
    # Check if HAProxy is installed
    if ! command -v haproxy >/dev/null 2>&1; then
        print_info "Installing HAProxy..."
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update && apt-get install -y haproxy
        elif command -v yum >/dev/null 2>&1; then
            yum install -y haproxy
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y haproxy
        else
            echo "Error: Could not install HAProxy. Please install it manually."
            exit 1
        fi
    fi
    
    # Validate HAProxy configuration
    if ! haproxy -c -f /etc/haproxy/haproxy.cfg >/dev/null 2>&1; then
        echo "Error: HAProxy configuration is invalid"
        haproxy -c -f /etc/haproxy/haproxy.cfg
        exit 1
    fi
    
    # Enable and start HAProxy service
    if command -v systemctl >/dev/null 2>&1; then
        systemctl enable haproxy
        if systemctl is-active --quiet haproxy; then
            systemctl reload haproxy
            print_info "HAProxy service reloaded"
        else
            systemctl start haproxy
            print_info "HAProxy service started"
        fi
    else
        service haproxy start
        print_info "HAProxy service started"
    fi
}
