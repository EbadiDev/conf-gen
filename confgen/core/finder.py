"""Autonomous Cross-Border Tunnel Protocol Optimizer (Best Tunnel Finder).

Coordinates between Kharej (Agent) and Iran (Orchestrator) to sweep IPv4
protocol replacement numbers for WaterWall ProtoSwap (IpManipulator).
Measures real-world bandwidth, latency, and packet loss, ranks candidates,
and automatically applies the winning configuration to both servers.
"""

import json
import os
import platform
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
from confgen.generators.waterwall.bitswap import (
    generate_bitswap_iran,
    generate_bitswap_kharej,
)
from confgen.generators.waterwall.protoswap import (
    generate_protoswap_iran,
    generate_protoswap_kharej,
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

# Standard protocol sweep presets for DPI circumvention (ProtoSwap + BitSwap)
DEFAULT_HOSPITAL_SNIS: List[str] = [
    "miladhospital.com",     # Milad Hospital Tehran (Let's Encrypt, TLS OK)
    "rhc.ac.ir",             # Rajaie Cardiovascular Medical Center (Let's Encrypt, TLS OK)
    "farabi.tums.ac.ir",     # Farabi Eye Hospital (Let's Encrypt, TLS OK)
    "sina.tums.ac.ir",       # Sina Hospital (Let's Encrypt, TLS OK)
    "shariati.tums.ac.ir",   # Shariati Hospital (Let's Encrypt, TLS OK)
    "bahmanhospital.ir",     # Bahman Hospital (Certum, TLS OK)
    "pasteur.ac.ir",         # Pasteur Institute of Iran (Certum, TLS OK)
    "tums.ac.ir",            # Tehran University of Medical Sciences (Let's Encrypt, TLS OK)
    "sbmu.ac.ir",            # Shahid Beheshti Medical University (Certum, TLS OK)
    "iums.ac.ir",            # Iran University of Medical Sciences (Certum, TLS OK)
]

DEFAULT_IRAN_SNIS: List[str] = [
    "telewebion.ir",
    "miladhospital.com",
    "rhc.ac.ir",
    "farabi.tums.ac.ir",
    "sina.tums.ac.ir",
    "shariati.tums.ac.ir",
    "bahmanhospital.ir",
    "pasteur.ac.ir",
    "tums.ac.ir",
    "sbmu.ac.ir",
    "filimo.com",
    "aparat.com",
    "namava.ir",
    "ble.ir",
    "eitaa.com",
    "shad.ir",
    "rubika.ir",
    "neshan.org",
    "snapp.ir",
    "tci.ir",
    "irancell.ir",
    "mci.ir",
    "divar.ir",
    "cafebazaar.ir",
]

CANDIDATES_PRESETS: Dict[str, List[Dict[str, Any]]] = {
    "methods": [
        {"id": "rev_reality_grpc", "name": "Reverse Reality (gRPC+HD)", "type": "reverse_reality", "domain": "telewebion.ir", "white_ip": "185.165.205.129", "password": "arch1234net", "use_grpc": True, "use_halfduplex": True},
        {"id": "rev_reality", "name": "Reverse Reality (telewebion)", "type": "reverse_reality", "domain": "telewebion.ir", "white_ip": "185.165.205.129", "password": "arch1234net"},
        {"id": "bitswap_v2", "name": "BitSwap V2 (URG/ECE + Dup 3)", "type": "bitswap", "tcp": 6, "udp": 17, "bitswap": True, "pattern": "variant2"},
        {"id": "bitswap_rst", "name": "BitSwap (PSH <-> RST)", "type": "bitswap", "tcp": 6, "udp": 17, "bitswap": True, "pattern": "psh/rst"},
        {"id": "bitswap_cwr", "name": "BitSwap (PSH <-> CWR)", "type": "bitswap", "tcp": 6, "udp": 17, "bitswap": True, "pattern": "psh/cwr"},
        {"id": "protoswap_esp_rst", "name": "ProtoSwap 50 + BitSwap RST", "type": "protoswap", "tcp": 50, "udp": 51, "bitswap": True, "pattern": "psh/rst"},
        {"id": "protoswap_esp", "name": "ProtoSwap ESP (50/51)", "type": "protoswap", "tcp": 50, "udp": 51, "bitswap": False},
        {"id": "protoswap_gre", "name": "ProtoSwap GRE (47/136)", "type": "protoswap", "tcp": 47, "udp": 136, "bitswap": False},
        {"id": "protoswap_253", "name": "ProtoSwap 253/252", "type": "protoswap", "tcp": 253, "udp": 252, "bitswap": False},
        {"id": "tls_reverse", "name": "TLS Reverse", "type": "tls_reverse", "sni": "telewebion.ir"},
        {"id": "udp_reverse", "name": "UDP Reverse", "type": "udp_reverse", "xor_key": 153},
    ],
    "top": [
        {"id": "bitswap_rst", "name": "BitSwap (PSH <-> RST)", "type": "bitswap", "tcp": 6, "udp": 17, "bitswap": True, "pattern": "psh/rst"},
        {"id": "bitswap_pure", "name": "BitSwap (PSH <-> CWR)", "type": "bitswap", "tcp": 6, "udp": 17, "bitswap": True, "pattern": "psh/cwr"},
        {"id": "ah_51_52_bit", "name": "AH + BitSwap", "type": "protoswap", "tcp": 51, "udp": 52, "bitswap": True},
        {"id": "ah_51_52", "name": "AH (IPsec)", "type": "protoswap", "tcp": 51, "udp": 52, "bitswap": False},
        {"id": "sctp_132_133", "name": "SCTP", "type": "protoswap", "tcp": 132, "udp": 133, "bitswap": False},
        {"id": "sctp_132_133_bit", "name": "SCTP + BitSwap", "type": "protoswap", "tcp": 132, "udp": 133, "bitswap": True},
        {"id": "custom_200_201", "name": "Custom Range 200", "type": "protoswap", "tcp": 200, "udp": 201, "bitswap": False},
        {"id": "custom_200_201_bit", "name": "Custom 200 + BitSwap", "type": "protoswap", "tcp": 200, "udp": 201, "bitswap": True},
        {"id": "custom_222_223", "name": "Custom Range 222", "type": "protoswap", "tcp": 222, "udp": 223, "bitswap": False},
        {"id": "custom_222_223_bit", "name": "Custom 222 + BitSwap", "type": "protoswap", "tcp": 222, "udp": 223, "bitswap": True},
        {"id": "esp_50_51", "name": "ESP (IPsec)", "type": "protoswap", "tcp": 50, "udp": 51, "bitswap": False},
        {"id": "esp_50_51_bit", "name": "ESP + BitSwap", "type": "protoswap", "tcp": 50, "udp": 51, "bitswap": True},
        {"id": "gre_47_136", "name": "GRE / UDPLite", "type": "protoswap", "tcp": 47, "udp": 136, "bitswap": False},
        {"id": "gre_47_136_bit", "name": "GRE + BitSwap", "type": "protoswap", "tcp": 47, "udp": 136, "bitswap": True},
    ],
    "fast": [
        {"id": "bitswap_rst", "name": "BitSwap (PSH <-> RST)", "type": "bitswap", "tcp": 6, "udp": 17, "bitswap": True, "pattern": "psh/rst"},
        {"id": "bitswap_pure", "name": "BitSwap (PSH <-> CWR)", "type": "bitswap", "tcp": 6, "udp": 17, "bitswap": True, "pattern": "psh/cwr"},
        {"id": "ah_51_52_bit", "name": "AH + BitSwap", "type": "protoswap", "tcp": 51, "udp": 52, "bitswap": True},
        {"id": "sctp_132_133", "name": "SCTP", "type": "protoswap", "tcp": 132, "udp": 133, "bitswap": False},
        {"id": "custom_200_201", "name": "Custom Range 200", "type": "protoswap", "tcp": 200, "udp": 201, "bitswap": False},
        {"id": "esp_50_51", "name": "ESP (IPsec)", "type": "protoswap", "tcp": 50, "udp": 51, "bitswap": False},
    ],
    "combo": [
        {"id": "bitswap_pure", "name": "Pure BitSwap", "type": "bitswap", "tcp": 6, "udp": 17, "bitswap": True},
        {"id": "ah_51_52_bit", "name": "AH + BitSwap", "type": "protoswap", "tcp": 51, "udp": 52, "bitswap": True},
        {"id": "sctp_132_133_bit", "name": "SCTP + BitSwap", "type": "protoswap", "tcp": 132, "udp": 133, "bitswap": True},
        {"id": "custom_200_201_bit", "name": "Custom 200 + BitSwap", "type": "protoswap", "tcp": 200, "udp": 201, "bitswap": True},
        {"id": "esp_50_51_bit", "name": "ESP + BitSwap", "type": "protoswap", "tcp": 50, "udp": 51, "bitswap": True},
        {"id": "custom_222_223_bit", "name": "Custom 222 + BitSwap", "type": "protoswap", "tcp": 222, "udp": 223, "bitswap": True},
        {"id": "gre_47_136_bit", "name": "GRE + BitSwap", "type": "protoswap", "tcp": 47, "udp": 136, "bitswap": True},
        {"id": "rfc3692_253_252_bit", "name": "RFC 3692 + BitSwap", "type": "protoswap", "tcp": 253, "udp": 252, "bitswap": True},
    ],
    "all": [
        {"id": "bitswap_pure", "name": "Pure BitSwap", "type": "bitswap", "tcp": 6, "udp": 17, "bitswap": True},
        {"id": "ah_51_52_bit", "name": "AH + BitSwap", "type": "protoswap", "tcp": 51, "udp": 52, "bitswap": True},
        {"id": "ah_51_52", "name": "AH (IPsec)", "type": "protoswap", "tcp": 51, "udp": 52, "bitswap": False},
        {"id": "sctp_132_133", "name": "SCTP", "type": "protoswap", "tcp": 132, "udp": 133, "bitswap": False},
        {"id": "sctp_132_133_bit", "name": "SCTP + BitSwap", "type": "protoswap", "tcp": 132, "udp": 133, "bitswap": True},
        {"id": "custom_200_201", "name": "Custom Range 200", "type": "protoswap", "tcp": 200, "udp": 201, "bitswap": False},
        {"id": "custom_200_201_bit", "name": "Custom 200 + BitSwap", "type": "protoswap", "tcp": 200, "udp": 201, "bitswap": True},
        {"id": "custom_222_223", "name": "Custom Range 222", "type": "protoswap", "tcp": 222, "udp": 223, "bitswap": False},
        {"id": "custom_222_223_bit", "name": "Custom 222 + BitSwap", "type": "protoswap", "tcp": 222, "udp": 223, "bitswap": True},
        {"id": "esp_50_51", "name": "ESP (IPsec)", "type": "protoswap", "tcp": 50, "udp": 51, "bitswap": False},
        {"id": "esp_50_51_bit", "name": "ESP + BitSwap", "type": "protoswap", "tcp": 50, "udp": 51, "bitswap": True},
        {"id": "gre_47_136", "name": "GRE / UDPLite", "type": "protoswap", "tcp": 47, "udp": 136, "bitswap": False},
        {"id": "gre_47_136_bit", "name": "GRE + BitSwap", "type": "protoswap", "tcp": 47, "udp": 136, "bitswap": True},
        {"id": "rfc3692_253_252", "name": "RFC 3692 Exp 1", "type": "protoswap", "tcp": 253, "udp": 252, "bitswap": False},
        {"id": "rfc3692_253_252_bit", "name": "RFC 3692 + BitSwap", "type": "protoswap", "tcp": 253, "udp": 252, "bitswap": True},
        {"id": "ipcomp_108_109", "name": "IPComp", "type": "protoswap", "tcp": 108, "udp": 109, "bitswap": False},
        {"id": "vrrp_112_113", "name": "VRRP", "type": "protoswap", "tcp": 112, "udp": 113, "bitswap": False},
        {"id": "l2tp_115_116", "name": "L2TP", "type": "protoswap", "tcp": 115, "udp": 116, "bitswap": False},
        {"id": "ospf_89_90", "name": "OSPF", "type": "protoswap", "tcp": 89, "udp": 90, "bitswap": False},
        {"id": "custom_240_241", "name": "Custom Range 240", "type": "protoswap", "tcp": 240, "udp": 241, "bitswap": False},
    ],
}


import zipfile

WATERWALL_TEST_BIN_NAME = "Waterwall-test"


def get_cpu_architecture() -> str:
    """Return normalized CPU architecture: 'arm64' or 'x64'."""
    machine = platform.machine().lower()
    if machine in ("aarch64", "arm64", "armv8", "armv8b", "armv8l"):
        return "arm64"
    return "x64"


def get_waterwall_release_url() -> str:
    """Return appropriate WaterWall release download URL based on CPU architecture."""
    arch = get_cpu_architecture()
    base = "https://github.com/radkesvat/WaterWall/releases/download/v1.46.94"
    if arch == "arm64":
        return f"{base}/Waterwall-linux-gcc-arm64.zip"
    else:
        return f"{base}/Waterwall-linux-gcc-x64-old-cpu.zip"


def is_binary_runnable(bin_path: str) -> bool:
    """Check if the binary can be executed without Exec format error."""
    if not os.path.isfile(bin_path) or not os.access(bin_path, os.X_OK):
        return False
    try:
        proc = subprocess.run([bin_path, "-v"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=2.0)
        return True
    except OSError as e:
        # e.errno == 8 (Exec format error)
        return False
    except Exception:
        return True


def get_default_test_dir() -> str:
    """Return the isolated working directory for WaterWall benchmark instances."""
    custom = os.environ.get("WATERWALL_TEST_DIR")
    if custom:
        return os.path.abspath(custom)
    if os.name != "nt" and hasattr(os, "geteuid") and os.geteuid() == 0:
        return "/root/waterwall-test"
    home = os.path.expanduser("~")
    cand = os.path.join(home, "waterwall-test")
    try:
        os.makedirs(cand, exist_ok=True)
        return cand
    except Exception:
        return "/tmp/waterwall-test"


def download_and_extract_waterwall(target_dir: str) -> Optional[str]:
    """Download WaterWall release and install an isolated Waterwall-test binary.

    Follows:
    curl -4 -L -o waterwall.zip <RELEASE_URL> && unzip waterwall.zip && chmod +x Waterwall && cp Waterwall Waterwall-test
    """
    os.makedirs(target_dir, exist_ok=True)
    zip_path = os.path.join(target_dir, "waterwall.zip")
    bin_test = os.path.join(target_dir, WATERWALL_TEST_BIN_NAME)

    # Clean any stale zip or broken/unrunnable binaries
    for b_file in [zip_path, bin_test, os.path.join(target_dir, "Waterwall"), os.path.join(target_dir, "waterwall")]:
        if os.path.exists(b_file) and (b_file == zip_path or not is_binary_runnable(b_file)):
            try:
                os.remove(b_file)
            except Exception:
                pass

    arch = get_cpu_architecture()
    release_url = get_waterwall_release_url()
    print_info(f"Downloading isolated WaterWall benchmark instance for {arch} into {target_dir}...")
    downloaded = False

    # Attempt 1: curl -4 -L -o
    curl_bin = shutil.which("curl")
    if curl_bin:
        try:
            ret = subprocess.run(
                [curl_bin, "-4", "-fsSL", "--connect-timeout", "15", "--max-time", "120", "-o", zip_path, release_url],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=130,
            )
            if ret.returncode == 0 and os.path.exists(zip_path) and os.path.getsize(zip_path) > 1000:
                downloaded = True
        except Exception as e:
            print_warning(f"curl download failed: {e}")

    # Attempt 2: Python urllib
    if not downloaded:
        try:
            req = Request(release_url, headers={"User-Agent": "Mozilla/5.0"})
            with urlopen(req, timeout=30.0) as resp, open(zip_path, "wb") as out_f:
                shutil.copyfileobj(resp, out_f)
            if os.path.exists(zip_path) and os.path.getsize(zip_path) > 1000:
                downloaded = True
        except Exception as e:
            print_warning(f"urllib download failed: {e}")

    if not downloaded:
        print_warning(f"Failed to download WaterWall release archive to {zip_path}")
        # Fallback: check if main /root/waterwall exists on host and copy it
        for main_dir in ["/root/waterwall", os.path.expanduser("~/waterwall")]:
            for b_name in ["Waterwall", "waterwall"]:
                main_ww = os.path.join(main_dir, b_name)
                if os.path.isfile(main_ww):
                    print_info(f"Copying existing WaterWall from {main_ww} to isolated {bin_test}...")
                    shutil.copy2(main_ww, bin_test)
                    os.chmod(bin_test, 0o755)
                    main_libs = os.path.join(main_dir, "libs")
                    target_libs = os.path.join(target_dir, "libs")
                    if os.path.isdir(main_libs) and not os.path.exists(target_libs):
                        try:
                            shutil.copytree(main_libs, target_libs, dirs_exist_ok=True)
                        except Exception:
                            pass
                    return bin_test
        return None

    # Extraction: try zipfile, fallback to system unzip
    extracted = False
    try:
        with zipfile.ZipFile(zip_path, "r") as zf:
            zf.extractall(target_dir)
        extracted = True
    except Exception as e:
        print_warning(f"Python zipfile extraction failed ({e}), attempting system unzip...")
        unzip_bin = shutil.which("unzip")
        if unzip_bin:
            try:
                ret = subprocess.run([unzip_bin, "-o", zip_path, "-d", target_dir], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                if ret.returncode == 0:
                    extracted = True
            except Exception:
                pass

    # Clean zip archive
    if os.path.exists(zip_path):
        try:
            os.remove(zip_path)
        except Exception:
            pass

    if not extracted:
        print_error(f"Failed to extract WaterWall archive in {target_dir}")
        return None

    # Locate extracted binary and provision Waterwall-test
    base_ww = None
    for name in ["Waterwall", "waterwall"]:
        cand = os.path.join(target_dir, name)
        if os.path.exists(cand):
            base_ww = cand
            break

    if base_ww:
        try:
            os.chmod(base_ww, 0o755)
        except Exception:
            pass
        shutil.copy2(base_ww, bin_test)
        os.chmod(bin_test, 0o755)
        print_success(f"Isolated WaterWall benchmark binary prepared at {bin_test}")

    # Ensure libs directory is present if main /root/waterwall/libs exists
    target_libs = os.path.join(target_dir, "libs")
    main_libs = "/root/waterwall/libs"
    if not os.path.isdir(target_libs) and os.path.isdir(main_libs):
        try:
            shutil.copytree(main_libs, target_libs, dirs_exist_ok=True)
        except Exception:
            pass

    return bin_test if os.path.exists(bin_test) and os.access(bin_test, os.X_OK) else None


def get_test_waterwall_launch_info(
    test_dir: Optional[str] = None,
    auto_download: bool = True,
) -> Tuple[str, str]:
    """Find or provision the isolated WaterWall test executable and working directory.

    NEVER uses the main /root/waterwall directory so production tunnels remain untouched.
    Returns (executable_path, working_directory).
    """
    target_dir = os.path.abspath(test_dir) if test_dir else get_default_test_dir()
    os.makedirs(target_dir, exist_ok=True)
    test_bin = os.path.join(target_dir, WATERWALL_TEST_BIN_NAME)

    # 1. Existing Waterwall-test in target_dir (must be runnable)
    if os.path.isfile(test_bin) and os.access(test_bin, os.X_OK):
        if is_binary_runnable(test_bin):
            return test_bin, target_dir
        else:
            print_warning(f"Existing binary at {test_bin} has wrong architecture (Exec format error). Re-downloading...")
            try:
                os.remove(test_bin)
            except Exception:
                pass

    # 2. Existing Waterwall in target_dir -> copy to Waterwall-test (if runnable)
    for b_name in ["Waterwall", "waterwall"]:
        cand = os.path.join(target_dir, b_name)
        if os.path.isfile(cand) and os.access(cand, os.X_OK):
            if is_binary_runnable(cand):
                try:
                    shutil.copy2(cand, test_bin)
                    os.chmod(test_bin, 0o755)
                    return test_bin, target_dir
                except Exception:
                    pass
            else:
                try:
                    os.remove(cand)
                except Exception:
                    pass

    # 3. Auto-download from GitHub into target_dir
    if auto_download:
        provisioned = download_and_extract_waterwall(target_dir)
        if provisioned and os.path.isfile(provisioned) and os.access(provisioned, os.X_OK):
            return provisioned, target_dir

    # 4. Fallback: Copy from /root/waterwall if host has it installed
    for main_dir in ["/root/waterwall", os.path.expanduser("~/waterwall")]:
        for b_name in ["Waterwall", "waterwall"]:
            cand = os.path.join(main_dir, b_name)
            if os.path.isfile(cand) and os.access(cand, os.X_OK):
                try:
                    shutil.copy2(cand, test_bin)
                    os.chmod(test_bin, 0o755)
                    libs_src = os.path.join(main_dir, "libs")
                    libs_dst = os.path.join(target_dir, "libs")
                    if os.path.isdir(libs_src) and not os.path.exists(libs_dst):
                        try:
                            shutil.copytree(libs_src, libs_dst, dirs_exist_ok=True)
                        except Exception:
                            pass
                    return test_bin, target_dir
                except Exception:
                    pass

    return test_bin, target_dir


def get_waterwall_launch_info(
    test_mode: bool = True,
    test_dir: Optional[str] = None,
) -> Tuple[str, str]:
    """Find the WaterWall executable and its working directory.

    When test_mode is True (default for benchmarking/finder), returns the isolated
    Waterwall-test instance in the benchmark directory to protect production tunnels.
    """
    if test_mode:
        return get_test_waterwall_launch_info(test_dir=test_dir)

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


def find_waterwall_binary(test_dir: Optional[str] = None) -> Optional[str]:
    """Locate a runnable WaterWall binary on the host (checks test instance then host)."""
    bin_path, _ = get_test_waterwall_launch_info(test_dir=test_dir, auto_download=False)
    if is_binary_runnable(bin_path):
        return bin_path
    for d in ["/root/waterwall", os.path.expanduser("~/waterwall"), "/usr/local/bin", "/usr/bin"]:
        for n in ["Waterwall", "waterwall"]:
            p = os.path.join(d, n)
            if is_binary_runnable(p):
                return p
    for n in ["Waterwall", "waterwall"]:
        w = shutil.which(n)
        if w and is_binary_runnable(w):
            return w
    return None


def find_iperf3_binary() -> Optional[str]:
    """Locate the iperf3 binary on the host."""
    return shutil.which("iperf3")


def ensure_iperf3_installed() -> Optional[str]:
    """Ensure iperf3 binary is available, attempting automatic installation if missing."""
    bin_path = find_iperf3_binary()
    if bin_path:
        return bin_path

    print_info("iperf3 binary not found. Attempting non-interactive installation via package manager...")
    env = os.environ.copy()
    env["DEBIAN_FRONTEND"] = "noninteractive"
    env["NEEDRESTART_MODE"] = "a"

    # Debian / Ubuntu
    if shutil.which("apt-get"):
        try:
            # 1. Try direct installation first with lock timeout and non-interactive options (takes ~2s if cached)
            cmd_fast = [
                "apt-get", "install", "-y",
                "-o", "DPkg::Lock::Timeout=60",
                "-o", "Dpkg::Options::=--force-confdef",
                "-o", "Dpkg::Options::=--force-confold",
                "--no-install-recommends",
                "iperf3",
            ]
            subprocess.run(cmd_fast, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20, check=False)
            bin_path = find_iperf3_binary()
            if not bin_path:
                # 2. If cached install failed, run quick update with strict timeout then retry
                subprocess.run(["apt-get", "update", "-qq"], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15, check=False)
                subprocess.run(cmd_fast, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=25, check=False)
        except Exception as e:
            print_warning(f"apt-get installation attempt encountered error: {e}")
    # Arch / CachyOS / Manjaro
    elif shutil.which("pacman"):
        try:
            subprocess.run(["pacman", "-Sy", "--noconfirm", "iperf3"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=25, check=False)
        except Exception:
            pass
    # RHEL / CentOS / Alma / Rocky / Fedora
    elif shutil.which("dnf") or shutil.which("yum"):
        pkg_mgr = shutil.which("dnf") or shutil.which("yum")
        try:
            subprocess.run([pkg_mgr, "install", "-y", "iperf3"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=25, check=False)
        except Exception:
            pass
    # openSUSE
    elif shutil.which("zypper"):
        try:
            subprocess.run(["zypper", "--non-interactive", "install", "iperf3"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=25, check=False)
        except Exception:
            pass
    # Alpine
    elif shutil.which("apk"):
        try:
            subprocess.run(["apk", "add", "iperf3"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20, check=False)
        except Exception:
            pass

    bin_path = find_iperf3_binary()
    if bin_path:
        print_success(f"iperf3 successfully installed: {bin_path}")
    else:
        print_warning("iperf3 could not be installed automatically; will use native Python socket benchmark probe if needed.")
    return bin_path


def _ensure_self_signed_cert(cert_path: str, key_path: str) -> None:
    """Generate temporary self-signed cert and key for TLS reverse benchmark if missing."""
    if os.path.exists(cert_path) and os.path.exists(key_path):
        return
    Path(cert_path).parent.mkdir(parents=True, exist_ok=True)
    if shutil.which("openssl"):
        try:
            cmd = [
                "openssl", "req", "-x509", "-newkey", "rsa:2048",
                "-nodes", "-keyout", key_path, "-out", cert_path,
                "-days", "1", "-subj", "/CN=telewebion.ir",
            ]
            subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10, check=True)
            return
        except Exception:
            pass
    # Minimal fallback dummy PEM if openssl fails
    Path(cert_path).write_text("-----BEGIN CERTIFICATE-----\nMIIC+jCCAm+gAwIBAgIUW6w6dummy=\n-----END CERTIFICATE-----\n")
    Path(key_path).write_text("-----BEGIN PRIVATE KEY-----\nMIIEvgIBADANBgkqhkiG9w0Bdummy=\n-----END PRIVATE KEY-----\n")


def _generate_candidate_kharej(
    cand_type: str,
    req: Dict[str, Any],
    name: str,
    iran_ip: str,
    kharej_ip: str,
    tcp_port: int,
    p_tcp: int,
    p_udp: int,
    enable_bitswap: bool,
    private_ip: str,
    private_ip_2: Optional[str],
) -> Dict[str, Any]:
    """Generate candidate configuration for Kharej server across all WaterWall methods."""
    pattern = req.get("pattern", "psh/cwr")
    domain = req.get("domain", "telewebion.ir")
    password = req.get("password", "arch1234net")
    sni = req.get("sni", domain)
    xor_key = int(req.get("xor_key", 90))
    use_halfduplex = bool(req.get("use_halfduplex", False))
    use_fisher = bool(req.get("use_fisher", False))
    use_mux = bool(req.get("use_mux", False))
    packet_duplicate = int(req.get("packet_duplicate", 1))

    if cand_type == "reverse_reality":
        return generate_reverse_reality_tcp_kharej(
            config_name=name,
            iran_ip=iran_ip,
            kharej_ip=kharej_ip,
            port=tcp_port,
            domain=domain,
            final_port=tcp_port,
            password=password,
            use_halfduplex=use_halfduplex,
            use_fisher=use_fisher,
            use_mux=use_mux,
        )
    elif cand_type == "tls_reverse":
        return generate_waterwall_tls_reverse_kharej(
            config_name=name,
            iran_ip=iran_ip,
            port=tcp_port,
            sni=sni,
            final_port=tcp_port,
        )
    elif cand_type == "udp_reverse":
        return generate_udp_reverse_kharej(
            config_name=name,
            iran_public_ip=iran_ip,
            kharej_public_ip=kharej_ip,
            target_port=tcp_port,
            tunnel_port=tcp_port,
            xor_key=xor_key,
        )
    elif cand_type == "bitswap":
        return generate_bitswap_kharej(
            config_name=name,
            iran_ip=iran_ip,
            kharej_ip=kharej_ip,
            tcp_ports=[tcp_port],
            udp_ports=[tcp_port],
            tcp_tunnel_port=58443,
            udp_tunnel_port=58444,
            final_ip="127.0.0.1",
            custom_private_ip=private_ip,
            custom_private_ip_2=private_ip_2,
            bitswap_pattern=pattern,
            packet_duplicate=packet_duplicate,
        )
    else:
        return generate_protoswap_kharej(
            config_name=name,
            iran_ip=iran_ip,
            kharej_ip=kharej_ip,
            tcp_ports=[tcp_port],
            udp_ports=[tcp_port],
            tcp_tunnel_port=58443,
            udp_tunnel_port=58444,
            protoswap_tcp=p_tcp,
            protoswap_udp=p_udp,
            final_ip="127.0.0.1",
            enable_bitswap=enable_bitswap,
            bitswap_pattern=pattern,
            use_mux=use_mux,
            custom_private_ip=private_ip,
            custom_private_ip_2=private_ip_2,
        )


def _generate_candidate_iran(
    cand_type: str,
    cand: Dict[str, Any],
    name: str,
    clean_iran: str,
    clean_kharej: str,
    clean_port: int,
    p_tcp: int,
    p_udp: int,
    cand_bitswap: bool,
    clean_private_ip: str,
    clean_private_ip_2: Optional[str],
    ww_cwd: str,
) -> Dict[str, Any]:
    """Generate candidate configuration for Iran server across all WaterWall methods."""
    pattern = cand.get("pattern", "psh/cwr")
    domain = cand.get("domain", "telewebion.ir")
    white_ip = cand.get("white_ip", "185.165.205.129")
    password = cand.get("password", "arch1234net")
    sni = cand.get("sni", domain)
    xor_key = int(cand.get("xor_key", 90))
    use_halfduplex = bool(cand.get("use_halfduplex", False))
    use_fisher = bool(cand.get("use_fisher", False))
    use_mux = bool(cand.get("use_mux", False))
    packet_duplicate = int(cand.get("packet_duplicate", 1))

    if cand_type == "reverse_reality":
        white_ip = cand.get("white_ip") or resolve_sni_ip(domain)
        return generate_reverse_reality_tcp_iran(
            config_name=name,
            iran_ip=clean_iran,
            kharej_ip=clean_kharej,
            port=clean_port,
            domain=domain,
            white_ip=white_ip,
            password=password,
            use_halfduplex=use_halfduplex,
            use_fisher=use_fisher,
            use_mux=use_mux,
        )
    elif cand_type == "tls_reverse":
        cert_file = str(Path(ww_cwd) / "finder_tls_cert.pem")
        key_file = str(Path(ww_cwd) / "finder_tls_key.pem")
        _ensure_self_signed_cert(cert_file, key_file)
        return generate_waterwall_tls_reverse_iran(
            config_name=name,
            iran_ip=clean_iran,
            port=clean_port,
            cert_path=cert_file,
            key_path=key_file,
            kharej_ips=[clean_kharej],
        )
    elif cand_type == "udp_reverse":
        return generate_udp_reverse_iran(
            config_name=name,
            iran_public_ip=clean_iran,
            kharej_public_ip=clean_kharej,
            listen_port=clean_port,
            tunnel_port=clean_port,
            xor_key=xor_key,
        )
    elif cand_type == "bitswap":
        return generate_bitswap_iran(
            config_name=name,
            iran_ip=clean_iran,
            kharej_ip=clean_kharej,
            tcp_ports=[clean_port],
            udp_ports=[clean_port],
            tcp_tunnel_port=58443,
            udp_tunnel_port=58444,
            custom_private_ip=clean_private_ip,
            custom_private_ip_2=clean_private_ip_2,
            bitswap_pattern=pattern,
            packet_duplicate=packet_duplicate,
        )
    else:
        return generate_protoswap_iran(
            config_name=name,
            iran_ip=clean_iran,
            kharej_ip=clean_kharej,
            tcp_ports=[clean_port],
            udp_ports=[clean_port],
            tcp_tunnel_port=58443,
            udp_tunnel_port=58444,
            protoswap_tcp=p_tcp,
            protoswap_udp=p_udp,
            enable_bitswap=cand_bitswap,
            bitswap_pattern=pattern,
            use_mux=use_mux,
            custom_private_ip=clean_private_ip,
            custom_private_ip_2=clean_private_ip_2,
        )


def measure_tcp_rtt(port: int, host: str = "127.0.0.1", timeout: float = 3.0) -> Optional[float]:
    """Measure TCP handshake round-trip time in milliseconds."""
    try:
        t0 = time.perf_counter()
        with socket.create_connection((host, port), timeout=timeout):
            pass
        return round((time.perf_counter() - t0) * 1000.0, 1)
    except Exception:
        return None


def _run_native_socket_test(
    port: int,
    duration: int = 5,
    host: str = "127.0.0.1",
) -> Tuple[float, int, bool]:
    """Pure-Python synthetic TCP throughput test against local port (fallback for iperf3)."""
    chunk = b"\xaa" * 1300  # 1300 B chunk fits safely within tunnel MTU without fragmentation
    total_bytes = 0
    t_end = time.perf_counter() + duration
    try:
        with socket.create_connection((host, port), timeout=4.0) as s:
            s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            while time.perf_counter() < t_end:
                s.sendall(chunk)
                total_bytes += len(chunk)
        mbps = round((total_bytes * 8) / (duration * 1_000_000.0), 2)
        return mbps, 0, False
    except (socket.timeout, TimeoutError):
        return 0.0, 0, True
    except Exception:
        return 0.0, 0, False


def parse_custom_protocols(
    proto_str: str,
    include_bitswap: bool = False,
    force_bitswap: bool = False,
) -> List[Dict[str, Any]]:
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
        if force_bitswap:
            candidates.append({
                "id": f"custom_{t_num}_{u_num}_bit",
                "name": f"Protocol {t_num}/{u_num} + BitSwap",
                "tcp": t_num,
                "udp": u_num,
                "bitswap": True,
            })
        elif include_bitswap:
            candidates.append({
                "id": f"custom_{t_num}_{u_num}",
                "name": f"Protocol {t_num}/{u_num}",
                "tcp": t_num,
                "udp": u_num,
                "bitswap": False,
            })
            candidates.append({
                "id": f"custom_{t_num}_{u_num}_bit",
                "name": f"Protocol {t_num}/{u_num} + BitSwap",
                "tcp": t_num,
                "udp": u_num,
                "bitswap": True,
            })
        else:
            candidates.append({
                "id": f"custom_{t_num}_{u_num}",
                "name": f"Protocol {t_num}/{u_num}",
                "tcp": t_num,
                "udp": u_num,
                "bitswap": False,
            })
    return candidates



# =============================================================================
# TEARDOWN & CLEANUP HELPERS
# =============================================================================

KNOWN_IRAN_ORIGIN_IPS: Dict[str, str] = {
    "telewebion.ir": "185.165.205.132",
    "tums.ac.ir": "185.143.233.132",
    "shariati.tums.ac.ir": "185.143.234.132",
    "farabi.tums.ac.ir": "194.225.62.74",
    "sina.tums.ac.ir": "194.225.62.69",
    "rhc.ac.ir": "194.225.92.55",
    "miladhospital.com": "79.175.169.140",
    "bahmanhospital.ir": "185.88.153.233",
    "pasteur.ac.ir": "194.225.106.107",
    "sbmu.ac.ir": "2.188.27.94",
    "iums.ac.ir": "194.225.184.101",
    "mums.ac.ir": "185.116.24.163",
    "sums.ac.ir": "185.143.234.132",
    "tbzmed.ac.ir": "80.191.203.10",
    "kmu.ac.ir": "185.144.65.22",
    "filimo.com": "185.147.178.23",
    "aparat.com": "185.147.179.11",
    "namava.ir": "94.182.176.33",
    "ble.ir": "2.189.68.126",
    "eitaa.com": "2.189.58.6",
    "shad.ir": "5.106.11.218",
    "rubika.ir": "5.106.8.151",
    "neshan.org": "185.166.104.6",
    "snapp.ir": "185.143.233.122",
    "tci.ir": "217.218.86.185",
    "irancell.ir": "92.42.50.130",
    "mci.ir": "5.106.4.1",
    "divar.ir": "185.166.104.6",
    "cafebazaar.ir": "185.166.104.93",
}


def resolve_sni_ip(domain: str, fallback: Optional[str] = None) -> str:
    """Dynamically resolve real IPv4 address behind SNI domain with verified fallbacks."""
    clean = domain.strip().lower()
    try:
        ip = socket.gethostbyname(clean)
        if ip and ip.count(".") == 3 and not ip.startswith("127."):
            return ip
    except Exception:
        pass

    if clean in KNOWN_IRAN_ORIGIN_IPS:
        return KNOWN_IRAN_ORIGIN_IPS[clean]

    parts = clean.split(".")
    if len(parts) > 2:
        parent = ".".join(parts[1:])
        if parent in KNOWN_IRAN_ORIGIN_IPS:
            return KNOWN_IRAN_ORIGIN_IPS[parent]

    return fallback or "185.143.233.132"


def stop_waterwall_and_test(
    proc: Optional[subprocess.Popen] = None,
    name: Optional[str] = None,
    ww_cwd: Optional[str] = None,
) -> None:
    """Deterministically terminate ONLY the isolated test WaterWall process.

    CRITICAL SAFETY INVARIANT:
    Never kills or touches production WaterWall or other live tunnels.
    Never wipes system-wide iptables rules.
    Never touches production TUN devices (e.g. wtun1, manual-proto, etc.).
    Only targets the explicit test process (proc) and test directory files.
    """
    # 1. Gracefully terminate provided test process by its explicit PID/pgid
    if proc:
        try:
            pgid = os.getpgid(proc.pid)
            os.killpg(pgid, signal.SIGTERM)
        except Exception:
            pass
        try:
            proc.wait(timeout=0.4)
        except Exception:
            try:
                proc.kill()
            except Exception:
                pass

    # 2. Terminate isolated test instances (Waterwall-test) & test iperf3 only
    for pat in [WATERWALL_TEST_BIN_NAME, "iperf3"]:
        try:
            subprocess.run(["pkill", "-15", "-f", pat], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=0.5)
        except Exception:
            pass
    time.sleep(0.2)
    for pat in [WATERWALL_TEST_BIN_NAME, "iperf3"]:
        try:
            subprocess.run(["pkill", "-9", "-f", pat], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=0.5)
        except Exception:
            pass

    # 3. Clean temporary test config files in test working directory ONLY
    if ww_cwd and name:
        for f in (Path(ww_cwd) / f"_tmp_{name}.json", Path(ww_cwd) / f"_core_{name}.json", Path(ww_cwd) / f"{name}.json"):
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
    lock = threading.RLock()

    @classmethod
    def cancel_timer(cls) -> None:
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
                    cls.iperf_proc.wait(timeout=0.5)
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
                    cls.ww_proc.wait(timeout=0.5)
                except Exception:
                    pass
                cls.ww_proc = None

            for pat in [WATERWALL_TEST_BIN_NAME, "iperf3"]:
                try:
                    subprocess.run(["pkill", "-9", "-f", pat], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=1.0)
                except Exception:
                    pass

    @classmethod
    def auto_teardown(cls, name: str, ww_cwd: str) -> None:
        print_info(f"[{time.strftime('%X')}] [Kharej Agent] Auto-teardown triggered for '{name}' after test window.")
        cls.kill_active_processes()
        stop_waterwall_and_test(None, name, ww_cwd)
        print_success(f"[{time.strftime('%X')}] [Kharej Agent] Auto-teardown complete for '{name}'. WaterWall stopped, control channel restored.")

    @classmethod
    def start_candidate(
        cls,
        name: str,
        ww_bin: str,
        ww_cwd: str,
        tcp_port: int,
        duration: int,
    ) -> None:
        cmd_ww = [ww_bin]
        print_info(f"[{time.strftime('%X')}] [Kharej Agent] Starting WaterWall directly:")
        try:
            cls.ww_proc = subprocess.Popen(
                cmd_ww,
                cwd=ww_cwd,
                start_new_session=True,
                stdout=None,
                stderr=None,
            )
        except Exception as e:
            print_error(f"[{time.strftime('%X')}] [Kharej Agent] Failed to start WaterWall: {e}")
            return

        time.sleep(0.3)
        if cls.ww_proc.poll() is not None:
            print_error(f"[{time.strftime('%X')}] [Kharej Agent] WaterWall exited immediately with code {cls.ww_proc.returncode}")
            return

        # Launch iperf3 server on tcp_port
        iperf_bin = find_iperf3_binary()
        if iperf_bin:
            try:
                cls.iperf_proc = subprocess.Popen(
                    [iperf_bin, "-s", "-p", str(tcp_port)],
                    start_new_session=True,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
            except Exception as e:
                print_warning(f"Failed to start iperf3: {e}")

        # Arm auto-teardown timer (ensure upload, download, and UDP probes complete before reset)
        test_window = (duration * 2) + 12.0
        with cls.lock:
            cls.auto_timer = threading.Timer(
                test_window,
                cls.auto_teardown,
                args=[name, ww_cwd],
            )
            cls.auto_timer.daemon = True
            cls.auto_timer.start()

        print_success(f"[{time.strftime('%X')}] [Kharej Agent] WaterWall (PID {cls.ww_proc.pid}) & iperf3 active on port {tcp_port}. Auto-teardown armed in {test_window:.1f}s.")


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
        p_tcp = int(req.get("protoswap_tcp", 6))
        p_udp = int(req.get("protoswap_udp", 17))
        enable_bitswap = bool(req.get("bitswap", False))
        cand_type = req.get("type", "protoswap")
        duration = int(req.get("duration", 5))
        test_dir = req.get("test_dir")
        private_ip = req.get("private_ip", "10.99.0.1")
        private_ip_2 = req.get("private_ip_2")

        ww_bin, ww_cwd = get_test_waterwall_launch_info(test_dir=test_dir)
        print_info(f"[{time.strftime('%X')}] [Kharej Agent] Preparing candidate: {name} (type: {cand_type}, TCP: {p_tcp}, UDP: {p_udp}, BitSwap: {enable_bitswap}, private_ip: {private_ip}, duration: {duration}s)...")
        print_info(f"[{time.strftime('%X')}] [Kharej Agent] Using isolated test binary: {ww_bin} in {ww_cwd}")

        # 1. Reset any active WaterWall & iperf processes
        FinderAgentState.kill_active_processes()
        stop_waterwall_and_test(None, name, ww_cwd)

        # 2. Generate Kharej configuration inside isolated test directory
        Path(ww_cwd, "log").mkdir(parents=True, exist_ok=True)
        cfg = _generate_candidate_kharej(
            cand_type=cand_type,
            req=req,
            name=name,
            iran_ip=iran_ip,
            kharej_ip=kharej_ip,
            tcp_port=tcp_port,
            p_tcp=p_tcp,
            p_udp=p_udp,
            enable_bitswap=enable_bitswap,
            private_ip=private_ip,
            private_ip_2=private_ip_2,
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

        # 3. Respond 200 OK to Iran BEFORE starting WaterWall so HTTP handshake completes unimpeded
        self._send_json(200, {"status": "ready", "tcp_port": tcp_port})

        # 4. Launch WaterWall and iperf3 in background
        FinderAgentState.start_candidate(name, ww_bin, ww_cwd, tcp_port, duration)

    def _handle_teardown(self, req: Dict[str, Any]) -> None:
        name = req.get("name", "finder-kharej")
        test_dir = req.get("test_dir")
        ww_bin, ww_cwd = get_test_waterwall_launch_info(test_dir=test_dir, auto_download=False)
        print_info(f"[{time.strftime('%X')}] [Kharej Agent] Teardown requested for '{name}'...")
        FinderAgentState.kill_active_processes()
        stop_waterwall_and_test(None, name, ww_cwd)
        print_success(f"[{time.strftime('%X')}] [Kharej Agent] Teardown complete for '{name}'.")
        self._send_json(200, {"status": "stopped"})

    def _handle_apply_winner(self, req: Dict[str, Any]) -> None:
        name = req.get("name", "finder-tunnel")
        test_dir = req.get("test_dir")
        ww_bin, ww_cwd = get_test_waterwall_launch_info(test_dir=test_dir, auto_download=False)
        print_info(f"[{time.strftime('%X')}] [Kharej Agent] Applying winning config '{name}'...")
        FinderAgentState.kill_active_processes()
        stop_waterwall_and_test(None, name, ww_cwd)

        iran_ip = req["iran_ip"]
        kharej_ip = req["kharej_ip"]
        tcp_port = int(req.get("tcp_port", 9000))
        p_tcp = int(req.get("protoswap_tcp", 6))
        p_udp = int(req.get("protoswap_udp", 17))
        enable_bitswap = bool(req.get("bitswap", False))
        cand_type = req.get("type", "protoswap")
        private_ip = req.get("private_ip", "10.99.0.1")
        private_ip_2 = req.get("private_ip_2")

        cfg = _generate_candidate_kharej(
            cand_type=cand_type,
            req=req,
            name=name,
            iran_ip=iran_ip,
            kharej_ip=kharej_ip,
            tcp_port=tcp_port,
            p_tcp=p_tcp,
            p_udp=p_udp,
            enable_bitswap=enable_bitswap,
            private_ip=private_ip,
            private_ip_2=private_ip_2,
        )
        filepath = Path(ww_cwd) / f"{name}.json"
        core_path = Path(ww_cwd) / "core.json"
        saved = save_waterwall_config(cfg, filepath=filepath, name=name, auto_core=True, core_path=core_path)
        print_success(f"[{time.strftime('%X')}] [Kharej Agent] Saved {saved} and synced to {core_path}.")
        self._send_json(200, {"status": "applied", "file": str(saved)})


def run_finder_server(port: int = 8088, host: str = "0.0.0.0", test_dir: Optional[str] = None) -> int:
    """Start the Kharej control agent daemon."""
    # Pre-provision test WaterWall binary in isolated directory
    ww_bin, ww_cwd = get_test_waterwall_launch_info(test_dir=test_dir)
    print_info(f"Isolated WaterWall benchmark instance: {ww_bin} (working dir: {ww_cwd})")

    # Ensure iperf3 is available on Kharej server
    iperf_bin = ensure_iperf3_installed()
    if iperf_bin:
        print_success(f"iperf3 benchmark engine ready: {iperf_bin}")
    else:
        print_warning("iperf3 is not installed on this host! Please install with 'apt install -y iperf3'.")

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
) -> Tuple[float, int, bool]:
    """Run iperf3 client probe against local WaterWall listener (127.0.0.1:port).
    
    Returns (throughput_mbps, retransmissions, timed_out).
    """
    iperf_bin = find_iperf3_binary()
    if not iperf_bin:
        return 0.0, 0, False

    cmd = [iperf_bin, "-c", "127.0.0.1", "-p", str(port), "-t", str(duration), "-M", "1300", "-J"]
    if reverse:
        cmd.append("-R")

    try:
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=duration + 8)
        if proc.returncode != 0:
            err_msg = ""
            try:
                err_data = json.loads(proc.stdout)
                err_msg = err_data.get("error", "")
            except Exception:
                pass
            if not err_msg:
                err_msg = (proc.stderr or proc.stdout or "").strip()
                if err_msg:
                    err_msg = err_msg.splitlines()[0]
            print_warning(f"iperf3 returned code {proc.returncode}: {err_msg}")
            return 0.0, 0, False
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
        return mbps, retr, False
    except subprocess.TimeoutExpired:
        # Expected behavior when a candidate protocol is blocked/dropped by DPI
        return 0.0, 0, True
    except Exception as e:
        print_warning(f"iperf3 probe exception: {e}")
        return 0.0, 0, False


def _run_iperf_udp_test(
    port: int,
    duration: int = 3,
    target_bandwidth: str = "0",
) -> Tuple[float, float, float]:
    """Run iperf3 UDP client probe against local WaterWall listener (127.0.0.1:port).
    
    Returns (throughput_mbps, lost_percent, jitter_ms).
    """
    iperf_bin = find_iperf3_binary()
    if not iperf_bin:
        return 0.0, 100.0, 0.0

    cmd = [
        iperf_bin,
        "-c", "127.0.0.1",
        "-p", str(port),
        "-u",
        "-l", "1200",
        "-b", str(target_bandwidth),
        "-t", str(duration),
        "-J",
    ]

    try:
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=duration + 8)
        if proc.returncode != 0:
            err_msg = ""
            try:
                err_data = json.loads(proc.stdout)
                err_msg = err_data.get("error", "")
            except Exception:
                pass
            if not err_msg:
                err_msg = (proc.stderr or proc.stdout or "").strip()
                if err_msg:
                    err_msg = err_msg.splitlines()[0]
            print_warning(f"iperf3 UDP returned code {proc.returncode}: {err_msg}")
            return 0.0, 100.0, 0.0
        data = json.loads(proc.stdout)
        end = data.get("end", {})
        
        sum_data = end.get("sum", {})
        bps = sum_data.get("bits_per_second", 0.0)
        lost_pct = sum_data.get("lost_percent", 0.0)
        jitter = sum_data.get("jitter_ms", 0.0)

        if not bps and "streams" in end and len(end["streams"]) > 0:
            stream_udp = end["streams"][0].get("udp", {})
            bps = stream_udp.get("bits_per_second", 0.0)
            lost_pct = stream_udp.get("lost_percent", 0.0)
            jitter = stream_udp.get("jitter_ms", 0.0)

        # If 100% loss or no packets arrived, throughput received is 0.0
        if lost_pct >= 99.9:
            mbps = 0.0
        else:
            mbps = round(bps / 1_000_000.0, 2)

        lost_pct = round(lost_pct, 1)
        jitter = round(jitter, 2)
        return mbps, lost_pct, jitter
    except subprocess.TimeoutExpired:
        # Expected behavior when a candidate protocol is blocked/dropped by DPI
        return 0.0, 100.0, 0.0
    except Exception as e:
        print_warning(f"iperf3 UDP probe exception: {e}")
        return 0.0, 100.0, 0.0


def run_finder_client(
    iran_ip: str,
    kharej_ip: str,
    control_port: int = 8088,
    tcp_port: int = 9001,
    name: str = "finder-tunnel",
    duration: int = 5,
    preset: str = "top",
    custom_protocols: Optional[str] = None,
    bitswap: bool = False,
    include_bitswap: bool = False,
    auto_apply: bool = False,
    test_dir: Optional[str] = None,
    private_ip: str = "10.99.0.1",
    private_ip_2: Optional[str] = None,
    tls_domain: Optional[str] = None,
    tls_cert: Optional[str] = None,
    tls_key: Optional[str] = None,
    sni: str = "telewebion.ir",
    snis: Optional[str] = None,
    sni_file: Optional[str] = None,
) -> int:
    """Orchestrate protocol sweep against Kharej agent."""
    # Ensure local iperf3 is available on Iran (fallback to native socket if missing)
    local_iperf = ensure_iperf3_installed()
    if not local_iperf:
        print_info("iperf3 is not installed on Iran orchestrator; native Python socket probe engine will be used.")

    clean_iran = validate_ip(iran_ip)
    clean_kharej = validate_ip(kharej_ip)
    clean_port = validate_port(tcp_port)
    clean_private_ip = validate_ip(private_ip)
    clean_private_ip_2 = validate_ip(private_ip_2) if private_ip_2 else None

    agent_url = f"http://{clean_kharej}:{control_port}"
    print("=" * 76)
    print("⚡ WATERWALL BEST TUNNEL FINDER - AUTONOMOUS SWEEP")
    print("=" * 76)
    print(f"Iran IP:        {clean_iran}")
    print(f"Kharej IP:      {clean_kharej}")
    print(f"Control Agent:  {agent_url}")
    print(f"Test Port:      {clean_port}")
    print(f"Test Private IP:{clean_private_ip}")
    print(f"Test Duration:  {duration}s per direction")

    # 1. Verify Kharej Agent connectivity
    print_info(f"Connecting to Kharej Agent at {agent_url}...")
    try:
        health = _get_json(f"{agent_url}/health")
        print_success(f"Kharej Agent reachable! (WaterWall: {health.get('waterwall')}, iperf3: {health.get('iperf3')})")
        if not health.get("iperf3"):
            print_info("Kharej Agent does not have iperf3; native Python socket engine will be used.")
    except Exception as e:
        print_error(f"Cannot reach Kharej Agent at {agent_url}: {e}")
        print_error(f"Ensure 'finder server --port {control_port}' is running on Kharej and port is open.")
        return 1

    # 2. Select Candidates
    is_sni_sweep = False
    if snis or sni_file or preset in ("sni", "hospital", "hospitals"):
        is_sni_sweep = True
        raw_list = []
        if snis:
            raw_list = [s.strip() for s in snis.split(",") if s.strip()]
        elif sni_file:
            p = Path(sni_file)
            if p.exists():
                with open(p, "r", encoding="utf-8") as f:
                    raw_list = [line.strip() for line in f if line.strip() and not line.startswith("#")]
            else:
                print_error(f"SNI file not found: {sni_file}")
                return 1
        elif preset in ("hospital", "hospitals"):
            raw_list = list(DEFAULT_HOSPITAL_SNIS)
        else:
            raw_list = list(DEFAULT_IRAN_SNIS)

        target_label = "Hospital" if preset in ("hospital", "hospitals") else "SNI"
        print_info(f"Targeting {len(raw_list)} {target_label} domain(s) with Reverse Reality + HD + Fisher architecture...")
        candidates = []
        for d in raw_list:
            origin_ip = resolve_sni_ip(d)
            candidates.append({
                "id": f"rr_hd_cf_{d.replace('.', '_')}",
                "name": f"RR+HD+Fisher ({d})",
                "type": "reverse_reality",
                "domain": d,
                "white_ip": origin_ip,
                "password": "arch1234net",
                "use_halfduplex": True,
                "use_fisher": True,
            })
    elif custom_protocols:
        candidates = parse_custom_protocols(
            custom_protocols,
            include_bitswap=include_bitswap,
            force_bitswap=bitswap,
        )
    elif preset == "methods":
        # Stage 1: Base architectures screening
        candidates = [
            {"id": "rev_reality", "name": f"Reverse Reality ({sni})", "type": "reverse_reality", "domain": sni, "white_ip": "185.165.205.129", "password": "arch1234net"},
            {"id": "bitswap_rst", "name": "BitSwap (PSH <-> RST)", "type": "bitswap", "tcp": 6, "udp": 17, "bitswap": True, "pattern": "psh/rst"},
            {"id": "bitswap_cwr", "name": "BitSwap (PSH <-> CWR)", "type": "bitswap", "tcp": 6, "udp": 17, "bitswap": True, "pattern": "psh/cwr"},
            {"id": "protoswap_esp", "name": "ProtoSwap ESP (50/51)", "type": "protoswap", "tcp": 50, "udp": 51, "bitswap": False},
            {"id": "protoswap_gre", "name": "ProtoSwap GRE (47/136)", "type": "protoswap", "tcp": 47, "udp": 136, "bitswap": False},
            {"id": "protoswap_253", "name": "ProtoSwap 253/252", "type": "protoswap", "tcp": 253, "udp": 252, "bitswap": False},
            {"id": "udp_reverse", "name": "UDP Reverse", "type": "udp_reverse", "xor_key": 153},
        ]
        if tls_domain and tls_cert:
            candidates.append({
                "id": "tls_reverse",
                "name": f"TLS Reverse ({tls_domain})",
                "type": "tls_reverse",
                "sni": tls_domain,
                "cert": tls_cert,
                "key": tls_key or tls_cert,
            })
        else:
            print_info("TLS Reverse skipped from sweep (supply --tls-domain and --tls-cert to benchmark).")
    else:
        candidates = list(CANDIDATES_PRESETS.get(preset, CANDIDATES_PRESETS["top"]))
        if bitswap:
            # Filter to BitSwap candidates, or force bitswap if none present
            bit_cands = [c for c in candidates if c.get("bitswap", False)]
            if bit_cands:
                candidates = bit_cands
            else:
                updated_cands = []
                for c in candidates:
                    c_copy = dict(c)
                    c_copy["bitswap"] = True
                    if not c_copy["name"].endswith("+ BitSwap"):
                        c_copy["name"] = f"{c_copy['name']} + BitSwap"
                    updated_cands.append(c_copy)
                candidates = updated_cands
        elif include_bitswap:
            expanded = []
            seen_ids = set()
            for c in candidates:
                if c["id"] not in seen_ids:
                    expanded.append(c)
                    seen_ids.add(c["id"])
                bit_id = f"{c['id']}_bit" if not c.get("bitswap") else c["id"]
                if not c.get("bitswap") and bit_id not in seen_ids:
                    c_bit = dict(c)
                    c_bit["id"] = bit_id
                    c_bit["name"] = f"{c['name']} + BitSwap"
                    c_bit["bitswap"] = True
                    expanded.append(c_bit)
                    seen_ids.add(bit_id)
            candidates = expanded

    total = len(candidates)
    print_info(f"Testing {total} protocol candidates ({preset} preset)...\n")

    ww_bin, ww_cwd = get_test_waterwall_launch_info(test_dir=test_dir)
    print_info(f"Using isolated WaterWall test binary: {ww_bin} (working dir: {ww_cwd})")
    results: List[Dict[str, Any]] = []

    # 3. Execution Sweep Loop Helper
    def _test_candidate(idx: int, total_count: int, cand: Dict[str, Any]) -> None:
        cid = cand["id"]
        cname = cand["name"]
        p_tcp = cand.get("tcp", 6)
        p_udp = cand.get("udp", 17)
        cand_bitswap = bool(cand.get("bitswap", False))
        cand_type = cand.get("type", "protoswap")
        bs_str = "YES" if cand_bitswap else "NO"

        print(f"\n{'=' * 76}")
        print(f"[*] [{idx}/{total_count}] Testing {cname} (type: {cand_type}, TCP: {p_tcp}, UDP: {p_udp}, BitSwap: {bs_str})...")
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
            return

        print_info(f"Signaling Kharej Agent to prepare candidate (TCP: {p_tcp}, UDP: {p_udp}, BitSwap: {bs_str})...")
        try:
            prep_payload = {
                "name": name,
                "iran_ip": clean_iran,
                "kharej_ip": clean_kharej,
                "tcp_port": clean_port,
                "protoswap_tcp": p_tcp,
                "protoswap_udp": p_udp,
                "bitswap": cand_bitswap,
                "type": cand_type,
                "pattern": cand.get("pattern", "psh/cwr"),
                "domain": cand.get("domain", "telewebion.ir"),
                "white_ip": cand.get("white_ip") or resolve_sni_ip(cand.get("domain", "telewebion.ir")),
                "password": cand.get("password", "arch1234net"),
                "sni": cand.get("sni", cand.get("domain", "telewebion.ir")),
                "xor_key": cand.get("xor_key", 90),
                "use_halfduplex": bool(cand.get("use_halfduplex", False)),
                "use_fisher": bool(cand.get("use_fisher", False)),
                "use_mux": bool(cand.get("use_mux", False)),
                "packet_duplicate": int(cand.get("packet_duplicate", 1)),
                "duration": duration,
                "private_ip": clean_private_ip,
                "private_ip_2": clean_private_ip_2,
            }
            if test_dir:
                prep_payload["test_dir"] = test_dir
            prep = _post_json(f"{agent_url}/prepare", prep_payload, timeout=15.0)
            if prep.get("status") != "ready":
                print_warning(f"    Kharej failed to prepare: {prep}")
                return
        except Exception as e:
            print_error(f"    Failed to contact Kharej agent: {e}")
            return

        # Step 3: Generate Iran configuration and start local WaterWall SECOND
        Path(ww_cwd, "log").mkdir(parents=True, exist_ok=True)
        cfg_iran = _generate_candidate_iran(
            cand_type=cand_type,
            cand=cand,
            name=name,
            clean_iran=clean_iran,
            clean_kharej=clean_kharej,
            clean_port=clean_port,
            p_tcp=p_tcp,
            p_udp=p_udp,
            cand_bitswap=cand_bitswap,
            clean_private_ip=clean_private_ip,
            clean_private_ip_2=clean_private_ip_2,
            ww_cwd=ww_cwd,
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
                return

            time.sleep(1.5)  # Wait for tunnel initialization

            # Step 4: Run Latency and Bandwidth Probes
            rtt_ms = measure_tcp_rtt(clean_port, timeout=3.0)
            rtt_str = f"{rtt_ms:.0f} ms" if rtt_ms is not None else "timeout"
            print_info(f"TCP Handshake Latency: {rtt_str}")

            has_iperf = bool(find_iperf3_binary() and health.get("iperf3"))
            # Test 1: Upload (Iran -> Kharej)
            print_info(f"Running TCP upload probe (Iran -> Kharej, {duration}s)...")
            if has_iperf:
                up_mbps, retr, timed_out = _run_iperf_test(clean_port, duration=duration, reverse=False)
            else:
                up_mbps, retr, timed_out = _run_native_socket_test(clean_port, duration=duration)

            if timed_out:
                print_info("    Control connection timed out (traffic blocked by DPI) -> candidate marked BLOCKED.")
                down_mbps = 0.0
                udp_mbps = 0.0
                udp_loss = 100.0
                udp_jitter = 0.0
            else:
                time.sleep(1.0)
                # Test 2: Download (Kharej -> Iran)
                print_info(f"Running TCP download probe (Kharej -> Iran, {duration}s)...")
                if has_iperf:
                    down_mbps, _, _ = _run_iperf_test(clean_port, duration=duration, reverse=True)
                else:
                    down_mbps = up_mbps

                time.sleep(1.0)
                # Test 3: UDP Probe (Iran -> Kharej)
                udp_dur = min(duration, 3)
                print_info(f"Running UDP probe (Iran -> Kharej, {udp_dur}s)...")
                if has_iperf:
                    udp_mbps, udp_loss, udp_jitter = _run_iperf_udp_test(clean_port, duration=udp_dur, target_bandwidth="0")
                else:
                    udp_mbps, udp_loss, udp_jitter = up_mbps, 0.0, 0.0

            rtt_val = rtt_ms if rtt_ms is not None else 999.0
            loss_factor = max(0.0, 1.0 - (udp_loss / 100.0))
            if up_mbps > 0 or down_mbps > 0:
                score = round((up_mbps + down_mbps) * (1.0 - (loss_factor * 0.2)) - (rtt_val * 0.05), 2)
                score = max(score, 0.0)
            else:
                score = 0.0

            if up_mbps == 0 and down_mbps == 0 and udp_mbps == 0:
                status_label = "BLOCKED ❌"
            elif udp_loss >= 99.0 and (up_mbps > 0 or down_mbps > 0):
                status_label = "TCP ONLY ⚠️"
            elif retr > 0 or udp_loss > 10.0:
                status_label = "DEGRADED ⚠️"
            else:
                status_label = "ACTIVE ✅"

            results.append({
                "cand": cand,
                "upload": up_mbps,
                "download": down_mbps,
                "udp": udp_mbps,
                "udp_loss": udp_loss,
                "udp_jitter": udp_jitter,
                "rtt": rtt_ms,
                "retr": retr,
                "score": score,
                "status": status_label,
            })

            print(f"\n    -> TCP Up: {up_mbps:6.2f} Mbps | TCP Down: {down_mbps:6.2f} Mbps | UDP: {udp_mbps:6.2f} Mbps (Loss: {udp_loss:4.1f}%) | RTT: {rtt_str} | {status_label}")

        finally:
            print_info(f"Resetting WaterWall on Iran...")
            stop_waterwall_and_test(local_ww, name, ww_cwd)
            local_ww = None

            print_info(f"Awaiting Kharej reset and restoring control channel...")
            teardown_payload = {"name": name}
            if test_dir:
                teardown_payload["test_dir"] = test_dir
            for check_attempt in range(15):
                try:
                    _post_json(f"{agent_url}/teardown", teardown_payload, timeout=1.5)
                    break
                except Exception:
                    time.sleep(1.0)

        time.sleep(0.5)

    # Run Stage 1 candidates
    for idx, cand in enumerate(candidates, 1):
        _test_candidate(idx, total, cand)

    # Adaptive Stage 2: Deep Optimization of working tunnels (only for methods sweep)
    if preset == "methods" and not is_sni_sweep:
        working_types = {r["cand"].get("type") for r in results if r["upload"] > 0 or r["download"] > 0}
        stage2_cands = []
        if "reverse_reality" in working_types:
            stage2_cands.extend([
                {"id": "rev_reality_hd", "name": f"Reverse Reality + HD ({sni})", "type": "reverse_reality", "domain": sni, "white_ip": resolve_sni_ip(sni), "password": "arch1234net", "use_halfduplex": True},
                {"id": "rev_reality_fisher", "name": f"Reverse Reality + Fisher ({sni})", "type": "reverse_reality", "domain": sni, "white_ip": resolve_sni_ip(sni), "password": "arch1234net", "use_fisher": True},
                {"id": "rev_reality_mux", "name": f"Reverse Reality + MUX ({sni})", "type": "reverse_reality", "domain": sni, "white_ip": resolve_sni_ip(sni), "password": "arch1234net", "use_mux": True},
                {"id": "rev_reality_hd_cf", "name": f"Reverse Reality + HD + Fisher ({sni})", "type": "reverse_reality", "domain": sni, "white_ip": resolve_sni_ip(sni), "password": "arch1234net", "use_halfduplex": True, "use_fisher": True},
                {"id": "rev_reality_hd_mux", "name": f"Reverse Reality + HD + MUX ({sni})", "type": "reverse_reality", "domain": sni, "white_ip": resolve_sni_ip(sni), "password": "arch1234net", "use_halfduplex": True, "use_mux": True},
                {"id": "rev_reality_bazaar", "name": "Reverse Reality + HD (cafebazaar.ir)", "type": "reverse_reality", "domain": "cafebazaar.ir", "white_ip": resolve_sni_ip("cafebazaar.ir"), "password": "arch1234net", "use_halfduplex": True},
                {"id": "rev_reality_snapp", "name": "Reverse Reality + HD (snapp.ir)", "type": "reverse_reality", "domain": "snapp.ir", "white_ip": resolve_sni_ip("snapp.ir"), "password": "arch1234net", "use_halfduplex": True},
                {"id": "rev_reality_divar", "name": "Reverse Reality + HD (divar.ir)", "type": "reverse_reality", "domain": "divar.ir", "white_ip": resolve_sni_ip("divar.ir"), "password": "arch1234net", "use_halfduplex": True},
            ])
        if "bitswap" in working_types:
            stage2_cands.extend([
                {"id": "bitswap_rst", "name": "BitSwap (PSH <-> RST)", "type": "bitswap", "tcp": 6, "udp": 17, "bitswap": True, "pattern": "psh/rst"},
                {"id": "bitswap_cwr_ece", "name": "BitSwap (CWR <-> ECE)", "type": "bitswap", "tcp": 6, "udp": 17, "bitswap": True, "pattern": "cwr/ece"},
                {"id": "bitswap_ack_fin", "name": "BitSwap (ACK <-> FIN)", "type": "bitswap", "tcp": 6, "udp": 17, "bitswap": True, "pattern": "ack/fin"},
            ])
        if "protoswap" in working_types:
            stage2_cands.extend([
                {"id": "protoswap_direct", "name": "ProtoSwap 50 (Direct No-Mux)", "type": "protoswap", "tcp": 50, "udp": 51, "use_mux": False},
                {"id": "protoswap_esp_rst", "name": "ProtoSwap 50 + BitSwap RST", "type": "protoswap", "tcp": 50, "udp": 51, "bitswap": True, "pattern": "psh/rst"},
            ])

        if stage2_cands:
            print("\n" + "=" * 76)
            print("⚡ STAGE 2: DEEP OPTIMIZATION OF WORKING ARCHITECTURES")
            print("=" * 76)
            print_info(f"Testing {len(stage2_cands)} variations of the working tunnels...\n")
            s2_total = len(stage2_cands)
            for s2_idx, s2_cand in enumerate(stage2_cands, 1):
                _test_candidate(s2_idx, s2_total, s2_cand)

    # 4. Results & Leaderboard
    if not results:
        print_error("No candidates were successfully tested.")
        return 1

    # Sort descending by quality score
    results.sort(key=lambda r: r["score"], reverse=True)

    print("\n" + "=" * 115)
    if is_sni_sweep:
        print("🏆 WATERWALL SNI BENCHMARK LEADERBOARD (Reverse Reality + HD + Fisher)")
        print("=" * 115)
        print(f"{'Rank':<5} | {'SNI Domain':<28} | {'Origin IP':<15} | {'TCP Up':<11} | {'TCP Down':<11} | {'Loss':<6} | {'RTT':<7} | {'Status'}")
        print("-" * 115)
        for i, r in enumerate(results, 1):
            c = r["cand"]
            sni_name = c.get("domain", c["name"])
            origin_ip = c.get("white_ip", "N/A")
            rtt_val = f"{r['rtt']:.0f}ms" if r.get("rtt") is not None else "N/A"
            badge = "BEST ⭐" if i == 1 and r["score"] > 0 else r["status"]
            print(f"#{i:<4} | {sni_name:<28} | {origin_ip:<15} | {r['upload']:>6.2f} Mbps | {r['download']:>6.2f} Mbps | {r['udp_loss']:>5.1f}% | {rtt_val:>7} | {badge}")
    else:
        print("🏆 WATERWALL BENCHMARK & PROTOCOL SWEEP LEADERBOARD")
        print("=" * 115)
        print(f"{'Rank':<5} | {'Candidate':<28} | {'Type':<15} | {'TCP Up':<11} | {'TCP Down':<11} | {'UDP Up':<11} | {'Loss':<6} | {'RTT':<7} | {'Status'}")
        print("-" * 115)
        for i, r in enumerate(results, 1):
            c = r["cand"]
            ctype = c.get("type", "protoswap")
            rtt_val = f"{r['rtt']:.0f}ms" if r.get("rtt") is not None else "N/A"
            badge = "BEST ⭐" if i == 1 and r["score"] > 0 else r["status"]
            print(f"#{i:<4} | {c['name']:<28} | {ctype:<15} | {r['upload']:>6.2f} Mbps | {r['download']:>6.2f} Mbps | {r['udp']:>6.2f} Mbps | {r['udp_loss']:>5.1f}% | {rtt_val:>7} | {badge}")

    print("=" * 115)

    winner = results[0]
    if winner["score"] == 0:
        print_warning("All tested methods yielded 0 Mbps. Check firewall/security groups on both servers.")
        return 0

    best_cand = winner["cand"]
    best_cand_bitswap = bool(best_cand.get("bitswap", False))
    best_cand_type = best_cand.get("type", "protoswap")
    print_success(f"Winner: {best_cand['name']} ({best_cand_type}) with score {winner['score']}!")

    # 5. Apply Winning Configuration
    if auto_apply:
        print_info(f"Applying winning configuration '{name}.json' to Iran and Kharej...")
        best_cfg_iran = _generate_candidate_iran(
            cand_type=best_cand_type,
            cand=best_cand,
            name=name,
            clean_iran=clean_iran,
            clean_kharej=clean_kharej,
            clean_port=clean_port,
            p_tcp=best_cand.get("tcp", 253),
            p_udp=best_cand.get("udp", 252),
            cand_bitswap=best_cand_bitswap,
            clean_private_ip=clean_private_ip,
            clean_private_ip_2=clean_private_ip_2,
            ww_cwd=ww_cwd,
        )
        filepath = Path(ww_cwd) / f"{name}.json"
        core_path = Path(ww_cwd) / "core.json"
        saved_iran = save_waterwall_config(best_cfg_iran, filepath=filepath, name=name, auto_core=True, core_path=core_path)
        print_success(f"Activated in test dir: {saved_iran} (synced to {core_path})")

        # Signal Kharej to apply in isolated test dir
        apply_payload = {
            "name": name,
            "iran_ip": clean_iran,
            "kharej_ip": clean_kharej,
            "tcp_port": clean_port,
            "protoswap_tcp": best_cand.get("tcp", 253),
            "protoswap_udp": best_cand.get("udp", 252),
            "bitswap": best_cand_bitswap,
            "type": best_cand_type,
            "pattern": best_cand.get("pattern", "psh/cwr"),
            "domain": best_cand.get("domain", "telewebion.ir"),
            "white_ip": best_cand.get("white_ip", "185.165.205.129"),
            "password": best_cand.get("password", "arch1234net"),
            "sni": best_cand.get("sni", best_cand.get("domain", "telewebion.ir")),
            "xor_key": best_cand.get("xor_key", 90),
            "use_grpc": bool(best_cand.get("use_grpc", False)),
            "use_halfduplex": bool(best_cand.get("use_halfduplex", False)),
            "grpc_concurrency": int(best_cand.get("grpc_concurrency", 64)),
            "private_ip": clean_private_ip,
            "private_ip_2": clean_private_ip_2,
        }
        if test_dir:
            apply_payload["test_dir"] = test_dir
        try:
            resp = _post_json(f"{agent_url}/apply_winner", apply_payload)
            print_success(f"Activated on Kharej in test dir: {resp.get('file', name + '.json')} (synced to core.json)")
        except Exception as e:
            print_warning(f"Could not apply to Kharej test directory: {e}")
    else:
        print_info(f"\n[INFO] Auto-apply disabled (inspection mode). Production configurations remain untouched.")
        top_type = best_cand.get("type", "protoswap")
        if top_type == "protoswap":
            proto_info = f" (TCP proto: {best_cand.get('tcp', 253)}, UDP proto: {best_cand.get('udp', 252)}, BitSwap: {'YES' if best_cand_bitswap else 'NO'})"
        elif top_type == "bitswap":
            proto_info = f" (BitSwap Pattern: {best_cand.get('pattern', 'psh/rst')})"
        elif top_type == "reverse_reality":
            proto_info = f" (Reality SNI: {best_cand.get('domain', 'telewebion.ir')})"
        else:
            proto_info = f" (Type: {top_type})"
        print_info(f"Top Candidate:  {best_cand['name']}{proto_info}")
        print_info("To automatically apply the winning configuration in the isolated test directory, re-run with '--apply'.")

    return 0
