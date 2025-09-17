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
        # GOST server supports port range: <start_port> <end_port> <server_ip> <internal_waterwall_port>
        # Legacy/HAProxy server uses: -p <port> <server_ip> [internal_port]
        local port_flag="${remaining_args[0]}"
        local port="${remaining_args[1]}"
        local server_ip
        local haproxy_port

        # GOST single-port server mode: -p <gost_port> <server_ip> [waterwall_port]
        if [ "$use_gost" = true ] && [ "$port_flag" = "-p" ]; then
            local gost_port="${remaining_args[1]}"
            server_ip="${remaining_args[2]}"
            haproxy_port="${remaining_args[3]}"   # optional Waterwall internal port

            if [ -z "$gost_port" ] || [ -z "$server_ip" ]; then
                echo "Error: Invalid GOST server (-p) parameters"
                echo "Usage: half <website> <password> gost [tcp|udp] server <config_name> -p <gost_port> <server_ip> [waterwall_port]"
                exit 1
            fi

            # Default internal Waterwall port to gost_port+1 if not provided
            if [ -z "$haproxy_port" ]; then
                haproxy_port=$((gost_port + 1))
            fi

            # Advanced Reality server chain
            cat << EOF > "${config_name}.json"
{
    "name": "${config_name}",
    "nodes": [
        {
            "name": "users_inbound",
            "type": "${LISTENER_TYPE}",
            "settings": {
                "address": "0.0.0.0",
                "port": ${haproxy_port},
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
                "password": "${password}"
            },
            "next": "halfs"
        },
        {
            "name": "kharej_inbound",
            "type": "${LISTENER_TYPE}",
            "settings": {
                "address": "0.0.0.0",
                "port": ${haproxy_port},
                "nodelay": true,
                "whitelist": [
                    "${server_ip}/32"
                ]
            },
            "next": "reality_server"
        },
        {
            "name": "reality_dest",
            "type": "${CONNECTOR_TYPE}",
            "settings": {
                "nodelay": true,
                "address": "${website}",
                "port": 443
            }
        }
    ]
}
EOF

            if [ $? -eq 0 ]; then
                add_to_core_json "$config_name" "half"
                print_info "Setting up GOST configuration for Half server (-p single-port)..."
                # GOST listens on :gost_port and forwards to 127.0.0.1:haproxy_port
                create_gost_server_config "$config_name" "$gost_port" "127.0.0.1" "$haproxy_port" "$protocol"
                manage_gost_service "$config_name"
                open_firewall_ports "$gost_port" "$gost_port"
                echo "Half server configuration file ${config_name}.json has been created successfully!"
                echo "Reality server stack listening on internal: ${haproxy_port}"
                echo "GOST: :${gost_port} -> 127.0.0.1:${haproxy_port}"
            else
                echo "Error: Failed to create half server configuration file"
                exit 1
            fi

            return
        fi

        if [ "$use_gost" = true ] && [ "$port_flag" != "-p" ]; then
            # GOST range mode
            local start_port="${remaining_args[0]}"
            local end_port="${remaining_args[1]}"
            server_ip="${remaining_args[2]}"
            haproxy_port="${remaining_args[3]}"   # internal waterwall port

            if [ -z "$start_port" ] || [ -z "$end_port" ] || [ -z "$server_ip" ] || [ -z "$haproxy_port" ]; then
                echo "Error: Invalid GOST server parameters"
                echo "Usage: half <website> <password> gost [tcp|udp] server <config_name> <start_port> <end_port> <server_ip> <internal_waterwall_port>"
                exit 1
            fi

            # Waterwall listens on internal port; GOST handles external range
            local waterwall_listen_port="$haproxy_port"
            port="$start_port"  # for logging

            # Advanced Reality server chain (same as single-port mode)
            cat << EOF > "${config_name}.json"
{
    "name": "${config_name}",
    "nodes": [
        {
            "name": "users_inbound",
            "type": "${LISTENER_TYPE}",
            "settings": {
                "address": "0.0.0.0",
                "port": ${waterwall_listen_port},
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
                "password": "${password}"
            },
            "next": "halfs"
        },
        {
            "name": "kharej_inbound",
            "type": "${LISTENER_TYPE}",
            "settings": {
                "address": "0.0.0.0",
                "port": ${waterwall_listen_port},
                "nodelay": true,
                "whitelist": [
                    "${server_ip}/32"
                ]
            },
            "next": "reality_server"
        },
        {
            "name": "reality_dest",
            "type": "${CONNECTOR_TYPE}",
            "settings": {
                "nodelay": true,
                "address": "${website}",
                "port": 443
            }
        }
    ]
}
EOF

            if [ $? -eq 0 ]; then
                add_to_core_json "$config_name" "half"
                print_info "Setting up GOST configuration for Half server (range)..."
                create_gost_server_config_range "$config_name" "$start_port" "$end_port" "127.0.0.1" "$haproxy_port" "$protocol"
                manage_gost_service "$config_name"
                open_firewall_ports "$start_port" "$end_port"
                echo "Half server configuration file ${config_name}.json has been created successfully!"
                echo "Reality server stack listening on internal: ${haproxy_port}"
                echo "GOST: :${start_port}-${end_port} -> 127.0.0.1:${haproxy_port}"
            else
                echo "Error: Failed to create half server configuration file"
                exit 1
            fi

            # Done with GOST server
            return
        fi

        # Legacy or HAProxy flow
        local server_ip_in="${remaining_args[2]}"
        local haproxy_port_in="${remaining_args[3]}"
        if [ "$port_flag" != "-p" ] || [ -z "$port" ] || [ -z "$server_ip_in" ]; then
            echo "Error: Invalid server configuration parameters"
            echo "Usage: half <website> <password> [tcp|udp] server <config_name> -p <port> <server_ip> [internal_port]"
            exit 1
        fi
        server_ip="$server_ip_in"; haproxy_port="$haproxy_port_in"
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
        # GOST client specialized syntax: -p <destination_port> <destination_ip> <gost_port>
        # Legacy/HAProxy: <start_port> <end_port> <destination_ip> <destination_port> [internal_port]
        local start_port="${remaining_args[0]}"
        local end_port="${remaining_args[1]}"
        local destination_ip
        local destination_port
        local haproxy_port

        if [ "$use_gost" = true ] && [ "$start_port" = "-p" ]; then
            destination_port="${remaining_args[1]}"
            destination_ip="${remaining_args[2]}"
            haproxy_port="${remaining_args[3]}"   # GOST listener port
            if [ -z "$destination_port" ] || [ -z "$destination_ip" ] || [ -z "$haproxy_port" ]; then
                echo "Error: Invalid GOST client parameters"
                echo "Usage: half <website> <password> gost [tcp|udp] client <config_name> -p <destination_port> <destination_ip> <gost_port>"
                exit 1
            fi

            # Waterwall connects to local GOST - Advanced Reality server chain
            cat << EOF > "${config_name}.json"
{
    "name": "${config_name}",
    "nodes": [
        {
            "name": "users_inbound",
            "type": "${LISTENER_TYPE}",
            "settings": {
                "address": "0.0.0.0",
                "port": 443,
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
                "password": "${password}"
            },
            "next": "halfs"
        },
        {
            "name": "kharej_inbound",
            "type": "${LISTENER_TYPE}",
            "settings": {
                "address": "0.0.0.0",
                "port": 443,
                "nodelay": true
            },
            "next": "reality_server"
        },
        {
            "name": "reality_dest",
            "type": "${CONNECTOR_TYPE}",
            "settings": {
                "nodelay": true,
                "address": "127.0.0.1",
                "port": ${haproxy_port}
            }
        }
    ]
}
EOF

            if [ $? -eq 0 ]; then
                add_to_core_json "$config_name" "half"
                print_info "Setting up GOST configuration for Half client..."
                # GOST listens on :gost_port and forwards to 127.0.0.1:destination_port with Proxy Protocol
                create_gost_client_config "$config_name" "" "$haproxy_port" "127.0.0.1" "$destination_port" "$protocol"
                manage_gost_service "$config_name"
                echo "Half client configuration file ${config_name}.json has been created successfully!"
                echo "Reality/gRPC client serving: ${website}"
                echo "GOST: :${haproxy_port} -> 127.0.0.1:${destination_port}"
            else
                echo "Error: Failed to create half client configuration file"
                exit 1
            fi

            return
        fi

        # Legacy/HAProxy mode
        destination_ip="${remaining_args[2]}"
        destination_port="${remaining_args[3]}"
        haproxy_port="${remaining_args[4]}"
        
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
                create_gost_client_config "$config_name" "127.0.0.1" "$haproxy_port" "$destination_ip" "$destination_port" "$protocol"
                manage_gost_service "$config_name"
                print_info "Half Client with GOST: 127.0.0.1:${haproxy_port} -> ${destination_ip}:${destination_port}"
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
    # Positional overview: $1=half, $2=website, $3=password, then optional [haproxy|gost] [tcp|udp] <type> <config_name> ...
    local website="$2"
    local password="$3"
    local protocol="tcp"  # Default protocol
    local use_haproxy=false
    local use_gost=false

    # Build args array from $4 onward for robust indexing
    shift 3
    local args=("$@")
    local idx=0

    # Optional proxy helper
    if [ "${args[0]}" = "haproxy" ]; then
        use_haproxy=true
        idx=$((idx + 1))
    elif [ "${args[0]}" = "gost" ]; then
        use_gost=true
        idx=$((idx + 1))
    fi

    # Optional protocol
    if [ "${args[$idx]}" = "tcp" ] || [ "${args[$idx]}" = "udp" ]; then
        protocol="${args[$idx]}"
        idx=$((idx + 1))
    fi

    # Required: type and config_name
    local type="${args[$idx]}"; idx=$((idx + 1))
    local config_name="${args[$idx]}"; idx=$((idx + 1))

    # Validate required parameters
    if [ -z "$website" ] || [ -z "$password" ] || [ -z "$type" ] || [ -z "$config_name" ]; then
        echo "Usage: $0 half <website> <password> [haproxy|gost] [tcp|udp] <server|client> <config_name> [additional_params...]"
        echo "Examples:"
        echo "  $0 half web-cdn.snapp.ir mypass haproxy tcp server myconfig -p 8080 192.168.1.100 [internal_port]"
        echo "  $0 half web-cdn.snapp.ir mypass gost tcp server myconfig <start_port> <end_port> <server_ip> <internal_port>"
        echo "  $0 half web-cdn.snapp.ir mypass client myconfig <start_port> <end_port> <dest_ip> <dest_port> [internal_port]"
        echo "  $0 half web-cdn.snapp.ir mypass gost client myconfig -p <dest_port> <dest_ip> <gost_port>"
        exit 1
    fi

    # Remaining parameters for the specific mode
    local remaining=("${args[@]:$idx}")

    create_half_config "$website" "$password" "$protocol" "$type" "$config_name" "$use_haproxy" "$use_gost" "${remaining[@]}"
}
