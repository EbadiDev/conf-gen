"""Waterwall Reverse Reality Configuration Generator (TCP & UDP)."""

from typing import Any, Dict, List, Optional, Union
from confgen.core.validator import validate_ip, validate_port


def generate_reverse_reality_tcp_iran(
    config_name: str,
    iran_ip: str,
    kharej_ip: str,
    port: Union[int, List[int]],
    domain: str,
    white_ip: str,
    password: str = "arch1234net",
    float_ips: Optional[List[str]] = None,
    cert_path: Optional[str] = None,
    key_path: Optional[str] = None,
    use_proxy_protocol: bool = False,
    use_halfduplex: bool = False,
    use_fisher: bool = False,
    use_mux: bool = False,
    mux_count: int = 8,
    reverse_secret_length: Optional[int] = None,
    reverse_secret: Optional[str] = None,
) -> Dict[str, Any]:
    """Generate Iran server TCP Reverse Reality configuration (supports single port or multiport list)."""
    float_ips = float_ips or []
    clean_iran_ip = validate_ip(iran_ip)
    clean_kharej_ip = validate_ip(kharej_ip)
    clean_white_ip = validate_ip(white_ip)

    clean_ports = [validate_port(p) for p in port] if isinstance(port, list) else [validate_port(port)]
    carrier_port = clean_ports[0]
    has_multi = len(clean_ports) > 1

    variables: Dict[str, Any] = {
        "ip_server_iran": clean_iran_ip,
        "domain_white": domain,
        "ip_behind_domain_white": clean_white_ip,
        "ip_server_kharej": f"{clean_kharej_ip}/32" if "/" not in clean_kharej_ip else clean_kharej_ip,
        "user_and_server_kharej_port": carrier_port,
        "password": password,
    }
    if has_multi:
        variables["users_listen_ports"] = clean_ports

    for idx, fip in enumerate(float_ips):
        clean_fip = validate_ip(fip)
        variables[f"ip_server_kharej_float_{idx + 1}"] = f"{clean_fip}/32" if "/" not in clean_fip else clean_fip

    if cert_path and key_path:
        variables["certificate_path"] = cert_path
        variables["key_path"] = key_path

    user_side_entry = "mux-client" if use_mux else "bridge_user_side"
    kharej_listener_next = "fisher_server" if use_fisher else "reality-server"

    first_next = user_side_entry
    if use_proxy_protocol:
        first_next = "proxy-header"
    if cert_path:
        first_next = "tls_termination"

    listen_port_setting = "$users_listen_ports$" if has_multi else "$user_and_server_kharej_port$"
    inbound_next = "header_client" if has_multi else first_next
    nodes: List[Dict[str, Any]] = [
        {
            "name": "users_inbound",
            "type": "TcpListener",
            "settings": {
                "address": "0.0.0.0",
                "port": listen_port_setting,
                "nodelay": True,
            },
            "next": inbound_next,
        }
    ]

    if has_multi:
        nodes.append({
            "name": "header_client",
            "type": "HeaderClient",
            "settings": {"data": "src_context->port"},
            "next": first_next,
        })

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

    if use_mux:
        nodes.append(
            {
                "name": "mux-client",
                "type": "MuxClient",
                "settings": {
                    "mode": "fixed-connections-count",
                    "per-worker-connections-count": mux_count,
                },
                "next": "bridge_user_side",
            }
        )

    reverse_settings: Dict[str, Any] = {"minimum-unused": "$min_held_connections$"}
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
        ]
    )

    reality_next = "halfs" if use_halfduplex else "reverse_server"
    if use_halfduplex:
        nodes.append(
            {
                "name": "halfs",
                "type": "HalfDuplexServer",
                "settings": {},
                "next": "reverse_server",
            }
        )

    nodes.extend(
        [
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
                "next": reality_next,
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
    use_mux: bool = False,
    reverse_secret_length: Optional[int] = None,
    reverse_secret: Optional[str] = None,
) -> Dict[str, Any]:
    """Generate Kharej client TCP Reverse Reality configuration."""
    float_ips = float_ips or []
    clean_iran_ip = validate_ip(iran_ip)
    clean_kharej_ip = validate_ip(kharej_ip)
    validated_port = validate_port(port)
    validated_final_port = validate_port(final_port) if (final_port and int(final_port) != 0) else 0

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
            "min_held_connections": min_held,
        }
    )
    if validated_final_port != 0:
        variables["final_port"] = validated_final_port

    is_preserve_ports = (validated_final_port == 0)
    if is_preserve_ports:
        nodes: List[Dict[str, Any]] = [
            {
                "name": "outbound_to_local_service",
                "type": "TcpConnector",
                "settings": {
                    "address": "127.0.0.1",
                    "port": "dest_context->port",
                    "nodelay": True,
                },
            },
            {
                "name": "header_server",
                "type": "HeaderServer",
                "settings": {"override": "dest_context->port"},
                "next": "outbound_to_local_service",
            },
            {
                "name": "bridge_local_side",
                "type": "Bridge",
                "settings": {"pair": "bridge_reverse_client_side"},
                "next": "header_server",
            },
        ]
    else:
        bridge_next = "mux-s" if use_mux else "outbound_to_local_service"
        nodes = [
            {
                "name": "outbound_to_local_service",
                "type": "TcpConnector",
                "settings": {
                    "address": "127.0.0.1",
                    "port": "$final_port$",
                    "nodelay": True,
                },
            },
        ]
        if use_mux:
            nodes.append(
                {
                    "name": "mux-s",
                    "type": "MuxServer",
                    "settings": {},
                    "next": "outbound_to_local_service",
                }
            )
        nodes.append(
            {
                "name": "bridge_local_side",
                "type": "Bridge",
                "settings": {"pair": "bridge_reverse_client_side"},
                "next": bridge_next,
            }
        )

    reverse_settings: Dict[str, Any] = {"minimum-unused": "$min_held_connections$"}
    if reverse_secret_length:
        reverse_settings["reverse-secret-length"] = reverse_secret_length
    if reverse_secret:
        reverse_settings["reverse-secret"] = reverse_secret

    rev_next = "halfc" if use_halfduplex else "reality-client"
    nodes.extend(
        [
            {
                "name": "bridge_reverse_client_side",
                "type": "Bridge",
                "settings": {"pair": "bridge_local_side"},
                "next": "reverse_client",
            },
            {
                "name": "reverse_client",
                "type": "ReverseClient",
                "settings": reverse_settings,
                "next": rev_next,
            },
        ]
    )

    if use_halfduplex:
        nodes.append(
            {
                "name": "halfc",
                "type": "HalfDuplexClient",
                "settings": {},
                "next": "reality-client",
            }
        )

    reality_next = "fisher_client" if use_fisher else "tcp_to_iran"
    nodes.append(
        {
            "name": "reality-client",
            "type": "RealityClient",
            "settings": {
                "sni": "$domain_to_handshake_reality$",
                "verify": True,
                "password": "$password$",
                "algorithm": "chacha20-poly1305",
                "kdf-iterations": 12000,
            },
            "next": reality_next,
        }
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


def generate_reverse_reality_udp_iran(
    config_name: str,
    iran_ip: str,
    kharej_ip: str,
    port: int,
    domain: str,
    white_ip: str,
    password: str = "arch1234net",
    float_ips: Optional[List[str]] = None,
    use_halfduplex: bool = False,
    use_fisher: bool = False,
    reverse_secret_length: Optional[int] = None,
    reverse_secret: Optional[str] = None,
) -> Dict[str, Any]:
    """Generate Iran server UDP Reverse Reality configuration (UdpListener -> UdpOverTcpClient -> Reality)."""
    float_ips = float_ips or []
    clean_iran_ip = validate_ip(iran_ip)
    clean_kharej_ip = validate_ip(kharej_ip)
    clean_white_ip = validate_ip(white_ip)
    validated_port = validate_port(port)

    variables: Dict[str, Any] = {
        "domain_white": domain,
        "ip_behind_domain_white": clean_white_ip,
        "ip_server_kharej": f"{clean_kharej_ip}/32" if "/" not in clean_kharej_ip else clean_kharej_ip,
        "user_and_server_kharej_port": validated_port,
        "password": password,
    }

    for idx, fip in enumerate(float_ips):
        clean_fip = validate_ip(fip)
        variables[f"ip_server_kharej_float_{idx + 1}"] = f"{clean_fip}/32" if "/" not in clean_fip else clean_fip

    nodes: List[Dict[str, Any]] = [
        {
            "name": "users_inbound",
            "type": "UdpListener",
            "settings": {
                "address": "0.0.0.0",
                "port": "$user_and_server_kharej_port$",
            },
            "next": "udpovertcp_client",
        },
        {
            "name": "udpovertcp_client",
            "type": "UdpOverTcpClient",
            "settings": {},
            "next": "bridge_user_side",
        },
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
    ]

    reverse_settings: Dict[str, Any] = {"minimum-unused": "$min_held_connections$"}
    if reverse_secret_length:
        reverse_settings["reverse-secret-length"] = reverse_secret_length
    if reverse_secret:
        reverse_settings["reverse-secret"] = reverse_secret

    nodes.append(
        {
            "name": "reverse_server",
            "type": "ReverseServer",
            "settings": reverse_settings,
            "next": "bridge_reverse_side",
        }
    )

    reality_next = "halfs" if use_halfduplex else "reverse_server"
    if use_halfduplex:
        nodes.append(
            {
                "name": "halfs",
                "type": "HalfDuplexServer",
                "settings": {},
                "next": "reverse_server",
            }
        )

    nodes.extend(
        [
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
                "next": reality_next,
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

    kharej_listener_next = "fisher_server" if use_fisher else "reality-server"
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


def generate_reverse_reality_udp_kharej(
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
    """Generate Kharej server UDP Reverse Reality configuration (Reality -> Bridge -> UdpOverTcpServer -> UdpConnector)."""
    float_ips = float_ips or []
    clean_iran_ip = validate_ip(iran_ip)
    clean_kharej_ip = validate_ip(kharej_ip)
    validated_port = validate_port(port)
    validated_final_port = validate_port(final_port) if (final_port and int(final_port) != 0) else 0

    variables: Dict[str, Any] = {
        "ip_server_iran": clean_iran_ip,
        "ip_server_kharej": clean_kharej_ip,
        "connect_to_iran_port": validated_port,
        "domain_to_handshake_reality": domain,
        "password": password,
        "min_held_connections": min_held,
    }
    if validated_final_port != 0:
        variables["final_port"] = validated_final_port

    for idx, fip in enumerate(float_ips):
        variables[f"ip_server_kharej_float_{idx + 1}"] = validate_ip(fip)

    nodes: List[Dict[str, Any]] = [
        {
            "name": "outbound_to_local_service",
            "type": "UdpConnector",
            "settings": {
                "address": "127.0.0.1",
                "port": "$final_port$",
            },
        },
        {
            "name": "udpovertcp_server",
            "type": "UdpOverTcpServer",
            "settings": {},
            "next": "outbound_to_local_service",
        },
        {
            "name": "bridge_local_side",
            "type": "Bridge",
            "settings": {"pair": "bridge_reverse_client_side"},
            "next": "udpovertcp_server",
        },
        {
            "name": "bridge_reverse_client_side",
            "type": "Bridge",
            "settings": {"pair": "bridge_local_side"},
            "next": "reverse_client",
        },
    ]

    reverse_settings: Dict[str, Any] = {"minimum-unused": "$min_held_connections$"}
    if reverse_secret_length:
        reverse_settings["reverse-secret-length"] = reverse_secret_length
    if reverse_secret:
        reverse_settings["reverse-secret"] = reverse_secret

    rev_next = "halfc" if use_halfduplex else "reality-client"
    nodes.append(
        {
            "name": "reverse_client",
            "type": "ReverseClient",
            "settings": reverse_settings,
            "next": rev_next,
        }
    )

    if use_halfduplex:
        nodes.append(
            {
                "name": "halfc",
                "type": "HalfDuplexClient",
                "settings": {},
                "next": "reality-client",
            }
        )

    reality_next = "fisher_client" if use_fisher else "tcp_to_iran"
    nodes.append(
        {
            "name": "reality-client",
            "type": "RealityClient",
            "settings": {
                "sni": "$domain_to_handshake_reality$",
                "verify": True,
                "password": "$password$",
                "algorithm": "chacha20-poly1305",
                "kdf-iterations": 12000,
            },
            "next": reality_next,
        }
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

    if not float_ips:
        nodes.append(
            {
                "name": "tcp_to_iran",
                "type": "TcpConnector",
                "settings": {
                    "address": "$ip_server_iran$",
                    "port": "$connect_to_iran_port$",
                    "nodelay": True,
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


def generate_reverse_reality_dual_iran(
    config_name: str,
    iran_ip: str,
    kharej_ip: str,
    tcp_ports: List[int],
    tcp_forward_port: int = 10005,
    udp_port: Optional[int] = 27012,
    udp_forward_port: Optional[int] = 10006,
    carrier_port: int = 58443,
    carrier_udp_port: int = 58444,
    domain: str = "shariati.tums.ac.ir",
    white_ip: Optional[str] = None,
    password: str = "arch1234net",
    float_ips: Optional[List[str]] = None,
    use_halfduplex: bool = True,
    use_fisher: bool = True,
) -> Dict[str, Any]:
    """Generate Iran server dual TCP + UDP Reverse Reality configuration."""
    float_ips = float_ips or []
    clean_iran = validate_ip(iran_ip)
    clean_kharej = validate_ip(kharej_ip)
    clean_white = white_ip or "185.143.234.132"
    clean_tcp_ports = [validate_port(p) for p in tcp_ports]

    variables: Dict[str, Any] = {
        "ip_server_iran": clean_iran,
        "ip_server_kharej": f"{clean_kharej}/32" if "/" not in clean_kharej else clean_kharej,
        "domain_white": domain,
        "ip_behind_domain_white": clean_white,
        "tunnel_carrier_port": carrier_port,
        "tunnel_carrier_udp_port": carrier_udp_port,
        "password": password,
    }
    for idx, fip in enumerate(float_ips):
        variables[f"ip_server_kharej_float_{idx + 1}"] = f"{validate_ip(fip)}/32"

    has_multi_tcp = len(clean_tcp_ports) > 1
    next_after_inbound_tcp = "header_client_tcp" if has_multi_tcp else "bridge_tcp_user"

    nodes: List[Dict[str, Any]] = [
        # --- TCP Stream Pipeline ---
        {
            "name": "users_inbound_tcp",
            "type": "TcpListener",
            "settings": {
                "address": "0.0.0.0",
                "port": clean_tcp_ports if has_multi_tcp else clean_tcp_ports[0],
                "nodelay": True,
            },
            "next": next_after_inbound_tcp,
        },
    ]

    if has_multi_tcp:
        nodes.append({
            "name": "header_client_tcp",
            "type": "HeaderClient",
            "settings": {"data": "src_context->port"},
            "next": "bridge_tcp_user",
        })

    nodes.extend([
        {
            "name": "bridge_tcp_user",
            "type": "Bridge",
            "settings": {"pair": "bridge_tcp_rev"},
        },
        {
            "name": "bridge_tcp_rev",
            "type": "Bridge",
            "settings": {"pair": "bridge_tcp_user"},
        },
        {
            "name": "reverse_server_tcp",
            "type": "ReverseServer",
            "settings": {"minimum-unused": 8},
            "next": "bridge_tcp_rev",
        },
    ])

    reality_tcp_next = "halfs_tcp" if use_halfduplex else "reverse_server_tcp"
    if use_halfduplex:
        nodes.append({
            "name": "halfs_tcp",
            "type": "HalfDuplexServer",
            "settings": {},
            "next": "reverse_server_tcp",
        })

    nodes.extend([
        {
            "name": "reality_server_tcp",
            "type": "RealityServer",
            "settings": {
                "destination": "dest_visitor_tcp",
                "password": "$password$",
                "algorithm": "chacha20-poly1305",
                "kdf-iterations": 12000,
                "sniffing-attempts": 8,
            },
            "next": reality_tcp_next,
        },
        {
            "name": "dest_visitor_tcp",
            "type": "TcpConnector",
            "settings": {
                "address": "$ip_behind_domain_white$",
                "port": 443,
                "nodelay": True,
            },
        },
    ])

    carrier_tcp_next = "fisher_server_tcp" if use_fisher else "reality_server_tcp"
    if use_fisher:
        nodes.append({
            "name": "fisher_server_tcp",
            "type": "ConnectionFisherServer",
            "settings": {},
            "next": "reality_server_tcp",
        })

    whitelist = ["$ip_server_kharej$"]
    for idx in range(len(float_ips)):
        whitelist.append(f"$ip_server_kharej_float_{idx + 1}$")

    nodes.append({
        "name": "kharej_inbound_tcp",
        "type": "TcpListener",
        "settings": {
            "address": "0.0.0.0",
            "port": "$tunnel_carrier_port$",
            "nodelay": True,
            "whitelist": whitelist,
        },
        "next": carrier_tcp_next,
    })

    # --- UDP Pipeline (Optional) ---
    if udp_port:
        clean_udp_port = validate_port(udp_port)
        nodes.extend([
            {
                "name": "users_inbound_udp",
                "type": "UdpListener",
                "settings": {
                    "address": "0.0.0.0",
                    "port": clean_udp_port,
                },
                "next": "u2t",
            },
            {
                "name": "u2t",
                "type": "UdpOverTcpClient",
                "settings": {},
                "next": "bridge_udp_user",
            },
            {
                "name": "bridge_udp_user",
                "type": "Bridge",
                "settings": {"pair": "bridge_udp_rev"},
            },
            {
                "name": "bridge_udp_rev",
                "type": "Bridge",
                "settings": {"pair": "bridge_udp_user"},
            },
            {
                "name": "reverse_server_udp",
                "type": "ReverseServer",
                "settings": {"minimum-unused": 8},
                "next": "bridge_udp_rev",
            },
        ])

        reality_udp_next = "halfs_udp" if use_halfduplex else "reverse_server_udp"
        if use_halfduplex:
            nodes.append({
                "name": "halfs_udp",
                "type": "HalfDuplexServer",
                "settings": {},
                "next": "reverse_server_udp",
            })

        nodes.extend([
            {
                "name": "reality_server_udp",
                "type": "RealityServer",
                "settings": {
                    "destination": "dest_visitor_udp",
                    "password": "$password$",
                    "algorithm": "chacha20-poly1305",
                    "kdf-iterations": 12000,
                    "sniffing-attempts": 8,
                },
                "next": reality_udp_next,
            },
            {
                "name": "dest_visitor_udp",
                "type": "TcpConnector",
                "settings": {
                    "address": "$ip_behind_domain_white$",
                    "port": 443,
                    "nodelay": True,
                },
            },
        ])

        carrier_udp_next = "fisher_server_udp" if use_fisher else "reality_server_udp"
        if use_fisher:
            nodes.append({
                "name": "fisher_server_udp",
                "type": "ConnectionFisherServer",
                "settings": {},
                "next": "reality_server_udp",
            })

        nodes.append({
            "name": "kharej_inbound_udp",
            "type": "TcpListener",
            "settings": {
                "address": "0.0.0.0",
                "port": "$tunnel_carrier_udp_port$",
                "nodelay": True,
                "whitelist": whitelist,
            },
            "next": carrier_udp_next,
        })

    return {
        "name": config_name,
        "variables": variables,
        "nodes": nodes,
    }


def generate_reverse_reality_dual_kharej(
    config_name: str,
    iran_ip: str,
    kharej_ip: str,
    tcp_forward_port: int = 10005,
    udp_forward_port: Optional[int] = 10006,
    carrier_port: int = 58443,
    carrier_udp_port: int = 58444,
    domain: str = "shariati.tums.ac.ir",
    password: str = "arch1234net",
    float_ips: Optional[List[str]] = None,
    use_halfduplex: bool = True,
    use_fisher: bool = True,
) -> Dict[str, Any]:
    """Generate Kharej server dual TCP + UDP Reverse Reality configuration."""
    float_ips = float_ips or []
    clean_iran = validate_ip(iran_ip)
    clean_kharej = validate_ip(kharej_ip)

    variables: Dict[str, Any] = {
        "ip_server_iran": clean_iran,
        "ip_server_kharej": clean_kharej,
        "tunnel_carrier_port": carrier_port,
        "tunnel_carrier_udp_port": carrier_udp_port,
        "domain_to_handshake_reality": domain,
        "password": password,
        "final_tcp_port": tcp_forward_port,
    }
    if udp_forward_port:
        variables["final_udp_port"] = udp_forward_port

    for idx, fip in enumerate(float_ips):
        variables[f"ip_server_kharej_float_{idx + 1}"] = validate_ip(fip)

    is_preserve_ports = (tcp_forward_port == 0)
    if is_preserve_ports:
        nodes: List[Dict[str, Any]] = [
            {
                "name": "outbound_tcp",
                "type": "TcpConnector",
                "settings": {
                    "address": "127.0.0.1",
                    "port": "dest_context->port",
                    "nodelay": True,
                },
            },
            {
                "name": "header_server_tcp",
                "type": "HeaderServer",
                "settings": {"override": "dest_context->port"},
                "next": "outbound_tcp",
            },
            {
                "name": "bridge_tcp_local",
                "type": "Bridge",
                "settings": {"pair": "bridge_tcp_rev_client"},
                "next": "header_server_tcp",
            },
        ]
    else:
        nodes: List[Dict[str, Any]] = [
            {
                "name": "outbound_tcp",
                "type": "TcpConnector",
                "settings": {
                    "address": "127.0.0.1",
                    "port": "$final_tcp_port$",
                    "nodelay": True,
                },
            },
            {
                "name": "bridge_tcp_local",
                "type": "Bridge",
                "settings": {"pair": "bridge_tcp_rev_client"},
                "next": "outbound_tcp",
            },
            {
                "name": "bridge_tcp_rev_client",
                "type": "Bridge",
                "settings": {"pair": "bridge_tcp_local"},
                "next": "rev_client_tcp",
            },
            {
                "name": "rev_client_tcp",
                "type": "ReverseClient",
                "settings": {"minimum-unused": 8},
                "next": "halfc_tcp" if use_halfduplex else "reality_client_tcp",
            },
        ]

    if use_halfduplex:
        nodes.append({
            "name": "halfc_tcp",
            "type": "HalfDuplexClient",
            "settings": {},
            "next": "reality_client_tcp",
        })

    reality_tcp_next = "fisher_client_tcp" if use_fisher else "tcp_to_iran"
    nodes.append({
        "name": "reality_client_tcp",
        "type": "RealityClient",
        "settings": {
            "sni": "$domain_to_handshake_reality$",
            "verify": True,
            "password": "$password$",
            "algorithm": "chacha20-poly1305",
            "kdf-iterations": 12000,
        },
        "next": reality_tcp_next,
    })

    if use_fisher:
        nodes.append({
            "name": "fisher_client_tcp",
            "type": "ConnectionFisherClient",
            "settings": {},
            "next": "tcp_to_iran",
        })

    nodes.append({
        "name": "tcp_to_iran",
        "type": "TcpConnector",
        "settings": {
            "address": "$ip_server_iran$",
            "port": "$tunnel_carrier_port$",
            "nodelay": True,
        },
    })

    # --- UDP Outbound (Optional) ---
    if udp_forward_port:
        nodes.extend([
            {
                "name": "outbound_udp",
                "type": "UdpConnector",
                "settings": {
                    "address": "127.0.0.1",
                    "port": "$final_udp_port$",
                },
            },
            {
                "name": "t2u",
                "type": "UdpOverTcpServer",
                "settings": {},
                "next": "outbound_udp",
            },
            {
                "name": "bridge_udp_local",
                "type": "Bridge",
                "settings": {"pair": "bridge_udp_rev_client"},
                "next": "t2u",
            },
            {
                "name": "bridge_udp_rev_client",
                "type": "Bridge",
                "settings": {"pair": "bridge_udp_local"},
                "next": "rev_client_udp",
            },
            {
                "name": "rev_client_udp",
                "type": "ReverseClient",
                "settings": {"minimum-unused": 8},
                "next": "halfc_udp" if use_halfduplex else "reality_client_udp",
            },
        ])

        if use_halfduplex:
            nodes.append({
                "name": "halfc_udp",
                "type": "HalfDuplexClient",
                "settings": {},
                "next": "reality_client_udp",
            })

        reality_udp_next = "fisher_client_udp" if use_fisher else "tcp_to_iran_udp"
        nodes.append({
            "name": "reality_client_udp",
            "type": "RealityClient",
            "settings": {
                "sni": "$domain_to_handshake_reality$",
                "verify": True,
                "password": "$password$",
                "algorithm": "chacha20-poly1305",
                "kdf-iterations": 12000,
            },
            "next": reality_udp_next,
        })

        if use_fisher:
            nodes.append({
                "name": "fisher_client_udp",
                "type": "ConnectionFisherClient",
                "settings": {},
                "next": "tcp_to_iran_udp",
            })

        nodes.append({
            "name": "tcp_to_iran_udp",
            "type": "TcpConnector",
            "settings": {
                "address": "$ip_server_iran$",
                "port": "$tunnel_carrier_udp_port$",
                "nodelay": True,
            },
        })

    return {
        "name": config_name,
        "variables": variables,
        "nodes": nodes,
    }
