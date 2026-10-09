"""Common output, file system, and formatting utilities."""

import json
from pathlib import Path
from typing import Any, Dict


# ANSI Color Codes
RED = "\033[0;31m"
GREEN = "\033[0;32m"
YELLOW = "\033[1;33m"
BLUE = "\033[0;34m"
NC = "\033[0m"


def print_info(msg: str) -> None:
    print(f"{BLUE}[INFO]{NC} {msg}")


def print_success(msg: str) -> None:
    print(f"{GREEN}[SUCCESS]{NC} {msg}")


def print_warning(msg: str) -> None:
    print(f"{YELLOW}[WARNING]{NC} {msg}")


def print_error(msg: str) -> None:
    print(f"{RED}[ERROR]{NC} {msg}")


def resolve_variables(config: Dict[str, Any]) -> Dict[str, Any]:
    """Resolve $variable$ tokens within node settings using config['variables'].

    Preserves the top-level 'variables' dictionary for documentation, but
    ensures all node settings contain concrete data types (integers, strings, lists)
    as required by WaterWall's native C++ JSON schema parser.
    """
    vars_map = config.get("variables", {})
    if not vars_map or "nodes" not in config:
        return config

    def _resolve(val: Any) -> Any:
        if isinstance(val, dict):
            return {k: _resolve(v) for k, v in val.items()}
        elif isinstance(val, list):
            return [_resolve(v) for v in val]
        elif isinstance(val, str):
            if val.startswith("$") and val.endswith("$") and val.count("$") == 2:
                var_key = val[1:-1]
                if var_key in vars_map:
                    return vars_map[var_key]
            elif "$" in val:
                for k, v in vars_map.items():
                    token = f"${k}$"
                    if token in val:
                        val = val.replace(token, str(v))
                return val
            return val
        return val

    config["nodes"] = _resolve(config["nodes"])
    return config


def write_json(data: Dict[str, Any], filepath: str | Path, indent: int = 2) -> Path:
    """Safely write JSON configuration to a destination file."""
    if "variables" in data and "nodes" in data:
        data = resolve_variables(data)

    p = Path(filepath)
    if not p.suffix:
        p = p.with_suffix(".json")
    
    p.parent.mkdir(parents=True, exist_ok=True)
    with open(p, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=indent, ensure_ascii=False)
        f.write("\n")
    
    print_success(f"Configuration written: {p.resolve()}")
    return p


def update_core_json(config_name: str, core_path: str | Path = "core.json") -> None:
    """Add generated config to core.json if present."""
    cp = Path(core_path)
    cfg_filename = f"{config_name}.json" if not config_name.endswith(".json") else config_name
    
    if not cp.exists():
        initial_data = {
            "log": {
                "path": "log/",
                "internal": {"loglevel": "WARN", "console": False},
                "core": {"loglevel": "WARN", "console": False},
                "network": {"loglevel": "WARN", "console": False},
                "dns": {"loglevel": "WARN", "console": False},
            },
            "dns": {},
            "misc": {
                "workers": 0,
                "ram-profile": "server",
                "mtu": 1400,
                "libs-path": "libs/",
            },
            "configs": [cfg_filename],
        }
        with open(cp, "w", encoding="utf-8") as f:
            json.dump(initial_data, f, indent=4)
        print_info(f"Created core.json with {cfg_filename}")
        return

    try:
        with open(cp, "r", encoding="utf-8") as f:
            data = json.load(f)
        
        configs = data.get("configs", [])
        if cfg_filename not in configs:
            configs.append(cfg_filename)
            data["configs"] = configs
            with open(cp, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=4)
            print_info(f"Added {cfg_filename} to {cp}")
    except Exception as e:
        print_warning(f"Failed to update {cp}: {e}")
