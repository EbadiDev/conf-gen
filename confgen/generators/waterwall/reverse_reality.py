"""Waterwall Reverse Reality Configuration Generator (TCP & UDP)."""

from typing import Any, Dict, List, Optional
from confgen.core.validator import validate_ip, validate_port


def generate_reverse_reality_tcp_iran(
    config_name: str,
    iran_ip: str,
    kharej_ip: str,
    port: int,
    domain: str,
    white_ip: str,
    password: str = "arch1234net",
    float_ips: Optional[List[str]] = None,
    cert_path: Optional[str] = None,
    key_path: Optional[str] = None,
    use_proxy_protocol: bool = False,
    use_halfduplex: bool = False,
    use_fisher: bool = False,
    reverse_secret_length: Optional[int] = None,
    reverse_secret: Optional[str] = None,
) -> Dict[str, Any]:
    """Generate Iran server TCP Reverse Reality configuration."""
    float_ips = float_ips or []
    clean_iran_ip = validate_ip(iran_ip)
    clean_kharej_ip = validate_ip(kharej_ip)
    clean_white_ip = validate_ip(white_ip)
    validated_port = validate_port(port)

    variables: Dict[str, Any] = {
        "ip_server_iran": clean_iran_ip,
        "domain_white": domain,
        "ip_behind_domain_white": clean_white_ip,
        "ip_server_kharej": f"{clean_kharej_ip}/32" if "/" not in clean_kharej_ip else clean_kharej_ip,
    }

    for idx, fip in enumerate(float_ips):
        clean_fip = validate_ip(fip)
        variables[f"ip_server_kharej_float_{idx + 1}"] = f"{clean_fip}/32" if "/" not in clean_fip else clean_fip

    if cert_path and key_path:
        variables["certificate_path"] = cert_path
        variables["key_path"] = key_path

    variables["user_and_server_kharej_port"] = validated_port
    variables["password"] = password

    user_side_entry = "halfduplex_client" if use_halfduplex else "bridge_user_side"
    kharej_listener_next = "fisher_server" if use_fisher else "reality-server"

    first_next = user_side_entry
    if use_proxy_protocol:
        first_next = "proxy-header"
    if cert_path:
        first_next = "tls_termination"

    nodes: List[Dict[str, Any]] = [
        {
            "name": "users_inbound",
            "type": "TcpListener",
            "settings": {
                "address": "0.0.0.0",
                "port": "$user_and_server_kharej_port$",
                "nodelay": True,
            },
            "next": first_next,
        }
    ]

    if cert_path:
        after_tls = "proxy-header" if use_proxy_protocol else user_side_entry
        nodes.append(
            {
                "name": "tls_termination",
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
                "next": after_tls,
            }
        )

    if use_proxy_protocol:
        nodes.append(
            {
                "name": "proxy-header",
                "type": "HeaderClient",
                "settings": {
                    "data": "proxy-protocol",
                    "frontend-ipv4": "$ip_server_iran$",
                },
                "next": user_side_entry,
            }
        )

    if use_halfduplex:
        nodes.append(
            {
                "name": "halfduplex_client",
                "type": "HalfDuplexClient",
                "settings": {},
                "next": "bridge_user_side",
            }
        )

    reverse_settings: Dict[str, Any] = {}
    if reverse_secret_length:
        reverse_settings["reverse-secret-length"] = reverse_secret_length
    if reverse_secret:
        reverse_settings["reverse-secret"] = reverse_secret

    nodes.extend(
        [
            {
                "name": "bridge_user_side",
                "type": "Bridge",
                "settings": {"pair": "bridge_reverse_side"},
            },
            {
                "name": "bridge_reverse_side",
                "type": "Bridge",
                "settings": {"pair": "bridge_user_side"},
            },
            {
                "name": "reverse_server",
                "type": "ReverseServer",
                "settings": reverse_settings,
                "next": "bridge_reverse_side",
            },
            {
                "name": "reality-server",
                "type": "RealityServer",
                "settings": {
                    "destination": "dest-visitor",
                    "password": "$password$",
                    "algorithm": "chacha20-poly1305",
                    "kdf-iterations": 12000,
                    "sniffing-attempts": 8,
                },
                "next": "reverse_server",
            },
            {
                "name": "dest-visitor",
                "type": "TcpConnector",
                "settings": {
                    "address": "$ip_behind_domain_white$",
                    "port": 443,
                    "nodelay": True,
                },
            },
        ]
    )

    whitelist = ["$ip_server_kharej$"]
    for idx in range(len(float_ips)):
        whitelist.append(f"$ip_server_kharej_float_{idx + 1}$")

    nodes.append(
        {
            "name": "germany_reverse_tls_inbound",
            "type": "TcpListener",
            "settings": {
                "address": "0.0.0.0",
                "port": "$user_and_server_kharej_port$",
                "nodelay": True,
                "whitelist": whitelist,
            },
            "next": kharej_listener_next,
        }
    )

    if use_fisher:
        nodes.append(
            {
                "name": "fisher_server",
                "type": "ConnectionFisherServer",
                "settings": {},
                "next": "reality-server",
            }
        )

    return {
        "name": config_name,
        "variables": variables,
        "nodes": nodes,
    }


def generate_reverse_reality_tcp_kharej(
    config_name: str,
    iran_ip: str,
    kharej_ip: str,
    port: int,
    domain: str,
    final_port: int,
    password: str = "arch1234net",
    min_held: int = 8,
    float_ips: Optional[List[str]] = None,
    use_halfduplex: bool = False,
    use_fisher: bool = False,
    reverse_secret_length: Optional[int] = None,
    reverse_secret: Optional[str] = None,
) -> Dict[str, Any]:
    """Generate Kharej client TCP Reverse Reality configuration."""
    float_ips = float_ips or []
    clean_iran_ip = validate_ip(iran_ip)
    clean_kharej_ip = validate_ip(kharej_ip)
    validated_port = validate_port(port)
    validated_final_port = validate_port(final_port)

    variables: Dict[str, Any] = {
        "ip_server_iran": clean_iran_ip,
        "ip_server_kharej": clean_kharej_ip,
    }

    for idx, fip in enumerate(float_ips):
        variables[f"ip_server_kharej_float_{idx + 1}"] = validate_ip(fip)

    variables.update(
        {
            "connect_to_iran_port": validated_port,
            "domain_to_handshake_reality": domain,
            "password": password,
            "final_port": validated_final_port,
            "min_held_connections": min_held,
        }
    )

    nodes: List[Dict[str, Any]] = [
        {
            "name": "outbound_to_local_service",
            "type": "TcpConnector",
            "settings": {
                "address": "127.0.0.1",
                "port": "$final_port$",
                "nodelay": True,
            },
        },
        {
            "name": "bridge_local_side",
            "type": "Bridge",
            "settings": {"pair": "bridge_reverse_client_side"},
            "next": "halfduplex_server" if use_halfduplex else "outbound_to_local_service",
        },
    ]

    if use_halfduplex:
        nodes.append(
            {
                "name": "halfduplex_server",
                "type": "HalfDuplexServer",
                "settings": {},
                "next": "outbound_to_local_service",
            }
        )

    reverse_settings: Dict[str, Any] = {"min-held": "$min_held_connections$"}
    if reverse_secret_length:
        reverse_settings["reverse-secret-length"] = reverse_secret_length
    if reverse_secret:
        reverse_settings["reverse-secret"] = reverse_secret

    nodes.extend(
        [
            {
                "name": "germany_reverse_tls_client",
                "type": "ReverseClient",
                "settings": reverse_settings,
                "next": "bridge_local_side",
            },
            {
                "name": "bridge_reverse_client_side",
                "type": "Bridge",
                "settings": {"pair": "germany_reverse_tls_client"},
                "next": "reality-client",
            },
            {
                "name": "reality-client",
                "type": "RealityClient",
                "settings": {
                    "sni": "$domain_to_handshake_reality$",
                    "password": "$password$",
                    "algorithm": "chacha20-poly1305",
                    "kdf-iterations": 12000,
                },
                "next": "fisher_client" if use_fisher else "tcp_to_iran",
            },
        ]
    )

    if use_fisher:
        nodes.append(
            {
                "name": "fisher_client",
                "type": "ConnectionFisherClient",
                "settings": {},
                "next": "tcp_to_iran",
            }
        )

    # Connector settings with single or multiple floating IPs
    if not float_ips:
        nodes.append(
            {
                "name": "tcp_to_iran",
                "type": "TcpConnector",
                "settings": {
                    "address": "$ip_server_iran$",
                    "port": "$connect_to_iran_port$",
                    "nodelay": True,
                    "source_ip": "$ip_server_kharej$",
                },
            }
        )
    else:
        addresses = [
            {
                "address": "$ip_server_iran$",
                "port": "$connect_to_iran_port$",
                "source_ip": "$ip_server_kharej$",
                "weight": 1,
            }
        ]
        for idx in range(len(float_ips)):
            addresses.append(
                {
                    "address": "$ip_server_iran$",
                    "port": "$connect_to_iran_port$",
                    "source_ip": f"$ip_server_kharej_float_{idx + 1}$",
                    "weight": 1,
                }
            )
        nodes.append(
            {
                "name": "tcp_to_iran",
                "type": "TcpConnector",
                "settings": {
                    "addresses": addresses,
                    "balancer": "round-robin",
                    "nodelay": True,
                },
            }
        )

    return {
        "name": config_name,
        "variables": variables,
        "nodes": nodes,
    }
