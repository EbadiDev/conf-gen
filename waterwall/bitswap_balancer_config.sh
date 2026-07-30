#!/bin/bash

# One-config Germany balancer for two Iran BitSwap MUX peers.
# Reuses the current bitswap_config.sh generator, resolves its variables, gives
# every node a unique suffix, then merges both Germany-side chains.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/bitswap_config.sh"

bb_fail() { print_error "$1"; exit 1; }

bb_ipv4() {
    local label="$1" value="$2" a b c d
    IFS='.' read -r a b c d <<< "$value"
    [[ "$a" =~ ^[0-9]+$ && "$b" =~ ^[0-9]+$ && "$c" =~ ^[0-9]+$ && "$d" =~ ^[0-9]+$ ]] &&
      [ "$a" -le 255 ] && [ "$b" -le 245 ] && [ "$c" -le 255 ] && [ "$d" -le 254 ] ||
      bb_fail "$label must be a valid IPv4 address (second octet <=245 and last octet <=254 for private-IP arithmetic)."
}

bb_port() {
    local label="$1" value="$2"
    [[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -ge 1 ] && [ "$value" -le 65535 ] ||
      bb_fail "$label must be from 1 through 65535."
}

bb_tun_values() {
    local base="$1" a b c d
    IFS='.' read -r a b c d <<< "$base"
    BB_TUN1="$base"
    BB_TUN2="$a.$b.$c.$((d + 1))"
    BB_TUN_SECOND="$a.$((b + 10)).$c.$d"
}

bb_resolve_config() {
    local input="$1" output="$2" iran="$3" germany="$4" private="$5" listen_port="$6" final_ip="$7" final_port="$8"
    bb_tun_values "$private"

    local content
    content="$(cat "$input")"
    content="${content//\$ip_server_iran\$/\"$iran\"}"
    content="${content//\$ip_server_kharej\$/\"$germany\"}"
    content="${content//\$port_to_listen\$/$listen_port}"
    content="${content//\$final_ip\$/\"$final_ip\"}"
    content="${content//\$final_port\$/$final_port}"
    content="${content//\$tun_ip_1\$/\"$BB_TUN1\"}"
    content="${content//\$tun_ip_2\$/\"$BB_TUN2\"}"
    content="${content//\$tun2_ip_1\$/\"$BB_TUN_SECOND\"}"
    printf '%s\n' "$content" > "$output"

    jq empty "$output" >/dev/null 2>&1 || bb_fail "Could not resolve generated BitSwap config $input."
}

bb_suffix_nodes() {
    local input="$1" output="$2" suffix="$3" private="$4"
    jq --arg suffix "$suffix" --arg private "$private/32" '
      .nodes |= map(
        .name = (.name + $suffix)
        | if has("next") then .next = (.next + $suffix) else . end
        | if (.settings | type) == "object" and (.settings | has("pair")) then .settings.pair = (.settings.pair + $suffix) else . end
        | if .type == "PacketSplitStream" then
            .settings.up = (.settings.up + $suffix) | .settings.down = (.settings.down + $suffix)
          else . end
        | if .type == "RawSocket" and (.settings | has("capture-ip")) then
            .settings["capture-ips"] = [.settings["capture-ip"]] | del(.settings["capture-ip"])
          else . end
        | if .type == "TcpListener" and (.name | startswith("users_inbound")) then
            .settings.whitelist = [$private]
          else . end
      )
    ' "$input" > "$output"
}

create_bitswap_balancer_config() {
    local name="$1" germany="$2" iran1="$3" private1="$4" iran2="$5" private2="$6"
    local tunnel_port="$7" final_ip="$8" final_port="$9" mux_count="${10}" xor_key="${11}"

    bb_ipv4 "Germany IP" "$germany"
    bb_ipv4 "Iran 1 IP" "$iran1"
    bb_ipv4 "Iran 2 IP" "$iran2"
    bb_ipv4 "Private IP 1" "$private1"
    bb_ipv4 "Private IP 2" "$private2"
    [ "$iran1" != "$iran2" ] || bb_fail "Iran public IPs must differ."
    [ "$private1" != "$private2" ] || bb_fail "Private tunnel IPs must differ."
    bb_port "Tunnel port" "$tunnel_port"
    bb_port "Final port" "$final_port"
    bb_ipv4 "Final IP" "$final_ip"
    [[ "$mux_count" =~ ^[0-9]+$ ]] && [ "$mux_count" -gt 0 ] || bb_fail "MUX count must be positive."
    [[ "$xor_key" =~ ^[0-9]+$ ]] || bb_fail "XOR key must be numeric."

    local work
    work="$(mktemp -d /tmp/bitswap-balancer.XXXXXX)"
    trap 'rm -rf "$work"' RETURN

    (
      cd "$work"
      create_bitswap_config tcp single kharej pair1 "$iran1" "$germany" "$tunnel_port" "$final_port" "$final_ip" "$mux_count" false false "" "" "$xor_key" "$private1"
      create_bitswap_config tcp single kharej pair2 "$iran2" "$germany" "$tunnel_port" "$final_port" "$final_ip" "$mux_count" false false "" "" "$xor_key" "$private2"
    ) >/dev/null

    bb_resolve_config "$work/pair1.json" "$work/pair1-resolved.json" "$iran1" "$germany" "$private1" "$tunnel_port" "$final_ip" "$final_port"
    bb_resolve_config "$work/pair2.json" "$work/pair2-resolved.json" "$iran2" "$germany" "$private2" "$tunnel_port" "$final_ip" "$final_port"
    bb_suffix_nodes "$work/pair1-resolved.json" "$work/pair1-suffixed.json" "-ir1" "$private1"
    bb_suffix_nodes "$work/pair2-resolved.json" "$work/pair2-suffixed.json" "-ir2" "$private2"

    jq -s --arg name "$name" '{name: $name, nodes: (.[0].nodes + .[1].nodes)}' \
      "$work/pair1-suffixed.json" "$work/pair2-suffixed.json" > "${name}.json"
    jq empty "${name}.json" >/dev/null 2>&1 || bb_fail "Merged BitSwap balancer JSON is invalid."

    add_to_core_json "$name" "bitswap-balancer"
    print_success "One Germany BitSwap MUX balancer config created: ${name}.json"
    print_info "RawSocket public-IP filters: ${iran1}, ${iran2}"
    print_info "Internal listener whitelists: ${private1}/32, ${private2}/32"
    print_info "Both MUX paths use port ${tunnel_port} and forward to ${final_ip}:${final_port}"
}

show_bitswap_balancer_usage() {
    cat << EOF
Usage:
  $0 bitswap-balancer <name> <germany_ip> <iran1_ip> <private1> <iran2_ip> <private2> <tunnel_port> <final_port> [options]

Options:
  --final-ip IP     Backend address (default 127.0.0.1)
  --mux-count N     Per-worker fixed MUX connections (default 8)
  --xor-key N       Obfuscator XOR key (default 90)

Example:
  $0 bitswap-balancer bit-de-pool 2.2.2.2 1.1.1.1 10.11.1.1 1.1.1.2 10.12.1.1 443 8080
EOF
}

handle_bitswap_balancer_config() {
    local name="$2" germany="$3" iran1="$4" private1="$5" iran2="$6" private2="$7" tunnel_port="$8" final_port="$9"
    [ -n "$final_port" ] || { show_bitswap_balancer_usage; exit 1; }
    shift 9
    local final_ip="127.0.0.1" mux_count=8 xor_key=90
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --final-ip) final_ip="${2:?--final-ip requires a value}"; shift 2 ;;
        --mux-count) mux_count="${2:?--mux-count requires a value}"; shift 2 ;;
        --xor-key) xor_key="${2:?--xor-key requires a value}"; shift 2 ;;
        -h|--help) show_bitswap_balancer_usage; return 0 ;;
        *) bb_fail "Unknown BitSwap balancer option: $1" ;;
      esac
    done
    create_bitswap_balancer_config "$name" "$germany" "$iran1" "$private1" "$iran2" "$private2" "$tunnel_port" "$final_ip" "$final_port" "$mux_count" "$xor_key"
}
