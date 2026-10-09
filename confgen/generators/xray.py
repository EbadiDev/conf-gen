"""Xray Configuration Generator.

Supports VLESS Reverse Tunneling (WS, WS+TLS, Reality) across Iran (Portal) and Kharej (Bridge).
"""

from typing import Any, Dict, List, Optional
from confgen.core.validator import validate_ip, validate_port, validate_ports_list
from confgen.core.utils import write_json, print_success


DEFAULT_UUID = "e3b0c442-98fc-1c14-9afb-f4c8996fb924"
DEFAULT_WS_PATH = "/api/v3/live"


def generate_xray_iran_config(
    listen_port: int,
    tcp_ports: List[int],
    udp_ports: Optional[List[int]] = None,
    uuid: str = DEFAULT_UUID,
    ws_path: str = DEFAULT_WS_PATH,
    tls_cert: Optional[str] = None,
    tls_key: Optional[str] = None,
    reality_dest: Optional[str] = None,
    reality_server_names: Optional[List[str]] = None,
    reality_private_key: Optional[str] = None,
    reality_short_ids: Optional[List[str]] = None,
) -> Dict[str, Any]:
    """Generate Xray Portal (Iran) configuration."""
    validated_listen_port = validate_port(listen_port)
    udp_ports = udp_ports or []

    stream_settings: Dict[str, Any] = {
        "network": "ws",
        "wsSettings": {
            "path": ws_path,
        },
    }

    if tls_cert and tls_key:
        stream_settings["security"] = "tls"
        stream_settings["tlsSettings"] = {
            "certificates": [
                {
                    "certificateFile": tls_cert,
                    "keyFile": tls_key,
                }
            ],
            "alpn": ["http/1.1"],
        }
    elif reality_private_key and reality_dest:
        stream_settings["network"] = "tcp"
        stream_settings.pop("wsSettings", None)
        stream_settings["security"] = "reality"
        stream_settings["realitySettings"] = {
            "show": False,
            "dest": reality_dest,
            "xver": 0,
            "serverNames": reality_server_names or ["telewebion.ir"],
            "privateKey": reality_private_key,
            "shortIds": reality_short_ids or ["e3b0c442"],
        }

    inbounds: List[Dict[str, Any]] = [
        {
            "tag": "portal",
            "listen": "0.0.0.0",
            "port": validated_listen_port,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": uuid,
                        "reverse": {
                            "tag": "reverse-portal",
                        },
                    }
                ],
                "decryption": "none",
            },
            "streamSettings": stream_settings,
        }
    ]

    all_tunnel_tags: List[str] = []

    for port in tcp_ports:
        p = validate_port(port)
        tag = f"tunnel-{p}"
        all_tunnel_tags.append(tag)
        inbounds.append(
            {
                "tag": tag,
                "listen": "0.0.0.0",
                "port": p,
                "protocol": "tunnel",
                "settings": {
                    "allowedNetwork": "tcp",
                    "rewriteAddress": "127.0.0.1",
                    "rewritePort": p,
                },
            }
        )

    for port in udp_ports:
        p = validate_port(port)
        tag = f"tunnel-{p}-udp"
        all_tunnel_tags.append(tag)
        inbounds.append(
            {
                "tag": tag,
                "listen": "0.0.0.0",
                "port": p,
                "protocol": "tunnel",
                "settings": {
                    "allowedNetwork": "udp",
                    "rewriteAddress": "127.0.0.1",
                    "rewritePort": p,
                },
            }
        )

    return {
        "log": {
            "loglevel": "warning",
        },
        "inbounds": inbounds,
        "routing": {
            "rules": [
                {
                    "inboundTag": all_tunnel_tags,
                    "outboundTag": "reverse-portal",
                }
            ]
        },
        "outbounds": [
            {
                "protocol": "freedom",
                "tag": "direct",
            }
        ],
    }


def generate_xray_kharej_config(
    iran_ip: str,
    connect_port: int,
    uuid: str = DEFAULT_UUID,
    ws_path: str = DEFAULT_WS_PATH,
    early_data: Optional[int] = 2560,
    tls_sni: Optional[str] = None,
    reality_server_name: Optional[str] = None,
    reality_public_key: Optional[str] = None,
    reality_short_id: Optional[str] = None,
) -> Dict[str, Any]:
    """Generate Xray Bridge (Kharej) configuration."""
    clean_iran_ip = validate_ip(iran_ip)
    validated_port = validate_port(connect_port)

    client_path = ws_path
    if early_data:
        client_path = f"{ws_path}?ed={early_data}"

    stream_settings: Dict[str, Any] = {
        "network": "ws",
        "wsSettings": {
            "path": client_path,
        },
    }

    if tls_sni:
        stream_settings["security"] = "tls"
        stream_settings["tlsSettings"] = {
            "serverName": tls_sni,
            "allowInsecure": False,
            "alpn": ["http/1.1"],
        }
        stream_settings["wsSettings"]["headers"] = {
            "Host": tls_sni,
        }
    elif reality_public_key and reality_server_name:
        stream_settings["network"] = "tcp"
        stream_settings.pop("wsSettings", None)
        stream_settings["security"] = "reality"
        stream_settings["realitySettings"] = {
            "show": False,
            "fingerprint": "chrome",
            "serverName": reality_server_name,
            "publicKey": reality_public_key,
            "shortId": reality_short_id or "e3b0c442",
            "spiderX": "",
        }

    return {
        "log": {
            "loglevel": "warning",
        },
        "routing": {
            "rules": [
                {
                    "inboundTag": [
                        "reverse-bridge",
                    ],
                    "outboundTag": "direct",
                }
            ]
        },
        "outbounds": [
            {
                "protocol": "freedom",
                "tag": "direct",
                "settings": {
                    "finalRules": [
                        {
                            "action": "allow",
                            "ip": [
                                "127.0.0.1",
                                "::1",
                            ],
                        }
                    ]
                },
            },
            {
                "tag": "bridge-out",
                "protocol": "vless",
                "settings": {
                    "address": clean_iran_ip,
                    "port": validated_port,
                    "id": uuid,
                    "encryption": "none",
                    "reverse": {
                        "tag": "reverse-bridge",
                    },
                },
                "streamSettings": stream_settings,
            },
        ],
    }
