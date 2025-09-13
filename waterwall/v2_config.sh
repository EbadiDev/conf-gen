#!/bin/bash

# V2 Configuration Module for Waterwall
# Handles V2 server and client configurations with TUN devices and IP manipulation

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/haproxy.sh"

# V2 Server Configuration
create_v2_server_config() {
    local config_name="$1"
    local start_port="$2"
    local end_port="$3"
    local non_iran_ip="$4"
    local iran_ip="$5"
    local private_ip="$6"
    local haproxy_port="$7"
    local protoswap_tcp="$8"
    local use_haproxy="$9"

    # Calculate PRIVATE_IP+1 for output and ipovsrc2
    IFS='.' read -r ip1 ip2 ip3 ip4 <<< "$private_ip"
    local ip_plus1="$ip1.$ip2.$ip3.$((ip4+1))"

    # Determine listener port based on HAProxy usage
    local waterwall_listen_port
    if [ "$use_haproxy" = true ]; then
        # With HAProxy: waterwall listens on internal port, HAProxy handles external range
        waterwall_listen_port="$haproxy_port"
    else
        # Without HAProxy: waterwall listens on external port range
        waterwall_listen_port="[${start_port},${end_port}]"
    fi

    cat << EOF > "${config_name}.json"
{
    "name": "${config_name}",
    "nodes": [
        {
            "name": "my tun",
            "type": "TunDevice",
            "settings": {
                "device-name": "${config_name}",
                "device-ip": "${private_ip}/24"
            },
            "next": "ipovsrc"
        },
        {
            "name": "ipovsrc",
            "type": "IpOverrider",
            "settings": {
                "direction": "up",
                "mode": "source-ip",
                "ipv4": "${iran_ip}"
            },
            "next": "ipovdest"
        },
        {
            "name": "ipovdest",
            "type": "IpOverrider",
            "settings": {
                "direction": "up",
                "mode": "dest-ip",
                "ipv4": "${non_iran_ip}"
            },
            "next": "manip"
        },
        {
            "name": "manip",
            "type": "IpManipulator",
            "settings": {
                "protoswap-tcp": ${protoswap_tcp}
            },
            "next": "ipovsrc2"
        },
        {
            "name": "ipovsrc2",
            "type": "IpOverrider",
            "settings": {
                "direction": "down",
                "mode": "source-ip",
                "ipv4": "${ip_plus1}"
            },
            "next": "ipovdest2"
        },
        {
            "name": "ipovdest2",
            "type": "IpOverrider",
            "settings": {
                "direction": "down",
                "mode": "dest-ip",
                "ipv4": "${private_ip}"
            },
            "next": "rd"
        },
        {
            "name": "rd",
            "type": "RawSocket",
            "settings": {
                "capture-filter-mode": "source-ip",
                "capture-ip": "${non_iran_ip}"
            }
        },
        {
            "name": "input",
            "type": "TcpListener",
            "settings": {
                "address": "0.0.0.0",
                "port": ${waterwall_listen_port},
                "nodelay": true
            },
            "next": "output"
        },
        {
            "name": "output",
            "type": "TcpConnector",
            "settings": {
                "nodelay": true,
                "address": "${ip_plus1}",
                "port": ${haproxy_port}
            }
        }
    ]
}
EOF

    if [ $? -eq 0 ]; then
        add_to_core_json "$config_name" "v2"
        
        # Generate HAProxy configuration only if haproxy flag is used
        if [ "$use_haproxy" = true ]; then
            print_info "Setting up HAProxy configuration for V2 server..."
            
            # V2 Server acts as server - external clients connect to port range, forward to waterwall on single internal port
            create_haproxy_server_config_range "$config_name" "$start_port" "$end_port" "127.0.0.1" "$haproxy_port" "tcp"
            manage_haproxy_service
            
            # Open additional ports for V2 Server with HAProxy
            print_info "Opening additional firewall ports for V2 Server HAProxy setup..."
            open_firewall_ports "$start_port" "$end_port"
            open_firewall_ports "$haproxy_port" "$haproxy_port"
            
            print_info "V2 Server with HAProxy:"
            print_info "- External clients connect to ports: $start_port-$end_port"
            print_info "- HAProxy forwards to waterwall on: $haproxy_port"
            print_info "- Waterwall connects to: ${ip_plus1}:${haproxy_port}"
        else
            open_firewall_ports "$start_port" "$end_port"
        fi
        
        echo "V2 Server configuration file ${config_name}.json has been created successfully!"
        echo "TUN device name: $config_name"
        echo "TUN device IP: $private_ip/24"
        echo "Protocol swapping: TCP to $protoswap_tcp"
    else
        echo "Error: Failed to create V2 server configuration file"
        exit 1
    fi
}

# V2 Client Configuration
create_v2_client_config() {
    local config_name="$1"
    local non_iran_ip="$2"
    local iran_ip="$3"
    local private_ip="$4"
    local haproxy_port="$5"
    local protoswap_tcp="$6"
    local app_port="$7"
    local use_haproxy="$8"

    # Calculate PRIVATE_IP+1 for input address
    IFS='.' read -r ip1 ip2 ip3 ip4 <<< "$private_ip"
    local ip_plus1="$ip1.$ip2.$ip3.$((ip4+1))"

    cat << EOF > "${config_name}.json"
{
    "name": "${config_name}",
    "nodes": [
        {
            "name": "rd",
            "type": "RawSocket",
            "settings": {
                "capture-filter-mode": "source-ip",
                "capture-ip": "${iran_ip}"
            },
            "next": "ipovsrc"
        },
        {
            "name": "ipovsrc",
            "type": "IpOverrider",
            "settings": {
                "direction": "down",
                "mode": "source-ip",
                "ipv4": "${non_iran_ip}"
            },
            "next": "ipovdest"
        },
        {
            "name": "ipovdest",
            "type": "IpOverrider",
            "settings": {
                "direction": "down",
                "mode": "dest-ip",
                "ipv4": "${iran_ip}"
            },
            "next": "manip"
        },
        {
            "name": "manip",
            "type": "IpManipulator",
            "settings": {
                "protoswap-tcp": ${protoswap_tcp}
            },
            "next": "ipovsrc2"
        },
        {
            "name": "ipovsrc2",
            "type": "IpOverrider",
            "settings": {
                "direction": "up",
                "mode": "source-ip",
                "ipv4": "${ip_plus1}"
            },
            "next": "ipovdest2"
        },
        {
            "name": "ipovdest2",
            "type": "IpOverrider",
            "settings": {
                "direction": "up",
                "mode": "dest-ip",
                "ipv4": "${private_ip}"
            },
            "next": "my tun"
        },
        {
            "name": "my tun",
            "type": "TunDevice",
            "settings": {
                "device-name": "${config_name}",
                "device-ip": "${private_ip}/24"
            },
            "next": "input"
        },
        {
            "name": "input",
            "type": "TcpListener",
            "settings": {
                "address": "${ip_plus1}",
                "port": ${haproxy_port},
                "nodelay": true
            },
            "next": "output"
        },
        {
            "name": "output",
            "type": "TcpConnector",
            "settings": {
                "nodelay": true,
                "address": "127.0.0.1",
                "port": ${app_port}
            }
        }
    ]
}
EOF

    if [ $? -eq 0 ]; then
        add_to_core_json "$config_name" "v2"
        
        # Generate HAProxy configuration only if haproxy flag is used
        if [ "$use_haproxy" = true ]; then
            print_info "Setting up HAProxy configuration for V2 client..."
            
            # V2 Client configuration: HAProxy binds to private IP and forwards to application
            create_haproxy_client_config "$config_name" "$private_ip" "$haproxy_port" "127.0.0.1" "$app_port" "tcp"
            manage_haproxy_service
            
            print_info "V2 Client with HAProxy:"
            print_info "- Tunnel connects to waterwall on: ${ip_plus1}:${haproxy_port}"
            print_info "- HAProxy binds to: ${private_ip}:${haproxy_port}"
            print_info "- HAProxy forwards to app: 127.0.0.1:${app_port}"
        fi
        
        echo "V2 Client configuration file ${config_name}.json has been created successfully!"
        echo "TUN device name: $config_name"
        echo "TUN device IP: $private_ip/24"
        echo "Protocol swapping: TCP to $protoswap_tcp"
        if [ "$use_haproxy" = true ]; then
            echo "HAProxy binding: ${private_ip}:${haproxy_port}"
        fi
    else
        echo "Error: Failed to create V2 client configuration file"
        exit 1
    fi
}

# Main V2 handler function
handle_v2_config() {
    local use_haproxy=false
    local config_type
    
    # Check if haproxy flag is present
    if [ "$2" = "haproxy" ]; then
        use_haproxy=true
        config_type="$3"  # server or client
        shift 1  # Remove haproxy flag
    else
        config_type="$2"  # server or client
    fi
    
    if [ "$config_type" = "server" ]; then
        # v2 server config_name start-port end-port non-iran-ip iran-ip private-ip haproxy-port protocol
        if [ "$#" -lt 9 ]; then
            if [ "$use_haproxy" = true ]; then
                echo "Usage: $0 v2 haproxy server <config_name> <start_port> <end_port> <non_iran_ip> <iran_ip> <private_ip> <haproxy_port> <protocol>"
            else
                echo "Usage: $0 v2 server <config_name> <start_port> <end_port> <non_iran_ip> <iran_ip> <private_ip> <haproxy_port> <protocol>"
            fi
            exit 1
        fi
        
        create_v2_server_config "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}" "$use_haproxy"
        
    elif [ "$config_type" = "client" ]; then
        # v2 client config_name non-iran-ip iran-ip private-ip haproxy-port protocol app-port
        if [ "$#" -lt 8 ]; then
            if [ "$use_haproxy" = true ]; then
                echo "Usage: $0 v2 haproxy client <config_name> <non_iran_ip> <iran_ip> <private_ip> <haproxy_port> <protocol> <app_port>"
            else
                echo "Usage: $0 v2 client <config_name> <non_iran_ip> <iran_ip> <private_ip> <haproxy_port> <protocol> <app_port>"
            fi
            exit 1
        fi
        
        create_v2_client_config "$3" "$4" "$5" "$6" "$7" "$8" "$9" "$use_haproxy"
        
    else
        echo "Error: v2 config type must be either 'server' or 'client'"
        exit 1
    fi
}
