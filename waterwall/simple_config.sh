#!/bin/bash

# Simple Configuration Module for Waterwall
# Handles simple TCP/UDP port forwarding configurations, with optional GOST front

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/gost.sh"

# Simple Configuration
create_simple_config() {
    local protocol="$1"
    local type="$2"
    local config_name="$3"
    local start_port="$4"
    local end_port="$5"
    local destination_ip="$6"
    local destination_port="$7"
    local use_gost="${8:-false}"
    local internal_port="${9}"
    local ss_password="${10:-${GOST_SS_PASSWORD:-apple123ApPle}}"

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

    # Choose listener port(s)
    local listen_port_json
    local effective_internal_port
    if [ "$use_gost" = true ]; then
        # Use a single internal port and put GOST in front to handle external range
        if [ -z "$internal_port" ]; then
            effective_internal_port=$((start_port + 1000))
        else
            effective_internal_port="$internal_port"
        fi
        listen_port_json=${effective_internal_port}
    else
        listen_port_json="[${start_port}, ${end_port}]"
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
                "port": ${listen_port_json},
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

        if [ "$use_gost" = true ]; then
            print_info "Setting up GOST configuration for Simple ${protocol^^} server..."
            create_gost_server_config_range "$config_name" "$start_port" "$end_port" "127.0.0.1" "$effective_internal_port" "$protocol" "$ss_password"
            manage_gost_service "$config_name"
            open_firewall_ports "$start_port" "$end_port"
            open_firewall_ports "$effective_internal_port" "$effective_internal_port"
            echo "Simple ${protocol^^} (with GOST) configuration ${config_name}.json created."
            echo "GOST: :${start_port}-${end_port} -> 127.0.0.1:${effective_internal_port} (SS aes-128-cfb)"
            echo "Waterwall: ${LISTEN_ADDRESS}:${effective_internal_port} -> ${destination_ip}:${destination_port}"
        else
            open_firewall_ports "$start_port" "$end_port"
            echo "Simple ${protocol^^} configuration file ${config_name}.json has been created successfully!"
            echo "Forwarding ports ${start_port}-${end_port} to ${destination_ip}:${destination_port}"
        fi
    else
        echo "Error: Failed to create simple configuration file"
        exit 1
    fi
}

# Main simple handler function
handle_simple_config() {
    local protocol="tcp"  # Default protocol
    local use_gost=false
    local gost_password=""

    # Args after 'simple'
    shift 1
    local args=("$@")
    local idx=0

    # Optional 'gost' and optional password
    if [ "${args[$idx]}" = "gost" ]; then
        use_gost=true
        idx=$((idx + 1))
        if [ -n "${args[$idx]}" ] && [ "${args[$idx]}" != "tcp" ] && [ "${args[$idx]}" != "udp" ] && [ "${args[$idx]}" != "server" ] && [ "${args[$idx]}" != "client" ]; then
            gost_password="${args[$idx]}"
            idx=$((idx + 1))
        fi
    fi

    # Optional protocol
    if [ "${args[$idx]}" = "tcp" ] || [ "${args[$idx]}" = "udp" ]; then
        protocol="${args[$idx]}"
        idx=$((idx + 1))
    fi

    # Required params
    local type="${args[$idx]}"; idx=$((idx + 1))
    local config_name="${args[$idx]}"; idx=$((idx + 1))
    local start_port="${args[$idx]}"; idx=$((idx + 1))
    local end_port="${args[$idx]}"; idx=$((idx + 1))
    local destination_ip="${args[$idx]}"; idx=$((idx + 1))
    local destination_port="${args[$idx]}"; idx=$((idx + 1))
    local internal_port="${args[$idx]}"  # optional when use_gost=true

    # Validate required parameters
    if [ -z "$destination_port" ]; then
        if [ "$use_gost" = true ]; then
            echo "Usage: $0 simple gost [<ss_password>] [tcp|udp] <type> <config_name> <start_port> <end_port> <destination_ip> <destination_port> [internal_port]"
        else
            echo "Usage: $0 simple [tcp|udp] <type> <config_name> <start_port> <end_port> <destination_ip> <destination_port>"
        fi
        echo "Examples:"
        echo "  $0 simple tcp server myconfig 100 199 192.168.1.100 8080"
        echo "  $0 simple gost mySecret tcp server mygost 300 399 10.0.0.10 10410 10310"
        exit 1
    fi

    # Resolve password
    local ss_password
    if [ -n "$gost_password" ]; then
        ss_password="$gost_password"
    else
        ss_password="${GOST_SS_PASSWORD:-apple123ApPle}"
    fi

    create_simple_config "$protocol" "$type" "$config_name" "$start_port" "$end_port" "$destination_ip" "$destination_port" "$use_gost" "$internal_port" "$ss_password"
}
