"""Autonomous Cross-Border Tunnel Protocol Optimizer (Best Tunnel Finder).

Coordinates between Kharej (Agent) and Iran (Orchestrator) to sweep IPv4
protocol replacement numbers for WaterWall ProtoSwap (IpManipulator).
Measures real-world bandwidth, latency, and packet loss, ranks candidates,
and automatically applies the winning configuration to both servers.
"""

import json
import os
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
try:
    from http.server import ThreadingHTTPServer as HttpServerClass
except ImportError:
    from http.server import HTTPServer as HttpServerClass  # type: ignore
from http.server import BaseHTTPRequestHandler
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from urllib.request import Request, urlopen

from confgen.core.utils import (
    print_error,
    print_info,
    print_success,
    print_warning,
    save_waterwall_config,
    write_json,
)
from confgen.core.validator import validate_ip, validate_port
from confgen.generators.waterwall.core import generate_core_config
from confgen.generators.waterwall.protoswap import (
    generate_protoswap_iran,
    generate_protoswap_kharej,
)

# Standard protocol sweep presets for DPI circumvention
CANDIDATES_PRESETS: Dict[str, List[Dict[str, Any]]] = {
    "top": [
        {"id": "esp_50_51", "name": "ESP (IPsec)", "tcp": 50, "udp": 51},
        {"id": "ah_51_52", "name": "AH (IPsec)", "tcp": 51, "udp": 52},
        {"id": "rfc3692_253_252", "name": "RFC 3692 Exp 1", "tcp": 253, "udp": 252},
        {"id": "gre_47_136", "name": "GRE / UDPLite", "tcp": 47, "udp": 136},
        {"id": "ipip_4_41", "name": "IPIP / 6in4", "tcp": 4, "udp": 41},
        {"id": "sctp_132_133", "name": "SCTP", "tcp": 132, "udp": 133},
        {"id": "custom_200_201", "name": "Custom Range 200", "tcp": 200, "udp": 201},
        {"id": "custom_222_223", "name": "Custom Range 222", "tcp": 222, "udp": 223},
    ],
    "fast": [
        {"id": "esp_50_51", "name": "ESP (IPsec)", "tcp": 50, "udp": 51},
        {"id": "ah_51_52", "name": "AH (IPsec)", "tcp": 51, "udp": 52},
        {"id": "rfc3692_253_252", "name": "RFC 3692 Exp 1", "tcp": 253, "udp": 252},
        {"id": "gre_47_136", "name": "GRE / UDPLite", "tcp": 47, "udp": 136},
    ],
    "all": [
        {"id": "esp_50_51", "name": "ESP (IPsec)", "tcp": 50, "udp": 51},
        {"id": "ah_51_52", "name": "AH (IPsec)", "tcp": 51, "udp": 52},
        {"id": "rfc3692_253_252", "name": "RFC 3692 Exp 1", "tcp": 253, "udp": 252},
        {"id": "rfc3692_254_253", "name": "RFC 3692 Exp 2", "tcp": 254, "udp": 253},
        {"id": "gre_47_136", "name": "GRE / UDPLite", "tcp": 47, "udp": 136},
        {"id": "ipip_4_41", "name": "IPIP / 6in4", "tcp": 4, "udp": 41},
        {"id": "ipv6_tun_41_42", "name": "IPv6-in-IPv4", "tcp": 41, "udp": 42},
        {"id": "sctp_132_133", "name": "SCTP", "tcp": 132, "udp": 133},
        {"id": "ipcomp_108_109", "name": "IPComp", "tcp": 108, "udp": 109},
        {"id": "vrrp_112_113", "name": "VRRP", "tcp": 112, "udp": 113},
        {"id": "l2tp_115_116", "name": "L2TP", "tcp": 115, "udp": 116},
        {"id": "ospf_89_90", "name": "OSPF", "tcp": 89, "udp": 90},
        {"id": "custom_200_201", "name": "Custom Range 200", "tcp": 200, "udp": 201},
        {"id": "custom_222_223", "name": "Custom Range 222", "tcp": 222, "udp": 223},
        {"id": "custom_240_241", "name": "Custom Range 240", "tcp": 240, "udp": 241},
    ],
}


def get_waterwall_launch_info() -> Tuple[str, str]:
    """Find the WaterWall executable and its working directory.

    WaterWall requires its 'libs/' directory in its working directory, so cwd
    must point to the directory containing the binary (usually /root/waterwall).
    Returns (executable_path, working_directory).
    """
    search_dirs = [
        "/root/waterwall",
        os.path.expanduser("~/waterwall"),
        os.getcwd(),
        "/usr/local/bin",
        "/usr/bin",
    ]
    binary_names = ["Waterwall", "waterwall"]

    for d in search_dirs:
        if not os.path.isdir(d):
            continue
        for b_name in binary_names:
            full_path = os.path.join(d, b_name)
            if os.path.isfile(full_path) and os.access(full_path, os.X_OK):
                return os.path.abspath(full_path), os.path.abspath(d)

    for b_name in binary_names:
        w = shutil.which(b_name)
        if w:
            abs_w = os.path.abspath(w)
            return abs_w, os.path.dirname(abs_w)

    default_dir = "/root/waterwall" if os.path.isdir("/root/waterwall") else os.getcwd()
    for b_name in binary_names:
        cand = os.path.join(default_dir, b_name)
        if os.path.exists(cand):
            return cand, default_dir

    return os.path.join(default_dir, "Waterwall"), default_dir


def find_waterwall_binary() -> Optional[str]:
    """Locate the WaterWall binary on the host."""
    bin_path, _ = get_waterwall_launch_info()
    if os.path.isfile(bin_path) and os.access(bin_path, os.X_OK):
        return bin_path
    return None


def find_iperf3_binary() -> Optional[str]:
    """Locate the iperf3 binary on the host."""
    return shutil.which("iperf3")


def parse_custom_protocols(proto_str: str) -> List[Dict[str, Any]]:
    """Parse custom protocols string (e.g. '50/51,51/52,47/136')."""
    candidates: List[Dict[str, Any]] = []
    pairs = [p.strip() for p in proto_str.split(",") if p.strip()]
    for idx, pair in enumerate(pairs):
        if "/" in pair:
            t_s, u_s = pair.split("/", 1)
        elif ":" in pair:
            t_s, u_s = pair.split(":", 1)
        else:
            t_s = pair
            u_s = str(int(pair) + 1)
        t_num = int(t_s)
        u_num = int(u_s)
        candidates.append({
            "id": f"custom_{t_num}_{u_num}",
            "name": f"Protocol {t_num}/{u_num}",
            "tcp": t_num,
            "udp": u_num,
        })
    return candidates


# =============================================================================
# TEARDOWN & CLEANUP HELPERS
# =============================================================================

def stop_waterwall_and_test(
    proc: Optional[subprocess.Popen] = None,
    name: Optional[str] = None,
    ww_cwd: Optional[str] = None,
) -> None:
    """Deterministically terminate WaterWall and test processes."""
    # 1. Terminate provided process and its process group
    if proc:
        try:
            pgid = os.getpgid(proc.pid)
            os.killpg(pgid, signal.SIGKILL)
        except Exception:
            pass
        try:
            proc.kill()
            proc.wait(timeout=0.5)
        except Exception:
            pass

    # 2. Case-insensitive kill of all WaterWall instances (including memfd:waterwall) & iperf3
    for pat in ["waterwall", "iperf3"]:
        try:
            subprocess.run(["pkill", "-9", "-i", "-f", pat], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=1.0)
        except Exception:
            pass

    time.sleep(0.5)

    # 3. Clean temporary test config files
    if ww_cwd and name:
        for f in (Path(ww_cwd) / f"_tmp_{name}.json", Path(ww_cwd) / f"_core_{name}.json"):
            if f.exists():
                try:
                    f.unlink()
                except Exception:
                    pass


kill_waterwall_and_clean_tun = stop_waterwall_and_test


# =============================================================================
# KHAREJ AGENT SERVER (HTTP JSON CONTROL DAEMON)
# =============================================================================

class FinderAgentState:
    ww_proc: Optional[subprocess.Popen] = None
    iperf_proc: Optional[subprocess.Popen] = None
    current_name: Optional[str] = None
    auto_timer: Optional[threading.Timer] = None
    lock = threading.Lock()

    @classmethod
    def cancel_timer(cls) -> None:
        with cls.lock:
            if cls.auto_timer:
                try:
                    cls.auto_timer.cancel()
                except Exception:
                    pass
                cls.auto_timer = None

    @classmethod
    def kill_active_processes(cls) -> None:
        with cls.lock:
            cls.cancel_timer()
            if cls.iperf_proc:
                try:
                    pgid = os.getpgid(cls.iperf_proc.pid)
                    os.killpg(pgid, signal.SIGKILL)
                except Exception:
                    pass
                try:
                    cls.iperf_proc.kill()
                    cls.iperf_proc.wait(timeout=1.0)
                except Exception:
                    pass
                cls.iperf_proc = None

            if cls.ww_proc:
                try:
                    pgid = os.getpgid(cls.ww_proc.pid)
                    os.killpg(pgid, signal.SIGKILL)
                except Exception:
                    pass
                try:
                    cls.ww_proc.kill()
                    cls.ww_proc.wait(timeout=1.0)
                except Exception:
                    pass
                cls.ww_proc = None

            for pat in ["iperf3", "Waterwall", "waterwall", "_core_"]:
                try:
                    subprocess.run(["pkill", "-9", "-f", pat], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=2.0)
                except Exception:
                    pass

    @classmethod
    def auto_teardown(cls, name: str, ww_cwd: str) -> None:
        print_info(f"[{time.strftime('%X')}] [Kharej Agent] Auto-teardown triggered for '{name}' after test window.")
        cls.kill_active_processes()
        stop_waterwall_and_test(None, name, ww_cwd)
        print_success(f"[{time.strftime('%X')}] [Kharej Agent] Auto-teardown complete for '{name}'. WaterWall stopped, control channel restored.")


class FinderHTTPHandler(BaseHTTPRequestHandler):
    def log_message(self, format: str, *args: Any) -> None:
        sys.stderr.write(f"[{time.strftime('%X')}] [Kharej Agent] " + (format % args) + "\n")
        sys.stderr.flush()

    def _send_json(self, status_code: int, data: Dict[str, Any]) -> None:
        payload = json.dumps(data).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(payload)
        self.wfile.flush()
        self.close_connection = True

    def do_GET(self) -> None:
        if self.path in ("/health", "/status", "/"):
            self._send_json(200, {
                "status": "ready",
                "waterwall": bool(find_waterwall_binary()),
                "iperf3": bool(find_iperf3_binary()),
            })
        else:
            self._send_json(404, {"error": "Not found"})

    def do_POST(self) -> None:
        content_len = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_len).decode("utf-8") if content_len > 0 else "{}"
        try:
            req = json.loads(body)
        except Exception:
            self._send_json(400, {"error": "Invalid JSON"})
            return

        try:
            if self.path == "/prepare":
                self._handle_prepare(req)
            elif self.path == "/teardown":
                self._handle_teardown(req)
            elif self.path == "/apply_winner":
                self._handle_apply_winner(req)
            else:
                self._send_json(404, {"error": "Not found"})
        except Exception as e:
            import traceback
            traceback.print_exc()
            self._send_json(500, {"error": f"Internal agent error: {e}"})

    def _handle_prepare(self, req: Dict[str, Any]) -> None:
        name = req.get("name", "finder-kharej")
        FinderAgentState.current_name = name
        iran_ip = req["iran_ip"]
        kharej_ip = req["kharej_ip"]
        tcp_port = int(req.get("tcp_port", 9000))
        p_tcp = int(req["protoswap_tcp"])
        p_udp = int(req["protoswap_udp"])
        duration = int(req.get("duration", 5))

        ww_bin, ww_cwd = get_waterwall_launch_info()
        print_info(f"[{time.strftime('%X')}] [Kharej Agent] Preparing candidate: {name} (TCP: {p_tcp}, UDP: {p_udp}, duration: {duration}s)...")

        # 1. Reset any active WaterWall & iperf processes
        FinderAgentState.kill_active_processes()
        stop_waterwall_and_test(None, name, ww_cwd)

        # 2. Generate Kharej configuration inside WaterWall directory
        Path(ww_cwd, "log").mkdir(parents=True, exist_ok=True)
        cfg = generate_protoswap_kharej(
            config_name=name,
            iran_ip=iran_ip,
            kharej_ip=kharej_ip,
            tcp_ports=[tcp_port],
            protoswap_tcp=p_tcp,
            protoswap_udp=p_udp,
            final_ip="127.0.0.1",
        )
        conf_file = Path(ww_cwd) / f"{name}.json"
        core_file = Path(ww_cwd) / "core.json"
        write_json(cfg, conf_file)
        core_cfg = generate_core_config(
            config_paths=[f"{name}.json"],
            loglevel="DEBUG",
            console=True,
            log_path=str(Path(ww_cwd) / "log/"),
        )
        write_json(core_cfg, core_file)

        # 3. Launch WaterWall directly (binary automatically loads core.json from working dir)
        cmd_ww = [ww_bin]
        print_info(f"[{time.strftime('%X')}] [Kharej Agent] Starting WaterWall directly:")
        try:
            FinderAgentState.ww_proc = subprocess.Popen(
                cmd_ww,
                cwd=ww_cwd,
                start_new_session=True,
                stdout=None,
                stderr=None,
            )
        except Exception as e:
            self._send_json(500, {"error": f"Failed to start WaterWall ({ww_bin}): {e}"})
            return

        time.sleep(0.5)
        if FinderAgentState.ww_proc.poll() is not None:
            self._send_json(500, {"error": f"WaterWall exited immediately with code {FinderAgentState.ww_proc.returncode}"})
            return

        # 4. Launch iperf3 server on tcp_port
        iperf_bin = find_iperf3_binary()
        if iperf_bin:
            try:
                FinderAgentState.iperf_proc = subprocess.Popen(
                    [iperf_bin, "-s", "-p", str(tcp_port)],
                    start_new_session=True,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
            except Exception as e:
                print_warning(f"Failed to start iperf3: {e}")

        # 5. Arm auto-teardown timer
        test_window = (duration * 2) + 3.5
        with FinderAgentState.lock:
            FinderAgentState.auto_timer = threading.Timer(
                test_window,
                FinderAgentState.auto_teardown,
                args=[name, ww_cwd],
            )
            FinderAgentState.auto_timer.daemon = True
            FinderAgentState.auto_timer.start()

        time.sleep(1.0)  # Allow WaterWall and iperf3 to bind
        print_success(f"[{time.strftime('%X')}] [Kharej Agent] WaterWall (PID {FinderAgentState.ww_proc.pid}) & iperf3 ready on port {tcp_port}. Auto-teardown armed in {test_window:.1f}s.")
        self._send_json(200, {"status": "ready", "tcp_port": tcp_port})

    def _handle_teardown(self, req: Dict[str, Any]) -> None:
        name = req.get("name", "finder-kharej")
        ww_bin, ww_cwd = get_waterwall_launch_info()
        print_info(f"[{time.strftime('%X')}] [Kharej Agent] Teardown requested for '{name}'...")
        FinderAgentState.kill_active_processes()
        stop_waterwall_and_test(None, name, ww_cwd)
        print_success(f"[{time.strftime('%X')}] [Kharej Agent] Teardown complete for '{name}'.")
        self._send_json(200, {"status": "stopped"})

    def _handle_apply_winner(self, req: Dict[str, Any]) -> None:
        name = req.get("name", "parspack-nl")
        ww_bin, ww_cwd = get_waterwall_launch_info()
        print_info(f"[{time.strftime('%X')}] [Kharej Agent] Applying winning config '{name}'...")
        FinderAgentState.kill_active_processes()
        stop_waterwall_and_test(None, name, ww_cwd)

        iran_ip = req["iran_ip"]
        kharej_ip = req["kharej_ip"]
        tcp_port = int(req.get("tcp_port", 9000))
        p_tcp = int(req["protoswap_tcp"])
        p_udp = int(req["protoswap_udp"])

        cfg = generate_protoswap_kharej(
            config_name=name,
            iran_ip=iran_ip,
            kharej_ip=kharej_ip,
            tcp_ports=[tcp_port],
            protoswap_tcp=p_tcp,
            protoswap_udp=p_udp,
            final_ip="127.0.0.1",
        )
        filepath = Path(ww_cwd) / f"{name}.json"
        core_path = Path(ww_cwd) / "core.json"
        saved = save_waterwall_config(cfg, filepath=filepath, name=name, auto_core=True, core_path=core_path)
        print_success(f"[{time.strftime('%X')}] [Kharej Agent] Saved {saved} and synced to core.json.")
        self._send_json(200, {"status": "applied", "file": str(saved)})


def run_finder_server(port: int = 8088, host: str = "0.0.0.0") -> int:
    """Start the Kharej control agent daemon."""
    server_address = (host, port)
    HttpServerClass.allow_reuse_address = True
    httpd = HttpServerClass(server_address, FinderHTTPHandler)
    httpd.daemon_threads = True
    print_info(f"⚡ WaterWall Finder Agent active on http://{host}:{port}")
    print_info("Awaiting automated benchmark commands from Iran orchestrator... (Press Ctrl+C to stop)")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print_info("\nStopping Finder Agent...")
        ww_bin, ww_cwd = get_waterwall_launch_info()
        FinderAgentState.kill_active_processes()
        stop_waterwall_and_test(None, FinderAgentState.current_name, ww_cwd)
        httpd.server_close()
    return 0


# =============================================================================
# IRAN ORCHESTRATOR CLIENT
# =============================================================================

def _post_json(url: str, data: Dict[str, Any], timeout: float = 25.0, retries: int = 1) -> Dict[str, Any]:
    last_err: Optional[Exception] = None
    for attempt in range(retries + 1):
        try:
            req = Request(
                url,
                data=json.dumps(data).encode("utf-8"),
                headers={
                    "Content-Type": "application/json",
                    "Connection": "close",
                },
            )
            with urlopen(req, timeout=timeout) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except Exception as e:
            last_err = e
            if attempt < retries:
                time.sleep(1.0)
    raise last_err or Exception(f"Failed to post to {url}")


def _get_json(url: str, timeout: float = 12.0) -> Dict[str, Any]:
    req = Request(url, headers={"Connection": "close"})
    with urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def _run_iperf_test(
    port: int,
    duration: int,
    reverse: bool = False,
) -> Tuple[float, int]:
    """Run iperf3 client probe against local WaterWall listener (127.0.0.1:port).
    
    Returns (throughput_mbps, retransmissions).
    """
    iperf_bin = find_iperf3_binary()
    if not iperf_bin:
        return 0.0, 0

    cmd = [iperf_bin, "-c", "127.0.0.1", "-p", str(port), "-t", str(duration), "-J"]
    if reverse:
        cmd.append("-R")

    try:
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=duration + 8)
        if proc.returncode != 0:
            return 0.0, 0
        data = json.loads(proc.stdout)
        end = data.get("end", {})
        
        # Calculate Mbps
        if reverse:
            # Remote is sending, we receive
            rx = end.get("sum_received", {})
            bps = rx.get("bits_per_second", 0.0)
            if not bps:
                bps = end.get("sum_sent", {}).get("bits_per_second", 0.0)
            retr = 0
        else:
            tx = end.get("sum_sent", {})
            bps = tx.get("bits_per_second", 0.0)
            if not bps:
                bps = end.get("sum_received", {}).get("bits_per_second", 0.0)
            retr = tx.get("retransmits", 0)

        mbps = round(bps / 1_000_000.0, 2)
        return mbps, retr
    except Exception:
        return 0.0, 0


def run_finder_client(
    iran_ip: str,
    kharej_ip: str,
    control_port: int = 8088,
    tcp_port: int = 9001,
    name: str = "parspack-nl",
    duration: int = 5,
    preset: str = "top",
    custom_protocols: Optional[str] = None,
    auto_apply: bool = True,
) -> int:
    """Orchestrate protocol sweep against Kharej agent."""
    clean_iran = validate_ip(iran_ip)
    clean_kharej = validate_ip(kharej_ip)
    clean_port = validate_port(tcp_port)

    agent_url = f"http://{clean_kharej}:{control_port}"
    print("=" * 76)
    print("⚡ WATERWALL BEST TUNNEL FINDER - AUTONOMOUS SWEEP")
    print("=" * 76)
    print(f"Iran IP:        {clean_iran}")
    print(f"Kharej IP:      {clean_kharej}")
    print(f"Control Agent:  {agent_url}")
    print(f"Test Port:      {clean_port}")
    print(f"Test Duration:  {duration}s per direction")

    # 1. Verify Kharej Agent connectivity
    print_info(f"Connecting to Kharej Agent at {agent_url}...")
    try:
        health = _get_json(f"{agent_url}/health")
        print_success(f"Kharej Agent reachable! (WaterWall: {health.get('waterwall')}, iperf3: {health.get('iperf3')})")
    except Exception as e:
        print_error(f"Cannot reach Kharej Agent at {agent_url}: {e}")
        print_error(f"Ensure 'finder server --port {control_port}' is running on Kharej and port is open.")
        return 1

    # 2. Select Candidates
    if custom_protocols:
        candidates = parse_custom_protocols(custom_protocols)
    else:
        candidates = CANDIDATES_PRESETS.get(preset, CANDIDATES_PRESETS["top"])

    total = len(candidates)
    print_info(f"Testing {total} protocol candidates ({preset} preset)...\n")

    ww_bin, ww_cwd = get_waterwall_launch_info()
    print_info(f"Using WaterWall binary: {ww_bin} (working dir: {ww_cwd})")
    results: List[Dict[str, Any]] = []

    # 3. Execution Sweep Loop
    for idx, cand in enumerate(candidates, 1):
        cid = cand["id"]
        cname = cand["name"]
        p_tcp = cand["tcp"]
        p_udp = cand["udp"]

        print(f"\n{'=' * 76}")
        print(f"[*] [{idx}/{total}] Testing {cname} (TCP: {p_tcp}, UDP: {p_udp})...")
        print(f"{'=' * 76}")

        # Step 2: Ensure Kharej Agent is responsive before signaling /prepare
        kharej_ready = False
        for wait_i in range(15):
            try:
                h = _get_json(f"{agent_url}/health", timeout=1.5)
                if h.get("status") == "ready":
                    kharej_ready = True
                    break
            except Exception:
                time.sleep(1.0)

        if not kharej_ready:
            print_error(f"    Kharej agent not responding at {agent_url}/health after wait. Skipping candidate.")
            continue

        print_info(f"Signaling Kharej Agent to prepare candidate (TCP: {p_tcp}, UDP: {p_udp})...")
        try:
            prep = _post_json(f"{agent_url}/prepare", {
                "name": name,
                "iran_ip": clean_iran,
                "kharej_ip": clean_kharej,
                "tcp_port": clean_port,
                "protoswap_tcp": p_tcp,
                "protoswap_udp": p_udp,
                "duration": duration,
            }, timeout=15.0)
            if prep.get("status") != "ready":
                print_warning(f"    Kharej failed to prepare: {prep}")
                continue
        except Exception as e:
            print_error(f"    Failed to contact Kharej agent: {e}")
            continue

        # Step 3: Generate Iran configuration and start local WaterWall SECOND
        Path(ww_cwd, "log").mkdir(parents=True, exist_ok=True)
        cfg_iran = generate_protoswap_iran(
            config_name=name,
            iran_ip=clean_iran,
            kharej_ip=clean_kharej,
            tcp_ports=[clean_port],
            protoswap_tcp=p_tcp,
            protoswap_udp=p_udp,
        )
        conf_file = Path(ww_cwd) / f"{name}.json"
        core_file = Path(ww_cwd) / "core.json"
        write_json(cfg_iran, conf_file)
        core_cfg = generate_core_config(
            config_paths=[f"{name}.json"],
            loglevel="DEBUG",
            console=True,
            log_path=str(Path(ww_cwd) / "log/"),
        )
        write_json(core_cfg, core_file)

        local_ww = None
        try:
            print_info(f"Starting WaterWall on Iran with DEBUG logging (live output below):")
            local_ww = subprocess.Popen(
                [ww_bin],
                cwd=ww_cwd,
                start_new_session=True,
                stdout=None,
                stderr=None,
            )
            time.sleep(0.5)
            if local_ww.poll() is not None:
                print_error(f"    WaterWall on Iran exited prematurely (code {local_ww.returncode})! Check {ww_bin}")
                continue

            time.sleep(1.5)  # Wait for tunnel initialization

            # Step 4: Run Bandwidth Probes
            # Test 1: Upload (Iran -> Kharej)
            print_info(f"Running upload probe (Iran -> Kharej, {duration}s)...")
            up_mbps, retr = _run_iperf_test(clean_port, duration=duration, reverse=False)

            # Pause so iperf3 server can reset listener cleanly
            time.sleep(1.0)

            # Test 2: Download (Kharej -> Iran)
            print_info(f"Running download probe (Kharej -> Iran, {duration}s)...")
            down_mbps, _ = _run_iperf_test(clean_port, duration=duration, reverse=True)

            score = round(up_mbps + down_mbps, 2)
            status_label = "BLOCKED ❌" if (up_mbps == 0 and down_mbps == 0) else ("ACTIVE ✅" if retr == 0 else "DEGRADED ⚠️")

            results.append({
                "cand": cand,
                "upload": up_mbps,
                "download": down_mbps,
                "retr": retr,
                "score": score,
                "status": status_label,
            })

            print(f"\n    -> Up: {up_mbps:6.2f} Mbps | Down: {down_mbps:6.2f} Mbps | Retr: {retr} | {status_label}")

        finally:
            # Step 5: Teardown: First Iran, then Kharej
            print_info(f"Resetting WaterWall on Iran...")
            stop_waterwall_and_test(local_ww, name, ww_cwd)
            local_ww = None

            print_info(f"Awaiting Kharej reset and restoring control channel...")
            for check_attempt in range(15):
                try:
                    _post_json(f"{agent_url}/teardown", {"name": name}, timeout=1.5)
                    break
                except Exception:
                    time.sleep(1.0)

        time.sleep(0.5)

    # 4. Results & Leaderboard
    if not results:
        print_error("No candidates were successfully tested.")
        return 1

    # Sort descending by combined throughput score
    results.sort(key=lambda r: r["score"], reverse=True)

    print("\n" + "=" * 76)
    print("🏆 PROTOSWAP PROTOCOL BENCHMARK LEADERBOARD")
    print("=" * 76)
    print(f"{'Rank':<5} | {'Candidate':<22} | {'TCP/UDP':<9} | {'Upload':<11} | {'Download':<11} | {'Status'}")
    print("-" * 76)

    for i, r in enumerate(results, 1):
        c = r["cand"]
        proto_str = f"{c['tcp']}/{c['udp']}"
        badge = "BEST ⭐" if i == 1 and r["score"] > 0 else r["status"]
        print(f"#{i:<4} | {c['name']:<22} | {proto_str:<9} | {r['upload']:>6.2f} Mbps | {r['download']:>6.2f} Mbps | {badge}")

    print("=" * 76)

    winner = results[0]
    if winner["score"] == 0:
        print_warning("All tested protocols yielded 0 Mbps. Check firewall/security groups on both servers.")
        return 0

    best_cand = winner["cand"]
    print_success(f"Winner: {best_cand['name']} (TCP: {best_cand['tcp']}, UDP: {best_cand['udp']}) with {winner['score']} Mbps combined!")

    # 5. Apply Winning Configuration
    if auto_apply:
        print_info(f"Applying winning configuration '{name}.json' to Iran and Kharej...")
        # Apply locally on Iran
        best_cfg_iran = generate_protoswap_iran(
            config_name=name,
            iran_ip=clean_iran,
            kharej_ip=clean_kharej,
            tcp_ports=[clean_port],
            protoswap_tcp=best_cand["tcp"],
            protoswap_udp=best_cand["udp"],
        )
        filepath = Path(ww_cwd) / f"{name}.json"
        core_path = Path(ww_cwd) / "core.json"
        saved_iran = save_waterwall_config(best_cfg_iran, filepath=filepath, name=name, auto_core=True, core_path=core_path)
        print_success(f"Activated on Iran: {saved_iran} (synced to {core_path})")

        # Signal Kharej to apply permanently
        try:
            resp = _post_json(f"{agent_url}/apply_winner", {
                "name": name,
                "iran_ip": clean_iran,
                "kharej_ip": clean_kharej,
                "tcp_port": clean_port,
                "protoswap_tcp": best_cand["tcp"],
                "protoswap_udp": best_cand["udp"],
            })
            print_success(f"Activated on Kharej: {resp.get('file', name + '.json')} (synced to core.json)")
        except Exception as e:
            print_warning(f"Could not automatically apply to Kharej: {e}")

    return 0
