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

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <type> <config_name> [parameters...]"
    echo "For server config:"
    echo "  With different ports: $0 server <config_name> <server1_address> <server1_port> [<server2_address> <server2_port> ...]"
    echo "  With same port: $0 server <config_name> -p <port> <server1_address> [<server2_address> ...]"
    echo "For iran config: $0 iran <config_name> <start_port> <end_port> <kharej_ip> <kharej_port>"
    exit 1
fi

TYPE="$1"
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
