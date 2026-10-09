"""Waterwall Core Settings Configuration Generator."""

from typing import Any, Dict, List, Optional


def generate_core_config(
    config_paths: Optional[List[str]] = None,
    loglevel: str = "WARN",
    console: bool = True,
    workers: int = 0,
    ram_profile: str = "server",
    mtu: int = 1400,
    libs_path: str = "libs/",
    log_path: str = "log/",
) -> Dict[str, Any]:
    """Generate a WaterWall core.json settings configuration.

    WaterWall executable requires core settings JSON as its top-level entry point,
    which references the actual tunnel configurations in its 'configs' array.
    """
    configs = list(config_paths or [])
    return {
        "log": {
            "path": log_path,
            "internal": {"loglevel": loglevel, "console": console},
            "core": {"loglevel": loglevel, "console": console},
            "network": {"loglevel": loglevel, "console": console},
            "dns": {"loglevel": loglevel, "console": False},
        },
        "dns": {},
        "misc": {
            "workers": workers,
            "ram-profile": ram_profile,
            "mtu": mtu,
            "libs-path": libs_path,
        },
        "configs": configs,
    }
