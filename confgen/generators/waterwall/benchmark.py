"""WaterWall Native Benchmarking Generator (SpeedTestClient and SpeedTestServer).

Generates:
1. SpeedTestServer configurations for Kharej (listening on TCP/UDP targets).
2. SpeedTestClient configurations for Iran (synthetically injecting TCP/UDP traffic into tunnel inbounds).
3. Automated multi-candidate benchmark suites (BitSwap vs ProtoSwap candidates: 253, ESP 50, GRE 47, Combo).
"""

import os
from typing import Any, Dict, List, Optional
from confgen.core.validator import validate_ip, validate_port
from confgen.generators.waterwall.bitswap import (
    generate_bitswap_iran,
    generate_bitswap_kharej,
)
from confgen.generators.waterwall.protoswap import (
    generate_protoswap_iran,
    generate_protoswap_kharej,
)


def generate_speedtest_server_config(
    config_name: str = "speedtest-server",
    tcp_port: Optional[int] = 9000,
    udp_port: Optional[int] = 9001,
    bind_address: str = "127.0.0.1",
    report_interval_ms: int = 1000,
    json_summary: bool = True,
    quiet: bool = False,
) -> Dict[str, Any]:
    """Generate a WaterWall SpeedTestServer configuration."""
    if not tcp_port and not udp_port:
        raise ValueError("At least one TCP or UDP listening port must be specified.")

    clean_bind = validate_ip(bind_address)
    nodes: List[Dict[str, Any]] = []

    if tcp_port:
        clean_tcp = validate_port(tcp_port)
        nodes.append(
            {
                "name": "speedtest-tcp-listener",
                "type": "TcpListener",
                "settings": {
                    "address": clean_bind,
                    "port": clean_tcp,
                    "nodelay": True,
                },
                "next": "speedtest-tcp-server",
            }
        )
        nodes.append(
            {
                "name": "speedtest-tcp-server",
                "type": "SpeedTestServer",
                "settings": {
                    "report-interval-ms": report_interval_ms,
                    "json-summary": json_summary,
                    "quiet": quiet,
                },
            }
        )

    if udp_port:
        clean_udp = validate_port(udp_port)
        nodes.append(
            {
                "name": "speedtest-udp-listener",
                "type": "UdpListener",
                "settings": {
                    "address": clean_bind,
                    "port": clean_udp,
                },
                "next": "speedtest-udp-server",
            }
        )
        nodes.append(
            {
                "name": "speedtest-udp-server",
                "type": "SpeedTestServer",
                "settings": {
                    "report-interval-ms": report_interval_ms,
                    "json-summary": json_summary,
                    "quiet": quiet,
                },
            }
        )

    return {
        "name": config_name,
        "nodes": nodes,
    }


def generate_speedtest_client_config(
    config_name: str = "speedtest-client",
    target_address: str = "127.0.0.1",
    target_port: int = 6443,
    mode: str = "tcp",
    direction: str = "bidirectional",
    duration_ms: int = 10000,
    warmup_ms: int = 1000,
    report_interval_ms: int = 1000,
    connection_count: int = 4,
    payload_size: Optional[int] = None,
    udp_target_bits_per_sec: Optional[int] = None,
    json_summary: bool = True,
    terminate_on_complete: bool = True,
    verify_payload: bool = False,
) -> Dict[str, Any]:
    """Generate a WaterWall SpeedTestClient configuration."""
    clean_target = validate_ip(target_address)
    clean_port = validate_port(target_port)

    mode = mode.lower()
    if mode not in ("tcp", "udp"):
        raise ValueError(f"Mode must be 'tcp' or 'udp', got {mode}")

    direction = direction.lower()
    if direction not in ("upload", "download", "bidirectional", "send", "receive", "both"):
        raise ValueError(f"Invalid direction: {direction}")

    default_payload = 131072 if mode == "tcp" else 3800
    chosen_payload = payload_size if payload_size is not None else default_payload

    settings: Dict[str, Any] = {
        "mode": mode,
        "direction": direction,
        "duration-ms": duration_ms,
        "warmup-ms": warmup_ms,
        "report-interval-ms": report_interval_ms,
        "connection-count": connection_count,
        "payload-size": chosen_payload,
        "verify-payload": verify_payload,
        "json-summary": json_summary,
        "terminate-on-complete": terminate_on_complete,
    }

    if mode == "udp" and udp_target_bits_per_sec is not None:
        settings["udp-target-bits-per-sec"] = udp_target_bits_per_sec

    connector_node = {
        "name": "speedtest-out",
        "type": "TcpConnector" if mode == "tcp" else "UdpConnector",
        "settings": {
            "address": clean_target,
            "port": clean_port,
        },
    }
    if mode == "tcp":
        connector_node["settings"]["nodelay"] = True

    return {
        "name": config_name,
        "nodes": [
            {
                "name": "speedtest-client",
                "type": "SpeedTestClient",
                "settings": settings,
                "next": "speedtest-out",
            },
            connector_node,
        ],
    }


def generate_benchmark_suite(
    iran_ip: str,
    kharej_ip: str,
    output_dir: str,
    tcp_ports: Optional[List[int]] = None,
    udp_ports: Optional[List[int]] = None,
    float_ips: Optional[List[str]] = None,
    speedtest_tcp_port: int = 9000,
    speedtest_udp_port: int = 9001,
    test_duration_ms: int = 10000,
    connection_count: int = 4,
) -> Dict[str, Any]:
    """Generate a complete benchmarking suite directory comparing BitSwap and ProtoSwap variants.

    Returns a dict mapping relative filepaths to configuration objects or script content.
    """
    clean_iran = validate_ip(iran_ip)
    clean_kharej = validate_ip(kharej_ip)
    float_ips = [validate_ip(f) for f in (float_ips or [])]

    tcp_ports = tcp_ports or [6443]
    udp_ports = udp_ports or [27015]

    suite: Dict[str, Any] = {}

    # 1. Kharej Target SpeedTest Server (listens locally on ports 9000 and 9001)
    suite["kharej_speedtest_server.json"] = generate_speedtest_server_config(
        config_name="kharej-speedtest-server",
        tcp_port=speedtest_tcp_port,
        udp_port=speedtest_udp_port,
        bind_address="127.0.0.1",
        report_interval_ms=1000,
        json_summary=True,
    )

    # 2. Iran Benchmark Clients (dials local tunnel entry)
    suite["client_test_tcp.json"] = generate_speedtest_client_config(
        config_name="bench-client-tcp",
        target_address="127.0.0.1",
        target_port=tcp_ports[0],
        mode="tcp",
        direction="bidirectional",
        duration_ms=test_duration_ms,
        connection_count=connection_count,
        json_summary=True,
    )

    suite["client_test_udp.json"] = generate_speedtest_client_config(
        config_name="bench-client-udp",
        target_address="127.0.0.1",
        target_port=udp_ports[0],
        mode="udp",
        direction="upload",
        duration_ms=test_duration_ms,
        connection_count=1,
        udp_target_bits_per_sec=50000000,  # 50 Mbps probe
        json_summary=True,
    )

    # 3. Candidate Matrix Definitions
    candidates = [
        {
            "id": "bitswap",
            "name": "BitSwap (Layer-4 TCP Flag Swap)",
            "type": "bitswap",
        },
        {
            "id": "protoswap_253",
            "name": "ProtoSwap RFC 3692 (TCP: 253, UDP: 252)",
            "type": "protoswap",
            "p_tcp": 253,
            "p_udp": 252,
            "bitswap": False,
        },
        {
            "id": "protoswap_esp",
            "name": "ProtoSwap IPsec ESP (TCP: 50, UDP: 51)",
            "type": "protoswap",
            "p_tcp": 50,
            "p_udp": 51,
            "bitswap": False,
        },
        {
            "id": "protoswap_gre",
            "name": "ProtoSwap GRE/UDPLite (TCP: 47, UDP: 136)",
            "type": "protoswap",
            "p_tcp": 47,
            "p_udp": 136,
            "bitswap": False,
        },
        {
            "id": "protoswap_combo",
            "name": "ProtoSwap 253 + BitSwap Combo (L3+L4)",
            "type": "protoswap",
            "p_tcp": 253,
            "p_udp": 252,
            "bitswap": True,
        },
    ]

    for cand in candidates:
        cid = cand["id"]
        if cand["type"] == "bitswap":
            suite[f"iran_{cid}.json"] = generate_bitswap_iran(
                config_name=f"iran-{cid}",
                iran_ip=clean_iran,
                kharej_ip=clean_kharej,
                tcp_ports=tcp_ports,
                udp_ports=udp_ports,
                float_ips=float_ips,
                tcp_tunnel_port=8445,
                udp_tunnel_port=8446,
            )
            suite[f"kharej_{cid}.json"] = generate_bitswap_kharej(
                config_name=f"kharej-{cid}",
                iran_ip=clean_iran,
                kharej_ip=clean_kharej,
                tcp_ports=[speedtest_tcp_port],
                udp_ports=[speedtest_udp_port],
                float_ips=float_ips,
                tcp_tunnel_port=8445,
                udp_tunnel_port=8446,
            )
        else:
            suite[f"iran_{cid}.json"] = generate_protoswap_iran(
                config_name=f"iran-{cid}",
                iran_ip=clean_iran,
                kharej_ip=clean_kharej,
                tcp_ports=tcp_ports,
                udp_ports=udp_ports,
                float_ips=float_ips,
                protoswap_tcp=cand["p_tcp"],
                protoswap_udp=cand["p_udp"],
                tcp_tunnel_port=8445,
                udp_tunnel_port=8446,
                enable_bitswap=cand["bitswap"],
            )
            suite[f"kharej_{cid}.json"] = generate_protoswap_kharej(
                config_name=f"kharej-{cid}",
                iran_ip=clean_iran,
                kharej_ip=clean_kharej,
                tcp_ports=[speedtest_tcp_port],
                udp_ports=[speedtest_udp_port],
                float_ips=float_ips,
                protoswap_tcp=cand["p_tcp"],
                protoswap_udp=cand["p_udp"],
                tcp_tunnel_port=8445,
                udp_tunnel_port=8446,
                enable_bitswap=cand["bitswap"],
            )

    # 4. Orchestration Runner Script (run_benchmark.py)
    runner_script = """#!/usr/bin/env python3
\"\"\"Automated WaterWall Tunnel Benchmark Orchestrator.\"\"\"

import json
import subprocess
import sys
import time
import os

CANDIDATES = [
    ("bitswap", "BitSwap (Layer-4 TCP Flag)"),
    ("protoswap_253", "ProtoSwap 253/252 (RFC 3692)"),
    ("protoswap_esp", "ProtoSwap 50/51 (IPsec ESP)"),
    ("protoswap_gre", "ProtoSwap 47/136 (GRE / UDPLite)"),
    ("protoswap_combo", "ProtoSwap 253 + BitSwap Combo"),
]

def find_waterwall():
    for bin_name in ["waterwall", "Waterwall", "./waterwall", "./Waterwall"]:
        import shutil
        if os.path.exists(bin_name) or shutil.which(bin_name):
            return bin_name
    return "waterwall"

WW_BIN = find_waterwall()

def run_test_client(config_file):
    cmd = [WW_BIN, f"-c:{config_file}"]
    try:
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=35)
        out = proc.stdout + proc.stderr
        for line in out.splitlines():
            line = line.strip()
            if line.startswith("{") and line.endswith("}"):
                try:
                    data = json.loads(line)
                    if "throughput_mbps" in data or "bytes" in data:
                        return data
                except Exception:
                    pass
        return {"status": "ok" if proc.returncode == 0 else "failed"}
    except subprocess.TimeoutExpired:
        return {"status": "timeout"}
    except Exception as e:
        return {"status": "error", "message": str(e)}

def main():
    print("=" * 70)
    print("⚡ WATERWALL CROSS-BORDER TUNNEL BENCHMARK RUNNER")
    print("=" * 70)
    print("Ensure the corresponding Kharej tunnel and 'kharej_speedtest_server.json'")
    print("are running on the Kharej server before executing tests on Iran side.\\n")

    results = []

    for cid, label in CANDIDATES:
        iran_conf = f"iran_{cid}.json"
        print(f"[*] Testing Candidate: {label} ({iran_conf})...")
        if not os.path.exists(iran_conf):
            print(f"    [SKIP] {iran_conf} not found.")
            continue

        # 1. Start Iran Tunnel
        tun_proc = subprocess.Popen([WW_BIN, f"-c:{iran_conf}"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(2)

        # 2. Test TCP
        print("    -> Running TCP SpeedTest (bidirectional, 10s)...")
        tcp_res = run_test_client("client_test_tcp.json")

        # 3. Test UDP
        print("    -> Running UDP SpeedTest (upload probe, 10s)...")
        udp_res = run_test_client("client_test_udp.json")

        tun_proc.terminate()
        try:
            tun_proc.wait(timeout=3)
        except Exception:
            tun_proc.kill()

        results.append((label, tcp_res, udp_res))
        print("    -> Finished.\\n")
        time.sleep(1)

    print("=" * 70)
    print("📊 BENCHMARK COMPARISON LEADERBOARD")
    print("=" * 70)
    print(f"{'Candidate':<35} | {'TCP Speed':<15} | {'UDP Result':<15}")
    print("-" * 70)
    for label, tcp_res, udp_res in results:
        tcp_str = f"{tcp_res.get('throughput_mbps', 'N/A')} Mbps" if "throughput_mbps" in tcp_res else tcp_res.get("status", "N/A")
        udp_str = f"{udp_res.get('throughput_mbps', 'N/A')} Mbps" if "throughput_mbps" in udp_res else udp_res.get("status", "N/A")
        print(f"{label:<35} | {tcp_str:<15} | {udp_str:<15}")
    print("=" * 70)

if __name__ == "__main__":
    main()
"""
    suite["run_benchmark.py"] = runner_script

    return suite
