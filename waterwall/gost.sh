#!/bin/bash

# GOST Configuration Module (v3.2.4 syntax)
# Provides server/client helpers using TCP and Proxy Protocol

# Create or update a systemd unit with a composed ExecStart
_gost_write_unit() {
    local service_name="$1"
    shift
    local exec_args=("$@")

    local unit_path="/etc/systemd/system/gost-${service_name}.service"

    # Ensure systemd directory exists
    mkdir -p /etc/systemd/system

    cat > "$unit_path" << EOF
[Unit]
Description=GOST Service for ${service_name}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
# Only log errors (can be overridden by editing this unit)
Environment=GOST_LOGGER_LEVEL=error
ExecStart=/usr/bin/env gost -D error ${exec_args[*]}
Restart=on-failure
RestartSec=2s
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

    echo "$unit_path"
}

# Manage GOST service lifecycle for a named unit
manage_gost_service() {
    local service_name="$1"

    # Validate gost binary exists
    if ! command -v gost >/dev/null 2>&1; then
        echo "Error: 'gost' binary not found. Please install GOST v3.2.4 (https://gost.run) and re-run." >&2
        exit 1
    fi

    systemctl daemon-reload
    systemctl enable "gost-${service_name}.service" >/dev/null 2>&1 || true
    if systemctl is-active --quiet "gost-${service_name}.service"; then
        systemctl restart "gost-${service_name}.service"
    else
        systemctl start "gost-${service_name}.service"
    fi
}

# Remove existing GOST service unit (if present)
remove_gost_service() {
    local service_name="$1"
    local unit_path="/etc/systemd/system/gost-${service_name}.service"
    if [ -f "$unit_path" ]; then
        systemctl stop "gost-${service_name}.service" >/dev/null 2>&1 || true
        systemctl disable "gost-${service_name}.service" >/dev/null 2>&1 || true
        rm -f "$unit_path"
        systemctl daemon-reload
    fi
}

# GOST Server Configuration (external clients connect to a port range)
# Binds :start-end and forwards to backend_ip:backend_port, sending Proxy Protocol header
create_gost_server_config_range() {
    local service_name="$1"
    local start_port="$2"
    local end_port="$3"
    local backend_ip="$4"
    local backend_port="$5"
    local protocol="$6"   # tcp only, kept for API symmetry

    # Emit one -L per port to ensure compatibility (many-to-one mappings may
    # not be supported in all builds). Example per-port:
    #   -L tcp://:450/127.0.0.1:10311?handler.proxyProtocol=1
    local args=()
    local p
    for ((p=start_port; p<=end_port; p++)); do
        args+=("-L" "tcp://:${p}/${backend_ip}:${backend_port}?handler.proxyProtocol=1")
    done

    remove_gost_service "$service_name"
    local unit_path
    unit_path=$(_gost_write_unit "$service_name" "${args[@]}")
    echo "Updated GOST unit: $unit_path"
}

# GOST Server Configuration (single external port)
create_gost_server_config() {
    local service_name="$1"
    local external_port="$2"
    local backend_ip="$3"
    local backend_port="$4"
    local protocol="$5"   # tcp only, kept for API symmetry

    local args=("-L" "tcp://:${external_port}/${backend_ip}:${backend_port}?handler.proxyProtocol=1")

    remove_gost_service "$service_name"
    local unit_path
    unit_path=$(_gost_write_unit "$service_name" "${args[@]}")
    echo "Updated GOST unit: $unit_path"
}

# GOST Client Configuration (binds to private_ip:tunnel_port and forwards to app_ip:app_port)
# Enables receiving Proxy Protocol on listener and sends Proxy Protocol upstream to the app
create_gost_client_config() {
    local service_name="$1"
    local bind_ip="$2"
    local tunnel_port="$3"
    local app_ip="$4"
    local app_port="$5"
    local protocol="$6"   # tcp only, kept for API symmetry

    # Accept Proxy Protocol if present, and send it upstream to the app
    local args=("-L" "tcp://${bind_ip}:${tunnel_port}/${app_ip}:${app_port}?proxyProtocol=1&handler.proxyProtocol=1")

    remove_gost_service "$service_name"
    local unit_path
    unit_path=$(_gost_write_unit "$service_name" "${args[@]}")
    echo "Updated GOST unit: $unit_path"
}
