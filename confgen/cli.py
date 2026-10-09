"""Command Line Interface for ConfGen with comprehensive flags and clean UX."""

import argparse
import os
import sys
from typing import Any, List, Optional

from confgen import __version__
from confgen.core.utils import print_error, print_info, print_success, write_json
from confgen.core.validator import validate_ports_list
from confgen.generators.xray import (
    DEFAULT_UUID,
    DEFAULT_WS_PATH,
    generate_xray_iran_config,
    generate_xray_kharej_config,
)
from confgen.generators.waterwall.reverse_reality import (
    generate_reverse_reality_tcp_iran,
    generate_reverse_reality_tcp_kharej,
)
from confgen.generators.waterwall.tls_reverse import (
    generate_waterwall_tls_reverse_iran,
    generate_waterwall_tls_reverse_kharej,
)
from confgen.generators.waterwall.udp_reverse import (
    generate_udp_reverse_iran,
    generate_udp_reverse_kharej,
)
from confgen.generators.waterwall.bitswap import (
    generate_bitswap_iran,
    generate_bitswap_kharej,
    generate_bitswap_tcp_iran,
    generate_bitswap_tcp_kharej,
    generate_bitswap_udp_iran,
    generate_bitswap_udp_kharej,
)
from confgen.generators.waterwall.protoswap import (
    generate_protoswap_iran,
    generate_protoswap_kharej,
)
from confgen.generators.waterwall.benchmark import (
    generate_speedtest_server_config,
    generate_speedtest_client_config,
    generate_benchmark_suite,
)
from confgen.generators.waterwall.core import generate_core_config
from confgen.generators.waterwall.simple import generate_simple_config


def _extract_ports(raw_list: Optional[List[Any]]) -> List[int]:
    if not raw_list:
        return []
    res = []
    for item in raw_list:
        for part in str(item).split(","):
            p = part.strip()
            if p.isdigit():
                res.append(int(p))
    return res


def _extract_ips(raw_list: Optional[List[str]]) -> List[str]:
    if not raw_list:
        return []
    res = []
    for item in raw_list:
        for part in str(item).split(","):
            ip = part.strip()
            if ip:
                res.append(ip)
    return res


class CustomFormatter(argparse.RawDescriptionHelpFormatter, argparse.ArgumentDefaultsHelpFormatter):
    pass


def create_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="confgen",
        description="Unified Configuration Generator for Anti-Censorship Tunnels (Xray, Waterwall, Rathole)",
        formatter_class=CustomFormatter,
    )
    parser.add_argument("-v", "--version", action="version", version=f"%(prog)s {__version__}")
    subparsers = parser.add_subparsers(dest="command", help="Target tunneling subsystem")

    # =========================================================================
    # 1. XRAY
    # =========================================================================
    xray_p = subparsers.add_parser(
        "xray",
        help="Xray-core configuration generator",
        formatter_class=CustomFormatter,
    )
    xray_sub = xray_p.add_subparsers(dest="subcommand", help="Xray architecture")

    # xray reverse
    xr_rev = xray_sub.add_parser("reverse", help="VLESS Reverse Tunnel (WS / TLS / Reality)", formatter_class=CustomFormatter)
    xr_rev_sub = xr_rev.add_subparsers(dest="side", help="Deployment endpoint (iran | kharej)")

    # xray reverse iran
    x_iran = xr_rev_sub.add_parser(
        "iran",
        help="Iran server (Portal listener)",
        formatter_class=CustomFormatter,
        epilog="""Examples:
  ./confgen.py xray reverse iran -n xray-iran -p 8443 --tcp 8085,8086 --udp 8087
  ./confgen.py xray reverse iran -n xray-iran -p 8443 --tls-cert /path/cert.pem --tls-key /path/key.pem
""",
    )
    x_iran.add_argument("pos_name", nargs="?", help="[Positional fallback] Configuration name")
    x_iran.add_argument("pos_port", nargs="?", type=int, help="[Positional fallback] Listener port")
    x_iran.add_argument("-n", "--name", help="Configuration name")
    x_iran.add_argument("-p", "--port", type=int, default=8443, help="VLESS listener port")
    x_iran.add_argument("--tcp", default="8085,8086", help="Comma-separated TCP ports to forward")
    x_iran.add_argument("--udp", default="", help="Comma-separated UDP ports to forward")
    x_iran.add_argument("-u", "--uuid", default=DEFAULT_UUID, help="VLESS user UUID")
    x_iran.add_argument("--path", default=DEFAULT_WS_PATH, help="WebSocket path")
    x_iran.add_argument("--tls-cert", help="Path to TLS certificate (fullchain.pem)")
    x_iran.add_argument("--tls-key", help="Path to TLS private key (privkey.pem)")
    x_iran.add_argument("-o", "--output", help="Output file path (default: <name>.json)")

    # xray reverse kharej
    x_kharej = xr_rev_sub.add_parser(
        "kharej",
        help="Kharej server (Bridge connector)",
        formatter_class=CustomFormatter,
        epilog="""Examples:
  ./confgen.py xray reverse kharej -n xray-kharej -ii 109.94.164.214 -p 8443
  ./confgen.py xray reverse kharej -n xray-kharej -ii 109.94.164.214 -p 8443 --tls france.archlix.com
""",
    )
    x_kharej.add_argument("pos_name", nargs="?", help="[Positional fallback] Configuration name")
    x_kharej.add_argument("pos_iran_ip", nargs="?", help="[Positional fallback] Iran IP")
    x_kharej.add_argument("pos_port", nargs="?", type=int, help="[Positional fallback] Port")
    x_kharej.add_argument("-n", "--name", help="Configuration name")
    x_kharej.add_argument("-ii", "--iran-ip", help="Iran Server public IP")
    x_kharej.add_argument("-p", "--port", type=int, default=8443, help="Iran listener port")
    x_kharej.add_argument("-u", "--uuid", default=DEFAULT_UUID, help="VLESS user UUID")
    x_kharej.add_argument("--path", default=DEFAULT_WS_PATH, help="WebSocket path")
    x_kharej.add_argument("--ed", type=int, default=2560, help="Early Data length threshold")
    x_kharej.add_argument("--tls", "--sni", dest="tls_sni", help="Enable TLS with SNI / Host header")
    x_kharej.add_argument("-o", "--output", help="Output file path (default: <name>.json)")

    # =========================================================================
    # 2. WATERWALL
    # =========================================================================
    ww_p = subparsers.add_parser(
        "waterwall",
        help="Waterwall configuration generator",
        formatter_class=CustomFormatter,
    )
    ww_sub = ww_p.add_subparsers(dest="subcommand", help="Waterwall module")

    # 2.1 waterwall reverse-reality
    ww_rr = ww_sub.add_parser("reverse-reality", help="Reverse Reality tunnel (TCP)", formatter_class=CustomFormatter)
    ww_rr_sub = ww_rr.add_subparsers(dest="side", help="Tunnel side (iran | kharej)")

    # ww rr iran
    w_rr_i = ww_rr_sub.add_parser(
        "iran",
        help="Iran server configuration",
        formatter_class=CustomFormatter,
        epilog="""Example:
  ./confgen.py waterwall reverse-reality iran -n rev-iran -ii 95.38.130.213 -ki 89.36.162.43 -p 443 -d telewebion.ir -wi 185.165.205.129 --proxy-protocol
""",
    )
    w_rr_i.add_argument("pos_name", nargs="?", help="[Positional fallback] Name")
    w_rr_i.add_argument("pos_iran_ip", nargs="?", help="[Positional fallback] Iran IP")
    w_rr_i.add_argument("pos_kharej_ip", nargs="?", help="[Positional fallback] Kharej IP")
    w_rr_i.add_argument("pos_port", nargs="?", type=int, help="[Positional fallback] Port")
    w_rr_i.add_argument("pos_domain", nargs="?", help="[Positional fallback] Domain")
    w_rr_i.add_argument("pos_white_ip", nargs="?", help="[Positional fallback] White IP")
    w_rr_i.add_argument("-n", "--name", help="Configuration name")
    w_rr_i.add_argument("-ii", "--iran-ip", help="Iran Server public IP")
    w_rr_i.add_argument("-ki", "--kharej-ip", help="Kharej Server main IP")
    w_rr_i.add_argument("-p", "--port", type=int, default=443, help="Tunnel port")
    w_rr_i.add_argument("-d", "--domain", default="telewebion.ir", help="Reality SNI domain")
    w_rr_i.add_argument("-wi", "--white-ip", help="IP address behind SNI domain")
    w_rr_i.add_argument("--pass", "--password", dest="password", default="arch1234net", help="Reality password")
    w_rr_i.add_argument("--float", nargs="*", default=[], help="Kharej floating IPs")
    w_rr_i.add_argument("--proxy-protocol", action="store_true", help="Enable Proxy Protocol header")
    w_rr_i.add_argument("--halfduplex", action="store_true", help="Enable HalfDuplex client")
    w_rr_i.add_argument("--fisher", action="store_true", help="Enable ConnectionFisher server")
    w_rr_i.add_argument("--tls-cert", help="TLS certificate path for local termination")
    w_rr_i.add_argument("--tls-key", help="TLS key path for local termination")
    w_rr_i.add_argument("-o", "--output", help="Output file path")

    # ww rr kharej
    w_rr_k = ww_rr_sub.add_parser(
        "kharej",
        help="Kharej server configuration",
        formatter_class=CustomFormatter,
        epilog="""Example:
  ./confgen.py waterwall reverse-reality kharej -n rev-kharej -ii 95.38.130.213 -ki 89.36.162.43 -p 443 -d telewebion.ir -fp 8443
""",
    )
    w_rr_k.add_argument("pos_name", nargs="?", help="[Positional fallback] Name")
    w_rr_k.add_argument("pos_iran_ip", nargs="?", help="[Positional fallback] Iran IP")
    w_rr_k.add_argument("pos_kharej_ip", nargs="?", help="[Positional fallback] Kharej IP")
    w_rr_k.add_argument("pos_port", nargs="?", type=int, help="[Positional fallback] Port")
    w_rr_k.add_argument("pos_domain", nargs="?", help="[Positional fallback] Domain")
    w_rr_k.add_argument("pos_final_port", nargs="?", type=int, help="[Positional fallback] Final port")
    w_rr_k.add_argument("-n", "--name", help="Configuration name")
    w_rr_k.add_argument("-ii", "--iran-ip", help="Iran Server public IP")
    w_rr_k.add_argument("-ki", "--kharej-ip", help="Kharej Server main IP")
    w_rr_k.add_argument("-p", "--port", type=int, default=443, help="Tunnel port")
    w_rr_k.add_argument("-d", "--domain", default="telewebion.ir", help="Reality SNI domain")
    w_rr_k.add_argument("-fp", "--final-port", type=int, help="Local service target port on Kharej")
    w_rr_k.add_argument("--pass", "--password", dest="password", default="arch1234net", help="Reality password")
    w_rr_k.add_argument("--min-held", type=int, default=8, help="Minimum held connections")
    w_rr_k.add_argument("--float", nargs="*", default=[], help="Kharej floating IPs")
    w_rr_k.add_argument("--halfduplex", action="store_true", help="Enable HalfDuplex server")
    w_rr_k.add_argument("--fisher", action="store_true", help="Enable ConnectionFisher client")
    w_rr_k.add_argument("-o", "--output", help="Output file path")

    # 2.2 waterwall tls-reverse
    ww_tls = ww_sub.add_parser("tls-reverse", help="TLS Reverse tunnel", formatter_class=CustomFormatter)
    ww_tls_sub = ww_tls.add_subparsers(dest="side", help="Tunnel side (iran | kharej)")

    w_tls_i = ww_tls_sub.add_parser("iran", help="Iran server configuration", formatter_class=CustomFormatter)
    w_tls_i.add_argument("-n", "--name", required=True, help="Configuration name")
    w_tls_i.add_argument("-ii", "--iran-ip", required=True, help="Iran Server IP")
    w_tls_i.add_argument("-p", "--port", type=int, default=8443, help="Tunnel port")
    w_tls_i.add_argument("--cert", required=True, help="Path to TLS certificate")
    w_tls_i.add_argument("--key", required=True, help="Path to TLS key")
    w_tls_i.add_argument("-ki", "--kharej-ips", nargs="+", required=True, help="Whitelisted Kharej IP(s)")
    w_tls_i.add_argument("--proxy-protocol", action="store_true", help="Enable Proxy Protocol")
    w_tls_i.add_argument("-o", "--output", help="Output file path")

    w_tls_k = ww_tls_sub.add_parser("kharej", help="Kharej server configuration", formatter_class=CustomFormatter)
    w_tls_k.add_argument("-n", "--name", required=True, help="Configuration name")
    w_tls_k.add_argument("-ii", "--iran-ip", required=True, help="Iran Server IP")
    w_tls_k.add_argument("-p", "--port", type=int, default=8443, help="Tunnel port")
    w_tls_k.add_argument("-d", "--sni", required=True, help="SNI domain")
    w_tls_k.add_argument("-fp", "--final-port", type=int, required=True, help="Target application port")
    w_tls_k.add_argument("--final-ip", default="127.0.0.1", help="Target application IP")
    w_tls_k.add_argument("-o", "--output", help="Output file path")

    # 2.3 waterwall udp-reverse
    ww_udp = ww_sub.add_parser("udp-reverse", help="UDP Reverse tunnel (RawSocket+XOR)", formatter_class=CustomFormatter)
    ww_udp_sub = ww_udp.add_subparsers(dest="side", help="Tunnel side (iran | kharej)")

    w_udp_i = ww_udp_sub.add_parser("iran", help="Iran server configuration", formatter_class=CustomFormatter)
    w_udp_i.add_argument("-n", "--name", required=True, help="Configuration name")
    w_udp_i.add_argument("-ii", "--iran-ip", required=True, help="Iran public IP")
    w_udp_i.add_argument("-ki", "--kharej-ip", required=True, help="Kharej public IP")
    w_udp_i.add_argument("-lp", "--listen-port", type=int, required=True, help="Public UDP listening port")
    w_udp_i.add_argument("-tp", "--tunnel-port", type=int, default=443, help="Internal tunnel transport port")
    w_udp_i.add_argument("--tun-iran", default="10.20.1.1", help="TUN interface IP for Iran")
    w_udp_i.add_argument("--tun-kharej", default="10.20.1.2", help="TUN interface IP for Kharej")
    w_udp_i.add_argument("--xor-key", type=int, default=153, help="XOR encryption key")
    w_udp_i.add_argument("--secret", default="begapour", help="Reverse handshake secret")
    w_udp_i.add_argument("-o", "--output", help="Output file path")

    w_udp_k = ww_udp_sub.add_parser("kharej", help="Kharej server configuration", formatter_class=CustomFormatter)
    w_udp_k.add_argument("-n", "--name", required=True, help="Configuration name")
    w_udp_k.add_argument("-ii", "--iran-ip", required=True, help="Iran public IP")
    w_udp_k.add_argument("-ki", "--kharej-ip", required=True, help="Kharej public IP")
    w_udp_k.add_argument("-fp", "--target-port", type=int, required=True, help="Local target UDP service port")
    w_udp_k.add_argument("-tp", "--tunnel-port", type=int, default=443, help="Internal tunnel transport port")
    w_udp_k.add_argument("--tun-iran", default="10.20.1.1", help="TUN interface IP for Iran")
    w_udp_k.add_argument("--tun-kharej", default="10.20.1.2", help="TUN interface IP for Kharej")
    w_udp_k.add_argument("--xor-key", type=int, default=153, help="XOR encryption key")
    w_udp_k.add_argument("--secret", default="begapour", help="Reverse handshake secret")
    w_udp_k.add_argument("-o", "--output", help="Output file path")

    # 2.4 waterwall bitswap
    ww_bit = ww_sub.add_parser(
        "bitswap",
        help="BitSwap MUX tunnel (auto-detects single/multi port & single/multi IP)",
        formatter_class=CustomFormatter,
    )
    ww_bit_sub = ww_bit.add_subparsers(dest="side", help="Tunnel side (iran | kharej)")

    w_bit_i = ww_bit_sub.add_parser(
        "iran",
        help="Iran server configuration",
        formatter_class=CustomFormatter,
        epilog="""Examples:
  # Single port:
  ./confgen.py waterwall bitswap iran -n bit-single -ii 198.51.100.10 -ki 203.0.113.20 --tcp 443

  # Multi-service hybrid with floating IP and TLS:
  ./confgen.py waterwall bitswap iran -n bit-hybrid -ii 198.51.100.10 -ki 203.0.113.20 \\
      --tcp 6443,2059 --udp 27015 --float 203.0.113.21 --proxy-protocol \\
      --tls-cert /path/cert.pem --tls-key /path/key.pem
""",
    )
    w_bit_i.add_argument("pos_name", nargs="?", help="[Positional fallback] Name")
    w_bit_i.add_argument("pos_iran_ip", nargs="?", help="[Positional fallback] Iran IP")
    w_bit_i.add_argument("pos_kharej_ip", nargs="?", help="[Positional fallback] Kharej IP")
    w_bit_i.add_argument("-n", "--name", help="Configuration name")
    w_bit_i.add_argument("-ii", "--iran-ip", help="Iran Server public IP")
    w_bit_i.add_argument("-ki", "--kharej-ip", help="Kharej Server main public IP")
    w_bit_i.add_argument("--tcp", nargs="*", default=[], help="TCP service port(s), e.g. --tcp 6443,2059 or --tcp 443")
    w_bit_i.add_argument("--udp", nargs="*", default=[], help="UDP service port(s), e.g. --udp 27015")
    w_bit_i.add_argument("-lp", "--listen-port", type=int, help="Single listening port fallback")
    w_bit_i.add_argument("-fp", "--forward-port", type=int, help="Single forward transport port fallback")
    w_bit_i.add_argument("--tcp-tunnel-port", type=int, default=8443, help="Transport port for TCP services (default: 8443)")
    w_bit_i.add_argument("--udp-tunnel-port", type=int, default=8444, help="Transport port for UDP services (default: 8444)")
    w_bit_i.add_argument("--float", nargs="*", default=[], help="Floating IPs (enables multi-IP mode)")
    w_bit_i.add_argument("--mux-count", type=int, default=8, help="Worker MUX connections count (default: 8)")
    w_bit_i.add_argument("--proxy-protocol", action="store_true", help="Enable Proxy Protocol header")
    w_bit_i.add_argument("--tls-cert", help="TLS certificate path for termination on Iran")
    w_bit_i.add_argument("--tls-key", help="TLS private key path for termination on Iran")
    w_bit_i.add_argument("--tls", nargs=2, metavar=("CERT", "KEY"), help="TLS cert and key paths")
    w_bit_i.add_argument("--xor-key", type=int, default=90, help="XOR obfuscation key (default: 90)")
    w_bit_i.add_argument("--private-ip", help="Custom base private IP subnet (e.g. 10.10.0.1)")
    w_bit_i.add_argument("--private-ip-2", help="Secondary internal private IP subnet")
    w_bit_i.add_argument("-o", "--output", help="Output file path")

    w_bit_k = ww_bit_sub.add_parser(
        "kharej",
        help="Kharej server configuration",
        formatter_class=CustomFormatter,
        epilog="""Examples:
  # Single port:
  ./confgen.py waterwall bitswap kharej -n bit-single -ii 198.51.100.10 -ki 203.0.113.20 --tcp 443

  # Multi-service hybrid with floating IP:
  ./confgen.py waterwall bitswap kharej -n bit-hybrid -ii 198.51.100.10 -ki 203.0.113.20 \\
      --tcp 6443,2059 --udp 27015 --float 203.0.113.21
""",
    )
    w_bit_k.add_argument("pos_name", nargs="?", help="[Positional fallback] Name")
    w_bit_k.add_argument("pos_iran_ip", nargs="?", help="[Positional fallback] Iran IP")
    w_bit_k.add_argument("pos_kharej_ip", nargs="?", help="[Positional fallback] Kharej IP")
    w_bit_k.add_argument("-n", "--name", help="Configuration name")
    w_bit_k.add_argument("-ii", "--iran-ip", help="Iran Server public IP")
    w_bit_k.add_argument("-ki", "--kharej-ip", help="Kharej Server main public IP")
    w_bit_k.add_argument("--tcp", nargs="*", default=[], help="TCP service port(s), e.g. --tcp 6443,2059 or --tcp 443")
    w_bit_k.add_argument("--udp", nargs="*", default=[], help="UDP service port(s), e.g. --udp 27015")
    w_bit_k.add_argument("-lp", "--listen-port", type=int, help="Single transport port fallback")
    w_bit_k.add_argument("-fp", "--final-port", type=int, help="Single destination service port fallback")
    w_bit_k.add_argument("--tcp-tunnel-port", type=int, default=8443, help="Transport port for TCP services (default: 8443)")
    w_bit_k.add_argument("--udp-tunnel-port", type=int, default=8444, help="Transport port for UDP services (default: 8444)")
    w_bit_k.add_argument("--final-ip", default="127.0.0.1", help="Local destination service IP (default: 127.0.0.1)")
    w_bit_k.add_argument("--float", nargs="*", default=[], help="Floating IPs (enables multi-IP mode)")
    w_bit_k.add_argument("--xor-key", type=int, default=90, help="XOR obfuscation key (default: 90)")
    w_bit_k.add_argument("--private-ip", help="Custom base private IP subnet (e.g. 10.10.0.1)")
    w_bit_k.add_argument("--private-ip-2", help="Secondary internal private IP subnet")
    w_bit_k.add_argument("-o", "--output", help="Output file path")

    # 2.5 waterwall protoswap
    ww_proto = ww_sub.add_parser(
        "protoswap",
        help="ProtoSwap tunnel (IPv4 protocol byte swapping, auto-detects single/multi port & IP)",
        formatter_class=CustomFormatter,
    )
    ww_proto_sub = ww_proto.add_subparsers(dest="side", help="Tunnel side (iran | kharej)")

    w_proto_i = ww_proto_sub.add_parser(
        "iran",
        help="Iran server configuration",
        formatter_class=CustomFormatter,
        epilog="""Examples:
  # Single port:
  ./confgen.py waterwall protoswap iran -n proto-single -ii 198.51.100.10 -ki 203.0.113.20 --tcp 443

  # Multi-service hybrid with custom protocols and floating IP:
  ./confgen.py waterwall protoswap iran -n proto-hybrid -ii 198.51.100.10 -ki 203.0.113.20 \\
      --tcp 6443,2059 --udp 27015 --protoswap-tcp 253 --protoswap-udp 252 --float 203.0.113.21
""",
    )
    w_proto_i.add_argument("pos_name", nargs="?", help="[Positional fallback] Name")
    w_proto_i.add_argument("pos_iran_ip", nargs="?", help="[Positional fallback] Iran IP")
    w_proto_i.add_argument("pos_kharej_ip", nargs="?", help="[Positional fallback] Kharej IP")
    w_proto_i.add_argument("-n", "--name", help="Configuration name")
    w_proto_i.add_argument("-ii", "--iran-ip", help="Iran Server public IP")
    w_proto_i.add_argument("-ki", "--kharej-ip", help="Kharej Server main public IP")
    w_proto_i.add_argument("--tcp", nargs="*", default=[], help="TCP service port(s), e.g. --tcp 6443,2059 or --tcp 443")
    w_proto_i.add_argument("--udp", nargs="*", default=[], help="UDP service port(s), e.g. --udp 27015")
    w_proto_i.add_argument("-lp", "--listen-port", type=int, help="Single listening port fallback")
    w_proto_i.add_argument("-fp", "--forward-port", type=int, help="Single forward transport port fallback")
    w_proto_i.add_argument("--protoswap-tcp", type=int, default=253, help="Replacement protocol number for TCP (default: 253)")
    w_proto_i.add_argument("--protoswap-udp", type=int, default=252, help="Replacement protocol number for UDP (default: 252)")
    w_proto_i.add_argument("--tcp-tunnel-port", type=int, default=8443, help="Transport port for TCP services (default: 8443)")
    w_proto_i.add_argument("--udp-tunnel-port", type=int, default=8444, help="Transport port for UDP services (default: 8444)")
    w_proto_i.add_argument("--float", nargs="*", default=[], help="Floating IPs (enables multi-IP mode)")
    w_proto_i.add_argument("--mux-count", type=int, default=8, help="Worker MUX connections count (default: 8)")
    w_proto_i.add_argument("--proxy-protocol", action="store_true", help="Enable Proxy Protocol header")
    w_proto_i.add_argument("--tls-cert", help="TLS certificate path for termination on Iran")
    w_proto_i.add_argument("--tls-key", help="TLS private key path for termination on Iran")
    w_proto_i.add_argument("--tls", nargs=2, metavar=("CERT", "KEY"), help="TLS cert and key paths")
    w_proto_i.add_argument("--xor-key", type=int, default=90, help="XOR obfuscation key (default: 90)")
    w_proto_i.add_argument("--private-ip", help="Custom base private IP subnet (e.g. 10.10.0.1)")
    w_proto_i.add_argument("--private-ip-2", help="Secondary internal private IP subnet")
    w_proto_i.add_argument("--bitswap", action="store_true", help="Also enable TCP bit-swapping alongside protoswap")
    w_proto_i.add_argument("-o", "--output", help="Output file path")

    w_proto_k = ww_proto_sub.add_parser(
        "kharej",
        help="Kharej server configuration",
        formatter_class=CustomFormatter,
        epilog="""Examples:
  # Single port:
  ./confgen.py waterwall protoswap kharej -n proto-single -ii 198.51.100.10 -ki 203.0.113.20 --tcp 443

  # Multi-service hybrid with custom protocols and floating IP:
  ./confgen.py waterwall protoswap kharej -n proto-hybrid -ii 198.51.100.10 -ki 203.0.113.20 \\
      --tcp 6443,2059 --udp 27015 --protoswap-tcp 253 --protoswap-udp 252 --float 203.0.113.21
""",
    )
    w_proto_k.add_argument("pos_name", nargs="?", help="[Positional fallback] Name")
    w_proto_k.add_argument("pos_iran_ip", nargs="?", help="[Positional fallback] Iran IP")
    w_proto_k.add_argument("pos_kharej_ip", nargs="?", help="[Positional fallback] Kharej IP")
    w_proto_k.add_argument("-n", "--name", help="Configuration name")
    w_proto_k.add_argument("-ii", "--iran-ip", help="Iran Server public IP")
    w_proto_k.add_argument("-ki", "--kharej-ip", help="Kharej Server main public IP")
    w_proto_k.add_argument("--tcp", nargs="*", default=[], help="TCP service port(s), e.g. --tcp 6443,2059 or --tcp 443")
    w_proto_k.add_argument("--udp", nargs="*", default=[], help="UDP service port(s), e.g. --udp 27015")
    w_proto_k.add_argument("-lp", "--listen-port", type=int, help="Single transport port fallback")
    w_proto_k.add_argument("-fp", "--final-port", type=int, help="Single destination service port fallback")
    w_proto_k.add_argument("--protoswap-tcp", type=int, default=253, help="Replacement protocol number for TCP (default: 253)")
    w_proto_k.add_argument("--protoswap-udp", type=int, default=252, help="Replacement protocol number for UDP (default: 252)")
    w_proto_k.add_argument("--tcp-tunnel-port", type=int, default=8443, help="Transport port for TCP services (default: 8443)")
    w_proto_k.add_argument("--udp-tunnel-port", type=int, default=8444, help="Transport port for UDP services (default: 8444)")
    w_proto_k.add_argument("--final-ip", default="127.0.0.1", help="Local destination service IP (default: 127.0.0.1)")
    w_proto_k.add_argument("--float", nargs="*", default=[], help="Floating IPs (enables multi-IP mode)")
    w_proto_k.add_argument("--xor-key", type=int, default=90, help="XOR obfuscation key (default: 90)")
    w_proto_k.add_argument("--private-ip", help="Custom base private IP subnet (e.g. 10.10.0.1)")
    w_proto_k.add_argument("--private-ip-2", help="Secondary internal private IP subnet")
    w_proto_k.add_argument("--bitswap", action="store_true", help="Also enable TCP bit-swapping alongside protoswap")
    w_proto_k.add_argument("-o", "--output", help="Output file path")

    # 2.6 waterwall benchmark
    ww_bench = ww_sub.add_parser(
        "benchmark",
        help="WaterWall SpeedTest benchmarking (SpeedTestServer / SpeedTestClient / Suite)",
        formatter_class=CustomFormatter,
    )
    ww_bench_sub = ww_bench.add_subparsers(dest="benchmark_cmd", help="Benchmark action (server | client | suite)")

    # ww benchmark server
    w_b_s = ww_bench_sub.add_parser(
        "server",
        help="Kharej SpeedTestServer configuration",
        formatter_class=CustomFormatter,
        epilog="""Example:
  ./confgen.py waterwall benchmark server -p 9000 --udp-port 9001 -o speedtest-server.json
""",
    )
    w_b_s.add_argument("-n", "--name", default="speedtest-server", help="Configuration name")
    w_b_s.add_argument("-p", "--tcp-port", type=int, default=9000, help="TCP listening port (default: 9000)")
    w_b_s.add_argument("--udp-port", type=int, default=9001, help="UDP listening port (default: 9001)")
    w_b_s.add_argument("-b", "--bind", default="127.0.0.1", help="Binding address (default: 127.0.0.1)")
    w_b_s.add_argument("--report-interval", type=int, default=1000, help="Report cadence in ms")
    w_b_s.add_argument("--quiet", action="store_true", help="Quiet mode (suppress interval logs)")
    w_b_s.add_argument("-o", "--output", help="Output file path")

    # ww benchmark client
    w_b_c = ww_bench_sub.add_parser(
        "client",
        help="Iran SpeedTestClient configuration",
        formatter_class=CustomFormatter,
        epilog="""Examples:
  # TCP bidirectional test:
  ./confgen.py waterwall benchmark client -t 127.0.0.1 -p 6443 --mode tcp --direction bidirectional -o client-tcp.json

  # UDP upload probe:
  ./confgen.py waterwall benchmark client -t 127.0.0.1 -p 27015 --mode udp --direction upload --udp-rate 50000000 -o client-udp.json
""",
    )
    w_b_c.add_argument("-n", "--name", default="speedtest-client", help="Configuration name")
    w_b_c.add_argument("-t", "--target-ip", default="127.0.0.1", help="Target tunnel entry IP")
    w_b_c.add_argument("-p", "--target-port", type=int, required=True, help="Target tunnel entry port")
    w_b_c.add_argument("-m", "--mode", choices=["tcp", "udp"], default="tcp", help="Protocol mode (tcp | udp)")
    w_b_c.add_argument("-d", "--direction", choices=["upload", "download", "bidirectional"], default="bidirectional", help="Traffic direction")
    w_b_c.add_argument("--duration", type=int, default=10000, help="Duration in ms (default: 10000)")
    w_b_c.add_argument("--warmup", type=int, default=1000, help="Warmup duration in ms (default: 1000)")
    w_b_c.add_argument("--connections", type=int, default=4, help="Parallel streams count (default: 4)")
    w_b_c.add_argument("--payload-size", type=int, help="Payload size in bytes")
    w_b_c.add_argument("--udp-rate", type=int, help="Target UDP rate in bits/sec")
    w_b_c.add_argument("-o", "--output", help="Output file path")

    # ww benchmark suite
    w_b_suite = ww_bench_sub.add_parser(
        "suite",
        help="Generate full multi-candidate benchmark suite (BitSwap vs ProtoSwap variants)",
        formatter_class=CustomFormatter,
        epilog="""Example:
  ./confgen.py waterwall benchmark suite -ii 198.51.100.10 -ki 203.0.113.20 --tcp 6443 --udp 27015 -o bench_suite
""",
    )
    w_b_suite.add_argument("-ii", "--iran-ip", required=True, help="Iran Server public IP")
    w_b_suite.add_argument("-ki", "--kharej-ip", required=True, help="Kharej Server main public IP")
    w_b_suite.add_argument("--tcp", nargs="*", default=[6443], help="TCP service port(s)")
    w_b_suite.add_argument("--udp", nargs="*", default=[27015], help="UDP service port(s)")
    w_b_suite.add_argument("--float", nargs="*", default=[], help="Kharej floating IPs")
    w_b_suite.add_argument("--speedtest-tcp-port", type=int, default=9000, help="Internal benchmark TCP target port")
    w_b_suite.add_argument("--speedtest-udp-port", type=int, default=9001, help="Internal benchmark UDP target port")
    w_b_suite.add_argument("--duration", type=int, default=10000, help="Test duration per candidate in ms")
    w_b_suite.add_argument("--connections", type=int, default=4, help="Parallel connection count")
    w_b_suite.add_argument("-o", "--output-dir", default="benchmark_suite", help="Output directory path")

    # 2.7 waterwall simple
    ww_s = ww_sub.add_parser("simple", help="Direct port-to-port forwarding", formatter_class=CustomFormatter)
    ww_s.add_argument("-n", "--name", required=True, help="Configuration name")
    ww_s.add_argument("--proto", "--protocol", dest="protocol", choices=["tcp", "udp"], default="tcp", help="Protocol")
    ww_s.add_argument("-sp", "--start-port", type=int, required=True, help="Starting port of range")
    ww_s.add_argument("-ep", "--end-port", type=int, required=True, help="Ending port of range")
    ww_s.add_argument("-di", "--dest-ip", required=True, help="Destination IP address")
    ww_s.add_argument("-dp", "--dest-port", type=int, required=True, help="Destination target port")
    ww_s.add_argument("-o", "--output", help="Output file path")

    # 2.8 waterwall core
    ww_core = ww_sub.add_parser(
        "core",
        help="Generate WaterWall core.json settings wrapper",
        formatter_class=CustomFormatter,
        epilog="""Examples:
  ./confgen.py waterwall core kharej_tun.json speed_srv.json -o core.json
""",
    )
    ww_core.add_argument("configs", nargs="*", default=[], help="Configuration JSON filenames to load")
    ww_core.add_argument("--loglevel", default="WARN", choices=["DEBUG", "INFO", "WARN", "ERROR"], help="Log level")
    ww_core.add_argument("--workers", type=int, default=0, help="Worker threads (0 = auto)")
    ww_core.add_argument("--mtu", type=int, default=1400, help="MTU size")
    ww_core.add_argument("-o", "--output", default="core.json", help="Output file path (default: core.json)")

    return parser


def main(argv: Optional[List[str]] = None) -> int:
    parser = create_parser()
    args = parser.parse_args(argv)

    if not args.command:
        parser.print_help()
        return 1

    try:
        # Route Xray
        if args.command == "xray":
            if args.subcommand == "reverse":
                if args.side == "iran":
                    name = args.name or args.pos_name or "xray-iran"
                    port = args.port if args.port != 8443 or not args.pos_port else args.pos_port
                    tcp_ports = validate_ports_list(args.tcp) if args.tcp else []
                    udp_ports = validate_ports_list(args.udp) if args.udp else []
                    cfg = generate_xray_iran_config(
                        listen_port=port,
                        tcp_ports=tcp_ports,
                        udp_ports=udp_ports,
                        uuid=args.uuid,
                        ws_path=args.path,
                        tls_cert=args.tls_cert,
                        tls_key=args.tls_key,
                    )
                    out_path = args.output or f"{name}.json"
                    write_json(cfg, out_path)
                    return 0

                elif args.side == "kharej":
                    name = args.name or args.pos_name or "xray-kharej"
                    iran_ip = args.iran_ip or args.pos_iran_ip
                    if not iran_ip:
                        print_error("Missing required parameter: -ii, --iran-ip")
                        return 1
                    port = args.port if args.port != 8443 or not args.pos_port else args.pos_port
                    cfg = generate_xray_kharej_config(
                        iran_ip=iran_ip,
                        connect_port=port,
                        uuid=args.uuid,
                        ws_path=args.path,
                        early_data=args.ed,
                        tls_sni=args.tls_sni,
                    )
                    out_path = args.output or f"{name}.json"
                    write_json(cfg, out_path)
                    return 0

        # Route Waterwall
        elif args.command == "waterwall":
            if args.subcommand == "reverse-reality":
                if args.side == "iran":
                    name = args.name or args.pos_name
                    iran_ip = args.iran_ip or args.pos_iran_ip
                    kharej_ip = args.kharej_ip or args.pos_kharej_ip
                    port = args.port if args.port != 443 or not args.pos_port else args.pos_port
                    domain = args.domain or args.pos_domain or "telewebion.ir"
                    white_ip = args.white_ip or args.pos_white_ip

                    if not (name and iran_ip and kharej_ip and white_ip):
                        print_error("Missing required parameters for Iran Reverse Reality (-n, -ii, -ki, -wi)")
                        return 1

                    cfg = generate_reverse_reality_tcp_iran(
                        config_name=name,
                        iran_ip=iran_ip,
                        kharej_ip=kharej_ip,
                        port=port,
                        domain=domain,
                        white_ip=white_ip,
                        password=args.password,
                        float_ips=args.float,
                        use_proxy_protocol=args.proxy_protocol,
                        use_halfduplex=args.halfduplex,
                        use_fisher=args.fisher,
                        cert_path=args.tls_cert,
                        key_path=args.tls_key,
                    )
                    out_path = args.output or f"{name}.json"
                    write_json(cfg, out_path)
                    return 0

                elif args.side == "kharej":
                    name = args.name or args.pos_name
                    iran_ip = args.iran_ip or args.pos_iran_ip
                    kharej_ip = args.kharej_ip or args.pos_kharej_ip
                    port = args.port if args.port != 443 or not args.pos_port else args.pos_port
                    domain = args.domain or args.pos_domain or "telewebion.ir"
                    final_port = args.final_port or args.pos_final_port

                    if not (name and iran_ip and kharej_ip and final_port):
                        print_error("Missing required parameters for Kharej Reverse Reality (-n, -ii, -ki, -fp)")
                        return 1

                    cfg = generate_reverse_reality_tcp_kharej(
                        config_name=name,
                        iran_ip=iran_ip,
                        kharej_ip=kharej_ip,
                        port=port,
                        domain=domain,
                        final_port=final_port,
                        password=args.password,
                        min_held=args.min_held,
                        float_ips=args.float,
                        use_halfduplex=args.halfduplex,
                        use_fisher=args.fisher,
                    )
                    out_path = args.output or f"{name}.json"
                    write_json(cfg, out_path)
                    return 0

            elif args.subcommand == "tls-reverse":
                if args.side == "iran":
                    cfg = generate_waterwall_tls_reverse_iran(
                        config_name=args.name,
                        iran_ip=args.iran_ip,
                        port=args.port,
                        cert_path=args.cert,
                        key_path=args.key,
                        kharej_ips=args.kharej_ips,
                        use_proxy_protocol=args.proxy_protocol,
                    )
                    out_path = args.output or f"{args.name}.json"
                    write_json(cfg, out_path)
                    return 0

                elif args.side == "kharej":
                    cfg = generate_waterwall_tls_reverse_kharej(
                        config_name=args.name,
                        iran_ip=args.iran_ip,
                        port=args.port,
                        sni=args.sni,
                        final_port=args.final_port,
                        final_ip=args.final_ip,
                    )
                    out_path = args.output or f"{args.name}.json"
                    write_json(cfg, out_path)
                    return 0

            elif args.subcommand == "udp-reverse":
                if args.side == "iran":
                    cfg = generate_udp_reverse_iran(
                        config_name=args.name,
                        iran_public_ip=args.iran_ip,
                        kharej_public_ip=args.kharej_ip,
                        listen_port=args.listen_port,
                        tunnel_port=args.tunnel_port,
                        tun_ip_iran=args.tun_iran,
                        tun_ip_kharej=args.tun_kharej,
                        xor_key=args.xor_key,
                        reverse_secret=args.secret,
                    )
                    out_path = args.output or f"{args.name}.json"
                    write_json(cfg, out_path)
                    return 0

                elif args.side == "kharej":
                    cfg = generate_udp_reverse_kharej(
                        config_name=args.name,
                        iran_public_ip=args.iran_ip,
                        kharej_public_ip=args.kharej_ip,
                        target_port=args.target_port,
                        tunnel_port=args.tunnel_port,
                        tun_ip_iran=args.tun_iran,
                        tun_ip_kharej=args.tun_kharej,
                        xor_key=args.xor_key,
                        reverse_secret=args.secret,
                    )
                    out_path = args.output or f"{args.name}.json"
                    write_json(cfg, out_path)
                    return 0

            elif args.subcommand == "bitswap":
                name = args.name or args.pos_name
                iran_ip = args.iran_ip or args.pos_iran_ip
                kharej_ip = args.kharej_ip or args.pos_kharej_ip

                if not name or not iran_ip or not kharej_ip:
                    print_error("Missing required parameters: name, iran-ip, and kharej-ip are required.")
                    return 1

                tcp_ports = _extract_ports(args.tcp)
                udp_ports = _extract_ports(args.udp)
                float_ips = _extract_ips(args.float)

                if args.side == "iran":
                    if not tcp_ports and args.listen_port:
                        tcp_ports = [args.listen_port]
                    tcp_tunnel_port = args.forward_port or args.tcp_tunnel_port

                    cert_path = args.tls_cert or (args.tls[0] if args.tls else None)
                    key_path = args.tls_key or (args.tls[1] if args.tls else None)
                    use_tls = bool(cert_path and key_path)

                    cfg = generate_bitswap_iran(
                        config_name=name,
                        iran_ip=iran_ip,
                        kharej_ip=kharej_ip,
                        tcp_ports=tcp_ports,
                        udp_ports=udp_ports,
                        float_ips=float_ips,
                        tcp_tunnel_port=tcp_tunnel_port,
                        udp_tunnel_port=args.udp_tunnel_port,
                        mux_count=args.mux_count,
                        use_proxy_protocol=args.proxy_protocol,
                        use_tls=use_tls,
                        cert_path=cert_path,
                        key_path=key_path,
                        xor_key=args.xor_key,
                        custom_private_ip=args.private_ip,
                        custom_private_ip_2=args.private_ip_2,
                    )
                    out_path = args.output or f"{name}.json"
                    write_json(cfg, out_path)
                    return 0

                elif args.side == "kharej":
                    if not tcp_ports and args.final_port:
                        tcp_ports = [args.final_port]
                    tcp_tunnel_port = args.listen_port or args.tcp_tunnel_port

                    cfg = generate_bitswap_kharej(
                        config_name=name,
                        iran_ip=iran_ip,
                        kharej_ip=kharej_ip,
                        tcp_ports=tcp_ports,
                        udp_ports=udp_ports,
                        float_ips=float_ips,
                        tcp_tunnel_port=tcp_tunnel_port,
                        udp_tunnel_port=args.udp_tunnel_port,
                        final_ip=args.final_ip,
                        xor_key=args.xor_key,
                        custom_private_ip=args.private_ip,
                        custom_private_ip_2=args.private_ip_2,
                    )
                    out_path = args.output or f"{name}.json"
                    write_json(cfg, out_path)
                    return 0

            elif args.subcommand == "protoswap":
                name = args.name or args.pos_name
                iran_ip = args.iran_ip or args.pos_iran_ip
                kharej_ip = args.kharej_ip or args.pos_kharej_ip

                if not name or not iran_ip or not kharej_ip:
                    print_error("Missing required parameters: name, iran-ip, and kharej-ip are required.")
                    return 1

                tcp_ports = _extract_ports(args.tcp)
                udp_ports = _extract_ports(args.udp)
                float_ips = _extract_ips(args.float)

                if args.side == "iran":
                    if not tcp_ports and args.listen_port:
                        tcp_ports = [args.listen_port]
                    tcp_tunnel_port = args.forward_port or args.tcp_tunnel_port

                    cert_path = args.tls_cert or (args.tls[0] if args.tls else None)
                    key_path = args.tls_key or (args.tls[1] if args.tls else None)
                    use_tls = bool(cert_path and key_path)

                    cfg = generate_protoswap_iran(
                        config_name=name,
                        iran_ip=iran_ip,
                        kharej_ip=kharej_ip,
                        tcp_ports=tcp_ports,
                        udp_ports=udp_ports,
                        float_ips=float_ips,
                        protoswap_tcp=args.protoswap_tcp,
                        protoswap_udp=args.protoswap_udp,
                        tcp_tunnel_port=tcp_tunnel_port,
                        udp_tunnel_port=args.udp_tunnel_port,
                        mux_count=args.mux_count,
                        use_proxy_protocol=args.proxy_protocol,
                        use_tls=use_tls,
                        cert_path=cert_path,
                        key_path=key_path,
                        xor_key=args.xor_key,
                        custom_private_ip=args.private_ip,
                        custom_private_ip_2=args.private_ip_2,
                        enable_bitswap=args.bitswap,
                    )
                    out_path = args.output or f"{name}.json"
                    write_json(cfg, out_path)
                    return 0

                elif args.side == "kharej":
                    if not tcp_ports and args.final_port:
                        tcp_ports = [args.final_port]
                    tcp_tunnel_port = args.listen_port or args.tcp_tunnel_port

                    cfg = generate_protoswap_kharej(
                        config_name=name,
                        iran_ip=iran_ip,
                        kharej_ip=kharej_ip,
                        tcp_ports=tcp_ports,
                        udp_ports=udp_ports,
                        float_ips=float_ips,
                        protoswap_tcp=args.protoswap_tcp,
                        protoswap_udp=args.protoswap_udp,
                        tcp_tunnel_port=tcp_tunnel_port,
                        udp_tunnel_port=args.udp_tunnel_port,
                        final_ip=args.final_ip,
                        xor_key=args.xor_key,
                        custom_private_ip=args.private_ip,
                        custom_private_ip_2=args.private_ip_2,
                        enable_bitswap=args.bitswap,
                    )
                    out_path = args.output or f"{name}.json"
                    write_json(cfg, out_path)
                    return 0

            elif args.subcommand == "benchmark":
                if args.benchmark_cmd == "server":
                    cfg = generate_speedtest_server_config(
                        config_name=args.name,
                        tcp_port=args.tcp_port,
                        udp_port=args.udp_port,
                        bind_address=args.bind,
                        report_interval_ms=args.report_interval,
                        json_summary=True,
                        quiet=args.quiet,
                    )
                    out_path = args.output or f"{args.name}.json"
                    write_json(cfg, out_path)
                    return 0

                elif args.benchmark_cmd == "client":
                    cfg = generate_speedtest_client_config(
                        config_name=args.name,
                        target_address=args.target_ip,
                        target_port=args.target_port,
                        mode=args.mode,
                        direction=args.direction,
                        duration_ms=args.duration,
                        warmup_ms=args.warmup,
                        connection_count=args.connections,
                        payload_size=args.payload_size,
                        udp_target_bits_per_sec=args.udp_rate,
                        json_summary=True,
                    )
                    out_path = args.output or f"{args.name}.json"
                    write_json(cfg, out_path)
                    return 0

                elif args.benchmark_cmd == "suite":
                    tcp_ports = _extract_ports(args.tcp) or [6443]
                    udp_ports = _extract_ports(args.udp) or [27015]
                    float_ips = _extract_ips(args.float)

                    suite_files = generate_benchmark_suite(
                        iran_ip=args.iran_ip,
                        kharej_ip=args.kharej_ip,
                        output_dir=args.output_dir,
                        tcp_ports=tcp_ports,
                        udp_ports=udp_ports,
                        float_ips=float_ips,
                        speedtest_tcp_port=args.speedtest_tcp_port,
                        speedtest_udp_port=args.speedtest_udp_port,
                        test_duration_ms=args.duration,
                        connection_count=args.connections,
                    )

                    os.makedirs(args.output_dir, exist_ok=True)
                    for filename, content in suite_files.items():
                        filepath = os.path.join(args.output_dir, filename)
                        if filename.endswith(".json"):
                            write_json(content, filepath)
                        else:
                            with open(filepath, "w", encoding="utf-8") as f:
                                f.write(content)
                            try:
                                os.chmod(filepath, 0o755)
                            except Exception:
                                pass

                    print_success(f"Benchmark suite generated successfully in: {args.output_dir}/")
                    print_info(f"Generated {len(suite_files)} files including 'run_benchmark.py'.")
                    return 0

            elif args.subcommand == "simple":
                cfg = generate_simple_config(
                    config_name=args.name,
                    protocol=args.protocol,
                    start_port=args.start_port,
                    end_port=args.end_port,
                    destination_ip=args.dest_ip,
                    destination_port=args.dest_port,
                )
                out_path = args.output or f"{args.name}.json"
                write_json(cfg, out_path)
                return 0

            elif args.subcommand == "core":
                cfg = generate_core_config(
                    config_paths=args.configs,
                    loglevel=args.loglevel,
                    console=True,
                    workers=args.workers,
                    mtu=args.mtu,
                )
                out_path = args.output or "core.json"
                write_json(cfg, out_path)
                return 0

        parser.print_help()
        return 1

    except Exception as e:
        print_error(f"Execution failed: {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
