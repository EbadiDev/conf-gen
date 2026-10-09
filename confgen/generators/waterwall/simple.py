"""Waterwall Simple Port Forwarding Configuration Generator."""

from typing import Any, Dict
from confgen.core.validator import validate_ip, validate_port


def generate_simple_config(
    config_name: str,
    protocol: str,
    start_port: int,
    end_port: int,
    destination_ip: str,
    destination_port: int,
) -> Dict[str, Any]:
    """Generate simple port-forwarding configuration for TCP or UDP."""
    proto = protocol.lower()
    if proto not in ("tcp", "udp"):
        raise ValueError(f"Protocol must be 'tcp' or 'udp', got {protocol}")

    val_start = validate_port(start_port)
    val_end = validate_port(end_port)
    val_dest_port = validate_port(destination_port)
    clean_dest_ip = validate_ip(destination_ip)

    listener_type = "TcpListener" if proto == "tcp" else "UdpListener"
    connector_type = "TcpConnector" if proto == "tcp" else "UdpConnector"

    listen_addr = "::" if ":" in clean_dest_ip else "0.0.0.0"
    port_spec = val_start if val_start == val_end else [val_start, val_end]

    return {
        "name": config_name,
        "nodes": [
            {
                "name": "input",
                "type": listener_type,
                "settings": {
                    "address": listen_addr,
                    "port": port_spec,
                    "nodelay": True,
                },
                "next": "output",
            },
            {
                "name": "output",
                "type": connector_type,
                "settings": {
                    "nodelay": True,
                    "address": clean_dest_ip,
                    "port": val_dest_port,
                },
            },
        ],
    }
