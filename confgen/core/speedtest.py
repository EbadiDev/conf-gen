"""Native Zero-Dependency High-Throughput Stream SpeedTest for ConfGen.

Replaces brittle iperf3 with pure-Python TCP streaming:
- Immune to Linux loopback MTU / MSS 22528 traps
- Works seamlessly across all WaterWall tunnels (ProtoSwap, BitSwap, Reality, TLS)
- Measures:
  1. Handshake Latency (RTT ms)
  2. Sustained TCP Upload (Mbps)
  3. Sustained TCP Download (Mbps)
"""

import socket
import sys
import threading
import time
from typing import Optional, Tuple

from confgen.core.utils import print_error, print_info, print_success, print_warning

CHUNK_SIZE = 1300  # Safe size fitting within 1400 tunnel MTU without fragmentation


def run_speedtest_server(port: int = 9001, bind: str = "0.0.0.0") -> int:
    """Start native speedtest receiver daemon."""
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        server.bind((bind, port))
        server.listen(10)
    except Exception as e:
        print_error(f"Cannot bind speedtest server to {bind}:{port}: {e}")
        return 1

    print_success(f"⚡ ConfGen SpeedTest server listening on {bind}:{port}")
    print_info("Awaiting client test connections... (Press Ctrl+C to stop)")

    chunk = b"\x00" * CHUNK_SIZE

    def _handle_client(conn: socket.socket, addr: Tuple[str, int]) -> None:
        try:
            conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            # Read 8-byte command: "UPLOAD:5" or "DNLOAD:5" or "PING0000"
            raw_cmd = conn.recv(8).decode("ascii", errors="ignore").strip()
            if raw_cmd.startswith("PING"):
                conn.sendall(b"PONG0000")
            elif raw_cmd.startswith("UPLOAD"):
                # Sink mode: receive as fast as possible until EOF
                while True:
                    data = conn.recv(65536)
                    if not data:
                        break
            elif raw_cmd.startswith("DNLOAD"):
                # Generator mode: stream data for N seconds
                parts = raw_cmd.split(":")
                dur = int(parts[1]) if len(parts) > 1 and parts[1].isdigit() else 5
                t_end = time.perf_counter() + dur
                while time.perf_counter() < t_end:
                    conn.sendall(chunk)
        except Exception:
            pass
        finally:
            try:
                conn.close()
            except Exception:
                pass

    try:
        while True:
            conn, addr = server.accept()
            threading.Thread(target=_handle_client, args=(conn, addr), daemon=True).start()
    except KeyboardInterrupt:
        print_info("\nSpeedTest server stopped.")
    finally:
        server.close()
    return 0


def run_speedtest_client(
    host: str = "127.0.0.1",
    port: int = 9001,
    duration: int = 5,
    parallel: int = 1,
    quiet: bool = False,
) -> Tuple[float, float, float]:
    """Execute native speedtest client against server with optional parallel streams."""
    if not quiet:
        print("=" * 65)
        print("⚡ CONFGEN NATIVE STREAM BENCHMARK")
        print("=" * 65)
        print(f"Target Endpoint:  {host}:{port}")
        print(f"Child Streams:    {parallel} connection(s)")
        print(f"Test Duration:    {duration}s per direction")
        print(f"Frame Size:       {CHUNK_SIZE} B (MTU-safe)")

    # 1. Latency RTT Probe
    rtt_ms: Optional[float] = None
    try:
        t0 = time.perf_counter()
        with socket.create_connection((host, port), timeout=3.0) as s:
            s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            s.sendall(b"PING0000")
            resp = s.recv(8)
            if resp.startswith(b"PONG"):
                rtt_ms = round((time.perf_counter() - t0) * 1000.0, 1)
    except Exception:
        pass

    rtt_str = f"{rtt_ms:.1f} ms" if rtt_ms is not None else "TIMEOUT / UNREACHABLE"
    if not quiet:
        print_info(f"Handshake Latency: {rtt_str}")

    # 2. Upload Test (Iran -> Kharej) with parallel child connections
    if not quiet:
        print_info(f"Testing Upload speed ({parallel} stream(s), {duration}s)...")
    total_up_bytes = 0
    up_bytes_lock = threading.Lock()
    chunk = b"\x55" * CHUNK_SIZE
    t_end = time.perf_counter() + duration

    def _worker_up():
        nonlocal total_up_bytes
        local_bytes = 0
        try:
            with socket.create_connection((host, port), timeout=4.0) as s:
                s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                s.sendall(f"UPLOAD:{duration}".encode("ascii"))
                while time.perf_counter() < t_end:
                    s.sendall(chunk)
                    local_bytes += len(chunk)
        except Exception:
            pass
        with up_bytes_lock:
            total_up_bytes += local_bytes

    threads = [threading.Thread(target=_worker_up) for _ in range(parallel)]
    t_start = time.perf_counter()
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    elapsed = time.perf_counter() - t_start
    up_mbps = round((total_up_bytes * 8) / (elapsed * 1_000_000.0), 2) if elapsed > 0 else 0.0
    if not quiet:
        print_success(f"Upload:   {up_mbps:6.2f} Mbps ({(total_up_bytes / (1024 * 1024)):.1f} MB in {duration}s across {parallel} streams)")

    time.sleep(0.5)

    # 3. Download Test (Kharej -> Iran) with parallel child connections
    if not quiet:
        print_info(f"Testing Download speed ({parallel} stream(s), {duration}s)...")
    total_down_bytes = 0
    down_bytes_lock = threading.Lock()

    def _worker_down():
        nonlocal total_down_bytes
        local_bytes = 0
        try:
            with socket.create_connection((host, port), timeout=4.0) as s:
                s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                s.sendall(f"DNLOAD:{duration}".encode("ascii"))
                t_down_end = time.perf_counter() + duration + 0.5
                while time.perf_counter() < t_down_end:
                    data = s.recv(65536)
                    if not data:
                        break
                    local_bytes += len(data)
        except Exception:
            pass
        with down_bytes_lock:
            total_down_bytes += local_bytes

    threads = [threading.Thread(target=_worker_down) for _ in range(parallel)]
    t_start = time.perf_counter()
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    elapsed = time.perf_counter() - t_start
    down_mbps = round((total_down_bytes * 8) / (elapsed * 1_000_000.0), 2) if elapsed > 0 else 0.0
    if not quiet:
        print_success(f"Download: {down_mbps:6.2f} Mbps ({(total_down_bytes / (1024 * 1024)):.1f} MB in {duration}s across {parallel} streams)")
        print("=" * 65)
        print(f"📊 SUMMARY: Up: {up_mbps} Mbps | Down: {down_mbps} Mbps | RTT: {rtt_str}")
        print("=" * 65 + "\n")

    return up_mbps, down_mbps, (rtt_ms or 0.0)


def run_mux_scaling_benchmark(
    host: str = "127.0.0.1",
    port: int = 9001,
    duration: int = 5,
    steps: Optional[List[int]] = None,
) -> None:
    """Run multi-connection scaling benchmark (1, 2, 8, 16 child connections) matching WaterWall docs."""
    from typing import List
    steps = steps or [1, 2, 8, 16]
    print("\n" + "=" * 80)
    print("⚡ WATERWALL MUX MULTI-CONNECTION SCALING BENCHMARK")
    print("=" * 80)
    print("Each cell shows throughput in Mbps. All child connections share the tunnel.")
    print(f"Target: {host}:{port} | Duration: {duration}s per test\n")

    matrix_results = []
    for count in steps:
        print(f"[*] Testing with {count} child connection(s)...")
        up, down, rtt = run_speedtest_client(host=host, port=port, duration=duration, parallel=count, quiet=True)
        print_success(f"    -> Up: {up:6.2f} Mbps | Down: {down:6.2f} Mbps")
        matrix_results.append((count, up, down, rtt))
        time.sleep(0.5)

    print("\n" + "=" * 80)
    print("📊 MUX CONCURRENCY SCALING BENCHMARK TABLE")
    print("=" * 80)
    print(f"{'Child Connections':<20} | {'Upload Throughput':<25} | {'Download Throughput':<25}")
    print("-" * 80)
    for count, up, down, rtt in matrix_results:
        up_str = f"{up:6.2f} Mbps ({(up/8):.1f} MB/s)"
        down_str = f"{down:6.2f} Mbps ({(down/8):.1f} MB/s)"
        print(f"{count:<20} | {up_str:<25} | {down_str:<25}")
    print("=" * 80 + "\n")
