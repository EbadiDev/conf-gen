#!/bin/bash

# Simple Configuration Module for Waterwall
# Handles simple TCP/UDP port forwarding configurations

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Simple Configuration
create_simple_config() {
    local protocol="$1"
    local type="$2"
    local config_name="$3"
    local start_port="$4"
    local end_port="$5"
    local destination_ip="$6"
    local destination_port="$7"

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

    # Determine address type and settings
    if [[ "$destination_ip" =~ .*:.* ]]; then
        # IPv6 address
        LISTEN_ADDRESS="::"
        WHITELIST_SUFFIX="/128"
    else
        # IPv4 address
        LISTEN_ADDRESS="0.0.0.0"
        WHITELIST_SUFFIX="/32"
    fi

    cat << EOF > "${config_name}.json"
{
    "name": "${config_name}",
    "nodes": [
        {
            "name": "input",
            "type": "${LISTENER_TYPE}",
            "settings": {
                "address": "${LISTEN_ADDRESS}",
                "port": [${start_port}, ${end_port}],
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
        add_to_core_json "$config_name" "simple"
        open_firewall_ports "$start_port" "$end_port"
        echo "Simple ${protocol^^} configuration file ${config_name}.json has been created successfully!"
        echo "Forwarding ports ${start_port}-${end_port} to ${destination_ip}:${destination_port}"
    else
        echo "Error: Failed to create simple configuration file"
        exit 1
    fi
}

# Main simple handler function
handle_simple_config() {
    local protocol="tcp"  # Default protocol
    local type_pos=2
    
    # Check if protocol is explicitly specified
    if [ "$2" = "tcp" ] || [ "$2" = "udp" ]; then
        protocol="$2"
        type_pos=3
    fi
    
    local type
    local config_name
    local start_port
    local end_port
    local destination_ip
    local destination_port
    
    case $type_pos in
        2)
            type="$2"
            config_name="$3"
            start_port="$4"
            end_port="$5"
            destination_ip="$6"
            destination_port="$7"
            ;;
        3)
            type="$3"
            config_name="$4"
            start_port="$5"
            end_port="$6"
            destination_ip="$7"
            destination_port="$8"
            ;;
    esac
    
    # Validate required parameters
    if [ -z "$destination_port" ]; then
        echo "Usage: $0 simple [tcp|udp] <type> <config_name> <start_port> <end_port> <destination_ip> <destination_port>"
        echo "Example: $0 simple tcp server myconfig 100 199 192.168.1.100 8080"
        exit 1
    fi
    
    create_simple_config "$protocol" "$type" "$config_name" "$start_port" "$end_port" "$destination_ip" "$destination_port"
}
