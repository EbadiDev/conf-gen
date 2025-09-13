#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output (matching rathole.sh style)
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

# Function to create HAProxy configuration for server (tunnel ingress)
create_haproxy_server_config() {
    local name="$1"
    local external_port="$2"
    local internal_port="$3"
    
    local haproxy_config="/etc/haproxy/haproxy.cfg"
    local temp_config="/tmp/haproxy_temp.cfg"
    
    # Create backup of existing config
    if [ -f "$haproxy_config" ]; then
        print_info "Creating backup of existing HAProxy config"
        cp "$haproxy_config" "${haproxy_config}.backup.$(date +%s)"
    fi
    
    # Start with clean global and defaults sections
    cat > "$temp_config" << 'EOF'
#---------------------------------------------------------------------
# Global settings - Stable and compatible
#---------------------------------------------------------------------
global
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
    option dontlognull
    retries 3
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms

EOF

    # If config exists, extract existing service configurations (excluding current service)
    if [ -f "$haproxy_config" ]; then
        # Extract all service sections except the one we're replacing
        awk -v service="$name" '
        BEGIN { 
            printing = 0
            in_target_service = 0
        }
        # Start of any service section
        /^#.*service configuration/ {
            if ($0 ~ service) {
                in_target_service = 1
                printing = 0
            } else {
                in_target_service = 0
                printing = 1
                print ""
                print $0
            }
            next
        }
        # Skip global/defaults sections 
        /^global/ || /^defaults/ || /^#.*Global settings/ || /^#.*Default settings/ {
            printing = 0
            next
        }
        # Print if we are in a service section (but not the target service)
        printing == 1 && in_target_service == 0 {
            print $0
        }
        # Start printing after seeing a service header (unless its the target service)
        /^frontend|^backend/ && in_target_service == 0 {
            printing = 1
            print $0
        }
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
    default_backend ${name}_backend

backend ${name}_backend
    mode tcp
    option tcp-check
    server waterwall1 127.0.0.1:${internal_port} check send-proxy
EOF

    # Move temp config to final location
    mkdir -p /etc/haproxy
    mv "$temp_config" "$haproxy_config"
    
    print_success "HAProxy configuration updated: $haproxy_config"
    print_info "Service '${name}' added to HAProxy configuration"
    print_info "External clients should connect to port ${external_port}"
    print_info "Traffic will be forwarded to internal port ${internal_port}"
    echo ""
}

# Function to create HAProxy configuration for client (tunnel egress)
create_haproxy_client_config() {
    local name="$1"
    local tunnel_port="$2"
    local service_port="$3"
    
    local haproxy_config="/etc/haproxy/haproxy.cfg"
    local temp_config="/tmp/haproxy_temp.cfg"
    
    # Create backup of existing config
    if [ -f "$haproxy_config" ]; then
        print_info "Creating backup of existing HAProxy config"
        cp "$haproxy_config" "${haproxy_config}.backup.$(date +%s)"
    fi
    
    # Start with clean global and defaults sections
    cat > "$temp_config" << 'EOF'
#---------------------------------------------------------------------
# Global settings - Stable and compatible
#---------------------------------------------------------------------
global
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
    option dontlognull
    retries 3
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms

EOF

    # If config exists, extract existing service configurations (excluding current service)
    if [ -f "$haproxy_config" ]; then
        # Extract all service sections except the one we're replacing
        awk -v service="$name" '
        BEGIN { 
            printing = 0
            in_target_service = 0
        }
        # Start of any service section
        /^#.*service configuration/ {
            if ($0 ~ service) {
                in_target_service = 1
                printing = 0
            } else {
                in_target_service = 0
                printing = 1
                print ""
                print $0
            }
            next
        }
        # Skip global/defaults sections 
        /^global/ || /^defaults/ || /^#.*Global settings/ || /^#.*Default settings/ {
            printing = 0
            next
        }
        # Print if we are in a service section (but not the target service)
        printing == 1 && in_target_service == 0 {
            print $0
        }
        # Start printing after seeing a service header (unless its the target service)
        /^frontend|^backend/ && in_target_service == 0 {
            printing = 1
            print $0
        }
        ' "$haproxy_config" >> "$temp_config"
    fi
    
    # Add the new service configuration
    cat >> "$temp_config" << EOF

#---------------------------------------------------------------------
# ${name} service configuration
#---------------------------------------------------------------------
frontend ${name}_frontend
    bind *:${tunnel_port} accept-proxy
    mode tcp
    default_backend ${name}_backend

backend ${name}_backend
    mode tcp
    option tcp-check
    server app1 127.0.0.1:${service_port} check send-proxy
EOF

    # Move temp config to final location
    mkdir -p /etc/haproxy
    mv "$temp_config" "$haproxy_config"
    
    print_success "HAProxy configuration updated: $haproxy_config"
    print_info "Service '${name}' added to HAProxy configuration"
    print_info "Your service should remain on port ${service_port}"
    print_info "Tunnel will forward to HAProxy on port ${tunnel_port}"
    echo ""
}

# Function to manage HAProxy service and firewall
manage_haproxy_service() {
    local port="$1"
    local action="$2"  # "start" or "stop"
    local internal_port="$3"  # optional internal port for health check
    
    if [[ "$action" == "start" ]]; then
        # Start and enable HAProxy service
        print_info "Starting HAProxy service..."
        systemctl enable haproxy >/dev/null 2>&1
        
        if systemctl is-active --quiet haproxy; then
            systemctl reload haproxy
            print_success "HAProxy service reloaded successfully"
        else
            systemctl start haproxy
            print_success "HAProxy service started successfully"
        fi
        
        # Open firewall port
        print_info "Opening firewall port $port..."
        if command -v ufw >/dev/null 2>&1 && ufw status >/dev/null 2>&1; then
            ufw allow "$port"/tcp >/dev/null 2>&1
            ufw allow "$port"/udp >/dev/null 2>&1
            print_success "Opened port $port (TCP & UDP) using UFW"
        elif command -v firewall-cmd >/dev/null 2>&1; then
            firewall-cmd --permanent --add-port="$port"/tcp >/dev/null 2>&1
            firewall-cmd --permanent --add-port="$port"/udp >/dev/null 2>&1
            firewall-cmd --reload >/dev/null 2>&1
            print_success "Opened port $port (TCP & UDP) using firewalld"
        else
            print_warning "Please manually open port $port in your firewall"
        fi
    elif [[ "$action" == "stop" ]]; then
        print_info "HAProxy service management: stop action not implemented"
    fi
}

# Function to add config to core.json if it doesn't exist
add_to_core_json() {
    local config_name="$1"
    local config_type="$2"
    
    # Use different path for v2 configurations
    if [ "$config_type" = "v2" ]; then
        local core_json="/root/tunnel/core.json"
    else
        local core_json="/root/core.json"
    fi
    
    # Check if core.json exists
    if [ ! -f "$core_json" ]; then
        if [ "$config_type" = "v2" ]; then
            echo "Error: core.json not found in /root/tunnel/"
        else
            echo "Error: core.json not found in /root/"
        fi
        return 1
    fi
    
    # Check if config already exists
    if grep -q "\"${config_name}.json\"" "$core_json"; then
        echo "Config ${config_name}.json already exists in core.json"
        return 0
    fi

    # Add new config to the configs array using awk
    awk -v conf="${config_name}.json" '
    BEGIN { in_array = 0; found_last = 0 }
    /^[[:space:]]*"configs":[[:space:]]*\[/ {
        in_array = 1;
        print;
        next;
    }
    in_array && !found_last {
        if ($0 ~ /^[[:space:]]*\]/) {
            if (last) {
                print last;
                printf "        ,\"%s\"\n", conf;
            } else {
                printf "        \"%s\"\n", conf;
            }
            found_last = 1;
        } else if ($0 !~ /^[[:space:]]*$/) {
            if (last) print last;
            last = $0;
            next;
        }
    }
    { print }
    ' "$core_json" > "${core_json}.tmp" && mv "${core_json}.tmp" "$core_json"
    
    echo "Added ${config_name}.json to core.json configurations"
}

# Function to open firewall ports
open_firewall_ports() {
    local start_port="$1"
    local end_port="$2"
    local protocol="$3"
    local single_port="$4"
    
    # Detect firewall system and open ports
    if command -v ufw >/dev/null 2>&1 && ufw status >/dev/null 2>&1; then
        # Ubuntu/Debian with UFW
        echo "Opening ports using UFW..."
        if [ -n "$single_port" ]; then
            ufw allow "$single_port" >/dev/null 2>&1
            echo "Opened port $single_port (TCP & UDP)"
        fi
        if [ "$start_port" != "$end_port" ]; then
            ufw allow "$start_port:$end_port/tcp" >/dev/null 2>&1
            ufw allow "$start_port:$end_port/udp" >/dev/null 2>&1
            echo "Opened port range $start_port:$end_port (TCP & UDP)"
        else
            ufw allow "$start_port/tcp" >/dev/null 2>&1
            ufw allow "$start_port/udp" >/dev/null 2>&1
            echo "Opened port $start_port (TCP & UDP)"
        fi
    elif command -v firewall-cmd >/dev/null 2>&1; then
        # CentOS/RHEL/Fedora with firewalld
        echo "Opening ports using firewalld..."
        if [ -n "$single_port" ]; then
            firewall-cmd --permanent --add-port="$single_port/tcp" >/dev/null 2>&1
            firewall-cmd --permanent --add-port="$single_port/udp" >/dev/null 2>&1
            echo "Opened port $single_port (TCP & UDP)"
        fi
        if [ "$start_port" != "$end_port" ]; then
            firewall-cmd --permanent --add-port="$start_port-$end_port/tcp" >/dev/null 2>&1
            firewall-cmd --permanent --add-port="$start_port-$end_port/udp" >/dev/null 2>&1
            echo "Opened port range $start_port-$end_port (TCP & UDP)"
        else
            firewall-cmd --permanent --add-port="$start_port/tcp" >/dev/null 2>&1
            firewall-cmd --permanent --add-port="$start_port/udp" >/dev/null 2>&1
            echo "Opened port $start_port (TCP & UDP)"
        fi
        firewall-cmd --reload >/dev/null 2>&1
    elif command -v iptables >/dev/null 2>&1; then
        # Generic iptables
        echo "Opening ports using iptables..."
        if [ -n "$single_port" ]; then
            iptables -A INPUT -p tcp --dport "$single_port" -j ACCEPT >/dev/null 2>&1
            iptables -A INPUT -p udp --dport "$single_port" -j ACCEPT >/dev/null 2>&1
            echo "Opened port $single_port (TCP & UDP)"
        fi
        if [ "$start_port" != "$end_port" ]; then
            iptables -A INPUT -p tcp --dport "$start_port:$end_port" -j ACCEPT >/dev/null 2>&1
            iptables -A INPUT -p udp --dport "$start_port:$end_port" -j ACCEPT >/dev/null 2>&1
            echo "Opened port range $start_port:$end_port (TCP & UDP)"
        else
            iptables -A INPUT -p tcp --dport "$start_port" -j ACCEPT >/dev/null 2>&1
            iptables -A INPUT -p udp --dport "$start_port" -j ACCEPT >/dev/null 2>&1
            echo "Opened port $start_port (TCP & UDP)"
        fi
        # Try to save iptables rules
        if command -v iptables-save >/dev/null 2>&1; then
            iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
        fi
    else
        echo "Warning: No supported firewall system detected. Please manually open ports:"
        if [ -n "$single_port" ]; then
            echo "  - Port $single_port (TCP & UDP)"
        fi
        if [ "$start_port" != "$end_port" ]; then
            echo "  - Port range $start_port:$end_port (TCP & UDP)"
        else
            echo "  - Port $start_port (TCP & UDP)"
        fi
    fi
}

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <type> <config_name> [parameters...]"
    echo "For server config:"
    echo "  With different ports: $0 server [tcp|udp] <config_name> <server1_address> <server1_port> [<server2_address> <server2_port> ...]"
    echo "  With same port: $0 server [tcp|udp] <config_name> -p <port> <server1_address> [<server2_address> ...]"
    echo "  With HAProxy: $0 haproxy server [tcp|udp] <config_name> -p <port> <server1_address> [<server2_address> ...] [haproxy_port]"
    echo "For iran config: $0 iran [tcp|udp] <config_name> <start_port> <end_port> <kharej_ip> <kharej_port>"
    echo "  With HAProxy: $0 haproxy iran [tcp|udp] <config_name> <start_port> <end_port> <kharej_ip> <kharej_port> [haproxy_port]"
    echo "For simple iran config: $0 simple [tcp|udp] iran <config_name> <start_port> <end_port> <ip> <port>"
    echo "For half iran config: $0 half <website> <password> [tcp|udp] iran <config_name> <start_port> <end_port> <kharej_ip> <kharej_port>"
    echo "  With HAProxy: $0 half haproxy <website> <password> [tcp|udp] iran <config_name> <start_port> <end_port> <kharej_ip> <kharej_port> [haproxy_port]"
    echo "For half server config: $0 half <website> <password> [tcp|udp] server <config_name> -p <port> <iran_ip>"
    echo "  With HAProxy: $0 half haproxy <website> <password> [tcp|udp] server <config_name> -p <port> <iran_ip> [haproxy_port]"
    echo "For v2 iran config: $0 v2 iran <config_name> <start_port> <end_port> <non_iran_ip> <iran_ip> <private_ip> <endpoint_port> <protocol>"
    echo "  With HAProxy: $0 v2 haproxy iran <config_name> <start_port> <end_port> <non_iran_ip> <iran_ip> <private_ip> <endpoint_port> <protocol> [haproxy_port]"
    echo "For v2 server config: $0 v2 server <config_name> <non_iran_ip> <iran_ip> <private_ip> <endpoint_port> <protocol>"
    echo "  With HAProxy: $0 v2 haproxy server <config_name> <non_iran_ip> <iran_ip> <private_ip> <endpoint_port> <protocol> [haproxy_port]"
    exit 1
fi

TYPE="$1"

# Check for HAProxy flag in legacy configurations
USE_HAPROXY_LEGACY=false
if [ "$TYPE" = "haproxy" ]; then
    USE_HAPROXY_LEGACY=true
    TYPE="$2"  # Get the actual type (server, iran, etc.)
    shift 1    # Remove haproxy flag from arguments
fi

# Check if it's the simple iran configuration
if [ "$TYPE" = "simple" ]; then
    # Check if second parameter is tcp, udp, or iran (for backward compatibility)
    if [ "$2" = "tcp" ] || [ "$2" = "udp" ]; then
        PROTOCOL="$2"
        if [ "$3" != "iran" ]; then
            echo "Error: Third parameter must be 'iran' for simple config"
            exit 1
        fi
        if [ "$#" -lt 8 ]; then
            echo "Error: Simple iran config needs protocol, config_name, start_port, end_port, ip, and port"
            exit 1
        fi
        CONFIG_NAME="$4"
        START_PORT="$5"
        END_PORT="$6"
        IP="$7"
        PORT="$8"
    elif [ "$2" = "iran" ]; then
        # Backward compatibility - default to TCP
        PROTOCOL="tcp"
        if [ "$#" -lt 7 ]; then
            echo "Error: Simple iran config needs config_name, start_port, end_port, ip, and port"
            exit 1
        fi
        CONFIG_NAME="$3"
        START_PORT="$4"
        END_PORT="$5"
        IP="$6"
        PORT="$7"
    else
        echo "Error: Second parameter must be 'tcp', 'udp', or 'iran' for simple config"
        exit 1
    fi
    
    # Set connection types based on protocol
    if [ "$PROTOCOL" = "udp" ]; then
        LISTENER_TYPE="UdpListener"
        CONNECTOR_TYPE="UdpConnector"
    else
        LISTENER_TYPE="TcpListener"
        CONNECTOR_TYPE="TcpConnector"
    fi
    
    cat << EOF > "${CONFIG_NAME}.json"
{
    "name": "${CONFIG_NAME}",
    "nodes": [
        {
            "name": "input",
            "type": "${LISTENER_TYPE}",
            "settings": {
                "address": "0.0.0.0",
                "port": [${START_PORT}, ${END_PORT}],
                "nodelay": true
            },
            "next": "output"
        },
        {
            "name": "output",
            "type": "${CONNECTOR_TYPE}",
            "settings": {
                "nodelay": true,
                "address": "${IP}",
                "port": ${PORT}
            }
        }
    ]
}
EOF
    if [ $? -eq 0 ]; then
        add_to_core_json "$CONFIG_NAME" "simple"
    fi

    echo "Simple ${PROTOCOL^^} Iran configuration file ${CONFIG_NAME}.json has been created successfully!"
    chmod 644 "${CONFIG_NAME}.json"
    open_firewall_ports "$START_PORT" "$END_PORT" "$PROTOCOL" "$PORT"
    exit 0
fi

# Check if it's the half configuration
if [ "$TYPE" = "half" ]; then
    # Check if haproxy flag is present for half configs
    USE_HAPROXY_HALF=false
    if [ "$2" = "haproxy" ]; then
        USE_HAPROXY_HALF=true
        WEBSITE="$3"
        PASSWORD="$4"
        shift 1  # Remove haproxy flag
    else
        WEBSITE="$2"
        PASSWORD="$3"
    fi
    
    if [ "$#" -lt 6 ]; then
        echo "Error: Half config needs website, password, and other parameters"
        exit 1
    fi
    
    # Check if fourth parameter is tcp, udp, or protocol is omitted
    if [ "$4" = "tcp" ] || [ "$4" = "udp" ]; then
        PROTOCOL="$4"
        CONFIG_TYPE="$5"  # iran or server
        if [ "$CONFIG_TYPE" = "iran" ]; then
            if [ "$#" -lt 10 ]; then
                if [ "$USE_HAPROXY_HALF" = true ]; then
                    echo "Error: Half haproxy iran config needs website, password, protocol, config_name, start_port, end_port, kharej_ip, kharej_port, and optional haproxy_port"
                else
                    echo "Error: Half iran config needs website, password, protocol, config_name, start_port, end_port, kharej_ip, and kharej_port"
                fi
                exit 1
            fi
            CONFIG_NAME="$6"
            START_PORT="$7"
            END_PORT="$8"
            KHAREJ_IP="$9"
            KHAREJ_PORT="${10}"
            HAPROXY_PORT="${11:-$((START_PORT + 1000))}"  # Optional haproxy port for half iran
        elif [ "$CONFIG_TYPE" = "server" ]; then
            if [ "$#" -lt 9 ]; then
                if [ "$USE_HAPROXY_HALF" = true ]; then
                    echo "Error: Half haproxy server config needs website, password, protocol, config_name, -p, port, iran_ip, and optional haproxy_port"
                else
                    echo "Error: Half server config needs website, password, protocol, config_name, -p, port, and iran_ip"
                fi
                exit 1
            fi
            CONFIG_NAME="$6"
            if [ "$7" != "-p" ]; then
                echo "Error: Half server config requires -p flag"
                exit 1
            fi
            PORT="$8"
            IRAN_IP="$9"
            HAPROXY_PORT="${10:-$((PORT + 1000))}"  # Optional haproxy port for half server
        fi
    else
        # Backward compatibility - default to TCP
        PROTOCOL="tcp"
        CONFIG_TYPE="$4"  # iran or server
        if [ "$CONFIG_TYPE" = "iran" ]; then
            if [ "$#" -lt 9 ]; then
                if [ "$USE_HAPROXY_HALF" = true ]; then
                    echo "Error: Half haproxy iran config needs website, password, config_name, start_port, end_port, kharej_ip, kharej_port, and optional haproxy_port"
                else
                    echo "Error: Half iran config needs website, password, config_name, start_port, end_port, kharej_ip, and kharej_port"
                fi
                exit 1
            fi
            CONFIG_NAME="$5"
            START_PORT="$6"
            END_PORT="$7"
            KHAREJ_IP="$8"
            KHAREJ_PORT="$9"
            HAPROXY_PORT="${10:-$((START_PORT + 1000))}"  # Optional haproxy port for half iran
        elif [ "$CONFIG_TYPE" = "server" ]; then
            if [ "$#" -lt 8 ]; then
                if [ "$USE_HAPROXY_HALF" = true ]; then
                    echo "Error: Half haproxy server config needs website, password, config_name, -p, port, iran_ip, and optional haproxy_port"
                else
                    echo "Error: Half server config needs website, password, config_name, -p, port, and iran_ip"
                fi
                exit 1
            fi
            CONFIG_NAME="$5"
            if [ "$6" != "-p" ]; then
                echo "Error: Half server config requires -p flag"
                exit 1
            fi
            PORT="$7"
            IRAN_IP="$8"
            HAPROXY_PORT="${9:-$((PORT + 1000))}"  # Optional haproxy port for half server
        fi
    fi
    
    # Set connection types based on protocol
    if [ "$PROTOCOL" = "udp" ]; then
        LISTENER_TYPE="UdpListener"
        CONNECTOR_TYPE="UdpConnector"
    else
        LISTENER_TYPE="TcpListener"
        CONNECTOR_TYPE="TcpConnector"
    fi
    
    if [ "$CONFIG_TYPE" = "iran" ]; then
        # Determine if IPv6 for kharej IP
        if [[ "$KHAREJ_IP" == *":"* ]]; then
            LISTEN_ADDRESS="::"
            IP_SUFFIX="/128"
        else
            LISTEN_ADDRESS="0.0.0.0"
            IP_SUFFIX="/32"
        fi
        
        # Create half Iran configuration
        cat << EOF > "${CONFIG_NAME}.json"
{
    "name": "${CONFIG_NAME}",
    "nodes": [
        {
            "name": "users_inbound",
            "type": "${LISTENER_TYPE}",
            "settings": {
                "address": "${LISTEN_ADDRESS}",
                "port": [${START_PORT},${END_PORT}],
                "nodelay": true
            },
            "next": "header"
        },
        {
            "name": "header",
            "type": "HeaderClient",
            "settings": {
                "data": "src_context->port"
            },
            "next": "bridge2"
        },
        {
            "name": "bridge2",
            "type": "Bridge",
            "settings": {
                "pair": "bridge1"
            }
        },
        {
            "name": "bridge1",
            "type": "Bridge",
            "settings": {
                "pair": "bridge2"
            }
        },
        {
            "name": "reverse_server",
            "type": "ReverseServer",
            "settings": {},
            "next": "bridge1"
        },
        {
            "name": "pbserver",
            "type": "ProtoBufServer",
            "settings": {},
            "next": "reverse_server"
        },
        {
            "name": "h2server",
            "type": "Http2Server",
            "settings": {},
            "next": "pbserver"
        },
        {
            "name": "halfs",
            "type": "HalfDuplexServer",
            "settings": {},
            "next": "h2server"
        },
        {
            "name": "reality_server",
            "type": "RealityServer",
            "settings": {
                "destination": "reality_dest",
                "password": "${PASSWORD}"
            },
            "next": "halfs"
        },
        {
            "name": "kharej_inbound",
            "type": "${LISTENER_TYPE}",
            "settings": {
                "address": "${LISTEN_ADDRESS}",
                "port": ${KHAREJ_PORT},
                "nodelay": true,
                "whitelist": [
                    "${KHAREJ_IP}${IP_SUFFIX}"
                ]
            },
            "next": "reality_server"
        },
        {
            "name": "reality_dest",
            "type": "${CONNECTOR_TYPE}",
            "settings": {
                "nodelay": true,
                "address": "${WEBSITE}",
                "port": 443
            }
        }
    ]
}
EOF
        
        if [ $? -eq 0 ]; then
            add_to_core_json "$CONFIG_NAME" "half"
            
            # Add HAProxy configuration for half iran configs
            if [ "$USE_HAPROXY_HALF" = true ]; then
                print_info "Setting up HAProxy configuration for half iran (client)..."
                
                # Use the configured haproxy port
                TUNNEL_PORT="$HAPROXY_PORT"
                
                # Create HAProxy client configuration
                create_haproxy_client_config "$CONFIG_NAME" "$TUNNEL_PORT" "$START_PORT"
                
                # Start HAProxy service  
                manage_haproxy_service "$TUNNEL_PORT" "start" "$TUNNEL_PORT"
                
                print_info "Half Iran with HAProxy:"
                print_info "  - Tunnel forwards to HAProxy: 127.0.0.1:$TUNNEL_PORT"
                print_info "  - HAProxy forwards to your service: 127.0.0.1:$START_PORT"
                print_info "  - Connect your service to: 127.0.0.1:$START_PORT"
            fi
        fi
        
        echo "Half ${PROTOCOL^^} Iran configuration file ${CONFIG_NAME}.json has been created successfully!"
        chmod 644 "${CONFIG_NAME}.json"
        open_firewall_ports "$START_PORT" "$END_PORT" "$PROTOCOL" "$KHAREJ_PORT"
        
    elif [ "$CONFIG_TYPE" = "server" ]; then
        # Create half server configuration
        cat << EOF > "${CONFIG_NAME}.json"
{
    "name": "${CONFIG_NAME}",
    "nodes": [
        {
            "name": "outbound_to_core",
            "type": "${CONNECTOR_TYPE}",
            "settings": {
                "nodelay": true,
                "address": "127.0.0.1",
                "port": ${PORT}
            }
        },
        {
            "name": "header",
            "type": "HeaderServer",
            "settings": {
                "override": "dest_context->port"
            },
            "next": "outbound_to_core"
        },
        {
            "name": "bridge1",
            "type": "Bridge",
            "settings": {
                "pair": "bridge2"
            },
            "next": "header"
        },
        {
            "name": "bridge2",
            "type": "Bridge",
            "settings": {
                "pair": "bridge1"
            },
            "next": "reverse_client"
        },
        {
            "name": "reverse_client",
            "type": "ReverseClient",
            "settings": {
                "minimum-unused": 16
            },
            "next": "pbclient"
        },
        {
            "name": "pbclient",
            "type": "ProtoBufClient",
            "settings": {},
            "next": "h2client"
        },
        {
            "name": "h2client",
            "type": "Http2Client",
            "settings": {
                "host": "${WEBSITE}",
                "port": 443,
                "path": "/",
                "content-type": "application/grpc",
                "concurrency": 64
            },
            "next": "halfc"
        },
        {
            "name": "halfc",
            "type": "HalfDuplexClient",
            "next": "reality_client"
        },
        {
            "name": "reality_client",
            "type": "RealityClient",
            "settings": {
                "sni": "${WEBSITE}",
                "password": "${PASSWORD}"
            },
            "next": "outbound_to_iran"
        },
        {
            "name": "outbound_to_iran",
            "type": "${CONNECTOR_TYPE}",
            "settings": {
                "nodelay": true,
                "address": "${IRAN_IP}",
                "port": ${PORT}
            }
        }
    ]
}
EOF
        
        if [ $? -eq 0 ]; then
            add_to_core_json "$CONFIG_NAME" "half"
            
            # Add HAProxy configuration for half server configs
            if [ "$USE_HAPROXY_HALF" = true ]; then
                print_info "Setting up HAProxy configuration for half server..."
                
                # Use the configured haproxy port
                EXTERNAL_PORT="$PORT"
                INTERNAL_PORT="$HAPROXY_PORT"
                
                # Create HAProxy server configuration
                create_haproxy_server_config "$CONFIG_NAME" "$EXTERNAL_PORT" "$INTERNAL_PORT"
                
                # Start HAProxy service
                manage_haproxy_service "$EXTERNAL_PORT" "start" "$INTERNAL_PORT"
                
                print_info "Half Server with HAProxy:"
                print_info "  - External clients connect to: *:$EXTERNAL_PORT"
                print_info "  - HAProxy forwards to internal: 127.0.0.1:$INTERNAL_PORT"
                print_info "  - Update your waterwall config to listen on: 127.0.0.1:$INTERNAL_PORT"
            fi
        fi
        
        echo "Half ${PROTOCOL^^} Server configuration file ${CONFIG_NAME}.json has been created successfully!"
        chmod 644 "${CONFIG_NAME}.json"
        open_firewall_ports "$PORT" "$PORT" "$PROTOCOL" "$PORT"
        
    else
        echo "Error: Half config type must be either 'iran' or 'server'"
        exit 1
    fi
    
    exit 0
fi

# --- V2 IRAN and V2 SERVER CONFIGS ---
if [ "$TYPE" = "v2" ]; then
    # Check if haproxy flag is present
    USE_HAPROXY=false
    if [ "$2" = "haproxy" ]; then
        USE_HAPROXY=true
        CONFIG_TYPE="$3"  # iran or server
        shift 1  # Remove haproxy flag
    else
        CONFIG_TYPE="$2"  # iran or server
    fi
    
    if [ "$CONFIG_TYPE" = "iran" ]; then
        # v2 iran config_name start-port end-port non-iran-ip iran-ip private-ip endpoint-port protocol [haproxy_port]
        if [ "$#" -lt 10 ]; then
            if [ "$USE_HAPROXY" = true ]; then
                echo "Usage: $0 v2 haproxy iran <config_name> <start_port> <end_port> <non_iran_ip> <iran_ip> <private_ip> <endpoint_port> <protocol> [haproxy_port]"
            else
                echo "Usage: $0 v2 iran <config_name> <start_port> <end_port> <non_iran_ip> <iran_ip> <private_ip> <endpoint_port> <protocol>"
            fi
            exit 1
        fi
        CONFIG_NAME="$3"
        START_PORT="$4"
        END_PORT="$5"
        NON_IRAN_IP="$6"
        IRAN_IP="$7"
        PRIVATE_IP="$8"
        ENDPOINT_PORT="$9"
        PROTOSWAP_TCP="${10}"
        HAPROXY_PORT="${11:-$((ENDPOINT_PORT + 1000))}"  # Optional haproxy port, default to endpoint_port + 1000

        # Calculate PRIVATE_IP+1 for output and ipovsrc2
        IFS='.' read -r ip1 ip2 ip3 ip4 <<< "$PRIVATE_IP"
        IP_PLUS1="$ip1.$ip2.$ip3.$((ip4+1))"

        cat << EOF > "${CONFIG_NAME}.json"
{
    "name": "${CONFIG_NAME}",
    "nodes": [
        {
            "name": "my tun",
            "type": "TunDevice",
            "settings": {
                "device-name": "${CONFIG_NAME}",
                "device-ip": "${PRIVATE_IP}/24"
            },
            "next": "ipovsrc"
        },
        {
            "name": "ipovsrc",
            "type": "IpOverrider",
            "settings": {
                "direction": "up",
                "mode": "source-ip",
                "ipv4": "${IRAN_IP}"
            },
            "next": "ipovdest"
        },
        {
            "name": "ipovdest",
            "type": "IpOverrider",
            "settings": {
                "direction": "up",
                "mode": "dest-ip",
                "ipv4": "${NON_IRAN_IP}"
            },
            "next": "manip"
        },
        {
            "name": "manip",
            "type": "IpManipulator",
            "settings": {
                "protoswap-tcp": ${PROTOSWAP_TCP}
            },
            "next": "ipovsrc2"
        },
        {
            "name": "ipovsrc2",
            "type": "IpOverrider",
            "settings": {
                "direction": "down",
                "mode": "source-ip",
                "ipv4": "${IP_PLUS1}"
            },
            "next": "ipovdest2"
        },
        {
            "name": "ipovdest2",
            "type": "IpOverrider",
            "settings": {
                "direction": "down",
                "mode": "dest-ip",
                "ipv4": "${PRIVATE_IP}"
            },
            "next": "rd"
        },
        {
            "name": "rd",
            "type": "RawSocket",
            "settings": {
                "capture-filter-mode": "source-ip",
                "capture-ip": "${NON_IRAN_IP}"
            }
        },
        {
            "name": "input",
            "type": "TcpListener",
            "settings": {
                "address": "0.0.0.0",
                "port": [${START_PORT},${END_PORT}],
                "nodelay": true
            },
            "next": "output"
        },
        {
            "name": "output",
            "type": "TcpConnector",
            "settings": {
                "nodelay": true,
                "address": "${IP_PLUS1}",
                "port": ${ENDPOINT_PORT}
            }
        }
    ]
}
EOF
        if [ $? -eq 0 ]; then
            add_to_core_json "$CONFIG_NAME" "v2"
            # Generate HAProxy configuration only if haproxy flag is used
            if [ "$USE_HAPROXY" = true ]; then
                print_info "Setting up HAProxy configuration for V2 iran (server)..."
                
                # V2 Iran acts as server - external clients connect to START_PORT, forward to waterwall on HAPROXY_PORT
                EXTERNAL_PORT="$START_PORT"
                INTERNAL_PORT="$HAPROXY_PORT"
                
                # Create HAProxy server configuration
                create_haproxy_server_config "$CONFIG_NAME" "$EXTERNAL_PORT" "$INTERNAL_PORT"
                
                # Start HAProxy service
                manage_haproxy_service "$EXTERNAL_PORT" "start" "$INTERNAL_PORT"
                
                print_info "V2 Iran with HAProxy:"
                print_info "  - External clients connect to: *:$EXTERNAL_PORT"
                print_info "  - HAProxy forwards to waterwall: 127.0.0.1:$INTERNAL_PORT"
                print_info "  - Update your waterwall config to listen on: 127.0.0.1:$INTERNAL_PORT"
            fi
        fi
        echo "V2 Iran configuration file ${CONFIG_NAME}.json has been created successfully!"
        chmod 644 "${CONFIG_NAME}.json"
        open_firewall_ports "$START_PORT" "$END_PORT" "tcp" "$ENDPOINT_PORT"
        exit 0
    elif [ "$CONFIG_TYPE" = "server" ]; then
        # v2 server config_name non-iran-ip iran-ip private-ip endpoint-port protocol [haproxy_port]
        if [ "$#" -lt 8 ]; then
            if [ "$USE_HAPROXY" = true ]; then
                echo "Usage: $0 v2 haproxy server <config_name> <non_iran_ip> <iran_ip> <private_ip> <endpoint_port> <protocol> [haproxy_port]"
            else
                echo "Usage: $0 v2 server <config_name> <non_iran_ip> <iran_ip> <private_ip> <endpoint_port> <protocol>"
            fi
            exit 1
        fi
        CONFIG_NAME="$3"
        NON_IRAN_IP="$4"
        IRAN_IP="$5"
        PRIVATE_IP="$6"
        ENDPOINT_PORT="$7"
        PROTOSWAP_TCP="$8"
        HAPROXY_PORT="${9:-$((ENDPOINT_PORT + 1000))}"  # Optional haproxy port, default to endpoint_port + 1000

        # Check if HAProxy is installed only when haproxy flag is used
        if [ "$USE_HAPROXY" = true ]; then
            if ! command -v haproxy >/dev/null 2>&1; then
                echo "Error: HAProxy is not installed!"
                echo "Please install HAProxy first:"
                echo "  Ubuntu/Debian: sudo apt update && sudo apt install haproxy"
                echo "  CentOS/RHEL/Fedora: sudo yum install haproxy  or  sudo dnf install haproxy"
                echo "  Arch Linux: sudo pacman -S haproxy"
                exit 1
            fi
        fi

        # Calculate PRIVATE_IP+1 for ipovsrc2
        IFS='.' read -r ip1 ip2 ip3 ip4 <<< "$PRIVATE_IP"
        IP_PLUS1="$ip1.$ip2.$ip3.$((ip4+1))"

        cat << EOF > "${CONFIG_NAME}.json"
{
    "name": "${CONFIG_NAME}",
    "nodes": [
        {
            "name": "rd",
            "type": "RawSocket",
            "settings": {
                "capture-filter-mode": "source-ip",
                "capture-ip": "${IRAN_IP}"
            },
            "next": "ipovsrc"
        },
        {
            "name": "ipovsrc",
            "type": "IpOverrider",
            "settings": {
                "direction": "down",
                "mode": "source-ip",
                "ipv4": "${NON_IRAN_IP}"
            },
            "next": "ipovdest"
        },
        {
            "name": "ipovdest",
            "type": "IpOverrider",
            "settings": {
                "direction": "down",
                "mode": "dest-ip",
                "ipv4": "${IRAN_IP}"
            },
            "next": "manip"
        },
        {
            "name": "manip",
            "type": "IpManipulator",
            "settings": {
                "protoswap-tcp": ${PROTOSWAP_TCP}
            },
            "next": "ipovsrc2"
        },
        {
            "name": "ipovsrc2",
            "type": "IpOverrider",
            "settings": {
                "direction": "up",
                "mode": "source-ip",
                "ipv4": "${IP_PLUS1}"
            },
            "next": "ipovdest2"
        },
        {
            "name": "ipovdest2",
            "type": "IpOverrider",
            "settings": {
                "direction": "up",
                "mode": "dest-ip",
                "ipv4": "${PRIVATE_IP}"
            },
            "next": "my tun"
        },
        {
            "name": "my tun",
            "type": "TunDevice",
            "settings": {
                "device-name": "${CONFIG_NAME}",
                "device-ip": "${PRIVATE_IP}/24"
            }
        }
    ]
}
EOF
        if [ $? -eq 0 ]; then
            add_to_core_json "$CONFIG_NAME" "v2"
            # Generate HAProxy configuration only if haproxy flag is used
            if [ "$USE_HAPROXY" = true ]; then
                print_info "Setting up HAProxy configuration for V2 server..."
                
                # Use the configured haproxy port
                INTERNAL_PORT="$HAPROXY_PORT"
                
                # Create HAProxy server configuration
                create_haproxy_server_config "$CONFIG_NAME" "$ENDPOINT_PORT" "$INTERNAL_PORT"
                
                # Start HAProxy service
                manage_haproxy_service "$ENDPOINT_PORT" "start" "$INTERNAL_PORT"
                
                print_info "V2 Server with HAProxy:"
                print_info "  - External clients connect to: $PRIVATE_IP:$ENDPOINT_PORT"
                print_info "  - HAProxy forwards to internal: 127.0.0.1:$INTERNAL_PORT"
                print_info "  - Connect your waterwall tunnel to: 127.0.0.1:$INTERNAL_PORT"
            fi
        fi
        echo "V2 Server configuration file ${CONFIG_NAME}.json has been created successfully!"
        if [ "$USE_HAPROXY" = false ]; then
            echo ""
            echo "Note: To use HAProxy with this config, run:"
            echo "$0 v2 haproxy server $CONFIG_NAME $NON_IRAN_IP $IRAN_IP $PRIVATE_IP $ENDPOINT_PORT $PROTOSWAP_TCP"
        fi
        chmod 644 "${CONFIG_NAME}.json"
        # V2 server doesn't need port range opening since it doesn't listen on external ports
        exit 0
    else
        echo "Error: v2 config type must be either 'iran' or 'server'"
        if [ "$USE_HAPROXY" = true ]; then
            echo "For HAProxy configs, use: v2 haproxy server ..."
        fi
        exit 1
    fi
fi

if [ "$TYPE" = "server" ]; then
    # Check if second parameter is a protocol
    if [ "$2" = "tcp" ] || [ "$2" = "udp" ]; then
        PROTOCOL="$2"
        CONFIG_NAME="$3"
        shift 3  # Remove 'server', protocol, and config_name
    else
        # Default to TCP for backward compatibility
        PROTOCOL="tcp"
        CONFIG_NAME="$2"
        shift 2  # Remove 'server' and config_name
    fi
    
    # Set connection types based on protocol
    if [ "$PROTOCOL" = "udp" ]; then
        LISTENER_TYPE="UdpListener"
        CONNECTOR_TYPE="UdpConnector"
    else
        LISTENER_TYPE="TcpListener"
        CONNECTOR_TYPE="TcpConnector"
    fi
    
    # Server configuration logic
    if [ "$1" = "-p" ]; then
        if [ "$#" -lt 3 ]; then
            echo "Error: Server config with -p needs port and at least one server address"
            exit 1
        fi
        COMMON_PORT="$2"
        shift 2
        
        # Check if last argument is a number (potential haproxy_port)
        # Only for haproxy legacy configs and when we have extra arguments
        if [ "$USE_HAPROXY_LEGACY" = true ] && [ "$#" -gt 1 ]; then
            # Check if last argument is numeric (potential haproxy port)
            last_arg="${@: -1}"
            if [[ "$last_arg" =~ ^[0-9]+$ ]]; then
                # Remove last argument and use it as haproxy port
                set -- "${@:1:$(($#-1))}"
                HAPROXY_PORT="$last_arg"
            else
                HAPROXY_PORT=$((COMMON_PORT + 1000))
            fi
        else
            HAPROXY_PORT=$((COMMON_PORT + 1000))
        fi
        
        SERVER_COUNT=$#
        
        # Convert addresses-only format to address-port pairs
        SERVERS=()
        for addr in "$@"; do
            SERVERS+=("$addr" "$COMMON_PORT")
        done
        set -- "${SERVERS[@]}"
    else
        if [ "$#" -lt 2 ]; then
            echo "Error: Server config needs at least one server address and port"
            exit 1
        fi
        
        if [ $(( $# % 2 )) -ne 0 ]; then
            echo "Error: Each server must have both address and port"
            exit 1
        fi
        SERVER_COUNT=$(( $# / 2 ))
    fi

    # Start JSON configuration
    cat << EOF > "${CONFIG_NAME}.json"
{
    "name": "${CONFIG_NAME}",
    "nodes": [
EOF

    # Generate configuration for each server
    for ((i=1; i<=SERVER_COUNT; i++)); do
        ADDRESS=$1
        PORT=$2
        shift 2

        # For all servers after the first, prefix with comma
        if [ $i -gt 1 ]; then
            cat << EOF >> "${CONFIG_NAME}.json"
        ,
EOF
        fi

        cat << EOF >> "${CONFIG_NAME}.json"
        {
            "name": "core${i}_connector",
            "type": "${CONNECTOR_TYPE}",
            "settings": {
                "nodelay": true,
                "address": "127.0.0.1",
                "port": ${PORT}
            }
        },
        {
            "name": "bridge_core${i}_in",
            "type": "Bridge",
            "settings": {
                "pair": "bridge_core${i}_out"
            },
            "next": "core${i}_connector"
        },
        {
            "name": "bridge_core${i}_out",
            "type": "Bridge",
            "settings": {
                "pair": "bridge_core${i}_in"
            },
            "next": "reverse_iran${i}"
        },
        {
            "name": "reverse_iran${i}",
            "type": "ReverseClient",
            "settings": {
                "minimum-unused": 16
            },
            "next": "iran${i}_connector"
        },
        {
            "name": "iran${i}_connector",
            "type": "${CONNECTOR_TYPE}",
            "settings": {
                "nodelay": true,
                "address": "${ADDRESS}",
                "port": ${PORT}
            }
        }
EOF
    done

elif [ "$TYPE" = "iran" ]; then
    # Check if second parameter is a protocol
    if [ "$2" = "tcp" ] || [ "$2" = "udp" ]; then
        PROTOCOL="$2"
        CONFIG_NAME="$3"
        shift 3  # Remove 'iran', protocol, and config_name
    else
        # Default to TCP for backward compatibility
        PROTOCOL="tcp"
        CONFIG_NAME="$2"
        shift 2  # Remove 'iran' and config_name
    fi
    
    # Set connection types based on protocol
    if [ "$PROTOCOL" = "udp" ]; then
        LISTENER_TYPE="UdpListener"
        CONNECTOR_TYPE="UdpConnector"
    else
        LISTENER_TYPE="TcpListener"
        CONNECTOR_TYPE="TcpConnector"
    fi
    
    # Iran configuration logic
    if [ "$#" -lt 4 ]; then
        echo "Error: Iran config needs start_port, end_port, kharej_ip, and kharej_port"
        exit 1
    fi

    START_PORT="$1"
    END_PORT="$2"
    KHAREJ_IP="$3"
    KHAREJ_PORT="$4"
    HAPROXY_PORT="${5:-$((START_PORT + 1000))}"  # Optional haproxy port, default to start_port + 1000

    # Determine if IPv6
    if [[ "$KHAREJ_IP" == *":"* ]]; then
        LISTEN_ADDRESS="::"
        IP_SUFFIX="/128"
    else
        LISTEN_ADDRESS="0.0.0.0"
        IP_SUFFIX="/32"
    fi

    # Create Iran configuration
    cat << EOF > "${CONFIG_NAME}.json"
{
    "name": "${CONFIG_NAME}",
    "nodes": [
        {
            "name": "users_inbound",
            "type": "${LISTENER_TYPE}",
            "settings": {
                "address": "${LISTEN_ADDRESS}",
                "port": [${START_PORT},${END_PORT}],
                "nodelay": true
            },
            "next":  "bridge2"
        },
        {
            "name": "bridge2",
            "type": "Bridge",
            "settings": {
                "pair": "bridge1"
            }
        },
        {
            "name": "bridge1",
            "type": "Bridge",
            "settings": {
                "pair": "bridge2"
            }
        },
        {
            "name": "reverse_server",
            "type": "ReverseServer",
            "settings": {},
            "next": "bridge1"
        },
        {
            "name": "kharej_inbound",
            "type": "${LISTENER_TYPE}",
            "settings": {
                "address": "${LISTEN_ADDRESS}",
                "port": ${KHAREJ_PORT},
                "nodelay": true,
                "whitelist": [
                    "${KHAREJ_IP}${IP_SUFFIX}"
                ]
            },
            "next": "reverse_server"
        }
    ]
}
EOF

    # Add HAProxy configuration for legacy iran configs
    if [ "$USE_HAPROXY_LEGACY" = true ]; then
        print_info "Setting up HAProxy configuration for legacy iran (client)..."
        
        # Use the configured haproxy port
        TUNNEL_PORT="$HAPROXY_PORT"
        
        # Create HAProxy client configuration
        create_haproxy_client_config "$CONFIG_NAME" "$TUNNEL_PORT" "$START_PORT"
        
        # Start HAProxy service  
        manage_haproxy_service "$TUNNEL_PORT" "start" "$TUNNEL_PORT"
        
        print_info "Legacy Iran with HAProxy:"
        print_info "  - Tunnel forwards to HAProxy: 127.0.0.1:$TUNNEL_PORT"
        print_info "  - HAProxy forwards to your service: 127.0.0.1:$START_PORT"
        print_info "  - Connect your service to: 127.0.0.1:$START_PORT"
    fi

else
    echo "Error: First parameter must be either 'server', 'iran', or 'v2'"
    exit 1
fi

# Close JSON structure for server type (iran type already closed)
if [ "$TYPE" = "server" ]; then
    cat << EOF >> "${CONFIG_NAME}.json"

    ]
}
EOF
fi

echo "Configuration file ${CONFIG_NAME}.json has been created successfully!"

# After successful config creation, add to core.json
if [ $? -eq 0 ]; then
    add_to_core_json "$CONFIG_NAME" "$TYPE"
    
    # Add HAProxy configuration for legacy server configs
    if [ "$USE_HAPROXY_LEGACY" = true ] && [ "$TYPE" = "server" ]; then
        print_info "Setting up HAProxy configuration for legacy server..."
        
        # For legacy server configs, use the common port as external port
        if [ -n "$COMMON_PORT" ]; then
            EXTERNAL_PORT="$COMMON_PORT"
            INTERNAL_PORT="$HAPROXY_PORT"
            
            # Create HAProxy server configuration
            create_haproxy_server_config "$CONFIG_NAME" "$EXTERNAL_PORT" "$INTERNAL_PORT"
            
            # Start HAProxy service
            manage_haproxy_service "$EXTERNAL_PORT" "start" "$INTERNAL_PORT"
            
            print_info "Legacy Server with HAProxy:"
            print_info "  - External clients connect to: *:$EXTERNAL_PORT"
            print_info "  - HAProxy forwards to internal: 127.0.0.1:$INTERNAL_PORT"
            print_info "  - Update your waterwall config to listen on: 127.0.0.1:$INTERNAL_PORT"
        else
            print_warning "HAProxy support for multi-port server configs not implemented yet"
        fi
    fi
    
    # Add HAProxy configuration for legacy iran configs  
    if [ "$USE_HAPROXY_LEGACY" = true ] && [ "$TYPE" = "iran" ]; then
        # HAProxy configuration was already handled in the iran section above
        print_info "HAProxy configuration for iran completed above"
    fi
fi

chmod 644 "${CONFIG_NAME}.json"

# Open firewall ports for server type configurations
if [ "$TYPE" = "server" ]; then
    for ((i=1; i<=SERVER_COUNT; i++)); do
        PORT=$(( $2 + i - 1 ))
        open_firewall_ports "$PORT" "$PORT" "tcp" "$PORT"
        shift 2
    done
fi
