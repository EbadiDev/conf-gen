"""Command Line Interface for ConfGen with comprehensive flags and clean UX."""

import argparse
import os
import sys
from typing import Any, List, Optional

from confgen import __version__
from confgen.core.utils import (
    print_error,
    print_info,
    print_success,
    save_waterwall_config,
    update_core_json,
    write_json,
)
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
from confgen.core.finder import (
    run_finder_server,
    run_finder_client,
)


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


def _add_v3_subparser(v3_p: argparse.ArgumentParser) -> None:
    v3_sub = v3_p.add_subparsers(dest="v3_side", help="V3 mode (server | client)")

    # v3 server (Iran side)
    v3_s = v3_sub.add_parser(
        "server",
        help="V3 Server configuration (Iran side)",
        formatter_class=CustomFormatter,
        epilog="""Examples:
  # Bash syntax:
  ./confgen.py v3 server atlanta 109.94.164.71 162.247.153.90 30.6.0.1 50 -l 8080 -f 8085 --mux 8 --tls /path/cert.pem /path/key.pem
""",
    )
    v3_s.add_argument("pos_name", nargs="?", help="Tunnel configuration name (e.g. atlanta)")
    v3_s.add_argument("pos_non_iran_ip", nargs="?", help="Kharej server IP")
    v3_s.add_argument("pos_iran_ip", nargs="?", help="Iran server IP")
    v3_s.add_argument("pos_private_ip", nargs="?", help="Private network IP (e.g. 30.6.0.1)")
    v3_s.add_argument("pos_protocol", nargs="?", type=int, help="Protoswap TCP protocol number")
    v3_s.add_argument("pos_udp_protocol", nargs="?", type=int, help="Protoswap UDP protocol number")

    v3_s.add_argument("-n", "--name", help="Configuration name")
    v3_s.add_argument("-ki", "--kharej-ip", help="Kharej server public IP")
    v3_s.add_argument("-ii", "--iran-ip", help="Iran server public IP")
    v3_s.add_argument("--private-ip", help="Private network IP")
    v3_s.add_argument("--protoswap-tcp", type=int, help="Replacement protocol number for TCP")
    v3_s.add_argument("--protoswap-udp", type=int, help="Replacement protocol number for UDP")
    v3_s.add_argument("-l", "-p", "--listen-port", "--listen", type=int, default=443, help="Listen port on Iran side (default: 443)")
    v3_s.add_argument("-f", "-t", "--target-port", "--forward", type=int, default=443, help="Target/forward port on Kharej side (default: 443)")
    v3_s.add_argument("--mux", nargs="?", const=8, type=int, default=0, help="Enable Mux multiplexing (default count: 8)")
    v3_s.add_argument("--no-mux", action="store_true", help="Disable Mux multiplexing (Direct Classic TCP mode)")
    v3_s.add_argument("--tls", nargs=2, metavar=("CERT", "KEY"), help="TLS certificate and key paths")
    v3_s.add_argument("--proxy-protocol", action="store_true", help="Enable Proxy Protocol header")
    v3_s.add_argument("--xor-key", type=int, default=90, help="XOR obfuscation key (default: 90)")
    v3_s.add_argument("--no-core", action="store_true", help="Do not automatically add to core.json")

    # v3 client (Kharej side)
    v3_c = v3_sub.add_parser(
        "client",
        help="V3 Client configuration (Kharej side)",
        formatter_class=CustomFormatter,
        epilog="""Examples:
  # Bash syntax:
  ./confgen.py v3 client atlanta 109.94.164.71 162.247.153.90 30.6.0.1 50 -l 8085 -f 8080 --mux 8
""",
    )
    v3_c.add_argument("pos_name", nargs="?", help="Tunnel configuration name (e.g. atlanta)")
    v3_c.add_argument("pos_non_iran_ip", nargs="?", help="Kharej server IP")
    v3_c.add_argument("pos_iran_ip", nargs="?", help="Iran server IP")
    v3_c.add_argument("pos_private_ip", nargs="?", help="Private network IP (e.g. 30.6.0.1)")
    v3_c.add_argument("pos_protocol", nargs="?", type=int, help="Protoswap TCP protocol number")
    v3_c.add_argument("pos_udp_protocol", nargs="?", type=int, help="Protoswap UDP protocol number")

    v3_c.add_argument("-n", "--name", help="Configuration name")
    v3_c.add_argument("-ki", "--kharej-ip", help="Kharej server public IP")
    v3_c.add_argument("-ii", "--iran-ip", help="Iran server public IP")
    v3_c.add_argument("--private-ip", help="Private network IP")
    v3_c.add_argument("--protoswap-tcp", type=int, help="Replacement protocol number for TCP")
    v3_c.add_argument("--protoswap-udp", type=int, help="Replacement protocol number for UDP")
    v3_c.add_argument("-l", "-p", "--listen-port", "--listen", type=int, default=443, help="Listen transport port on Kharej side (default: 443)")
    v3_c.add_argument("-f", "-t", "--target-port", "--forward", type=int, default=443, help="Final destination service port on Kharej side (default: 443)")
    v3_c.add_argument("--final-ip", default="127.0.0.1", help="Final destination service IP (default: 127.0.0.1)")
    v3_c.add_argument("--mux", nargs="?", const=8, type=int, default=0, help="Enable Mux multiplexing (default count: 8)")
    v3_c.add_argument("--no-mux", action="store_true", help="Disable Mux multiplexing (Direct Classic TCP mode)")
    v3_c.add_argument("--proxy-protocol", action="store_true", help="Enable Proxy Protocol header")
    v3_c.add_argument("--xor-key", type=int, default=90, help="XOR obfuscation key (default: 90)")
    v3_c.add_argument("--no-core", action="store_true", help="Do not automatically add to core.json")


def _handle_v3(args: argparse.Namespace) -> int:
    side = getattr(args, "v3_side", None) or getattr(args, "side", None)
    name = args.name or args.pos_name
    kharej_ip = args.kharej_ip or args.pos_non_iran_ip
    iran_ip = args.iran_ip or args.pos_iran_ip
    private_ip = args.private_ip or args.pos_private_ip
    proto_tcp = args.protoswap_tcp if args.protoswap_tcp is not None else args.pos_protocol
    proto_udp = args.protoswap_udp if args.protoswap_udp is not None else args.pos_udp_protocol

    if not name or not kharej_ip or not iran_ip or not private_ip or proto_tcp is None:
        print_error("Missing required parameters for v3 (<config_name> <non_iran_ip> <iran_ip> <private_ip> <protocol>)")
        return 1

    if proto_udp is None:
        proto_udp = proto_tcp + 1

    use_mux = not bool(getattr(args, "no_mux", False))
    mux_count = args.mux if (args.mux and args.mux > 0) else 8
    xor_key = getattr(args, "xor_key", 90) or 90

    if side in ("server", "iran"):
        cert_path = args.tls[0] if getattr(args, "tls", None) else None
        key_path = args.tls[1] if getattr(args, "tls", None) else None
        use_tls = bool(cert_path and key_path)

        cfg = generate_protoswap_iran(
            config_name=name,
            iran_ip=iran_ip,
            kharej_ip=kharej_ip,
            tcp_ports=[args.listen_port],
            tcp_tunnel_port=args.target_port,
            protoswap_tcp=proto_tcp,
            protoswap_udp=proto_udp,
            custom_private_ip=private_ip,
            mux_count=mux_count,
            use_proxy_protocol=args.proxy_protocol,
            use_tls=use_tls,
            cert_path=cert_path,
            key_path=key_path,
            xor_key=xor_key,
            use_mux=use_mux,
        )
        save_waterwall_config(cfg, name=name, auto_core=not args.no_core)
        from confgen.core.link import encode_setup_link, print_setup_box
        payload = {
            "type": "protoswap",
            "name": name,
            "iran_ip": iran_ip,
            "kharej_ip": kharej_ip,
            "tcp_ports": [args.listen_port],
            "tcp_tunnel_port": args.target_port,
            "protoswap_tcp": proto_tcp,
            "protoswap_udp": proto_udp,
            "private_ip": private_ip,
            "xor_key": xor_key,
            "use_mux": use_mux,
        }
        link = encode_setup_link(payload)
        mode_label = f"V3 ProtoSwap ({proto_tcp}/{proto_udp})" + (" (Direct No-Mux)" if not use_mux else "")
        print_setup_box(link, name, mode_label)
        return 0

    elif side in ("client", "kharej"):
        final_ip = getattr(args, "final_ip", "127.0.0.1") or "127.0.0.1"
        cfg = generate_protoswap_kharej(
            config_name=name,
            iran_ip=iran_ip,
            kharej_ip=kharej_ip,
            tcp_ports=[args.target_port],
            tcp_tunnel_port=args.listen_port,
            final_ip=final_ip,
            protoswap_tcp=proto_tcp,
            protoswap_udp=proto_udp,
            custom_private_ip=private_ip,
            xor_key=xor_key,
            use_mux=use_mux,
        )
        save_waterwall_config(cfg, name=name, auto_core=not args.no_core)
        return 0

    else:
        print_error("Invalid v3 mode. Must be 'server' or 'client'.")
        return 1


def _add_finder_subparser(finder_p: argparse.ArgumentParser) -> None:
    finder_sub = finder_p.add_subparsers(dest="finder_cmd", help="Finder role (server | client)")

    # finder server (Kharej daemon)
    f_srv = finder_sub.add_parser(
        "server",
        help="Start Finder Agent daemon on Kharej server",
        formatter_class=CustomFormatter,
        epilog="""Examples:
  ./confgen.py finder server --port 8088
  ./confgen.py waterwall finder server -p 8088
""",
    )
    f_srv.add_argument("pos_port", nargs="?", type=int, help="[Positional fallback] Control port")
    f_srv.add_argument("-p", "--port", type=int, default=8088, help="Control HTTP port (default: 8088)")
    f_srv.add_argument("--host", default="0.0.0.0", help="Bind IP address (default: 0.0.0.0)")
    f_srv.add_argument("--test-dir", help="Isolated directory for test WaterWall instance (default: /root/waterwall-test)")

    # finder client (Iran orchestrator)
    f_cli = finder_sub.add_parser(
        "client",
        help="Orchestrate automated tunnel protocol sweep from Iran",
        formatter_class=CustomFormatter,
        epilog="""Examples:
  ./confgen.py finder client -ii 198.51.100.10 -ki 203.0.113.20 --preset top
  ./confgen.py finder client 198.51.100.10 203.0.113.20 -cp 8088 -p 9001 -d 5
  ./confgen.py finder client -ii 198.51.100.10 -ki 203.0.113.20 --protocols 50/51,51/52,47/136
  ./confgen.py finder client -ii 198.51.100.10 -ki 203.0.113.20 --test-dir /root/waterwall-test
""",
    )
    f_cli.add_argument("pos_iran_ip", nargs="?", help="[Positional fallback] Iran Server IP")
    f_cli.add_argument("pos_kharej_ip", nargs="?", help="[Positional fallback] Kharej Server IP")
    f_cli.add_argument("-ii", "--iran-ip", help="Iran Server public IP")
    f_cli.add_argument("-ki", "--kharej-ip", help="Kharej Server public IP")
    f_cli.add_argument("-cp", "--control-port", type=int, default=8088, help="Kharej agent control port (default: 8088)")
    f_cli.add_argument("-p", "--port", "--tcp-port", dest="port", type=int, default=9001, help="WaterWall tunnel benchmarking port (default: 9001)")
    f_cli.add_argument("-n", "--name", default="finder-tunnel", help="Tunnel configuration name (default: finder-tunnel)")
    f_cli.add_argument("-t", "-d", "--duration", type=int, default=5, help="Test duration in seconds per direction (default: 5)")
    f_cli.add_argument("--preset", choices=["methods", "top", "fast", "combo", "sni", "hospital", "hospitals", "all"], default="top", help="Candidate protocol preset (default: top)")
    f_cli.add_argument("--protocols", help="Custom comma-separated protocol pairs (e.g. 50/51,51/52,47/136)")
    f_cli.add_argument("--bitswap", action="store_true", help="Force TCP BitSwap on all tested protocols")
    f_cli.add_argument("--include-bitswap", action="store_true", help="Include BitSwap variants for custom protocols or preset")
    f_cli.add_argument("--apply", action="store_true", help="Automatically activate winning configuration in test directory (default: off, view stats only)")
    f_cli.add_argument("--test-dir", help="Isolated directory for test WaterWall instance (default: /root/waterwall-test)")
    f_cli.add_argument("--private-ip", default="10.99.0.1", help="Custom base private IP for TUN test adapter (default: 10.99.0.1)")
    f_cli.add_argument("--private-ip-2", help="Optional secondary private IP for dual TUN")
    f_cli.add_argument("--tls-domain", help="Domain for TLS Reverse benchmark")
    f_cli.add_argument("--tls-cert", help="Path to TLS certificate (fullchain.pem) for TLS Reverse")
    f_cli.add_argument("--tls-key", help="Path to TLS private key (privkey.pem) for TLS Reverse")
    f_cli.add_argument("--sni", default="telewebion.ir", help="Reality SNI domain (default: telewebion.ir)")
    f_cli.add_argument("--snis", help="Comma-separated list of SNIs to benchmark with Reverse Reality + HD + Fisher")
    f_cli.add_argument("--sni-file", help="Path to text file containing SNI domains (one per line) to benchmark")


def _handle_finder(args: argparse.Namespace) -> int:
    cmd = getattr(args, "finder_cmd", None)
    if cmd == "server":
        port = args.port if args.port != 8088 or not getattr(args, "pos_port", None) else args.pos_port
        return run_finder_server(port=port, host=args.host, test_dir=getattr(args, "test_dir", None))
    elif cmd == "client":
        iran_ip = args.iran_ip or getattr(args, "pos_iran_ip", None)
        kharej_ip = args.kharej_ip or getattr(args, "pos_kharej_ip", None)
        if not iran_ip or not kharej_ip:
            print_error("Missing required parameters: iran-ip (-ii) and kharej-ip (-ki) are required.")
            return 1
        return run_finder_client(
            iran_ip=iran_ip,
            kharej_ip=kharej_ip,
            control_port=args.control_port,
            tcp_port=args.port,
            name=args.name,
            duration=args.duration,
            preset=args.preset,
            custom_protocols=args.protocols,
            bitswap=bool(getattr(args, "bitswap", False)),
            include_bitswap=bool(getattr(args, "include_bitswap", False)),
            auto_apply=bool(getattr(args, "apply", False)),
            test_dir=getattr(args, "test_dir", None),
            private_ip=getattr(args, "private_ip", "10.99.0.1") or "10.99.0.1",
            private_ip_2=getattr(args, "private_ip_2", None),
            tls_domain=getattr(args, "tls_domain", None),
            tls_cert=getattr(args, "tls_cert", None),
            tls_key=getattr(args, "tls_key", None),
            sni=getattr(args, "sni", "telewebion.ir"),
            snis=getattr(args, "snis", None),
            sni_file=getattr(args, "sni_file", None),
        )
    else:
        print_error("Invalid finder role. Choose 'server' or 'client'.")
        return 1


def create_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="confgen",
        description="Unified Configuration Generator for Anti-Censorship Tunnels (Xray, Waterwall, Rathole)",
        formatter_class=CustomFormatter,
    )
    parser.add_argument("-v", "--version", action="version", version=f"%(prog)s {__version__}")
    subparsers = parser.add_subparsers(dest="command", help="Target tunneling subsystem")

    # =========================================================================
    # 0. V3 (Top-level alias matching bash syntax)
    # =========================================================================
    v3_top_p = subparsers.add_parser(
        "v3",
        help="WaterWall V3 Protoswap tunnel configuration (bash-compatible syntax)",
        formatter_class=CustomFormatter,
    )
    _add_v3_subparser(v3_top_p)

    # =========================================================================
    # 0.0 LINK (One-line Kharej setup like BackPack)
    # =========================================================================
    link_p = subparsers.add_parser(
        "link",
        help="Tunnel setup link manager (one-line Kharej setup like BackPack)",
        formatter_class=CustomFormatter,
    )
    link_sub = link_p.add_subparsers(dest="link_cmd", help="Link actions (apply)")
    link_apply_p = link_sub.add_parser(
        "apply",
        help="Apply a setup link on Kharej server to bring up matching tunnel",
        formatter_class=CustomFormatter,
        epilog="""Examples:
  ./confgen.py link apply 'confgen://...'
  confgen link apply 'confgen://...' -ki 203.0.113.20
""",
    )
    link_apply_p.add_argument("link", help="confgen://... setup link or full curl command line")
    link_apply_p.add_argument("-ki", "--kharej-ip", help="Kharej server public IP (auto-detected if omitted)")
    link_apply_p.add_argument("--final-ip", default="127.0.0.1", help="Target service destination IP (default: 127.0.0.1)")
    link_apply_p.add_argument("-o", "--output-dir", help="Output directory path")
    link_apply_p.add_argument("--no-restart", action="store_true", help="Do not restart waterwall systemd service")

    # =========================================================================
    # 0.01 UPDATE & OPTIMIZE & MENU & TEST
    # =========================================================================
    subparsers.add_parser("update", help="Update ConfGen to latest version from GitHub", formatter_class=CustomFormatter)
    subparsers.add_parser("optimize", help="Apply system-wide network optimizations (BBR, sysctl, rp_filter)", formatter_class=CustomFormatter)
    subparsers.add_parser("menu", help="Open interactive BackPack-style terminal wizard", formatter_class=CustomFormatter)

    test_p = subparsers.add_parser("test", aliases=["speedtest"], help="Native zero-dependency stream benchmark", formatter_class=CustomFormatter)
    test_sub = test_p.add_subparsers(dest="test_cmd", help="Role (server | client)")
    t_srv = test_sub.add_parser("server", help="Start native SpeedTest server daemon", formatter_class=CustomFormatter)
    t_srv.add_argument("-p", "--port", type=int, default=9001, help="Listen port (default: 9001)")
    t_srv.add_argument("--bind", default="0.0.0.0", help="Bind IP address (default: 0.0.0.0)")

    t_cli = test_sub.add_parser("client", help="Run native SpeedTest against server", formatter_class=CustomFormatter)
    t_cli.add_argument("-t", "--host", default="127.0.0.1", help="Target host (default: 127.0.0.1)")
    t_cli.add_argument("-p", "--port", type=int, default=9001, help="Target port (default: 9001)")
    t_cli.add_argument("-d", "--duration", type=int, default=5, help="Test duration in seconds per direction (default: 5)")
    t_cli.add_argument("-P", "--parallel", type=int, default=1, help="Number of parallel child streams (default: 1)")
    t_cli.add_argument("--udp", action="store_true", help="Run UDP speed test instead of TCP")
    t_cli.add_argument("--matrix", "--scaling", dest="matrix", action="store_true", help="Run MUX multi-connection scaling benchmark table (1, 2, 8, 16 streams)")

    # =========================================================================
    # 0.1 FINDER (Top-level alias)
    # =========================================================================
    finder_top_p = subparsers.add_parser(
        "finder",
        help="Automated best tunnel finder and protocol optimizer",
        formatter_class=CustomFormatter,
    )
    _add_finder_subparser(finder_top_p)

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
    ww_rr = ww_sub.add_parser("reverse-reality", help="Reverse Reality tunnel (TCP & UDP)", formatter_class=CustomFormatter)
    ww_rr_sub = ww_rr.add_subparsers(dest="side", help="Tunnel side (iran | kharej | dual | udp)")

    # ww rr udp (Dedicated UDP Reverse Reality)
    w_rr_u = ww_rr_sub.add_parser(
        "udp",
        help="Dedicated UDP Reverse Reality tunnel (UdpOverTcp framing)",
        formatter_class=CustomFormatter,
        epilog="""Example:
  ./confgen.py waterwall reverse-reality udp iran -n champion-udp -ii 198.51.100.10 -ki 203.0.113.20 -p 27012 -fp 10006 -d shariati.tums.ac.ir --halfduplex --fisher
""",
    )
    w_rr_u.add_argument("mode", choices=["iran", "kharej"], help="Server role (iran | kharej)")
    w_rr_u.add_argument("-n", "--name", default="champion-udp", help="Configuration name (default: champion-udp)")
    w_rr_u.add_argument("-ii", "--iran-ip", required=True, help="Iran Server public IP")
    w_rr_u.add_argument("-ki", "--kharej-ip", required=True, help="Kharej Server public IP")
    w_rr_u.add_argument("-p", "--port", type=int, default=27012, help="UDP listening / carrier port (default: 27012)")
    w_rr_u.add_argument("-fp", "--final-port", type=int, default=10006, help="Target UDP service port on Kharej (default: 10006)")
    w_rr_u.add_argument("-d", "--domain", default="shariati.tums.ac.ir", help="Reality SNI domain (default: shariati.tums.ac.ir)")
    w_rr_u.add_argument("-wi", "--white-ip", help="Origin IP behind SNI domain")
    w_rr_u.add_argument("--pass", "--password", dest="password", default="arch1234net", help="Reality password")
    w_rr_u.add_argument("--float", nargs="*", default=[], help="Kharej floating IPs")
    w_rr_u.add_argument("--halfduplex", action="store_true", help="Enable HalfDuplex")
    w_rr_u.add_argument("--fisher", action="store_true", help="Enable ConnectionFisher")
    w_rr_u.add_argument("--no-core", action="store_true", help="Do not automatically add to core.json")

    # ww rr dual (Champion Multi-Port TCP + UDP)
    w_rr_d = ww_rr_sub.add_parser(
        "dual",
        help="Dual-stack (Multi-Port TCP + UDP) Reverse Reality tunnel (Champion 4.7 Gbps architecture)",
        formatter_class=CustomFormatter,
        epilog="""Example:
  ./confgen.py waterwall reverse-reality dual iran -n champion -ii 198.51.100.10 -ki 203.0.113.20 -tp 443 8080 5370 9008 -tf 10005 -up 27012 -uf 10006 -d shariati.tums.ac.ir
""",
    )
    w_rr_d.add_argument("mode", choices=["iran", "kharej"], help="Server role (iran | kharej)")
    w_rr_d.add_argument("-n", "--name", default="champion", help="Configuration name (default: champion)")
    w_rr_d.add_argument("-ii", "--iran-ip", required=True, help="Iran Server public IP")
    w_rr_d.add_argument("-ki", "--kharej-ip", required=True, help="Kharej Server public IP")
    w_rr_d.add_argument("-tp", "--tcp-ports", nargs="+", type=int, default=[443, 8080, 5370, 9008], help="Inbound TCP ports on Iran (default: 443 8080 5370 9008)")
    w_rr_d.add_argument("-tf", "--tcp-forward", type=int, default=0, help="Destination TCP port on Kharej (default: 0 = preserve incoming ports 1-to-1)")
    w_rr_d.add_argument("-up", "--udp-port", type=int, default=27012, help="Inbound UDP port on Iran (default: 27012)")
    w_rr_d.add_argument("-uf", "--udp-forward", type=int, default=0, help="Destination UDP port on Kharej (default: 0 = preserve incoming UDP port)")
    w_rr_d.add_argument("-cp", "--carrier-port", type=int, default=58443, help="TCP carrier tunnel port (default: 58443)")
    w_rr_d.add_argument("-cup", "--carrier-udp-port", type=int, default=58444, help="UDP carrier tunnel port (default: 58444)")
    w_rr_d.add_argument("-d", "--domain", default="shariati.tums.ac.ir", help="Reality SNI domain (default: shariati.tums.ac.ir)")
    w_rr_d.add_argument("-wi", "--white-ip", help="Origin IP behind SNI domain")
    w_rr_d.add_argument("--pass", "--password", dest="password", default="arch1234net", help="Reality password")
    w_rr_d.add_argument("--float", nargs="*", default=[], help="Kharej floating IPs")
    w_rr_d.add_argument("--no-halfduplex", action="store_true", help="Disable HalfDuplex")
    w_rr_d.add_argument("--no-fisher", action="store_true", help="Disable ConnectionFisher")
    w_rr_d.add_argument("--no-core", action="store_true", help="Do not automatically add to core.json")

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
    w_rr_i.add_argument("-p", "--port", nargs="+", type=int, default=[443], help="Tunnel port(s), e.g. -p 443 or -p 443 8080 5370 9008")
    w_rr_i.add_argument("-d", "--domain", default="shariati.tums.ac.ir", help="Reality SNI domain (default: shariati.tums.ac.ir)")
    w_rr_i.add_argument("-wi", "--white-ip", help="IP address behind SNI domain")
    w_rr_i.add_argument("--pass", "--password", dest="password", default="arch1234net", help="Reality password")
    w_rr_i.add_argument("--float", nargs="*", default=[], help="Kharej floating IPs")
    w_rr_i.add_argument("--proxy-protocol", action="store_true", help="Enable Proxy Protocol header")
    w_rr_i.add_argument("--halfduplex", action="store_true", help="Enable HalfDuplex client")
    w_rr_i.add_argument("--fisher", action="store_true", help="Enable ConnectionFisher server")
    w_rr_i.add_argument("--tls-cert", help="TLS certificate path for local termination")
    w_rr_i.add_argument("--tls-key", help="TLS key path for local termination")
    w_rr_i.add_argument("--no-core", action="store_true", help="Do not automatically add to core.json")

    # ww rr kharej
    w_rr_k = ww_rr_sub.add_parser(
        "kharej",
        help="Kharej server configuration",
        formatter_class=CustomFormatter,
        epilog="""Example:
  ./confgen.py waterwall reverse-reality kharej -n rev-kharej -ii 95.38.130.213 -ki 89.36.162.43 -p 443 -d shariati.tums.ac.ir -fp 0
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
    w_rr_k.add_argument("-d", "--domain", default="shariati.tums.ac.ir", help="Reality SNI domain (default: shariati.tums.ac.ir)")
    w_rr_k.add_argument("-fp", "--final-port", type=int, default=0, help="Local service target port on Kharej (default: 0 = preserve port)")
    w_rr_k.add_argument("--pass", "--password", dest="password", default="arch1234net", help="Reality password")
    w_rr_k.add_argument("--min-held", type=int, default=8, help="Minimum held connections")
    w_rr_k.add_argument("--float", nargs="*", default=[], help="Kharej floating IPs")
    w_rr_k.add_argument("--halfduplex", action="store_true", help="Enable HalfDuplex server")
    w_rr_k.add_argument("--fisher", action="store_true", help="Enable ConnectionFisher client")
    w_rr_k.add_argument("--no-core", action="store_true", help="Do not automatically add to core.json")

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
    w_tls_i.add_argument("--no-core", action="store_true", help="Do not automatically add to core.json")

    w_tls_k = ww_tls_sub.add_parser("kharej", help="Kharej server configuration", formatter_class=CustomFormatter)
    w_tls_k.add_argument("-n", "--name", required=True, help="Configuration name")
    w_tls_k.add_argument("-ii", "--iran-ip", required=True, help="Iran Server IP")
    w_tls_k.add_argument("-p", "--port", type=int, default=8443, help="Tunnel port")
    w_tls_k.add_argument("-d", "--sni", required=True, help="SNI domain")
    w_tls_k.add_argument("-fp", "--final-port", type=int, required=True, help="Target application port")
    w_tls_k.add_argument("--final-ip", default="127.0.0.1", help="Target application IP")
    w_tls_k.add_argument("--no-core", action="store_true", help="Do not automatically add to core.json")

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
    w_udp_i.add_argument("--no-core", action="store_true", help="Do not automatically add to core.json")

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
    w_udp_k.add_argument("--no-core", action="store_true", help="Do not automatically add to core.json")

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
    w_bit_i.add_argument("--pattern", default="psh/rst", help="BitSwap TCP flag pattern (default: psh/rst)")
    w_bit_i.add_argument("--no-core", action="store_true", help="Do not automatically add to core.json")

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
    w_bit_k.add_argument("--pattern", default="psh/rst", help="BitSwap TCP flag pattern (default: psh/rst)")
    w_bit_k.add_argument("--no-core", action="store_true", help="Do not automatically add to core.json")

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
    w_proto_i.add_argument("--no-core", action="store_true", help="Do not automatically add to core.json")

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
    w_proto_k.add_argument("--no-core", action="store_true", help="Do not automatically add to core.json")

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
    ww_s.add_argument("--no-core", action="store_true", help="Do not automatically add to core.json")

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

    # 2.9 waterwall v3
    ww_v3 = ww_sub.add_parser(
        "v3",
        help="WaterWall V3 Protoswap tunnel configuration (bash-compatible syntax)",
        formatter_class=CustomFormatter,
    )
    _add_v3_subparser(ww_v3)

    # 2.10 waterwall finder
    ww_finder = ww_sub.add_parser(
        "finder",
        help="Automated best tunnel finder and protocol optimizer",
        formatter_class=CustomFormatter,
    )
    _add_finder_subparser(ww_finder)

    return parser


def main(argv: Optional[List[str]] = None) -> int:
    parser = create_parser()
    args = parser.parse_args(argv)

    if not args.command:
        if (argv is None and sys.stdin.isatty()) or getattr(args, "command", None) == "menu":
            from confgen.core.menu import run_interactive_menu
            return run_interactive_menu()
        parser.print_help()
        return 1

    try:
        # Route Menu & Update & Optimize & Link
        if args.command == "menu":
            from confgen.core.menu import run_interactive_menu
            return run_interactive_menu()

        elif args.command == "update":
            from confgen.core.menu import update_app
            return update_app()

        elif args.command == "optimize":
            from confgen.core.menu import optimize_server
            optimize_server()
            return 0

        elif args.command in ("test", "speedtest"):
            from confgen.core.speedtest import run_speedtest_server, run_speedtest_client, run_mux_scaling_benchmark
            if getattr(args, "test_cmd", None) == "server":
                return run_speedtest_server(port=args.port, bind=args.bind)
            elif getattr(args, "test_cmd", None) == "client":
                if getattr(args, "matrix", False):
                    run_mux_scaling_benchmark(host=args.host, port=args.port, duration=args.duration)
                else:
                    run_speedtest_client(host=args.host, port=args.port, duration=args.duration, parallel=args.parallel, use_udp=bool(getattr(args, "udp", False)))
                return 0
            parser.print_help()
            return 1

        elif args.command == "link":
            if getattr(args, "link_cmd", None) == "apply":
                from confgen.core.link import apply_setup_link
                return apply_setup_link(
                    link_str=args.link,
                    kharej_ip=args.kharej_ip,
                    final_ip=args.final_ip,
                    output_dir=args.output_dir,
                    auto_restart=not args.no_restart,
                )
            parser.print_help()
            return 1

        # Route V3 top-level alias
        elif args.command == "v3":
            return _handle_v3(args)

        # Route Finder top-level alias
        elif args.command == "finder":
            return _handle_finder(args)

        # Route Xray
        elif args.command == "xray":
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
            if args.subcommand == "v3":
                return _handle_v3(args)

            elif args.subcommand == "finder":
                return _handle_finder(args)

            elif args.subcommand == "reverse-reality":
                if args.side == "udp":
                    name = args.name or "champion-udp"
                    iran_ip = args.iran_ip
                    kharej_ip = args.kharej_ip
                    port = args.port or 27012
                    final_port = args.final_port or 10006
                    domain = args.domain or "shariati.tums.ac.ir"
                    from confgen.core.finder import resolve_sni_ip
                    white_ip = args.white_ip or resolve_sni_ip(domain)
                    password = args.password
                    use_hd = bool(args.halfduplex)
                    use_cf = bool(args.fisher)

                    from confgen.generators.waterwall.reverse_reality import (
                        generate_reverse_reality_udp_iran,
                        generate_reverse_reality_udp_kharej,
                    )

                    if args.mode == "iran":
                        cfg = generate_reverse_reality_udp_iran(
                            config_name=name,
                            iran_ip=iran_ip,
                            kharej_ip=kharej_ip,
                            port=port,
                            domain=domain,
                            white_ip=white_ip,
                            password=password,
                            float_ips=args.float,
                            use_halfduplex=use_hd,
                            use_fisher=use_cf,
                        )
                        save_waterwall_config(cfg, name=name, auto_core=not args.no_core)
                        from confgen.core.link import encode_setup_link, print_setup_box
                        payload = {
                            "type": "reverse_reality_udp",
                            "name": name,
                            "iran_ip": iran_ip,
                            "kharej_ip": kharej_ip,
                            "tcp_ports": [port],
                            "tcp_tunnel_port": port,
                            "final_port": final_port,
                            "domain": domain,
                            "password": password,
                            "use_halfduplex": use_hd,
                            "use_fisher": use_cf,
                            "float_ips": args.float,
                        }
                        link = encode_setup_link(payload)
                        print_setup_box(link, name, f"Reverse Reality UDP ({domain})")
                        return 0
                    elif args.mode == "kharej":
                        cfg = generate_reverse_reality_udp_kharej(
                            config_name=name,
                            iran_ip=iran_ip,
                            kharej_ip=kharej_ip,
                            port=port,
                            domain=domain,
                            final_port=final_port,
                            password=password,
                            float_ips=args.float,
                            use_halfduplex=use_hd,
                            use_fisher=use_cf,
                        )
                        save_waterwall_config(cfg, name=name, auto_core=not args.no_core)
                        return 0

                elif args.side == "dual":
                    name = args.name or "champion"
                    iran_ip = args.iran_ip
                    kharej_ip = args.kharej_ip
                    tcp_ports = args.tcp_ports
                    tcp_fwd = args.tcp_forward
                    udp_port = args.udp_port
                    udp_fwd = args.udp_forward
                    carrier_p = args.carrier_port
                    carrier_udp_p = args.carrier_udp_port
                    domain = args.domain or "shariati.tums.ac.ir"
                    from confgen.core.finder import resolve_sni_ip
                    white_ip = args.white_ip or resolve_sni_ip(domain)
                    password = args.password
                    use_hd = not bool(args.no_halfduplex)
                    use_cf = not bool(args.no_fisher)

                    from confgen.generators.waterwall.reverse_reality import (
                        generate_reverse_reality_dual_iran,
                        generate_reverse_reality_dual_kharej,
                    )

                    if args.mode == "iran":
                        cfg = generate_reverse_reality_dual_iran(
                            config_name=name,
                            iran_ip=iran_ip,
                            kharej_ip=kharej_ip,
                            tcp_ports=tcp_ports,
                            tcp_forward_port=tcp_fwd,
                            udp_port=udp_port,
                            udp_forward_port=udp_fwd,
                            carrier_port=carrier_p,
                            carrier_udp_port=carrier_udp_p,
                            domain=domain,
                            white_ip=white_ip,
                            password=password,
                            float_ips=args.float,
                            use_halfduplex=use_hd,
                            use_fisher=use_cf,
                        )
                        save_waterwall_config(cfg, name=name, auto_core=not args.no_core)
                        from confgen.core.link import encode_setup_link, print_setup_box
                        payload = {
                            "type": "reverse_reality_dual",
                            "name": name,
                            "iran_ip": iran_ip,
                            "kharej_ip": kharej_ip,
                            "tcp_ports": tcp_ports,
                            "tcp_forward_port": tcp_fwd,
                            "udp_port": udp_port,
                            "udp_forward_port": udp_fwd,
                            "carrier_port": carrier_p,
                            "carrier_udp_port": carrier_udp_p,
                            "domain": domain,
                            "password": password,
                            "use_halfduplex": use_hd,
                            "use_fisher": use_cf,
                            "float_ips": args.float,
                        }
                        link = encode_setup_link(payload)
                        print_setup_box(link, name, f"Reverse Reality Dual TCP+UDP ({domain})")
                        return 0
                    elif args.mode == "kharej":
                        cfg = generate_reverse_reality_dual_kharej(
                            config_name=name,
                            iran_ip=iran_ip,
                            kharej_ip=kharej_ip,
                            tcp_forward_port=tcp_fwd,
                            udp_forward_port=udp_fwd,
                            carrier_port=carrier_p,
                            carrier_udp_port=carrier_udp_p,
                            domain=domain,
                            password=password,
                            float_ips=args.float,
                            use_halfduplex=use_hd,
                            use_fisher=use_cf,
                        )
                        save_waterwall_config(cfg, name=name, auto_core=not args.no_core)
                        return 0

                elif args.side == "iran":
                    name = args.name or args.pos_name
                    iran_ip = args.iran_ip or args.pos_iran_ip
                    kharej_ip = args.kharej_ip or args.pos_kharej_ip
                    ports = args.port if isinstance(args.port, list) else [args.port or 443]
                    domain = args.domain or args.pos_domain or "shariati.tums.ac.ir"
                    from confgen.core.finder import resolve_sni_ip
                    white_ip = args.white_ip or args.pos_white_ip or resolve_sni_ip(domain)

                    if not (name and iran_ip and kharej_ip):
                        print_error("Missing required parameters for Iran Reverse Reality (-n, -ii, -ki)")
                        return 1

                    cfg = generate_reverse_reality_tcp_iran(
                        config_name=name,
                        iran_ip=iran_ip,
                        kharej_ip=kharej_ip,
                        port=ports,
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
                    save_waterwall_config(cfg, name=name, auto_core=not args.no_core)
                    from confgen.core.link import encode_setup_link, print_setup_box
                    payload = {
                        "type": "reverse_reality",
                        "name": name,
                        "iran_ip": iran_ip,
                        "kharej_ip": kharej_ip,
                        "tcp_ports": ports,
                        "tcp_tunnel_port": ports[0],
                        "domain": domain,
                        "password": args.password,
                        "float_ips": args.float,
                        "use_halfduplex": args.halfduplex,
                        "use_fisher": args.fisher,
                    }
                    link = encode_setup_link(payload)
                    print_setup_box(link, name, f"Reverse Reality ({domain})")
                    return 0

                elif args.side == "kharej":
                    name = args.name or args.pos_name
                    iran_ip = args.iran_ip or args.pos_iran_ip
                    kharej_ip = args.kharej_ip or args.pos_kharej_ip
                    port = args.port[0] if isinstance(args.port, list) else (args.port or 443)
                    domain = args.domain or args.pos_domain or "shariati.tums.ac.ir"
                    final_port = args.final_port if args.final_port is not None else (args.pos_final_port if args.pos_final_port is not None else 0)

                    if not (name and iran_ip and kharej_ip):
                        print_error("Missing required parameters for Kharej Reverse Reality (-n, -ii, -ki)")
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
                    save_waterwall_config(cfg, name=name, auto_core=not args.no_core)
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
                    save_waterwall_config(cfg, name=args.name, auto_core=not args.no_core)
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
                    save_waterwall_config(cfg, name=args.name, auto_core=not args.no_core)
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
                    save_waterwall_config(cfg, name=args.name, auto_core=not args.no_core)
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
                    save_waterwall_config(cfg, name=args.name, auto_core=not args.no_core)
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

                    pattern = getattr(args, "pattern", "psh/rst") or "psh/rst"
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
                        bitswap_pattern=pattern,
                    )
                    save_waterwall_config(cfg, name=name, auto_core=not args.no_core)
                    from confgen.core.link import encode_setup_link, print_setup_box
                    payload = {
                        "type": "bitswap",
                        "name": name,
                        "iran_ip": iran_ip,
                        "kharej_ip": kharej_ip,
                        "tcp_ports": tcp_ports,
                        "udp_ports": udp_ports,
                        "float_ips": float_ips,
                        "tcp_tunnel_port": tcp_tunnel_port,
                        "udp_tunnel_port": args.udp_tunnel_port,
                        "xor_key": args.xor_key,
                        "private_ip": args.private_ip,
                        "private_ip_2": args.private_ip_2,
                        "pattern": pattern,
                    }
                    link = encode_setup_link(payload)
                    print_setup_box(link, name, "BitSwap")
                    return 0

                elif args.side == "kharej":
                    if not tcp_ports and args.final_port:
                        tcp_ports = [args.final_port]
                    tcp_tunnel_port = args.listen_port or args.tcp_tunnel_port

                    pattern = getattr(args, "pattern", "psh/rst") or "psh/rst"
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
                        bitswap_pattern=pattern,
                    )
                    save_waterwall_config(cfg, name=name, auto_core=not args.no_core)
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
                    save_waterwall_config(cfg, name=name, auto_core=not args.no_core)
                    from confgen.core.link import encode_setup_link, print_setup_box
                    payload = {
                        "type": "protoswap",
                        "name": name,
                        "iran_ip": iran_ip,
                        "kharej_ip": kharej_ip,
                        "tcp_ports": tcp_ports,
                        "udp_ports": udp_ports,
                        "float_ips": float_ips,
                        "protoswap_tcp": args.protoswap_tcp,
                        "protoswap_udp": args.protoswap_udp,
                        "tcp_tunnel_port": tcp_tunnel_port,
                        "udp_tunnel_port": args.udp_tunnel_port,
                        "xor_key": args.xor_key,
                        "private_ip": args.private_ip,
                        "private_ip_2": args.private_ip_2,
                        "bitswap": args.bitswap,
                    }
                    link = encode_setup_link(payload)
                    print_setup_box(link, name, f"ProtoSwap ({args.protoswap_tcp}/{args.protoswap_udp})")
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
                    save_waterwall_config(cfg, name=name, auto_core=not args.no_core)
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
                save_waterwall_config(cfg, name=args.name, auto_core=not args.no_core)
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
