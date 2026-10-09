"""Waterwall TLS Reverse Configuration Generator."""

from typing import Any, Dict, List, Optional
from confgen.core.validator import validate_ip, validate_port


def generate_waterwall_tls_reverse_iran(
    config_name: str,
    iran_ip: str,
    port: int,
    cert_path: str,
    key_path: str,
    kharej_ips: List[str],
    use_proxy_protocol: bool = False,
) -> Dict[str, Any]:
    """Generate Iran server TLS Reverse configuration."""
    clean_iran_ip = validate_ip(iran_ip)
    validated_port = validate_port(port)

    variables: Dict[str, Any] = {
        "ip_server_iran": clean_iran_ip,
        "certificate_path": cert_path,
        "key_path": key_path,
    }

    whitelist: List[str] = []
    for idx, ip_str in enumerate(kharej_ips):
        clean_ip = validate_ip(ip_str)
        cidr_ip = clean_ip if "/" in clean_ip else f"{clean_ip}/32"
        var_key = "ip_server_kharej" if idx == 0 else f"ip_server_kharej_{idx + 1}"
        variables[var_key] = cidr_ip
        whitelist.append(f"${var_key}$")

    variables["user_and_server_kharej_port"] = validated_port

    nodes: List[Dict[str, Any]] = [
        {
            "name": "users_inbound",
            "type": "TcpListener",
            "settings": {
                "address": "0.0.0.0",
                "port": "$user_and_server_kharej_port$",
                "nodelay": True,
            },
            "next": "proxy-header" if use_proxy_protocol else "bridge_user_side",
        }
    ]

    if use_proxy_protocol:
        nodes.append(
            {
                "name": "proxy-header",
                "type": "HeaderClient",
                "settings": {
                    "data": "proxy-protocol",
                    "frontend-ipv4": "$ip_server_iran$",
                },
                "next": "bridge_user_side",
            }
        )

    nodes.extend(
        [
            {
                "name": "bridge_user_side",
                "type": "Bridge",
                "settings": {
                    "pair": "bridge_reverse_side",
                },
            },
            {
                "name": "bridge_reverse_side",
                "type": "Bridge",
                "settings": {
                    "pair": "bridge_user_side",
                },
            },
            {
                "name": "reverse_server",
                "type": "ReverseServer",
                "settings": {},
                "next": "bridge_reverse_side",
            },
            {
                "name": "tls_server",
                "type": "TlsServer",
                "settings": {
                    "cert-file": "$certificate_path$",
                    "key-file": "$key_path$",
                    "min-version": "TLSv1.2",
                    "max-version": "TLSv1.3",
                    "ciphers": "HIGH:!aNULL:!MD5",
                    "session-cache": "none",
                    "session-tickets": True,
                    "verbose": False,
                },
                "next": "reverse_server",
            },
            {
                "name": "germany_reverse_tls_inbound",
                "type": "TcpListener",
                "settings": {
                    "address": "0.0.0.0",
                    "port": "$user_and_server_kharej_port$",
                    "nodelay": True,
                    "whitelist": whitelist,
                },
                "next": "tls_server",
            },
        ]
    )

    return {
        "name": config_name,
        "variables": variables,
        "nodes": nodes,
    }


def generate_waterwall_tls_reverse_kharej(
    config_name: str,
    iran_ip: str,
    port: int,
    sni: str,
    final_port: int,
    final_ip: str = "127.0.0.1",
    min_held: int = 8,
) -> Dict[str, Any]:
    """Generate Kharej client TLS Reverse configuration."""
    clean_iran_ip = validate_ip(iran_ip)
    clean_final_ip = validate_ip(final_ip)
    validated_port = validate_port(port)
    validated_final_port = validate_port(final_port)

    return {
        "name": config_name,
        "variables": {
            "ip_server_iran": clean_iran_ip,
            "domain_to_handshake_tls": sni,
            "target_ip_app": clean_final_ip,
            "connect_to_iran_port": validated_port,
            "target_port_app": validated_final_port,
            "min_held": min_held,
        },
        "nodes": [
            {
                "name": "tcp_to_app",
                "type": "TcpConnector",
                "settings": {
                    "address": "$target_ip_app$",
                    "port": "$target_port_app$",
                    "nodelay": True,
                },
            },
            {
                "name": "germany_reverse_tls_client",
                "type": "ReverseClient",
                "settings": {
                    "min-held": "$min_held$",
                },
                "next": "tcp_to_app",
            },
            {
                "name": "bridge_reverse_side",
                "type": "Bridge",
                "settings": {
                    "pair": "germany_reverse_tls_client",
                },
                "next": "tls_client",
            },
            {
                "name": "tls_client",
                "type": "TlsClient",
                "settings": {
                    "sni": "$domain_to_handshake_tls$",
                    "verify": True,
                },
                "next": "tcp_to_iran",
            },
            {
                "name": "tcp_to_iran",
                "type": "TcpConnector",
                "settings": {
                    "address": "$ip_server_iran$",
                    "port": "$connect_to_iran_port$",
                    "nodelay": True,
                },
            },
        ],
    }
