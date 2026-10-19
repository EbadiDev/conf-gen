"""Interactive Backpack-Style CLI Wizard for ConfGen.

Provides an intuitive terminal UI matching BackPack:
- 0) Benchmark & Protocol Finder (WaterWall Multi-Method Sweeper)
- 1) Setup Iran (Prints one-line Kharej setup command)
- 2) Setup Kharej (Interactive or via Setup Link)
- 3) Apply Setup Link (confgen://...)
- 4) Manage Tunnels (Status, Restart, Test)
- 5) Server Optimize (BBR, rp_filter, sysctl, limits)
- 6) Update ConfGen (Latest GitHub release)
- 0) Exit
"""

import os
import shutil
import subprocess
import sys
from typing import Optional

from confgen import __version__
from confgen.core.link import (
    apply_setup_link,
    decode_setup_link,
    encode_setup_link,
    print_setup_box,
)
from confgen.core.utils import (
    get_public_ip,
    print_error,
    print_info,
    print_success,
    print_warning,
    save_waterwall_config,
)
from confgen.core.validator import validate_ip, validate_port
from confgen.generators.waterwall.bitswap import generate_bitswap_iran, generate_bitswap_kharej
from confgen.generators.waterwall.protoswap import generate_protoswap_iran, generate_protoswap_kharej
from confgen.generators.waterwall.reverse_reality import (
    generate_reverse_reality_tcp_iran,
    generate_reverse_reality_tcp_kharej,
)
from confgen.generators.waterwall.tls_reverse import (
    generate_waterwall_tls_reverse_iran,
    generate_waterwall_tls_reverse_kharej,
)

INSTALL_BIN_PATH = "/usr/local/bin/confgen"
GITHUB_ZIP_URL = "https://raw.githubusercontent.com/EbadiDev/conf-gen/feat/confgen-python-protoswap-benchmark/confgen.zip"


def print_banner() -> None:
    """Print BackPack-style colorful banner."""
    ip = get_public_ip() or "Unknown"
    print("\033[1;36m" + "=" * 70)
    print("  ██████╗ ██████╗ ███╗   ██╗███████╗ ██████╗ ███████╗███╗   ██╗")
    print(" ██╔════╝██╔═══██╗████╗  ██║██╔════╝██╔════╝ ██╔════╝████╗  ██║")
    print(" ██║     ██║   ██║██╔██╗ ██║█████╗  ██║  ███╗█████╗  ██╔██╗ ██║")
    print(" ██║     ██║   ██║██║╚██╗██║██╔══╝  ██║   ██║██╔══╝  ██║╚██╗██║")
    print(" ╚██████╗╚██████╔╝██║ ╚████║██║     ╚██████╔╝███████╗██║ ╚████║")
    print("  ╚═════╝ ╚═════╝ ╚═╝  ╚═══╝╚═╝      ╚═════╝ ╚══════╝╚═╝  ╚═══╝")
    print(f"       Unified Tunnel Engine & Optimizer  —  v{__version__}")
    print(f"       Server Public IP: {ip}")
    print("=" * 70 + "\033[0m")


def prompt_string(prompt: str, default: Optional[str] = None) -> str:
    def_str = f" [{default}]" if default is not None else ""
    while True:
        val = input(f"{prompt}{def_str}: ").strip()
        if not val and default is not None:
            return default
        if val:
            return val
        print_error("Cannot be empty. Please enter a value.")


def prompt_int(prompt: str, default: int, min_val: int = 1, max_val: int = 65535) -> int:
    while True:
        val = input(f"{prompt} [{default}]: ").strip()
        if not val:
            return default
        try:
            num = int(val)
            if min_val <= num <= max_val:
                return num
            print_error(f"Value must be between {min_val} and {max_val}.")
        except ValueError:
            print_error("Please enter a valid integer.")


def prompt_ip(prompt: str, default: Optional[str] = None) -> str:
    def_str = f" [{default}]" if default is not None else ""
    while True:
        val = input(f"{prompt}{def_str}: ").strip()
        if not val and default is not None:
            return default
        try:
            return validate_ip(val)
        except ValueError as e:
            print_error(str(e))


def update_app() -> int:
    """Download the latest standalone ConfGen binary and install it to /usr/local/bin/confgen."""
    print_info("Fetching latest ConfGen standalone bundle from GitHub...")
    import urllib.request
    try:
        req = urllib.request.Request(GITHUB_ZIP_URL, headers={"User-Agent": "ConfGen-Updater"})
        with urllib.request.urlopen(req, timeout=20) as resp:
            data = resp.read()
        
        target = INSTALL_BIN_PATH if os.access("/usr/local/bin", os.W_OK) else os.path.expanduser("~/.local/bin/confgen")
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with open(target, "wb") as f:
            f.write(b"#!/usr/bin/env python3\n" + data)
        os.chmod(target, 0o755)
        print_success(f"ConfGen updated successfully to {target}!")
        return 0
    except Exception as e:
        print_error(f"Failed to update ConfGen: {e}")
        return 1


def optimize_server() -> None:
    """Apply Linux kernel network optimizations (sysctl, BBR, rp_filter, ulimits)."""
    print_info("Applying server network optimizations (sysctl, BBR, rp_filter=0, ulimits)...")
    if os.name == "nt" or (hasattr(os, "geteuid") and os.geteuid() != 0):
        print_warning("Server optimization requires root privileges (sudo).")
        return

    # 1. Disable rp_filter runtime
    for rp in ["/proc/sys/net/ipv4/conf/all/rp_filter", "/proc/sys/net/ipv4/conf/default/rp_filter"]:
        try:
            with open(rp, "w") as f:
                f.write("0\n")
        except Exception:
            pass

    # 2. Sysctl parameters
    sysctl_content = """
# ConfGen / WaterWall Optimizations
fs.file-max = 67108864
net.core.default_qdisc = fq
net.core.somaxconn = 65536
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_rmem = 8192 1048576 33554432
net.ipv4.tcp_wmem = 8192 1048576 33554432
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_forward = 1
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
"""
    try:
        with open("/etc/sysctl.d/99-confgen.conf", "w") as f:
            f.write(sysctl_content.strip() + "\n")
        subprocess.run(["sysctl", "--system"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        print_success("Sysctl optimizations and BBR applied.")
    except Exception as e:
        print_warning(f"Could not write sysctl config: {e}")

    # 3. Ulimits
    limits_content = """
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
"""
    try:
        with open("/etc/security/limits.d/99-confgen.conf", "w") as f:
            f.write(limits_content.strip() + "\n")
        print_success("System file-descriptor limits updated to 1,048,576.")
    except Exception:
        pass


def wizard_setup_iran() -> None:
    """Step-by-step Iran server setup wizard ending in a one-line Kharej setup command."""
    print("\n--- [1] SETUP IRAN SERVER ---")
    detected_ip = get_public_ip() or "1.1.1.1"
    iran_ip = prompt_ip("Iran Server Public IP", default=detected_ip)
    kharej_ip = prompt_ip("Kharej Server Public IP")
    name = prompt_string("Tunnel Configuration Name", default="tunnel-1")

    print("\nChoose WaterWall Tunnel Transport:")
    print("  1) V3 ProtoSwap (L3 IPv4 Protocol Rewrite: 50 ESP, 47 GRE, 253 RFC)")
    print("  2) BitSwap (L4 TCP Flag Swap: PSH <-> RST, PSH <-> CWR)")
    print("  3) Reverse Reality (Chrome TLS Camouflage to Iranian Domain)")
    print("  4) TLS Reverse (Pure TLS Stream)")
    print("  5) UDP Reverse (RawSocket + XOR Obfuscated UDP)")
    m_choice = prompt_string("Transport [1-5]", default="1")

    listen_port = prompt_int("Public Port to Listen on Iran (e.g. for users/xray)", default=443)
    target_port = prompt_int("Target Forward Port on Kharej", default=listen_port)

    payload: dict = {
        "name": name,
        "iran_ip": iran_ip,
        "kharej_ip": kharej_ip,
        "tcp_ports": [listen_port],
        "tcp_tunnel_port": target_port,
    }

    if m_choice == "2":
        # BitSwap
        pattern = prompt_string("BitSwap Flag Pattern (psh/rst or psh/cwr)", default="psh/rst")
        payload["type"] = "bitswap"
        payload["pattern"] = pattern
        cfg = generate_bitswap_iran(
            config_name=name,
            iran_ip=iran_ip,
            kharej_ip=kharej_ip,
            tcp_ports=[listen_port],
            tcp_tunnel_port=target_port,
            bitswap_pattern=pattern,
        )
        method_label = f"BitSwap ({pattern})"
    elif m_choice == "3":
        # Reverse Reality
        domain = prompt_string("Reality SNI Domain", default="telewebion.ir")
        white_ip = prompt_string("IP behind SNI Domain", default="185.165.205.129")
        password = prompt_string("Reality Password", default="arch1234net")
        payload["type"] = "reverse_reality"
        payload["domain"] = domain
        payload["white_ip"] = white_ip
        payload["password"] = password
        cfg = generate_reverse_reality_tcp_iran(
            config_name=name,
            iran_ip=iran_ip,
            kharej_ip=kharej_ip,
            port=listen_port,
            domain=domain,
            white_ip=white_ip,
            password=password,
        )
        method_label = f"Reverse Reality ({domain})"
    elif m_choice == "4":
        # TLS Reverse
        sni = prompt_string("TLS SNI Host", default="telewebion.ir")
        payload["type"] = "tls_reverse"
        payload["sni"] = sni
        cert_path = "/tmp/confgen_tls_cert.pem"
        key_path = "/tmp/confgen_tls_key.pem"
        from confgen.core.finder import _ensure_self_signed_cert
        _ensure_self_signed_cert(cert_path, key_path)
        cfg = generate_waterwall_tls_reverse_iran(
            config_name=name,
            iran_ip=iran_ip,
            port=listen_port,
            cert_path=cert_path,
            key_path=key_path,
            kharej_ips=[kharej_ip],
        )
        method_label = "TLS Reverse"
    elif m_choice == "5":
        # UDP Reverse
        payload["type"] = "udp_reverse"
        payload["xor_key"] = 153
        cfg = generate_udp_reverse_iran(
            config_name=name,
            iran_public_ip=iran_ip,
            kharej_public_ip=kharej_ip,
            listen_port=listen_port,
            tunnel_port=target_port,
            xor_key=153,
        )
        method_label = "UDP Reverse"
    else:
        # Default V3 ProtoSwap
        p_tcp = prompt_int("ProtoSwap TCP Protocol Number (e.g. 50, 47, 253)", default=50, min_val=0, max_val=255)
        p_udp = prompt_int("ProtoSwap UDP Protocol Number (e.g. 51, 136, 252)", default=p_tcp + 1, min_val=0, max_val=255)
        bit_ans = prompt_string("Enable BitSwap Flag Swap on top? (y/N)", default="y").lower()
        enable_bitswap = bit_ans in ("y", "yes")
        pattern = "psh/rst" if enable_bitswap else "psh/cwr"
        payload["type"] = "protoswap"
        payload["protoswap_tcp"] = p_tcp
        payload["protoswap_udp"] = p_udp
        payload["bitswap"] = enable_bitswap
        payload["pattern"] = pattern
        cfg = generate_protoswap_iran(
            config_name=name,
            iran_ip=iran_ip,
            kharej_ip=kharej_ip,
            tcp_ports=[listen_port],
            tcp_tunnel_port=target_port,
            protoswap_tcp=p_tcp,
            protoswap_udp=p_udp,
            enable_bitswap=enable_bitswap,
            bitswap_pattern=pattern,
        )
        method_label = f"V3 ProtoSwap ({p_tcp}/{p_udp})" + (" + BitSwap" if enable_bitswap else "")

    saved_path = save_waterwall_config(cfg, name=name, auto_core=True)
    print_success(f"Iran configuration generated: {saved_path}")

    # Generate setup link and boxed one-liner for Kharej
    link = encode_setup_link(payload)
    print_setup_box(link, name, method_label)


def wizard_apply_link() -> None:
    """Prompt user for a setup link and apply it."""
    print("\n--- [3] APPLY SETUP LINK ---")
    link = prompt_string("Paste Setup Link (confgen://... or full command line)")
    if "link apply" in link:
        # Extract link token from full curl command
        parts = link.split("link apply", 1)[1].strip().strip("'\"")
        link = parts.split()[0]
    apply_setup_link(link)


def manage_tunnels_menu() -> None:
    """Display active tunnel status and controls."""
    print("\n--- [4] MANAGE TUNNELS ---")
    if os.path.exists("core.json"):
        try:
            with open("core.json") as f:
                cdata = json.load(f)
            configs = cdata.get("configs", [])
            print_info(f"Configured Tunnels in core.json ({len(configs)}):")
            for idx, c in enumerate(configs, 1):
                print(f"  {idx}) {c}")
        except Exception as e:
            print_error(f"Could not read core.json: {e}")
    else:
        print_warning("No core.json found in current directory.")

    if shutil.which("systemctl"):
        res = subprocess.run(["systemctl", "is-active", "waterwall"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        st = res.stdout.strip()
        print_info(f"WaterWall Service Status: {st.upper() if st else 'NOT RUNNING'}")
        action = prompt_string("Restart WaterWall service now? (y/N)", default="n").lower()
        if action in ("y", "yes"):
            subprocess.run(["systemctl", "restart", "waterwall"], check=False)
            print_success("Service restarted.")


def run_interactive_menu() -> int:
    """Main interactive terminal loop matching BackPack."""
    while True:
        print_banner()
        print("Main Menu:")
        print("  0) Benchmark & Protocol Sweeper (Test All Methods)")
        print("  1) Setup Iran (Creates Tunnel & Prints One-Line Kharej Setup Command)")
        print("  2) Setup Kharej (Manual)")
        print("  3) Apply Setup Link (confgen://...)")
        print("  4) Manage Tunnels & Service Status")
        print("  5) Server Network Optimization (BBR, rp_filter, sysctl)")
        print("  6) Native Stream SpeedTest (Zero-Dependency, iperf3-Free)")
        print("  7) Update ConfGen")
        print("  q) Exit")
        print()
        choice = input("Select an option [0-7, q]: ").strip().lower()

        if choice in ("q", "exit", "quit"):
            print("Goodbye!")
            return 0
        elif choice == "0":
            from confgen.core.finder import run_finder_client, run_finder_server
            print("\n--- BENCHMARK & PROTOCOL SWEEPER ---")
            print("Select role:")
            print("  1) Iran (Run benchmark sweep against Kharej)")
            print("  2) Kharej (Start Finder Agent daemon)")
            print("  0) Back")
            role_choice = prompt_string("Choose [0-2]", default="1")
            if role_choice == "2":
                cp = prompt_int("Kharej Agent Control Port", default=8088)
                run_finder_server(port=cp)
            elif role_choice == "1":
                iran_ip = prompt_ip("Iran Public IP", default=get_public_ip())
                kharej_ip = prompt_ip("Kharej Public IP")
                print()
                print_info(f"Make sure Kharej Agent is running on {kharej_ip} (port 8088):")
                print_info(f"  On Kharej, run: confgen finder server --port 8088")
                print_info(f"  Or one-line: bash <(curl -fsSL {GITHUB_ZIP_URL}) finder server --port 8088\n")
                preset = prompt_string("Preset (methods | top | fast | combo | all)", default="methods")
                dur = prompt_int("Duration per test in seconds", default=5, min_val=2, max_val=30)
                apply_win = prompt_string("Auto-apply winning configuration? (y/N)", default="n").lower() in ("y", "yes")
                run_finder_client(
                    iran_ip=iran_ip,
                    kharej_ip=kharej_ip,
                    duration=dur,
                    preset=preset,
                    auto_apply=apply_win,
                )
                input("\nPress Enter to return to menu...")
            else:
                pass
        elif choice == "1":
            wizard_setup_iran()
            input("\nPress Enter to return to menu...")
        elif choice == "2":
            wizard_apply_link()
            input("\nPress Enter to return to menu...")
        elif choice == "3":
            wizard_apply_link()
            input("\nPress Enter to return to menu...")
        elif choice == "4":
            manage_tunnels_menu()
            input("\nPress Enter to return to menu...")
        elif choice == "5":
            optimize_server()
            input("\nPress Enter to return to menu...")
        elif choice == "6":
            from confgen.core.speedtest import run_speedtest_server, run_speedtest_client, run_mux_scaling_benchmark
            print("\n--- NATIVE STREAM SPEEDTEST ---")
            print("Select mode:")
            print("  1) Single Stream Client (1 connection)")
            print("  2) Mux Scaling Benchmark Table (1, 2, 8, 16 child connections)")
            print("  3) Custom Parallel Streams Client (e.g. 2, 8, 16 connections)")
            print("  4) Server (Start receiver daemon on Kharej)")
            print("  0) Back")
            st_choice = prompt_string("Choose [0-4]", default="1")
            if st_choice == "4":
                p = prompt_int("Listen Port", default=9001)
                run_speedtest_server(port=p)
            elif st_choice == "1":
                h = prompt_string("Target Host (IP or 127.0.0.1)", default="127.0.0.1")
                p = prompt_int("Target Port", default=9001)
                d = prompt_int("Duration in seconds", default=5, min_val=2, max_val=30)
                run_speedtest_client(host=h, port=p, duration=d, parallel=1)
                input("\nPress Enter to return to menu...")
            elif st_choice == "2":
                h = prompt_string("Target Host (IP or 127.0.0.1)", default="127.0.0.1")
                p = prompt_int("Target Port", default=9001)
                d = prompt_int("Duration per step in seconds", default=5, min_val=2, max_val=30)
                run_mux_scaling_benchmark(host=h, port=p, duration=d)
                input("\nPress Enter to return to menu...")
            elif st_choice == "3":
                h = prompt_string("Target Host (IP or 127.0.0.1)", default="127.0.0.1")
                p = prompt_int("Target Port", default=9001)
                d = prompt_int("Duration in seconds", default=5, min_val=2, max_val=30)
                par = prompt_int("Parallel Streams Count (e.g. 2, 8, 16)", default=8, min_val=1, max_val=64)
                run_speedtest_client(host=h, port=p, duration=d, parallel=par)
                input("\nPress Enter to return to menu...")
        elif choice == "7":
            update_app()
            input("\nPress Enter to return to menu...")
        else:
            print_error("Invalid option. Please enter 0-7 or q.")
