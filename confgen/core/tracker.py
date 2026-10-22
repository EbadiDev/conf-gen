"""Bandwidth Degradation Tracker & Periodic Capacity Monitor for ConfGen.

Measures and records real-time throughput over a dedicated probe port (e.g. 59852)
at scheduled intervals (e.g. every 15-30 minutes), tracking if, when, and by how
much line speed degrades over time (e.g. peak-hour DPI throttling).
"""

import json
import os
import time
from datetime import datetime
from typing import Any, Dict, List, Optional

from confgen.core.speedtest import run_speedtest_client
from confgen.core.utils import print_error, print_info, print_success, print_warning

DEFAULT_HISTORY_FILE = os.path.expanduser("~/.confgen/bandwidth_history.json")
DEFAULT_PROBE_FILE = os.path.expanduser("~/.confgen/probe_config.json")


def _ensure_history_dir(filepath: str) -> None:
    os.makedirs(os.path.dirname(os.path.abspath(filepath)), exist_ok=True)


def save_probe_config(port: int, proto: str = "TCP", filepath: Optional[str] = None) -> None:
    """Save the active probe port and protocol for zero-config tracking."""
    path = filepath or DEFAULT_PROBE_FILE
    _ensure_history_dir(path)
    try:
        with open(path, "w", encoding="utf-8") as f:
            json.dump({"port": port, "protocol": proto.upper()}, f, indent=2)
    except Exception:
        pass


def load_probe_config(filepath: Optional[str] = None) -> Dict[str, Any]:
    """Load the active probe port and protocol."""
    path = filepath or DEFAULT_PROBE_FILE
    if not os.path.exists(path):
        return {"port": 59852, "protocol": "TCP"}
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {"port": 59852, "protocol": "TCP"}


def load_history(filepath: Optional[str] = None) -> List[Dict[str, Any]]:
    path = filepath or DEFAULT_HISTORY_FILE
    if not os.path.exists(path):
        return []
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
            return data if isinstance(data, list) else []
    except Exception:
        return []


def record_sample(
    up_mbps: float,
    down_mbps: float,
    rtt_ms: float,
    port: int,
    proto: str = "TCP",
    filepath: Optional[str] = None,
) -> None:
    path = filepath or DEFAULT_HISTORY_FILE
    _ensure_history_dir(path)
    history = load_history(path)

    sample = {
        "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "port": port,
        "protocol": proto,
        "up_mbps": round(up_mbps, 2),
        "down_mbps": round(down_mbps, 2),
        "rtt_ms": round(rtt_ms, 1),
    }
    history.append(sample)

    # Keep last 500 records to prevent file growth
    if len(history) > 500:
        history = history[-500:]

    try:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(history, f, indent=2)
    except Exception as e:
        print_warning(f"Could not save bandwidth sample to {path}: {e}")


def show_bandwidth_history(filepath: Optional[str] = None, limit: int = 25) -> None:
    history = load_history(filepath)
    if not history:
        print_warning("No historical bandwidth samples found yet.")
        print_info("Run 'confgen track run --port <port>' to start tracking bandwidth.")
        return

    items = history[-limit:]
    baseline_down = max(x["down_mbps"] for x in history if x.get("down_mbps", 0) > 0) or 1.0

    print("\n" + "=" * 80)
    print("📊 TUNNEL BANDWIDTH DEGRADATION & SPEED HISTORY")
    print("=" * 80)
    print(f"{'Timestamp':<19} | {'Proto':<5} | {'Upload':<14} | {'Download':<14} | {'RTT':<7} | {'Status'}")
    print("-" * 80)

    for item in items:
        ts = item.get("timestamp", "N/A")
        proto = item.get("protocol", "TCP")
        up = item.get("up_mbps", 0.0)
        down = item.get("down_mbps", 0.0)
        rtt = item.get("rtt_ms", 0.0)

        drop = max(0.0, ((baseline_down - down) / baseline_down) * 100.0)
        if down == 0.0:
            status = "BLOCKED / DOWN ❌"
        elif drop >= 50.0:
            status = f"THROTTLED (-{drop:.0f}%) ⚠️"
        elif drop >= 20.0:
            status = f"DEGRADED (-{drop:.0f}%) ⚠️"
        else:
            status = "OPTIMAL ✅"

        up_str = f"{up:7.2f} Mbps"
        down_str = f"{down:7.2f} Mbps"
        rtt_str = f"{rtt:4.0f}ms"
        print(f"{ts:<19} | {proto:<5} | {up_str:<14} | {down_str:<14} | {rtt_str:<7} | {status}")

    print("=" * 80)
    max_down = max(x["down_mbps"] for x in items)
    min_down = min(x["down_mbps"] for x in items)
    avg_down = sum(x["down_mbps"] for x in items) / len(items)
    print(f"Summary (Last {len(items)} samples): Max: {max_down:.2f} Mbps | Min: {min_down:.2f} Mbps | Avg: {avg_down:.2f} Mbps\n")


def run_bandwidth_tracker(
    host: str = "127.0.0.1",
    port: Optional[int] = None,
    interval_minutes: int = 30,
    duration: int = 2,
    iterations: int = 0,
    use_udp: Optional[bool] = None,
    filepath: Optional[str] = None,
) -> None:
    """Continuously or periodically test probe port and track throughput degradation."""
    saved_cfg = load_probe_config()
    final_port = port if port is not None else saved_cfg.get("port", 59852)
    final_use_udp = use_udp if use_udp is not None else (saved_cfg.get("protocol", "TCP") == "UDP")
    proto = "UDP" if final_use_udp else "TCP"

    print("=" * 76)
    print(f"⚡ CONFGEN BANDWIDTH TRACKER ({proto} PROBE PORT: {final_port})")
    print("=" * 76)
    print(f"Target:       {host}:{final_port} ({proto})")
    print(f"Sample Burst: {duration}s per check")
    print(f"Interval:     Every {interval_minutes} minute(s)")
    print(f"Log File:     {filepath or DEFAULT_HISTORY_FILE}")
    print("Press Ctrl+C to stop tracking.\n")

    count = 0
    try:
        while True:
            count += 1
            now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            print_info(f"[{now_str}] Sampling probe port {final_port} ({duration}s burst)...")

            up, down, rtt = run_speedtest_client(
                host=host,
                port=final_port,
                duration=duration,
                parallel=1,
                quiet=True,
                use_udp=final_use_udp,
            )

            record_sample(
                up_mbps=up,
                down_mbps=down,
                rtt_ms=rtt,
                port=final_port,
                proto=proto,
                filepath=filepath,
            )

            if down > 0 or up > 0:
                print_success(f"    -> Up: {up:7.2f} Mbps | Down: {down:7.2f} Mbps | RTT: {rtt:.0f}ms")
            else:
                print_warning(f"    -> Probe port {final_port} unreachable / 0 Mbps (traffic blocked or daemon not running)")

            if iterations > 0 and count >= iterations:
                break

            time.sleep(interval_minutes * 60)
    except KeyboardInterrupt:
        print_info("\nBandwidth tracking stopped by user.")
