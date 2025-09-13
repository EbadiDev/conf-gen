#!/bin/bash

# Caddy Configuration Module
# Handles Caddy configuration generation and management

# Caddy Server Configuration (for external clients connecting to a port range)
create_caddy_server_config_range() {
    local service_name="$1"
    local start_port="$2"
    local end_port="$3"
    local backend_ip="$4"
    local backend_port="$5"
    local protocol="$6"
    
    local caddy_config="/etc/caddy/Caddyfile"
    local backup_file="${caddy_config}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Create backup if file exists
    if [ -f "$caddy_config" ]; then
        cp "$caddy_config" "$backup_file"
        print_info "Created backup: $backup_file"
    fi
    
    # Initialize Caddy config if it doesn't exist
    if [ ! -f "$caddy_config" ]; then
        create_caddy_base_config > "$caddy_config"
    else
        # Clean up existing default configuration
        clean_default_caddy_config "$caddy_config"
    fi
    
    # Remove existing service configuration if it exists
    remove_caddy_service "$service_name"
    
    # Generate port list (Caddy doesn't support ranges like HAProxy)
    local port_list=""
    for ((port=start_port; port<=end_port; port++)); do
        if [ -n "$port_list" ]; then
            port_list="$port_list, :$port"
        else
            port_list=":$port"
        fi
    done
    
    # Add new service configuration
    cat << EOF >> "$caddy_config"

#---------------------------------------------------------------------
# $service_name service configuration
#---------------------------------------------------------------------
$port_list {
    bind 0.0.0.0
    reverse_proxy $backend_ip:$backend_port {
        transport http {
            dial_timeout 2s
            response_header_timeout 30s
        }
    }
}
EOF
    
    print_info "Caddy configuration updated for service: $service_name"
}

# Caddy Server Configuration (for single port)
create_caddy_server_config() {
    local service_name="$1"
    local external_port="$2"
    local backend_ip="$3"
    local backend_port="$4"
    local protocol="$5"
    
    local caddy_config="/etc/caddy/Caddyfile"
    local backup_file="${caddy_config}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Create backup if file exists
    if [ -f "$caddy_config" ]; then
        cp "$caddy_config" "$backup_file"
        print_info "Created backup: $backup_file"
    fi
    
    # Initialize Caddy config if it doesn't exist
    if [ ! -f "$caddy_config" ]; then
        create_caddy_base_config > "$caddy_config"
    else
        # Clean up existing default configuration
        clean_default_caddy_config "$caddy_config"
    fi
    
    # Remove existing service configuration if it exists
    remove_caddy_service "$service_name"
    
    # Add new service configuration
    cat << EOF >> "$caddy_config"

#---------------------------------------------------------------------
# $service_name service configuration
#---------------------------------------------------------------------
:${external_port} {
    bind ${bind_ip}
    reverse_proxy $backend_ip:$backend_port {
        transport http {
            dial_timeout 2s
            response_header_timeout 30s
        }
    }
}
EOF
    
    print_info "Caddy configuration updated for service: $service_name"
}

# Caddy Client Configuration (for tunnel connecting to Caddy which forwards to application)
create_caddy_client_config() {
    local service_name="$1"
    local bind_ip="$2"
    local tunnel_port="$3"
    local app_ip="$4"
    local app_port="$5"
    local protocol="$6"
    
    local caddy_config="/etc/caddy/Caddyfile"
    local backup_file="${caddy_config}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Create backup if file exists
    if [ -f "$caddy_config" ]; then
        cp "$caddy_config" "$backup_file"
        print_info "Created backup: $backup_file"
    fi
    
    # Initialize Caddy config if it doesn't exist
    if [ ! -f "$caddy_config" ]; then
        create_caddy_base_config > "$caddy_config"
    else
        # Clean up existing default configuration
        clean_default_caddy_config "$caddy_config"
    fi
    
    # Remove existing service configuration if it exists
    remove_caddy_service "$service_name"
    
    # Add new service configuration
    cat << EOF >> "$caddy_config"

#---------------------------------------------------------------------
# $service_name service configuration
#---------------------------------------------------------------------
:${tunnel_port} {
    bind ${bind_ip}
    reverse_proxy $app_ip:$app_port {
        transport http {
            dial_timeout 2s
            response_header_timeout 30s
        }
    }
}
EOF
    
    print_info "Caddy configuration updated for service: $service_name"
}

# Caddy Client Configuration with Port Range
create_caddy_client_config_range() {
    local service_name="$1"
    local start_port="$2"
    local end_port="$3"
    local backend_ip="$4"
    local backend_port="$5"
    local protocol="$6"
    
    local caddy_config="/etc/caddy/Caddyfile"
    local backup_file="${caddy_config}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Create backup if file exists
    if [ -f "$caddy_config" ]; then
        cp "$caddy_config" "$backup_file"
        print_info "Created backup: $backup_file"
    fi
    
    # Initialize Caddy config if it doesn't exist
    if [ ! -f "$caddy_config" ]; then
        create_caddy_base_config > "$caddy_config"
    else
        # Clean up existing default configuration
        clean_default_caddy_config "$caddy_config"
    fi
    
    # Remove existing service configuration if it exists
    remove_caddy_service "$service_name"
    
    # Generate port list (Caddy doesn't support ranges like HAProxy)
    local port_list=""
    for ((port=start_port; port<=end_port; port++)); do
        if [ -n "$port_list" ]; then
            port_list="$port_list, :$port"
        else
            port_list=":$port"
        fi
    done
    
    # Add new service configuration
    cat << EOF >> "$caddy_config"

#---------------------------------------------------------------------
# $service_name service configuration
#---------------------------------------------------------------------
$port_list {
    reverse_proxy $backend_ip:$backend_port {
        transport http {
            dial_timeout 2s
            response_header_timeout 30s
        }
    }
}
EOF
    
    print_info "Caddy configuration updated for service: $service_name"
}

# Create base Caddy configuration
create_caddy_base_config() {
    cat << 'EOF'
{
    admin off
    auto_https off
    
    servers {
        timeouts {
            read_body   30s
            read_header 30s
            write       30s
            idle        120s
        }
    }
}
EOF
}

# Clean default Caddy configuration
clean_default_caddy_config() {
    local caddy_config="$1"
    
    # Remove default :80 site and comments
    sed -i '/^# The Caddyfile is an easy way/,/^# https:\/\/caddyserver.com\/docs\/caddyfile$/d' "$caddy_config"
    sed -i '/^:80 {/,/^}$/d' "$caddy_config"
    # Remove empty lines at the beginning and clean up
    sed -i '/./,$!d' "$caddy_config"
    sed -i '/^$/N;/^\n$/d' "$caddy_config"
    
    # Check if file has global config block, if not recreate completely
    if ! grep -q '^{' "$caddy_config"; then
        create_caddy_base_config > "$caddy_config"
    fi
}

# Remove existing Caddy service configuration
remove_caddy_service() {
    local service_name="$1"
    local caddy_config="/etc/caddy/Caddyfile"
    
    if [ -f "$caddy_config" ]; then
        # Rebuild config while dropping the entire block (including separators)
        # for the target service. A service block is defined as:
        #   #-------------------------------------------------------------
        #   # <name> service configuration
        #   #-------------------------------------------------------------
        #   <site block ...>
        # and ends right before the next such separator+header trio or EOF.

        local temp_config="/tmp/caddy_rebuilt.cfg"

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

            # Print preamble (global config) exactly once
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
        ' "$caddy_config" > "$temp_config"

        # Replace the original config
        mv "$temp_config" "$caddy_config"
        
        # Ensure global config block exists
        if ! grep -q '^{' "$caddy_config"; then
            create_caddy_base_config > "$caddy_config"
        fi
    fi
}

# Manage Caddy service (install, start, reload)
manage_caddy_service() {
    # Check if Caddy is installed
    if ! command -v caddy >/dev/null 2>&1; then
        print_info "Installing Caddy..."
        if command -v apt-get >/dev/null 2>&1; then
            # Install Caddy on Debian/Ubuntu
            apt install -y debian-keyring debian-archive-keyring apt-transport-https
            curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
            curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
            apt update
            apt install -y caddy
        elif command -v yum >/dev/null 2>&1; then
            # Install Caddy on RHEL/CentOS
            yum install -y yum-plugin-copr
            yum copr enable @caddy/caddy
            yum install -y caddy
        elif command -v dnf >/dev/null 2>&1; then
            # Install Caddy on Fedora
            dnf copr enable @caddy/caddy
            dnf install -y caddy
        else
            echo "Error: Could not install Caddy. Please install it manually."
            exit 1
        fi
    fi
    
    # Create config directory if it doesn't exist
    mkdir -p /etc/caddy
    
    # Validate Caddy configuration
    local caddy_config="/etc/caddy/Caddyfile"
    if ! caddy validate --config "$caddy_config" >/dev/null 2>&1; then
        echo "Error: Caddy configuration is invalid"
        caddy validate --config "$caddy_config"
        exit 1
    fi
    
    # Enable and start Caddy service
    if command -v systemctl >/dev/null 2>&1; then
        systemctl enable caddy
        if systemctl is-active --quiet caddy; then
            systemctl reload caddy
            print_info "Caddy service reloaded"
        else
            systemctl start caddy
            print_info "Caddy service started"
        fi
    else
        service caddy start
        print_info "Caddy service started"
    fi
}
