#!/bin/bash

# Half Configuration Module for Waterwall
# Handles Reality/gRPC tunneling configurations

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/haproxy.sh"
source "$SCRIPT_DIR/gost.sh"

# Half Configuration
create_half_config() {
    local website="$1"
    local password="$2"
    local protocol="$3"
    local type="$4"
    local config_name="$5"
    local use_haproxy="$6"
    local use_gost="$7"
    shift 7
    local remaining_args=("$@")

    # Determine protocol type
    if [ "$protocol" = "tcp" ]; then
        LISTENER_TYPE="TcpListener"
        CONNECTOR_TYPE="TcpConnector"
    elif [ "$protocol" = "udp" ]; then
        LISTENER_TYPE="UdpListener"
        CONNECTOR_TYPE="UdpConnector"
    else
        echo "Error: Protocol must be 'tcp' or 'udp'"
        exit 1
    fi

    if [ "$type" = "server" ]; then
        # server config: -p port server_ip [haproxy_port]
        local port_flag="${remaining_args[0]}"
        local port="${remaining_args[1]}"
        local server_ip="${remaining_args[2]}"
        local haproxy_port="${remaining_args[3]}"
        
        if [ "$port_flag" != "-p" ] || [ -z "$port" ] || [ -z "$server_ip" ]; then
            echo "Error: Invalid server configuration parameters"
            echo "Usage: half <website> <password> [tcp|udp] server <config_name> -p <port> <server_ip> [haproxy_port]"
            exit 1
        fi
        
        # Set default haproxy_port if not provided
        if [ -z "$haproxy_port" ]; then
            haproxy_port=$((port + 1000))
        fi
        
    # Determine listener port based on proxy usage
        local waterwall_listen_port
    if [ "$use_haproxy" = true ] || [ "$use_gost" = true ]; then
            waterwall_listen_port="$haproxy_port"
        else
            waterwall_listen_port="$port"
        fi

        cat << EOF > "${config_name}.json"
{
    "name": "${config_name}",
    "nodes": [
        {
            "name": "input",
            "type": "${LISTENER_TYPE}",
            "settings": {
                "address": "0.0.0.0",
                "port": ${waterwall_listen_port},
                "nodelay": true
            },
            "next": "output"
        },
        {
            "name": "output",
            "type": "RealityGrpcClient",
            "settings": {
                "multi-stream": true,
                "password": "${password}",
                "server-name": "${website}",
                "address": "${server_ip}",
                "port": 443,
                "nodelay": true
            }
        }
    ]
}
EOF

        if [ $? -eq 0 ]; then
            add_to_core_json "$config_name" "half"
            
            # Generate proxy configuration if requested
            if [ "$use_haproxy" = true ]; then
                print_info "Setting up HAProxy configuration for Half server..."
                
                # Half server acts as server - external clients connect to port, forward to waterwall on internal port
                create_haproxy_server_config "$config_name" "$port" "127.0.0.1" "$haproxy_port" "$protocol"
                manage_haproxy_service
                
                print_info "Half Server with HAProxy:"
                print_info "- External clients connect to port: $port"
                print_info "- HAProxy forwards to waterwall on: $haproxy_port"
                
                open_firewall_ports "$port" "$port"
            elif [ "$use_gost" = true ]; then
                print_info "Setting up GOST configuration for Half server..."
                create_gost_server_config "$config_name" "$port" "127.0.0.1" "$haproxy_port" "$protocol"
                manage_gost_service "$config_name"

                print_info "Half Server with GOST:"
                print_info "- External clients connect to port: $port"
                print_info "- GOST forwards to waterwall on: $haproxy_port (Proxy Protocol)"

                open_firewall_ports "$port" "$port"
            else
                open_firewall_ports "$port" "$port"
            fi
            
            echo "Half server configuration file ${config_name}.json has been created successfully!"
            echo "Reality/gRPC server connecting to: ${website} via ${server_ip}:443"
        else
            echo "Error: Failed to create half server configuration file"
            exit 1
        fi

    elif [ "$type" = "client" ]; then
        # client config: start_port end_port destination_ip destination_port [haproxy_port]
        local start_port="${remaining_args[0]}"
        local end_port="${remaining_args[1]}"
        local destination_ip="${remaining_args[2]}"
        local destination_port="${remaining_args[3]}"
        local haproxy_port="${remaining_args[4]}"
        
        if [ -z "$start_port" ] || [ -z "$end_port" ] || [ -z "$destination_ip" ] || [ -z "$destination_port" ]; then
            echo "Error: Invalid client configuration parameters"
            echo "Usage: half <website> <password> [tcp|udp] client <config_name> <start_port> <end_port> <destination_ip> <destination_port> [haproxy_port]"
            exit 1
        fi
        
        # Set default haproxy_port if not provided
        if [ -z "$haproxy_port" ]; then
            haproxy_port=$((start_port + 1000))
        fi

        cat << EOF > "${config_name}.json"
{
    "name": "${config_name}",
    "nodes": [
        {
            "name": "input",
            "type": "RealityGrpcServer",
            "settings": {
                "multi-stream": true,
                "password": "${password}",
                "server-name": "${website}",
                "address": "0.0.0.0",
                "port": 443,
                "nodelay": true
            },
            "next": "output"
        },
        {
            "name": "output",
            "type": "${CONNECTOR_TYPE}",
            "settings": {
                "nodelay": true,
                "address": "${destination_ip}",
                "port": ${destination_port}
            }
        }
    ]
}
EOF

        if [ $? -eq 0 ]; then
            add_to_core_json "$config_name" "half"
            
            # Generate proxy configuration if requested
            if [ "$use_haproxy" = true ]; then
                print_info "Setting up HAProxy configuration for Half client..."
                
                # Half client: tunnel connects to HAProxy, which forwards to application
                create_haproxy_client_config "$config_name" "127.0.0.1" "$haproxy_port" "$destination_ip" "$destination_port" "$protocol"
                manage_haproxy_service
                
                print_info "Half Client with HAProxy:"
                print_info "- Tunnel connects to HAProxy on: $haproxy_port"
                print_info "- HAProxy forwards to: ${destination_ip}:${destination_port}"
            elif [ "$use_gost" = true ]; then
                print_info "Setting up GOST configuration for Half client..."

                # Half client: tunnel connects to GOST listener, which forwards to application sending Proxy Protocol
                create_gost_client_config "$config_name" "127.0.0.1" "$haproxy_port" "$destination_ip" "$destination_port" "$protocol"
                manage_gost_service "$config_name"

                print_info "Half Client with GOST:"
                print_info "- Tunnel connects to GOST on: $haproxy_port (accept Proxy Protocol)"
                print_info "- GOST forwards to: ${destination_ip}:${destination_port} (send Proxy Protocol)"
            else
                open_firewall_ports "$start_port" "$end_port"
            fi
            
            echo "Half client configuration file ${config_name}.json has been created successfully!"
            echo "Reality/gRPC client serving: ${website}"
            echo "Port range: ${start_port}-${end_port} -> ${destination_ip}:${destination_port}"
        else
            echo "Error: Failed to create half client configuration file"
            exit 1
        fi
    else
        echo "Error: Type must be either 'server' or 'client'"
        exit 1
    fi
}

# Main half handler function
handle_half_config() {
    local website="$2"
    local password="$3"
    local protocol="tcp"  # Default protocol
    local type
    local config_name
    local use_haproxy=false
    local use_gost=false
    local param_offset=4
    
    # Check if proxy flag is present after password
    if [ "$4" = "haproxy" ]; then
        use_haproxy=true
        param_offset=5
    elif [ "$4" = "gost" ]; then
        use_gost=true
        param_offset=5
    fi
    
    # Check if protocol is explicitly specified
    if [ "${!param_offset}" = "tcp" ] || [ "${!param_offset}" = "udp" ]; then
        protocol="${!param_offset}"
        param_offset=$((param_offset + 1))
    fi
    
    type="${!param_offset}"
    config_name="${!$((param_offset + 1))}"
    
    # Validate required parameters
    if [ -z "$website" ] || [ -z "$password" ] || [ -z "$type" ] || [ -z "$config_name" ]; then
        echo "Usage: $0 half <website> <password> [haproxy] [tcp|udp] <type> <config_name> [additional_params...]"
        echo "Example: $0 half web-cdn.snapp.ir mypass haproxy tcp server myconfig -p 8080 192.168.1.100"
        exit 1
    fi
    
    # Get remaining arguments
    shift $((param_offset + 1))
    
    create_half_config "$website" "$password" "$protocol" "$type" "$config_name" "$use_haproxy" "$use_gost" "$@"
}
