"""Validation utilities for IP addresses, ports, and domains."""

import ipaddress
import re
from typing import List


def validate_port(port: int | str) -> int:
    """Validate a network port number (1-65535)."""
    try:
        p = int(port)
        if not (1 <= p <= 65535):
            raise ValueError(f"Port must be between 1 and 65535, got {p}")
        return p
    except ValueError as e:
        raise ValueError(f"Invalid port '{port}': {e}") from e


def validate_ports_list(ports_input: str | List[int] | List[str]) -> List[int]:
    """Validate and parse a comma-separated or list of ports."""
    if isinstance(ports_input, str):
        raw_ports = [p.strip() for p in ports_input.split(",") if p.strip()]
    else:
        raw_ports = [str(p).strip() for p in ports_input]

    return [validate_port(p) for p in raw_ports]


def validate_ip(ip: str) -> str:
    """Validate an IPv4 or IPv6 address or CIDR notation."""
    clean_ip = ip.strip()
    if "/" in clean_ip:
        ipaddress.ip_network(clean_ip, strict=False)
    else:
        ipaddress.ip_address(clean_ip)
    return clean_ip


def validate_domain(domain: str) -> str:
    """Basic validation for domain name / SNI."""
    d = domain.strip()
    if not d or len(d) > 253:
        raise ValueError(f"Invalid domain length: {domain}")
    # Regex check for standard domain / hostname
    pattern = r"^(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$"
    if not re.match(pattern, d) and d != "localhost":
        raise ValueError(f"Invalid domain name format: {domain}")
    return d
