#!/bin/bash

# Server and Client Configuration Module for Waterwall
# Handles standard server and client load balancing configurations

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/haproxy.sh"

# Server Configuration (Load Balancer)
create_server_config() {
    local config_name="$1"
    local use_haproxy="$2"
    shift 2
    local servers=("$@")
    
    local use_port_flag=false
    local common_port=""
    local server_addresses=()
    local server_ports=()
    
    # Check if -p flag is used for common port
    if [ "${servers[0]}" = "-p" ]; then
        use_port_flag=true
        common_port="${servers[1]}"
        # Remove -p and port from servers array
        servers=("${servers[@]:2}")
    fi
    
    # Parse server list
    if [ "$use_port_flag" = true ]; then
        # All servers use the same port
        for server in "${servers[@]}"; do
            server_addresses+=("$server")
            server_ports+=("$common_port")
        done
    else
        # Each server has its own port
        if [ $((${#servers[@]} % 2)) -ne 0 ]; then
            echo "Error: Each server must have a corresponding port"
            exit 1
        fi
        
        for ((i=0; i<${#servers[@]}; i+=2)); do
            server_addresses+=("${servers[i]}")
            server_ports+=("${servers[i+1]}")
        done
    fi
    
    # Determine address type for listen settings
    local listen_address="0.0.0.0"
    local whitelist_suffix="/32"
    
    # Check if any server is IPv6
    for addr in "${server_addresses[@]}"; do
        if [[ "$addr" =~ .*:.* ]]; then
            listen_address="::"
            whitelist_suffix="/128"
            break
        fi
    done

    cat << EOF > "${config_name}.json"
{
    "name": "${config_name}",
    "nodes": [
        {
            "name": "input",
            "type": "TcpListener",
            "settings": {
                "address": "${listen_address}",
                "port": ${common_port:-8080},
                "nodelay": true,
                "whitelist": [
EOF

    # Add whitelist entries for each server
    for i in "${!server_addresses[@]}"; do
        if [ $i -gt 0 ]; then
            echo "," >> "${config_name}.json"
        fi
        echo "                    \"${server_addresses[i]}${whitelist_suffix}\"" >> "${config_name}.json"
    done

    cat << EOF >> "${config_name}.json"
                ]
            },
            "next": "output"
        },
        {
            "name": "output",
            "type": "TcpConnector",
            "settings": {
                "nodelay": true,
                "servers": [
EOF

    # Add server entries
    for i in "${!server_addresses[@]}"; do
        if [ $i -gt 0 ]; then
            echo "," >> "${config_name}.json"
        fi
        cat << EOF >> "${config_name}.json"
                    {
                        "address": "${server_addresses[i]}",
                        "port": ${server_ports[i]}
                    }
EOF
    done

    cat << EOF >> "${config_name}.json"
                ]
            }
        }
    ]
}
EOF

    if [ $? -eq 0 ]; then
        add_to_core_json "$config_name" "server"
        
        # Generate HAProxy configuration only if haproxy flag is used
        if [ "$use_haproxy" = true ]; then
            print_info "Setting up HAProxy configuration for server..."
            
            local haproxy_port=$((common_port + 1000))
            create_haproxy_server_config "$config_name" "$common_port" "127.0.0.1" "$haproxy_port" "tcp"
            manage_haproxy_service
            
            print_info "Server with HAProxy:"
            print_info "- External clients connect to port: $common_port"
            print_info "- HAProxy forwards to waterwall on: $haproxy_port"
            
            open_firewall_ports "$common_port" "$common_port"
        else
            open_firewall_ports "$common_port" "$common_port"
        fi
        
        echo "Server configuration file ${config_name}.json has been created successfully!"
        echo "Load balancing between ${#server_addresses[@]} servers"
    else
        echo "Error: Failed to create server configuration file"
        exit 1
    fi
}

# Client Configuration (Iran-side)
create_client_config() {
    local config_name="$1"
    local start_port="$2"
    local end_port="$3"
    local kharej_ip="$4"
    local kharej_port="$5"
    local use_haproxy="$6"
    local haproxy_port="$7"

    # Set default haproxy_port if not provided
    if [ -z "$haproxy_port" ]; then
        haproxy_port=$((start_port + 1000))
    fi

    # Determine listener port based on HAProxy usage
    local waterwall_listen_port
    if [ "$use_haproxy" = true ]; then
        waterwall_listen_port="$haproxy_port"
    else
        waterwall_listen_port="[${start_port},${end_port}]"
    fi

    # Determine address type
    local listen_address="0.0.0.0"
    local whitelist_suffix="/32"
    
    if [[ "$kharej_ip" =~ .*:.* ]]; then
        listen_address="::"
        whitelist_suffix="/128"
    fi

    cat << EOF > "${config_name}.json"
{
    "name": "${config_name}",
    "nodes": [
        {
            "name": "input",
            "type": "TcpListener",
            "settings": {
                "address": "${listen_address}",
                "port": ${waterwall_listen_port},
                "nodelay": true,
                "whitelist": [
                    "${kharej_ip}${whitelist_suffix}"
                ]
            },
            "next": "output"
        },
        {
            "name": "output",
            "type": "TcpConnector",
            "settings": {
                "nodelay": true,
                "address": "${kharej_ip}",
                "port": ${kharej_port}
            }
        }
    ]
}
EOF

    if [ $? -eq 0 ]; then
        add_to_core_json "$config_name" "client"
        
        # Generate HAProxy configuration only if haproxy flag is used
        if [ "$use_haproxy" = true ]; then
            print_info "Setting up HAProxy configuration for client..."
            
            # Client configuration: HAProxy handles port range and forwards to waterwall
            create_haproxy_client_config_range "$config_name" "$start_port" "$end_port" "127.0.0.1" "$haproxy_port" "tcp"
            manage_haproxy_service
            
            print_info "Client with HAProxy:"
            print_info "- External services connect to ports: $start_port-$end_port"
            print_info "- HAProxy forwards to waterwall on: $haproxy_port"
            print_info "- Waterwall connects to: ${kharej_ip}:${kharej_port}"
            
            open_firewall_ports "$start_port" "$end_port"
        else
            open_firewall_ports "$start_port" "$end_port"
        fi
        
        echo "Client configuration file ${config_name}.json has been created successfully!"
        echo "Port range: ${start_port}-${end_port} -> ${kharej_ip}:${kharej_port}"
    else
        echo "Error: Failed to create client configuration file"
        exit 1
    fi
}

# Main server handler function
handle_server_config() {
    local use_haproxy=false
    local config_name
    local param_offset=2
    
    # Check if haproxy flag is present
    if [ "$2" = "haproxy" ]; then
        use_haproxy=true
        param_offset=4  # Skip "haproxy server tcp"
    fi
    
    case $param_offset in
        2) config_name="$2" ;;
        4) config_name="$4" ;;
    esac
    
    # Validate required parameters
    if [ -z "$config_name" ]; then
        echo "Usage: $0 server [haproxy] <config_name> [-p <port>] <server1> [<port1>] [<server2> <port2>] ..."
        echo "Example: $0 server myconfig -p 8080 192.168.1.100 10.0.0.50"
        exit 1
    fi
    
    # Get remaining arguments (servers and ports)
    shift $param_offset
    
    create_server_config "$config_name" "$use_haproxy" "$@"
}

# Main client handler function  
handle_client_config() {
    local use_haproxy=false
    local param_offset=2
    
    # Check if haproxy flag is present
    if [ "$2" = "haproxy" ]; then
        use_haproxy=true
        param_offset=4  # Skip "haproxy client tcp"
    fi
    
    local config_name
    local start_port
    local end_port
    local kharej_ip
    local kharej_port
    local haproxy_port
    
    case $param_offset in
        2)
            config_name="$2"
            start_port="$3"
            end_port="$4"
            kharej_ip="$5"
            kharej_port="$6"
            haproxy_port="$7"
            ;;
        4)
            config_name="$4"
            start_port="$5"
            end_port="$6"
            kharej_ip="$7"
            kharej_port="$8"
            haproxy_port="$9"
            ;;
    esac
    
    # Validate required parameters
    if [ -z "$config_name" ] || [ -z "$start_port" ] || [ -z "$end_port" ] || [ -z "$kharej_ip" ] || [ -z "$kharej_port" ]; then
        echo "Usage: $0 client [haproxy] <config_name> <start_port> <end_port> <kharej_ip> <kharej_port> [haproxy_port]"
        echo "Example: $0 client myconfig 14000 14999 192.168.1.100 13787"
        exit 1
    fi
    
    create_client_config "$config_name" "$start_port" "$end_port" "$kharej_ip" "$kharej_port" "$use_haproxy" "$haproxy_port"
}
