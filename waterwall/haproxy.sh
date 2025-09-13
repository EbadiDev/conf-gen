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
        # Rebuild config while dropping the entire block (including separators)
        # for the target service. A service block is defined as:
        #   #-------------------------------------------------------------
        #   # <name> service configuration
        #   #-------------------------------------------------------------
        #   <frontend + backend ...>
        # and ends right before the next such separator+header trio or EOF.

        local temp_config="/tmp/haproxy_rebuilt.cfg"

        awk -v target="$service_name" '
        {
            lines[NR] = $0
        }
        END {
            n = NR
            # Find the first service block start (separator followed by header)
            start = n + 1
            for (i = 1; i <= n - 1; i++) {
                if (lines[i] ~ /^#-+\s*$/ && lines[i+1] ~ /^# [^#]* service configuration\s*$/) {
                    start = i
                    break
                }
            }

            # Print preamble (global/defaults) exactly once
            for (i = 1; i < start; i++) {
                print lines[i]
            }

            # Walk through all service blocks and print all except the target
            i = start
            while (i <= n) {
                if (i <= n - 1 && lines[i] ~ /^#-+\s*$/ && lines[i+1] ~ /^# ([^#]*) service configuration\s*$/) {
                    # Extract service name from header
                    match(lines[i+1], /^# (.*) service configuration\s*$/, m)
                    name = m[1]

                    # Find end of this block (position just before next block start)
                    k = i + 2
                    while (k <= n - 1 && !(lines[k] ~ /^#-+\s*$/ && lines[k+1] ~ /^# [^#]* service configuration\s*$/)) {
                        k++
                    }
                    end = (k <= n - 1 ? k - 1 : n)

                    if (name != target) {
                        for (p = i; p <= end; p++) {
                            print lines[p]
                        }
                    }
                    i = end + 1
                } else {
                    # Not a recognized block start, just print
                    print lines[i]
                    i++
                }
            }
        }
        ' "$haproxy_config" > "$temp_config"

        # Replace the original config
        mv "$temp_config" "$haproxy_config"
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
