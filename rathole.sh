#!/bin/bash

# Rathole Configuration Generator
# This script generates rathole server and client configurations with systemd services

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
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

# Function to show usage
show_usage() {
    echo "Usage:"
    echo "  Server: $0 server <name> <port> <default_token> <client_port> <tcp|udp> <nodelay> [haproxy] [rathole_port]"
    echo "  Client: $0 client <name> <domain/ip:port> <default_token> <client_port> <tcp|udp> <nodelay> [haproxy] [rathole_port]"
    echo ""
    echo "Examples:"
    echo "  Basic:"
    echo "    $0 server myapp 2333 mysecrettoken 8080 tcp true"
    echo "    $0 client myapp example.com:2333 mysecrettoken 8080 tcp false"
    echo ""
    echo "  With HAProxy (for real IP logging and load balancing):"
    echo "    $0 server myapp 2333 mysecrettoken 8080 tcp true haproxy"
    echo "    $0 client myapp example.com:2333 mysecrettoken 8080 tcp false haproxy"
    echo ""
    echo "  With HAProxy and custom rathole internal port:"
    echo "    $0 server myapp 2333 mysecrettoken 8080 tcp true haproxy 9080"
    echo "    $0 client myapp example.com:2333 mysecrettoken 8080 tcp false haproxy 9080"
    echo ""
    echo "Parameters:"
    echo "  name              - Configuration name"
    echo "  port              - Server bind port (server only)"
    echo "  domain/ip:port    - Server address (client only)"
    echo "  default_token     - Authentication token"
    echo "  client_port       - Client service port"
    echo "  tcp|udp           - Protocol type"
    echo "  nodelay           - Enable/disable TCP nodelay (true/false)"
    echo "  haproxy           - Optional: Generate HAProxy configuration for real IP logging"
    echo "  rathole_port      - Optional: Custom rathole internal port (default: client_port + 1000)"
    echo ""
    echo "Note: The script will generate keys and ask for the remote public key interactively."
    echo "      With haproxy, additional HAProxy configuration files will be generated."
    echo "      HAProxy service will be automatically restarted and ports opened with ufw."
}

# Function to generate keys
generate_keys() {
    local rathole_binary="./rathole"
    
    if [ ! -f "$rathole_binary" ]; then
        print_error "rathole binary not found in current directory: $rathole_binary"
        exit 1
    fi
    
    if [ ! -x "$rathole_binary" ]; then
        print_error "rathole binary is not executable: $rathole_binary"
        exit 1
    fi
    
    local keys_output
    keys_output=$($rathole_binary --genkey 2>/dev/null || {
        print_error "Failed to generate keys using $rathole_binary"
        exit 1
    })
    
    echo "$keys_output"
}

# Function to extract keys from output
extract_keys() {
    local keys_output="$1"
    local private_key
    local public_key
    
    # Handle both styles of rathole --genkey output:
    #   1) Keys on the next line after the labels
    #   2) Keys on the same line as the labels
    private_key=$(awk '
        /^Private Key:/ {
            # Remove label and optional spaces
            line = $0
            sub(/^Private Key:[[:space:]]*/, "", line)
            if (length(line) > 0) {
                print line; exit
            } else {
                # Next line contains the key
                getline; print; exit
            }
        }
    ' <<< "$keys_output")

    public_key=$(awk '
        /^Public Key:/ {
            # Remove label and optional spaces
            line = $0
            sub(/^Public Key:[[:space:]]*/, "", line)
            if (length(line) > 0) {
                print line; exit
            } else {
                # Next line contains the key
                getline; print; exit
            }
        }
    ' <<< "$keys_output")
    
    # Debug: show extracted keys (kept commented)
    # echo "DEBUG: Extracted private key: '$private_key'" >&2
    # echo "DEBUG: Extracted public key: '$public_key'" >&2
    
    echo "$private_key|$public_key"
}

# Function to get remote public key from user
get_remote_public_key() {
    # Print prompts and info to stderr to avoid polluting captured stdout
    {
        echo ""
        print_warning "Please provide the remote public key from the other side:"
        print_info "The remote side should run 'rathole --genkey' and share their PUBLIC KEY with you."
        echo ""
        echo -n "Enter remote public key: "
    } >&2
    read -r remote_public_key
    
    # Clean the input - remove any extra whitespace or newlines
    remote_public_key=$(echo "$remote_public_key" | tr -d '\n\r' | xargs)
    
    # Basic validation - check if it looks like a base64 key
    if [[ -z "$remote_public_key" ]]; then
        print_error "Remote public key cannot be empty!"
        exit 1
    fi
    
    if [[ ${#remote_public_key} -lt 40 ]]; then
        print_error "Remote public key seems too short. Please check the key."
        exit 1
    fi
    
    echo "$remote_public_key"
}

# Function to manage HAProxy service and firewall
manage_haproxy_service() {
    local port="$1"
    local action="$2"  # "start" or "stop"
    local rathole_port="$3"  # optional rathole port for health check
    
    if [[ "$action" == "start" ]]; then
        # Check if rathole is listening if port provided
        if [[ -n "$rathole_port" ]]; then
            print_info "Checking if rathole is ready on port $rathole_port..."
            local retries=10
            while [ $retries -gt 0 ]; do
                if nc -z 127.0.0.1 "$rathole_port" 2>/dev/null; then
                    print_success "Rathole is ready on port $rathole_port"
                    break
                fi
                print_info "Waiting for rathole to start... ($retries retries left)"
                sleep 1
                retries=$((retries - 1))
            done
            
            if [ $retries -eq 0 ]; then
                print_warning "Rathole not ready yet, but continuing with HAProxy restart"
            fi
        fi
        
        print_info "Testing HAProxy configuration..."
        if haproxy -f /etc/haproxy/haproxy.cfg -c; then
            print_success "HAProxy configuration is valid"
        else
            print_error "HAProxy configuration test failed! Please check the config"
            return 1
        fi
        
        print_info "Restarting HAProxy service..."
        if systemctl restart haproxy; then
            print_success "HAProxy service restarted successfully"
        else
            print_error "Failed to restart HAProxy service"
            return 1
        fi
        
        print_info "Enabling HAProxy service..."
        systemctl enable haproxy
        
        print_info "Opening port $port in firewall..."
        if command -v ufw >/dev/null 2>&1; then
            ufw allow "$port"
            print_success "Port $port opened with ufw"
        elif command -v firewall-cmd >/dev/null 2>&1; then
            firewall-cmd --permanent --add-port="$port"/tcp
            firewall-cmd --reload
            print_success "Port $port opened with firewall-cmd"
        else
            print_warning "No firewall management tool found (ufw/firewall-cmd)"
            print_info "Please manually open port $port in your firewall"
        fi
    fi
}

# Function to create HAProxy configuration for server
create_haproxy_server_config() {
    local name="$1"
    local external_port="$2"
    local rathole_port="$3"
    
    local haproxy_config="/etc/haproxy/haproxy.cfg"
    local temp_config="/tmp/haproxy_temp.cfg"
    
    # Create backup of existing config
    if [ -f "$haproxy_config" ]; then
        cp "$haproxy_config" "${haproxy_config}.backup.$(date +%s)"
        print_info "Existing HAProxy config backed up"
    fi
    
    # Always use optimized global and defaults sections
    # Extract any existing service configurations, but replace global/defaults
    cat > "$temp_config" << 'EOF'
#---------------------------------------------------------------------
# Global settings - Stable and compatible
#---------------------------------------------------------------------
global
    log stdout local0
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

#---------------------------------------------------------------------
# Default settings - Stable and compatible
#---------------------------------------------------------------------
defaults
    mode tcp
    log global
    option tcplog
    option dontlognull
    retries 3
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms

EOF

    # If config exists, extract existing service configurations (excluding current service)
    if [ -f "$haproxy_config" ]; then
        awk -v service_name="${name}" '
        BEGIN { 
            skip = 0
            skip_global_defaults = 1
        }
        
        # Skip everything until we find the first service section
        /^#-+$/ {
            getline next_line
            if (next_line ~ "^# .* service configuration") {
                found_first_service = 1
                if (next_line ~ "^# " service_name " service configuration") {
                    skip_service = 1  # Skip this specific service (will be replaced)
                } else {
                    skip_service = 0  # Keep other services
                    print $0
                    print next_line
                }
                next
            } else if (found_first_service) {
                # After first service, print other separator lines
                if (skip_service == 0) {
                    print $0
                    print next_line
                }
                next
            } else {
                # Before first service, skip (global/defaults area)
                next
            }
        }
        
        # Handle service section transitions
        skip_service == 1 && /^#-+$/ {
            getline next_line
            if (next_line ~ "^# .* service configuration") {
                skip_service = 0
                print $0
                print next_line
                next
            } else {
                skip_service = 0
                if (next_line != "" && found_first_service) {
                    print $0
                    print next_line
                }
                next
            }
        }
        
        # Print lines that are not skipped and after first service found
        found_first_service == 1 && skip_service == 0 { print }
        ' "$haproxy_config" >> "$temp_config"
    fi
    
    # Add the new service configuration
    cat >> "$temp_config" << EOF

#---------------------------------------------------------------------
# ${name} service configuration
#---------------------------------------------------------------------
frontend ${name}_frontend
    bind *:${external_port}
    mode tcp
    option tcplog
    # Simple proxy protocol forwarding without stick tables
    default_backend ${name}_rathole

backend ${name}_rathole
    mode tcp
    option tcp-check
    # Just forward with proxy protocol to rathole
    server rathole1 127.0.0.1:${rathole_port} check send-proxy
EOF

    # Move temp config to final location
    mkdir -p /etc/haproxy
    mv "$temp_config" "$haproxy_config"
    
    print_success "HAProxy configuration updated: $haproxy_config"
    print_info "Service '${name}' added to HAProxy configuration"
    print_info "External clients should connect to port ${external_port}"
    print_info "Real client IPs will be visible in HAProxy logs (if logging enabled)"
    echo ""
}

# Function to create HAProxy configuration for client
create_haproxy_client_config() {
    local name="$1"
    local rathole_port="$2"
    local service_port="$3"
    
    local haproxy_config="/etc/haproxy/haproxy.cfg"
    local temp_config="/tmp/haproxy_temp.cfg"
    
    # Create backup of existing config
    if [ -f "$haproxy_config" ]; then
        cp "$haproxy_config" "${haproxy_config}.backup.$(date +%s)"
        print_info "Existing HAProxy config backed up"
    fi
    
    # Always use optimized global and defaults sections
    # Extract any existing service configurations, but replace global/defaults
    cat > "$temp_config" << 'EOF'
#---------------------------------------------------------------------
# Global settings - Stable and compatible
#---------------------------------------------------------------------
global
    log stdout local0
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

#---------------------------------------------------------------------
# Default settings - Stable and compatible
#---------------------------------------------------------------------
defaults
    mode tcp
    log global
    option tcplog
    option dontlognull
    retries 3
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms

EOF

    # If config exists, extract existing service configurations (excluding current service)
    if [ -f "$haproxy_config" ]; then
        awk -v service_name="${name}" '
        BEGIN { 
            skip_service = 0
            found_first_service = 0
        }
        
        # Skip everything until we find the first service section
        /^#-+$/ {
            getline next_line
            if (next_line ~ "^# .* service configuration") {
                found_first_service = 1
                if (next_line ~ "^# " service_name " service configuration") {
                    skip_service = 1  # Skip this specific service (will be replaced)
                } else {
                    skip_service = 0  # Keep other services
                    print $0
                    print next_line
                }
                next
            } else if (found_first_service) {
                # After first service, print other separator lines
                if (skip_service == 0) {
                    print $0
                    print next_line
                }
                next
            } else {
                # Before first service, skip (global/defaults area)
                next
            }
        }
        
        # Handle service section transitions
        skip_service == 1 && /^#-+$/ {
            getline next_line
            if (next_line ~ "^# .* service configuration") {
                skip_service = 0
                print $0
                print next_line
                next
            } else {
                skip_service = 0
                if (next_line != "" && found_first_service) {
                    print $0
                    print next_line
                }
                next
            }
        }
        
        # Print lines that are not skipped and after first service found
        found_first_service == 1 && skip_service == 0 { print }
        ' "$haproxy_config" >> "$temp_config"
    fi
    
    # Add the new service configuration
    cat >> "$temp_config" << EOF

#---------------------------------------------------------------------
# ${name} service configuration
#---------------------------------------------------------------------
# Frontend receiving from rathole - with real IP forwarding
frontend ${name}_frontend
    bind *:${rathole_port} accept-proxy
    mode tcp
    option tcplog
    default_backend ${name}_backend

# Backend to your actual service - with real IP forwarding
backend ${name}_backend
    mode tcp
    option tcp-check
    # Forward to your actual service with proxy protocol
    server app1 127.0.0.1:${service_port} check send-proxy
EOF

    # Move temp config to final location
    mkdir -p /etc/haproxy
    mv "$temp_config" "$haproxy_config"
    
    print_success "HAProxy configuration updated: $haproxy_config"
    print_info "Service '${name}' added to HAProxy configuration"
    print_info "Your service should remain on port ${service_port}"
    print_info "Rathole will forward to HAProxy on port ${rathole_port}"
    echo ""
}

# Function to create server configuration
create_server_config() {
    local name="$1"
    local port="$2"
    local default_token="$3"
    local client_port="$4"
    local protocol="$5"
    local nodelay="$6"
    local use_haproxy="${7:-}"
    local custom_rathole_port="${8:-}"
    
    # Generate keys for server
    local keys_output
    keys_output=$(generate_keys)
    # Do not print the raw --genkey output; we'll only show the final public key
    
    local keys
    keys=$(extract_keys "$keys_output")
    local local_private_key
    local local_public_key
    local_private_key=$(echo "$keys" | cut -d'|' -f1)
    local_public_key=$(echo "$keys" | cut -d'|' -f2)
    
    # Verify we got the keys correctly
    if [[ -z "$local_private_key" ]] || [[ -z "$local_public_key" ]]; then
        print_error "Failed to extract keys properly"
        print_error "Private key: '$local_private_key'"
        print_error "Public key: '$local_public_key'"
        exit 1
    fi
    
    echo ""
    print_success "Your server's public key is: $local_public_key"
    print_warning "Share this public key with the client side!"
    
    # Get remote public key from user
    local remote_public_key
    remote_public_key=$(get_remote_public_key)
    
    # Determine rathole bind port based on HAProxy usage
    local rathole_bind_port
    local external_port
    
    if [[ "$use_haproxy" == "haproxy" ]]; then
        # Use custom port if provided, otherwise default to client_port + 1000
        if [[ -n "$custom_rathole_port" ]]; then
            rathole_bind_port="$custom_rathole_port"
        else
            rathole_bind_port=$((client_port + 1000))
        fi
        external_port="$client_port"
        print_info "HAProxy mode enabled:"
        print_info "  - External port (HAProxy): $external_port"
        print_info "  - Rathole internal port: $rathole_bind_port"
    else
        rathole_bind_port="$client_port"
    fi
    
    # Create server configuration file
    local config_file="${name}_server.toml"
    
    cat > "$config_file" << EOF
[server]
bind_addr = "0.0.0.0:${port}"
default_token = "${default_token}"
heartbeat_interval = 35

[server.transport]
type = "noise"
[server.transport.noise]
pattern = "Noise_KK_25519_ChaChaPoly_BLAKE2s"
local_private_key = "${local_private_key}"
remote_public_key = "${remote_public_key}"

[server.services."${client_port}"]
type = "${protocol}"
bind_addr = "0.0.0.0:${rathole_bind_port}"
nodelay = ${nodelay}
EOF

    # Set secure permissions
    chmod 600 "$config_file"
    
    print_success "Server configuration created: $config_file"
    
    # Copy configuration to /etc/rathole/ automatically
    print_info "Installing configuration..."
    mkdir -p /etc/rathole
    cp "$config_file" /etc/rathole/
    chmod 600 "/etc/rathole/$config_file"
    
    # Create and install systemd service file first
    create_systemd_service "server" "$name"
    
    # Create HAProxy configuration if requested (after rathole is running)
    if [[ "$use_haproxy" == "haproxy" ]]; then
        create_haproxy_server_config "$name" "$external_port" "$rathole_bind_port"
        # Wait a moment for rathole to fully start
        print_info "Waiting for rathole service to start..."
        sleep 3
        # Manage HAProxy service and firewall with rathole port check
        manage_haproxy_service "$external_port" "start" "$rathole_bind_port"
    fi
    
    print_info "Configuration file path: $(pwd)/$config_file"
    print_success "Configuration copied to: /etc/rathole/$config_file"
}

# Function to create client configuration
create_client_config() {
    local name="$1"
    local remote_addr="$2"
    local default_token="$3"
    local client_port="$4"
    local protocol="$5"
    local nodelay="$6"
    local use_haproxy="${7:-}"
    local custom_rathole_port="${8:-}"
    
    # Generate keys for client
    local keys_output
    keys_output=$(generate_keys)
    # Do not print the raw --genkey output; we'll only show the final public key
    
    local keys
    keys=$(extract_keys "$keys_output")
    local local_private_key
    local local_public_key
    local_private_key=$(echo "$keys" | cut -d'|' -f1)
    local_public_key=$(echo "$keys" | cut -d'|' -f2)
    
    # Verify we got the keys correctly
    if [[ -z "$local_private_key" ]] || [[ -z "$local_public_key" ]]; then
        print_error "Failed to extract keys properly"
        print_error "Private key: '$local_private_key'"
        print_error "Public key: '$local_public_key'"
        exit 1
    fi
    
    echo ""
    print_success "Your client's public key is: $local_public_key"
    print_warning "Share this public key with the server side!"
    
    # Get remote public key from user
    local remote_public_key
    remote_public_key=$(get_remote_public_key)
    
    # Determine local address based on HAProxy usage
    local rathole_local_port
    local service_port="$client_port"
    
    if [[ "$use_haproxy" == "haproxy" ]]; then
        # Use custom port if provided, otherwise default to client_port + 1000
        if [[ -n "$custom_rathole_port" ]]; then
            rathole_local_port="$custom_rathole_port"
        else
            rathole_local_port=$((client_port + 1000))
        fi
        print_info "HAProxy mode enabled:"
        print_info "  - Rathole forwards to HAProxy on port: $rathole_local_port"
        print_info "  - Your service should remain on port: $service_port"
        print_info "  - HAProxy will forward traffic between them"
    else
        rathole_local_port="$client_port"
    fi
    
    # Create client configuration file
    local config_file="${name}_client.toml"
    
    cat > "$config_file" << EOF
[client]
remote_addr = "${remote_addr}"
default_token = "${default_token}"
heartbeat_timeout = 35
retry_interval = 1

[client.transport]
type = "noise"
[client.transport.noise]
pattern = "Noise_KK_25519_ChaChaPoly_BLAKE2s"
local_private_key = "${local_private_key}"
remote_public_key = "${remote_public_key}"

[client.services."${client_port}"]
type = "${protocol}"
local_addr = "127.0.0.1:${rathole_local_port}"
nodelay = ${nodelay}
EOF

    # Set secure permissions
    chmod 600 "$config_file"
    
    print_success "Client configuration created: $config_file"
    
    # Copy configuration to /etc/rathole/ automatically
    print_info "Installing configuration..."
    mkdir -p /etc/rathole
    cp "$config_file" /etc/rathole/
    chmod 600 "/etc/rathole/$config_file"
    
    # Create and install systemd service file first
    create_systemd_service "client" "$name"
    
    # Create HAProxy configuration if requested (after rathole is running)
    if [[ "$use_haproxy" == "haproxy" ]]; then
        create_haproxy_client_config "$name" "$rathole_local_port" "$service_port"
        # Wait a moment for rathole to fully start
        print_info "Waiting for rathole service to start..."
        sleep 3
        # Manage HAProxy service and firewall with rathole port check
        manage_haproxy_service "$rathole_local_port" "start" "$rathole_local_port"
    fi
    
    print_info "Configuration file path: $(pwd)/$config_file"
    print_success "Configuration copied to: /etc/rathole/$config_file"
}

# Function to create systemd service files
create_systemd_service() {
    local type="$1"  # server or client
    local name="$2"
    
    local service_name
    if [ "$type" = "server" ]; then
        service_name="ratholes@.service"
    else
        service_name="ratholec@.service"
    fi
    
    # Get the current directory path for rathole binary
    local rathole_path="$(pwd)/rathole"
    # Use config suffix per service template so the instance name can be just the 'name'
    local config_suffix
    if [ "$type" = "server" ]; then
        config_suffix="_server"
    else
        config_suffix="_client"
    fi
    
    # Create the systemd service file
    cat > "$service_name" << EOF
[Unit]
Description=Rathole ${type^} %i
After=network.target

[Service]
Type=simple
User=root
ExecStart=${rathole_path} --${type} /etc/rathole/%i${config_suffix}.toml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    print_success "Systemd service file created: $service_name"
    
    # Install the service file
    print_info "Installing systemd service..."
    cp "$service_name" /etc/systemd/system/
    systemctl daemon-reload
    
    # Auto-enable and start the service instance (without _server/_client suffix)
    local instance="${name}"
    local unit="${service_name%@.service}@${instance}"
    if systemctl enable "$unit" --now; then
        print_success "Service installed, enabled, and started: $unit"
    else
        print_warning "Service installed, but failed to enable/start: $unit"
        print_info "You can manually start it with:"
        echo "  sudo systemctl enable $unit --now"
    fi
    
    print_info "To check service status:"
    echo "  sudo systemctl status $unit"
    echo ""
    print_info "To view logs:"
    echo "  sudo journalctl -u $unit -f"
}

# Function to validate protocol
validate_protocol() {
    local protocol="$1"
    if [[ "$protocol" != "tcp" && "$protocol" != "udp" ]]; then
        print_error "Invalid protocol: $protocol. Must be 'tcp' or 'udp'"
        exit 1
    fi
}

# Function to validate nodelay
validate_nodelay() {
    local nodelay="$1"
    if [[ "$nodelay" != "true" && "$nodelay" != "false" ]]; then
        print_error "Invalid nodelay value: $nodelay. Must be 'true' or 'false'"
        exit 1
    fi
}

# Function to validate port
validate_port() {
    local port="$1"
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        print_error "Invalid port: $port. Must be a number between 1 and 65535"
        exit 1
    fi
}

# Main script logic
main() {
    if [ $# -lt 2 ]; then
        show_usage
        exit 1
    fi
    
    local type="$1"
    shift
    
    case "$type" in
        "server")
            if [ $# -lt 6 ] || [ $# -gt 8 ]; then
                print_error "Server configuration requires 6 parameters, with optional 7th for HAProxy and 8th for custom rathole port"
                show_usage
                exit 1
            fi
            
            local name="$1"
            local port="$2"
            local default_token="$3"
            local client_port="$4"
            local protocol="$5"
            local nodelay="$6"
            local use_haproxy="${7:-}"
            local custom_rathole_port="${8:-}"
            
            # Validate inputs
            validate_port "$port"
            validate_port "$client_port"
            validate_protocol "$protocol"
            validate_nodelay "$nodelay"
            
            if [[ -n "$use_haproxy" && "$use_haproxy" != "haproxy" ]]; then
                print_error "Invalid HAProxy parameter: $use_haproxy. Use 'haproxy' or omit"
                exit 1
            fi
            
            if [[ -n "$custom_rathole_port" ]]; then
                validate_port "$custom_rathole_port"
            fi
            
            create_server_config "$name" "$port" "$default_token" "$client_port" "$protocol" "$nodelay" "$use_haproxy" "$custom_rathole_port"
            ;;
            
        "client")
            if [ $# -lt 6 ] || [ $# -gt 8 ]; then
                print_error "Client configuration requires 6 parameters, with optional 7th for HAProxy and 8th for custom rathole port"
                show_usage
                exit 1
            fi
            
            local name="$1"
            local remote_addr="$2"
            local default_token="$3"
            local client_port="$4"
            local protocol="$5"
            local nodelay="$6"
            local use_haproxy="${7:-}"
            local custom_rathole_port="${8:-}"
            
            # Validate inputs
            validate_port "$client_port"
            validate_protocol "$protocol"
            validate_nodelay "$nodelay"
            
            if [[ -n "$use_haproxy" && "$use_haproxy" != "haproxy" ]]; then
                print_error "Invalid HAProxy parameter: $use_haproxy. Use 'haproxy' or omit"
                exit 1
            fi
            
            if [[ -n "$custom_rathole_port" ]]; then
                validate_port "$custom_rathole_port"
            fi
            
            create_client_config "$name" "$remote_addr" "$default_token" "$client_port" "$protocol" "$nodelay" "$use_haproxy" "$custom_rathole_port"
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
