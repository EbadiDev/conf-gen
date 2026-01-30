#!/bin/bash

# V2 Configuration Module for Waterwall
# Handles V2 server and client configurations with TUN devices and IP manipulation

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/haproxy.sh"
source "$SCRIPT_DIR/caddy.sh"
source "$SCRIPT_DIR/gost.sh"

# V2 Server Configuration
# Supports both single port (e.g., 443) and port range (e.g., 1000 1100)
create_v2_server_config() {
    local config_name="$1"
    local start_port="$2"
    local end_port="$3"      # Can be empty for single port mode
    local non_iran_ip="$4"
    local iran_ip="$5"
    local private_ip="$6"
    local haproxy_port="$7"
    local protoswap_tcp="$8"
    local use_haproxy="$9"
    local use_caddy="${10}"
    local use_gost="${11}"
    local ss_password="${12:-${GOST_SS_PASSWORD:-apple123ApPle}}"

    # Determine if single port or port range mode
    local is_single_port=false
    if [ -z "$end_port" ] || [ "$start_port" = "$end_port" ]; then
        is_single_port=true
        end_port="$start_port"  # Normalize for any code that needs both
    fi

    # Calculate PRIVATE_IP+1 for output and ipovsrc2
    IFS='.' read -r ip1 ip2 ip3 ip4 <<< "$private_ip"
    local ip_plus1="$ip1.$ip2.$ip3.$((ip4+1))"

    # Determine listener port based on HAProxy/Caddy usage
    local waterwall_listen_port
    if [ "$use_haproxy" = true ] || [ "$use_caddy" = true ] || [ "$use_gost" = true ]; then
        # With HAProxy/Caddy: waterwall listens on internal port, proxy handles external range
        waterwall_listen_port="$haproxy_port"
    else
        # Without proxy: waterwall listens on external port(s)
        if [ "$is_single_port" = true ]; then
            waterwall_listen_port="${start_port}"
        else
            waterwall_listen_port="[${start_port},${end_port}]"
        fi
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
            if [ "$is_single_port" = true ]; then
                print_info "- External clients connect to port: $start_port"
            else
                print_info "- External clients connect to ports: $start_port-$end_port"
            fi
            print_info "- HAProxy forwards to waterwall on: $haproxy_port"
            print_info "- Waterwall connects to: ${ip_plus1}:${haproxy_port}"
    elif [ "$use_caddy" = true ]; then
            print_info "Setting up Caddy configuration for V2 server..."
            
            # V2 Server acts as server - external clients connect to port range, forward to waterwall on single internal port
            create_caddy_server_config_range "$config_name" "$start_port" "$end_port" "127.0.0.1" "$haproxy_port" "tcp"
            manage_caddy_service
            
            # Open additional ports for V2 Server with Caddy
            print_info "Opening additional firewall ports for V2 Server Caddy setup..."
            open_firewall_ports "$start_port" "$end_port"
            open_firewall_ports "$haproxy_port" "$haproxy_port"
            
            print_info "V2 Server with Caddy:"
            if [ "$is_single_port" = true ]; then
                print_info "- External clients connect to port: $start_port"
            else
                print_info "- External clients connect to ports: $start_port-$end_port"
            fi
            print_info "- Caddy forwards to waterwall on: $haproxy_port"
            print_info "- Waterwall connects to: ${ip_plus1}:${haproxy_port}"
        elif [ "$use_gost" = true ]; then
            print_info "Setting up GOST configuration for V2 server..."
            
            # Use single port or range version based on port mode
            if [ "$is_single_port" = true ]; then
                create_gost_server_config "$config_name" "$start_port" "127.0.0.1" "$haproxy_port" "tcp" "$ss_password"
            else
                create_gost_server_config_range "$config_name" "$start_port" "$end_port" "127.0.0.1" "$haproxy_port" "tcp" "$ss_password"
            fi
            manage_gost_service "$config_name"

            # Open additional ports for V2 Server with GOST
            print_info "Opening additional firewall ports for V2 Server GOST setup..."
            open_firewall_ports "$start_port" "$end_port"
            open_firewall_ports "$haproxy_port" "$haproxy_port"

            print_info "V2 Server with GOST:"
            if [ "$is_single_port" = true ]; then
                print_info "- External clients connect to port: $start_port"
            else
                print_info "- External clients connect to ports: $start_port-$end_port"
            fi
            print_info "- GOST forwards to waterwall on: $haproxy_port (with Proxy Protocol)"
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
    local use_caddy="$9"
    local use_gost="${10}"
    local ss_password="${11:-${GOST_SS_PASSWORD:-apple123ApPle}}"

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
            print_info "- TUN device routes traffic through: ${private_ip}:${haproxy_port}"
            print_info "- HAProxy binds to: ${private_ip}:${haproxy_port}"
            print_info "- HAProxy forwards to app: 127.0.0.1:${app_port}"
    elif [ "$use_caddy" = true ]; then
            print_info "Setting up Caddy configuration for V2 client..."
            
            # V2 Client configuration: Caddy binds to private IP and forwards to application
            create_caddy_client_config "$config_name" "$private_ip" "$haproxy_port" "127.0.0.1" "$app_port" "tcp"
            manage_caddy_service
            
            print_info "V2 Client with Caddy:"
            print_info "- TUN device routes traffic through: ${private_ip}:${haproxy_port}"
            print_info "- Caddy binds to: ${private_ip}:${haproxy_port}"
            print_info "- Caddy forwards to app: 127.0.0.1:${app_port}"
        elif [ "$use_gost" = true ]; then
            print_info "Setting up GOST configuration for V2 client..."
            create_gost_client_config "$config_name" "$private_ip" "$haproxy_port" "127.0.0.1" "$app_port" "tcp" "$ss_password"
            manage_gost_service "$config_name"

            print_info "V2 Client with GOST:"
            print_info "- TUN device routes traffic through: ${private_ip}:${haproxy_port} (accept Proxy Protocol)"
            print_info "- GOST binds to: ${private_ip}:${haproxy_port}"
            print_info "- GOST forwards to app: 127.0.0.1:${app_port} (send Proxy Protocol)"
        else
            print_info "V2 Client without proxy:"
            print_info "- TUN device created: ${config_name}"
            print_info "- Route traffic manually through TUN device to your application"
        fi
        
        echo "V2 Client configuration file ${config_name}.json has been created successfully!"
        echo "TUN device name: $config_name"
        echo "TUN device IP: $private_ip/24"
        echo "Protocol swapping: TCP to $protoswap_tcp"
        if [ "$use_haproxy" = true ]; then
            echo "HAProxy binding: ${private_ip}:${haproxy_port}"
        elif [ "$use_caddy" = true ]; then
            echo "Caddy binding: ${private_ip}:${haproxy_port}"
        fi
    else
        echo "Error: Failed to create V2 client configuration file"
        exit 1
    fi
}

# Main V2 handler function
handle_v2_config() {
    local use_haproxy=false
    local use_caddy=false
    local use_gost=false
    local gost_password=""
    local config_type
    
    # Check if haproxy or caddy flag is present
    if [ "$2" = "haproxy" ]; then
        use_haproxy=true
        config_type="$3"  # server or client
        shift 1  # Remove haproxy flag
    elif [ "$2" = "caddy" ]; then
        use_caddy=true
        config_type="$3"  # server or client
        shift 1  # Remove caddy flag
    elif [ "$2" = "gost" ]; then
        use_gost=true
        # Optional password after 'gost'
        if [ -n "$3" ] && [ "$3" != "server" ] && [ "$3" != "client" ]; then
            gost_password="$3"
            config_type="$4"
            shift 2
        else
            config_type="$3"
            shift 1
        fi
    else
        config_type="$2"  # server or client
    fi
    
    if [ "$config_type" = "server" ]; then
        # Detect port mode from flags: --port <single> or --ports <start> <end>
        local start_port=""
        local end_port=""
        local port_arg_count=0
        local remaining_args=()
        
        # Parse remaining args after config_type
        shift 2  # Remove $1 (v2) and $2 (config_type or proxy type)
        if [ "$use_haproxy" = true ] || [ "$use_caddy" = true ]; then
            shift 1  # Remove 'server'
        elif [ "$use_gost" = true ]; then
            if [ -n "$gost_password" ]; then
                shift 1  # Already shifted for password, just shift 'server'
            else
                shift 1  # Remove 'server'
            fi
        else
            shift 1  # Remove 'server'  
        fi
        
        local config_name="$1"
        shift 1
        
        # Check for --port or --ports flag
        if [ "$1" = "--port" ]; then
            start_port="$2"
            end_port=""  # Empty for single port
            shift 2
        elif [ "$1" = "--ports" ]; then
            start_port="$2"
            end_port="$3"
            shift 3
        else
            # Legacy mode: assume first two args are ports if both are numbers
            if [[ "$1" =~ ^[0-9]+$ ]] && [[ "$2" =~ ^[0-9]+$ ]] && ! [[ "$2" == *.* ]]; then
                start_port="$1"
                end_port="$2"
                shift 2
            elif [[ "$1" =~ ^[0-9]+$ ]]; then
                start_port="$1"
                end_port=""
                shift 1
            else
                echo "Error: Port specification required. Use --port <port> or --ports <start> <end>"
                exit 1
            fi
        fi
        
        # Remaining args: non-iran-ip iran-ip private-ip haproxy-port protocol
        if [ "$#" -lt 5 ]; then
            echo "Usage: $0 v2 [gost [password]] server <config_name> --port <port> <non_iran_ip> <iran_ip> <private_ip> <haproxy_port> <protocol>"
            echo "       $0 v2 [gost [password]] server <config_name> --ports <start_port> <end_port> <non_iran_ip> <iran_ip> <private_ip> <haproxy_port> <protocol>"
            exit 1
        fi
        
        local non_iran_ip="$1"
        local iran_ip="$2"
        local private_ip="$3"
        local haproxy_port="$4"
        local protoswap_tcp="$5"
        
        create_v2_server_config "$config_name" "$start_port" "$end_port" "$non_iran_ip" "$iran_ip" "$private_ip" "$haproxy_port" "$protoswap_tcp" "$use_haproxy" "$use_caddy" "$use_gost" "$gost_password"
        
    elif [ "$config_type" = "client" ]; then
        # v2 client config_name non-iran-ip iran-ip private-ip haproxy-port protocol app-port
    if [ "$#" -lt 8 ]; then
            if [ "$use_haproxy" = true ]; then
                echo "Usage: $0 v2 haproxy client <config_name> <non_iran_ip> <iran_ip> <private_ip> <haproxy_port> <protocol> <app_port>"
            elif [ "$use_caddy" = true ]; then
                echo "Usage: $0 v2 caddy client <config_name> <non_iran_ip> <iran_ip> <private_ip> <haproxy_port> <protocol> <app_port>"
            elif [ "$use_gost" = true ]; then
        echo "Usage: $0 v2 gost [<ss_password>] client <config_name> <non_iran_ip> <iran_ip> <private_ip> <haproxy_port> <protocol> <app_port>"
            else
                echo "Usage: $0 v2 client <config_name> <non_iran_ip> <iran_ip> <private_ip> <haproxy_port> <protocol> <app_port>"
            fi
            exit 1
        fi
    # Pass gost_password as last param (only used when use_gost=true)
    create_v2_client_config "$3" "$4" "$5" "$6" "$7" "$8" "$9" "$use_haproxy" "$use_caddy" "$use_gost" "$gost_password"
        
    else
        echo "Error: v2 config type must be either 'server' or 'client'"
        exit 1
    fi
}
