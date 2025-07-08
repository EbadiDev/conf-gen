#!/bin/bash

# Function to add config to core.json if it doesn't exist
add_to_core_json() {
    local config_name="$1"
    local core_json="/root/core.json"
    
    # Check if core.json exists
    if [ ! -f "$core_json" ]; then
        echo "Error: core.json not found in /root/"
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
    echo "  With different ports: $0 server <config_name> <server1_address> <server1_port> [<server2_address> <server2_port> ...]"
    echo "  With same port: $0 server <config_name> -p <port> <server1_address> [<server2_address> ...]"
    echo "For iran config: $0 iran <config_name> <start_port> <end_port> <kharej_ip> <kharej_port>"
    echo "For simple iran config: $0 simple [tcp|udp] iran <config_name> <start_port> <end_port> <ip> <port>"
    echo "For half iran config: $0 half <website> <password> [tcp|udp] iran <config_name> <start_port> <end_port> <kharej_ip> <kharej_port>"
    echo "For half server config: $0 half <website> <password> [tcp|udp] server <config_name> -p <port> <iran_ip>"
    exit 1
fi

TYPE="$1"

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
        add_to_core_json "$CONFIG_NAME"
    fi

    echo "Simple ${PROTOCOL^^} Iran configuration file ${CONFIG_NAME}.json has been created successfully!"
    chmod 644 "${CONFIG_NAME}.json"
    open_firewall_ports "$START_PORT" "$END_PORT" "$PROTOCOL" "$PORT"
    exit 0
fi

# Check if it's the half configuration
if [ "$TYPE" = "half" ]; then
    if [ "$#" -lt 6 ]; then
        echo "Error: Half config needs website, password, and other parameters"
        exit 1
    fi
    
    WEBSITE="$2"
    PASSWORD="$3"
    
    # Check if fourth parameter is tcp, udp, or protocol is omitted
    if [ "$4" = "tcp" ] || [ "$4" = "udp" ]; then
        PROTOCOL="$4"
        CONFIG_TYPE="$5"  # iran or server
        if [ "$CONFIG_TYPE" = "iran" ]; then
            if [ "$#" -lt 10 ]; then
                echo "Error: Half iran config needs website, password, protocol, config_name, start_port, end_port, kharej_ip, and kharej_port"
                exit 1
            fi
            CONFIG_NAME="$6"
            START_PORT="$7"
            END_PORT="$8"
            KHAREJ_IP="$9"
            KHAREJ_PORT="${10}"
        elif [ "$CONFIG_TYPE" = "server" ]; then
            if [ "$#" -lt 9 ]; then
                echo "Error: Half server config needs website, password, protocol, config_name, -p, port, and iran_ip"
                exit 1
            fi
            CONFIG_NAME="$6"
            if [ "$7" != "-p" ]; then
                echo "Error: Half server config requires -p flag"
                exit 1
            fi
            PORT="$8"
            IRAN_IP="$9"
        fi
    else
        # Backward compatibility - default to TCP
        PROTOCOL="tcp"
        CONFIG_TYPE="$4"  # iran or server
        if [ "$CONFIG_TYPE" = "iran" ]; then
            if [ "$#" -lt 9 ]; then
                echo "Error: Half iran config needs website, password, config_name, start_port, end_port, kharej_ip, and kharej_port"
                exit 1
            fi
            CONFIG_NAME="$5"
            START_PORT="$6"
            END_PORT="$7"
            KHAREJ_IP="$8"
            KHAREJ_PORT="$9"
        elif [ "$CONFIG_TYPE" = "server" ]; then
            if [ "$#" -lt 8 ]; then
                echo "Error: Half server config needs website, password, config_name, -p, port, and iran_ip"
                exit 1
            fi
            CONFIG_NAME="$5"
            if [ "$6" != "-p" ]; then
                echo "Error: Half server config requires -p flag"
                exit 1
            fi
            PORT="$7"
            IRAN_IP="$8"
        fi
    fi
    
    if [ "$CONFIG_TYPE" = "iran" ]; then
        # Determine if IPv6 for kharej IP
        if [[ "$KHAREJ_IP" == *":"* ]]; then
            IP_SUFFIX="/128"
        else
            IP_SUFFIX="/32"
        fi
        
        # Create half Iran configuration
        cat << EOF > "${CONFIG_NAME}.json"
{
    "name": "${CONFIG_NAME}",
    "nodes": [
        {
            "name": "users_inbound",
            "type": "TcpListener",
            "settings": {
                "address": "0.0.0.0",
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
            "type": "TcpListener",
            "settings": {
                "address": "0.0.0.0",
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
            "type": "TcpConnector",
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
            add_to_core_json "$CONFIG_NAME"
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
            "type": "TcpConnector",
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
            "type": "TcpConnector",
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
            add_to_core_json "$CONFIG_NAME"
        fi
        
        echo "Half ${PROTOCOL^^} Server configuration file ${CONFIG_NAME}.json has been created successfully!"
        chmod 644 "${CONFIG_NAME}.json"
        
    else
        echo "Error: Half config type must be either 'iran' or 'server'"
        exit 1
    fi
    
    exit 0
fi

CONFIG_NAME="$2"
shift 2

if [ "$TYPE" = "server" ]; then
    # Server configuration logic
    if [ "$1" = "-p" ]; then
        if [ "$#" -lt 3 ]; then
            echo "Error: Server config with -p needs port and at least one server address"
            exit 1
        fi
        COMMON_PORT="$2"
        shift 2
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
            "type": "TcpConnector",
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
            "type": "TcpConnector",
            "settings": {
                "nodelay": true,
                "address": "${ADDRESS}",
                "port": ${PORT}
            }
        }
EOF
    done

elif [ "$TYPE" = "iran" ]; then
    # Iran configuration logic
    if [ "$#" -lt 4 ]; then
        echo "Error: Iran config needs start_port, end_port, kharej_ip, and kharej_port"
        exit 1
    fi

    START_PORT="$1"
    END_PORT="$2"
    KHAREJ_IP="$3"
    KHAREJ_PORT="$4"

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
            "type": "TcpListener",
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
            "type": "TcpListener",
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

else
    echo "Error: First parameter must be either 'server' or 'iran'"
    exit 1
fi

# Close JSON structure for server type (iran type already closed)
if [ "$TYPE" = "server" ]; then
    cat << EOF >> "${CONFIG_NAME}.json"

    ]
}
EOF
fi

# After successful config creation, add to core.json
if [ $? -eq 0 ]; then
    add_to_core_json "$CONFIG_NAME"
fi

echo "Configuration file ${CONFIG_NAME}.json has been created successfully!"
chmod 644 "${CONFIG_NAME}.json"

# Open firewall ports for server type configurations
if [ "$TYPE" = "server" ]; then
    for ((i=1; i<=SERVER_COUNT; i++)); do
        PORT=$(( $2 + i - 1 ))
        open_firewall_ports "$PORT" "$PORT" "tcp" "$PORT"
        shift 2
    done
fi
