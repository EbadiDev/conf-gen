#!/bin/bash

# GOST Configuration Module (v3.2.4 syntax)
# Provides server/client helpers using TCP and Proxy Protocol

# Create or update a systemd unit with a composed ExecStart
_gost_write_unit() {
    local service_name="$1"
    shift
    local exec_args=("$@")

    local unit_path="/etc/systemd/system/gost-${service_name}.service"

    # Build ExecStart with quoted -L targets (systemd-safe grouping)
    local gost_bin
    gost_bin="$(command -v gost 2>/dev/null || true)"
    if [ -z "$gost_bin" ]; then
        if [ -x "/usr/local/bin/gost" ]; then
            gost_bin="/usr/local/bin/gost"
        else
            echo "Error: 'gost' binary not found in PATH or at /usr/local/bin/gost" >&2
            exit 1
        fi
    fi
    local exec_line="${gost_bin}"
    local i=0
    while [ $i -lt ${#exec_args[@]} ]; do
        if [ "${exec_args[$i]}" = "-L" ] && [ $((i+1)) -lt ${#exec_args[@]} ]; then
            exec_line+=" -L \"${exec_args[$((i+1))]}\""
            i=$((i+2))
        else
            exec_line+=" ${exec_args[$i]}"
            i=$((i+1))
        fi
    done

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
ExecStart=${exec_line}
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
# You can append extra listener/handler tuning via env GOST_EXTRA_QUERY (e.g., "tfo=1&nodelay=1").
create_gost_server_config_range() {
    local service_name="$1"
    local start_port="$2"
    local end_port="$3"
    local backend_ip="$4"
    local backend_port="$5"
    local protocol="$6"   # tcp only, kept for API symmetry
    local ss_password="${7:-apple123ApPle}"

    # Use GOST's native port range support (many-to-one mapping)
    # Example: -L tcp://:450-499/127.0.0.1:10311?handler.proxyProtocol=2
    local base_query="handler.proxyProtocol=2&tfo=1&nodelay=true&keepAlive=true"
    if [ -n "${GOST_EXTRA_QUERY:-}" ]; then
        # Trim a leading & if present
        local extra="${GOST_EXTRA_QUERY#&}"
        base_query="${base_query}&${extra}"
    fi
    # Use Shadowsocks listener with minimal cipher and provided password
    local args=("-L" "ss://aes-128-cfb:${ss_password}@:${start_port}-${end_port}/${backend_ip}:${backend_port}?${base_query}")

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
    local ss_password="${6:-apple123ApPle}"

    local base_query="handler.proxyProtocol=2&tfo=1&nodelay=true&keepAlive=true"
    if [ -n "${GOST_EXTRA_QUERY:-}" ]; then
        local extra="${GOST_EXTRA_QUERY#&}"
        base_query="${base_query}&${extra}"
    fi
    local args=("-L" "ss://aes-128-cfb:${ss_password}@:${external_port}/${backend_ip}:${backend_port}?${base_query}")

    remove_gost_service "$service_name"
    local unit_path
    unit_path=$(_gost_write_unit "$service_name" "${args[@]}")
    echo "Updated GOST unit: $unit_path"
}

# GOST Client Configuration (binds to private_ip:tunnel_port and forwards to app_ip:app_port)
# Enables receiving Proxy Protocol on listener and sends Proxy Protocol upstream to the app
# Extra query parts can be appended via GOST_EXTRA_QUERY (applied to the listener URL).
create_gost_client_config() {
    local service_name="$1"
    local bind_ip="$2"
    local tunnel_port="$3"
    local app_ip="$4"
    local app_port="$5"
    local protocol="$6"   # tcp only, kept for API symmetry
    local ss_password="${7:-apple123ApPle}"

    # Prepare upstream host:port (bracket IPv6)
    local upstream_host="$app_ip"
    if [[ "$upstream_host" == *:* && "$upstream_host" != [* ]]; then
        upstream_host="[$upstream_host]"
    fi

    # Accept Proxy Protocol if present, and send it upstream to the app
    local base_query="proxyProtocol=2&handler.proxyProtocol=2&tfo=1&nodelay=true&keepAlive=true"
    if [ -n "${GOST_EXTRA_QUERY:-}" ]; then
        local extra="${GOST_EXTRA_QUERY#&}"
        base_query="${base_query}&${extra}"
    fi
    # Bind to specific IP if provided; empty means default (all interfaces)
    local bind_host bind_spec
    if [ -n "$bind_ip" ]; then
        bind_host="$bind_ip"
        # Bracket IPv6 bind IPs if not already bracketed
        if [[ "$bind_host" == *:* && "$bind_host" != [* ]]; then
            bind_host="[$bind_host]"
        fi
        bind_spec="${bind_host}:${tunnel_port}"
    else
        bind_spec=":${tunnel_port}"
    fi
    local args=("-L" "ss://aes-128-cfb:${ss_password}@${bind_spec}/${upstream_host}:${app_port}?${base_query}")

    remove_gost_service "$service_name"
    local unit_path
    unit_path=$(_gost_write_unit "$service_name" "${args[@]}")
    echo "Updated GOST unit: $unit_path"
}
