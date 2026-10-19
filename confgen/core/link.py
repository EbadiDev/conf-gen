"""Setup Link Encoder and Applicator (One-Command Kharej Join like BackPack).

Provides:
- Setup link generation (confgen://<compressed_base64>)
- One-line link apply for Kharej server (zero interactive questions)
- Auto-generation of matching Kharej configs for all WaterWall methods
"""

import base64
import json
import os
import shutil
import subprocess
import zlib
from typing import Any, Dict, Optional

from confgen.core.utils import (
    get_public_ip,
    print_error,
    print_info,
    print_success,
    print_warning,
    save_waterwall_config,
)
from confgen.generators.waterwall.bitswap import generate_bitswap_kharej
from confgen.generators.waterwall.protoswap import generate_protoswap_kharej
from confgen.generators.waterwall.reverse_reality import generate_reverse_reality_tcp_kharej
from confgen.generators.waterwall.tls_reverse import generate_waterwall_tls_reverse_kharej
from confgen.generators.waterwall.udp_reverse import generate_udp_reverse_kharej

RUN_SH_URL = "https://raw.githubusercontent.com/EbadiDev/conf-gen/feat/confgen-python-protoswap-benchmark/run.sh"


def encode_setup_link(payload: Dict[str, Any]) -> str:
    """Encode configuration dictionary into a compact confgen:// link."""
    compact_json = json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    compressed = zlib.compress(compact_json, level=9)
    encoded = base64.urlsafe_b64encode(compressed).decode("ascii").rstrip("=")
    return f"confgen://{encoded}"


def decode_setup_link(link_str: str) -> Dict[str, Any]:
    """Decode a confgen:// link back into its configuration dictionary."""
    raw = link_str.strip()
    if raw.startswith("confgen://"):
        raw = raw[len("confgen://"):]
    elif raw.startswith("backpack://"):
        raw = raw[len("backpack://"):]

    # Re-pad base64
    padding = len(raw) % 4
    if padding:
        raw += "=" * (4 - padding)

    try:
        compressed = base64.urlsafe_b64decode(raw.encode("ascii"))
        decompressed = zlib.decompress(compressed)
        return json.loads(decompressed.decode("utf-8"))
    except Exception as e:
        raise ValueError(f"Invalid or corrupted setup link: {e}")


def print_setup_box(link_str: str, tunnel_name: str, method_label: str) -> None:
    """Display a clean, formatted setup box with one-line command for Kharej."""
    print("\n" + "=" * 80)
    print(f"🎉 TUNNEL '{tunnel_name}' ({method_label}) CONFIGURED ON IRAN!")
    print("=" * 80)
    print("Run this ONE COMMAND on your Kharej server to bring up the tunnel:")
    print()
    print(f"  bash <(curl -fsSL {RUN_SH_URL}) link apply '{link_str}'")
    print()
    print("Or if confgen is already installed on Kharej:")
    print(f"  confgen link apply '{link_str}'")
    print("=" * 80 + "\n")


def apply_setup_link(
    link_str: str,
    kharej_ip: Optional[str] = None,
    final_ip: str = "127.0.0.1",
    output_dir: Optional[str] = None,
    auto_restart: bool = True,
) -> int:
    """Apply a setup link on Kharej server to generate matching configuration."""
    try:
        data = decode_setup_link(link_str)
    except ValueError as e:
        print_error(str(e))
        return 1

    method = data.get("type", "protoswap")
    name = data.get("name", "waterwall-tunnel")
    iran_ip = data.get("iran_ip")
    if not iran_ip:
        print_error("Setup link is missing required 'iran_ip'.")
        return 1

    # Detect Kharej public IP if not supplied
    clean_kharej = kharej_ip or data.get("kharej_ip") or get_public_ip()
    if not clean_kharej:
        print_error("Could not automatically detect Kharej public IP. Please specify with --kharej-ip (-ki).")
        return 1

    tcp_ports = data.get("tcp_ports", [443])
    udp_ports = data.get("udp_ports", [])
    tcp_tunnel_port = data.get("tcp_tunnel_port", 443)
    udp_tunnel_port = data.get("udp_tunnel_port", 444)
    private_ip = data.get("private_ip", "10.10.0.1")
    private_ip_2 = data.get("private_ip_2")
    float_ips = data.get("float_ips", [])
    xor_key = int(data.get("xor_key", 90))

    print("=" * 76)
    print("⚡ WATERWALL ONE-LINE KHAREJ SETUP (LINK APPLY)")
    print("=" * 76)
    print(f"Tunnel Name:  {name}")
    print(f"Method:       {method}")
    print(f"Iran IP:      {iran_ip}")
    print(f"Kharej IP:    {clean_kharej}")

    if method == "reverse_reality":
        domain = data.get("domain", "telewebion.ir")
        password = data.get("password", "arch1234net")
        final_port = 0 if len(tcp_ports) > 1 else (tcp_ports[0] if tcp_ports else 443)
        use_hd = bool(data.get("use_halfduplex", False))
        use_cf = bool(data.get("use_fisher", False))
        use_mux = bool(data.get("use_mux", False))
        cfg = generate_reverse_reality_tcp_kharej(
            config_name=name,
            iran_ip=iran_ip,
            kharej_ip=clean_kharej,
            port=tcp_tunnel_port,
            domain=domain,
            final_port=final_port,
            password=password,
            float_ips=float_ips,
            use_halfduplex=use_hd,
            use_fisher=use_cf,
            use_mux=use_mux,
        )
    elif method == "reverse_reality_dual":
        from confgen.generators.waterwall.reverse_reality import generate_reverse_reality_dual_kharej
        domain = data.get("domain", "shariati.tums.ac.ir")
        password = data.get("password", "arch1234net")
        tcp_fwd = int(data.get("tcp_forward_port", 10005))
        udp_fwd = int(data["udp_forward_port"]) if data.get("udp_forward_port") else None
        carrier_p = int(data.get("carrier_port", 58443))
        carrier_udp_p = int(data.get("carrier_udp_port", 58444))
        use_hd = bool(data.get("use_halfduplex", True))
        use_cf = bool(data.get("use_fisher", True))
        cfg = generate_reverse_reality_dual_kharej(
            config_name=name,
            iran_ip=iran_ip,
            kharej_ip=clean_kharej,
            tcp_forward_port=tcp_fwd,
            udp_forward_port=udp_fwd,
            carrier_port=carrier_p,
            carrier_udp_port=carrier_udp_p,
            domain=domain,
            password=password,
            float_ips=float_ips,
            use_halfduplex=use_hd,
            use_fisher=use_cf,
        )
    elif method == "tls_reverse":
        domain = data.get("sni", data.get("domain", "telewebion.ir"))
        final_port = tcp_ports[0] if tcp_ports else 443
        cfg = generate_waterwall_tls_reverse_kharej(
            config_name=name,
            iran_ip=iran_ip,
            port=tcp_tunnel_port,
            sni=domain,
            final_port=final_port,
            final_ip=final_ip,
        )
    elif method == "udp_reverse":
        listen_port = tcp_ports[0] if tcp_ports else 443
        cfg = generate_udp_reverse_kharej(
            config_name=name,
            iran_public_ip=iran_ip,
            kharej_public_ip=clean_kharej,
            target_port=listen_port,
            tunnel_port=tcp_tunnel_port,
            xor_key=xor_key,
        )
    elif method == "bitswap":
        pattern = data.get("pattern", "psh/cwr")
        cfg = generate_bitswap_kharej(
            config_name=name,
            iran_ip=iran_ip,
            kharej_ip=clean_kharej,
            tcp_ports=tcp_ports,
            udp_ports=udp_ports,
            float_ips=float_ips,
            tcp_tunnel_port=tcp_tunnel_port,
            udp_tunnel_port=udp_tunnel_port,
            final_ip=final_ip,
            xor_key=xor_key,
            custom_private_ip=private_ip,
            custom_private_ip_2=private_ip_2,
            bitswap_pattern=pattern,
        )
    else:  # protoswap
        p_tcp = int(data.get("protoswap_tcp", 253))
        p_udp = int(data.get("protoswap_udp", 252))
        enable_bitswap = bool(data.get("bitswap", False))
        pattern = data.get("pattern", "psh/cwr")
        cfg = generate_protoswap_kharej(
            config_name=name,
            iran_ip=iran_ip,
            kharej_ip=clean_kharej,
            tcp_ports=tcp_ports,
            udp_ports=udp_ports,
            float_ips=float_ips,
            protoswap_tcp=p_tcp,
            protoswap_udp=p_udp,
            tcp_tunnel_port=tcp_tunnel_port,
            udp_tunnel_port=udp_tunnel_port,
            final_ip=final_ip,
            xor_key=xor_key,
            custom_private_ip=private_ip,
            custom_private_ip_2=private_ip_2,
            enable_bitswap=enable_bitswap,
            bitswap_pattern=pattern,
            use_mux=data.get("use_mux", True),
        )

    # Save configuration
    target_path = None
    if output_dir:
        target_path = os.path.join(output_dir, f"{name}.json")
    saved_path = save_waterwall_config(cfg, filepath=target_path, name=name, auto_core=True)
    print_success(f"Configuration written: {saved_path}")
    print_success("Added configuration to core.json")

    # Restart WaterWall service if active
    if auto_restart and shutil.which("systemctl"):
        for svc in ["waterwall", "waterwall.service"]:
            try:
                res = subprocess.run(["systemctl", "is-active", svc], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
                if res.stdout.strip() == "active":
                    subprocess.run(["systemctl", "restart", svc], check=False)
                    print_success(f"Restarted {svc} systemd service to activate new tunnel.")
                    break
            except Exception:
                pass

    print("\n" + "=" * 76)
    print(f"🎉 TUNNEL '{name}' ACTIVATED ON KHAREJ!")
    print(f"Target Service: {final_ip}:{tcp_ports[0] if tcp_ports else 'N/A'}")
    print("=" * 76 + "\n")
    return 0
