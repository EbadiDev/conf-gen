"""Waterwall UDP Reverse Configuration Generator (RawSocket + Obfuscator + TunDevice)."""

from typing import Any, Dict
from confgen.core.validator import validate_ip, validate_port


def generate_udp_reverse_iran(
    config_name: str,
    iran_public_ip: str,
    kharej_public_ip: str,
    listen_port: int,
    tunnel_port: int = 443,
    tun_ip_iran: str = "10.20.1.1",
    tun_ip_kharej: str = "10.20.1.2",
    xor_key: int = 153,
    reverse_secret: str = "begapour",
) -> Dict[str, Any]:
    """Generate Iran server UDP Reverse configuration."""
    clean_iran_ip = validate_ip(iran_public_ip)
    clean_kharej_ip = validate_ip(kharej_public_ip)
    clean_tun_iran = validate_ip(tun_ip_iran)
    clean_tun_kharej = validate_ip(tun_ip_kharej)
    val_listen_port = validate_port(listen_port)
    val_tunnel_port = validate_port(tunnel_port)

    return {
        "name": config_name,
        "variables": {
            "ip_kharej_public": clean_kharej_ip,
            "ip_iran_public": clean_iran_ip,
            "tun_ip_kharej": clean_tun_kharej,
            "tun_ip_iran": clean_tun_iran,
            "xor_key": xor_key,
            "reverse_secret": reverse_secret,
        },
        "nodes": [
            {
                "name": "tun_device",
                "type": "TunDevice",
                "settings": {
                    "device-name": config_name,
                    "device-ip": f"{clean_tun_iran}/24",
                },
                "next": "ip_rewrite",
            },
            {
                "name": "ip_rewrite",
                "type": "IpOverrider",
                "settings": {
                    "up": {
                        "source-ip": {"ipv4": "$ip_iran_public$"},
                        "dest-ip": {"ipv4": "$ip_kharej_public$"},
                    },
                    "down": {
                        "source-ip": {"ipv4": "$tun_ip_kharej$"},
                        "dest-ip": {"ipv4": "$tun_ip_iran$"},
                    },
                },
                "next": "obfuscator_client",
            },
            {
                "name": "obfuscator_client",
                "type": "ObfuscatorClient",
                "settings": {
                    "method": "xor",
                    "xor_key": "$xor_key$",
                    "skip": "transport",
                    "tls_record_header": False,
                },
                "next": "raw_out",
            },
            {
                "name": "raw_out",
                "type": "RawSocket",
                "settings": {
                    "capture-filter-mode": "source-ip",
                    "capture-ips": ["$ip_kharej_public$"],
                },
            },
            {
                "name": "reverse_udp_listener",
                "type": "UdpListener",
                "settings": {
                    "address": "$tun_ip_iran$",
                    "port": val_tunnel_port,
                },
                "next": "reverse_server",
            },
            {
                "name": "reverse_server",
                "type": "ReverseServer",
                "settings": {"reverse-secret": "$reverse_secret$"},
                "next": "reverse_bridge_a",
            },
            {
                "name": "reverse_bridge_a",
                "type": "Bridge",
                "settings": {"pair": "reverse_bridge_b"},
            },
            {
                "name": "reverse_bridge_b",
                "type": "Bridge",
                "settings": {"pair": "reverse_bridge_a"},
            },
            {
                "name": "public_udp_inbound",
                "type": "UdpListener",
                "settings": {
                    "address": "0.0.0.0",
                    "port": val_listen_port,
                },
                "next": "reverse_bridge_b",
            },
        ],
    }


def generate_udp_reverse_kharej(
    config_name: str,
    iran_public_ip: str,
    kharej_public_ip: str,
    target_port: int,
    tunnel_port: int = 443,
    tun_ip_iran: str = "10.20.1.1",
    tun_ip_kharej: str = "10.20.1.2",
    xor_key: int = 153,
    reverse_secret: str = "begapour",
) -> Dict[str, Any]:
    """Generate Kharej server UDP Reverse configuration."""
    clean_iran_ip = validate_ip(iran_public_ip)
    clean_kharej_ip = validate_ip(kharej_public_ip)
    clean_tun_iran = validate_ip(tun_ip_iran)
    clean_tun_kharej = validate_ip(tun_ip_kharej)
    val_target_port = validate_port(target_port)
    val_tunnel_port = validate_port(tunnel_port)

    return {
        "name": config_name,
        "variables": {
            "ip_kharej_public": clean_kharej_ip,
            "ip_iran_public": clean_iran_ip,
            "tun_ip_kharej": clean_tun_kharej,
            "tun_ip_iran": clean_tun_iran,
            "xor_key": xor_key,
            "reverse_secret": reverse_secret,
        },
        "nodes": [
            {
                "name": "raw_in",
                "type": "RawSocket",
                "settings": {
                    "capture-filter-mode": "source-ip",
                    "capture-ips": ["$ip_iran_public$"],
                },
                "next": "obfuscator_server",
            },
            {
                "name": "obfuscator_server",
                "type": "ObfuscatorServer",
                "settings": {
                    "method": "xor",
                    "xor_key": "$xor_key$",
                    "skip": "transport",
                    "tls_record_header": False,
                },
                "next": "ip_rewrite",
            },
            {
                "name": "ip_rewrite",
                "type": "IpOverrider",
                "settings": {
                    "up": {
                        "source-ip": {"ipv4": "$tun_ip_iran$"},
                        "dest-ip": {"ipv4": "$tun_ip_kharej$"},
                    },
                    "down": {
                        "source-ip": {"ipv4": "$ip_kharej_public$"},
                        "dest-ip": {"ipv4": "$ip_iran_public$"},
                    },
                },
                "next": "tun_device",
            },
            {
                "name": "tun_device",
                "type": "TunDevice",
                "settings": {
                    "device-name": config_name,
                    "device-ip": f"{clean_tun_kharej}/24",
                },
            },
            {
                "name": "reverse_bridge_a",
                "type": "Bridge",
                "settings": {"pair": "reverse_bridge_b"},
                "next": "reverse_client",
            },
            {
                "name": "reverse_bridge_b",
                "type": "Bridge",
                "settings": {"pair": "reverse_bridge_a"},
                "next": "udp_to_local_service",
            },
            {
                "name": "reverse_client",
                "type": "ReverseClient",
                "settings": {
                    "minimum-unused": 8,
                    "reverse-secret": "$reverse_secret$",
                },
                "next": "udp_to_iran",
            },
            {
                "name": "udp_to_iran",
                "type": "UdpConnector",
                "settings": {
                    "address": "$tun_ip_iran$",
                    "port": val_tunnel_port,
                },
            },
            {
                "name": "udp_to_local_service",
                "type": "UdpConnector",
                "settings": {
                    "address": "127.0.0.1",
                    "port": val_target_port,
                },
            },
        ],
    }
