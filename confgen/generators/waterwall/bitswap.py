"""Waterwall BitSwap MUX Configuration Generator.

Unified generator supporting:
- Auto-detection: Single service vs Multiple/Hybrid services based on provided ports.
- Auto-detection: Single-IP vs Multi-IP based on presence of floating IPs.
- Pure Python standard library implementation.
"""

from typing import Any, Dict, List, Optional
from confgen.core.validator import validate_ip, validate_port
from confgen.core.utils import resolve_variables


def generate_bitswap_iran(
    config_name: str,
    iran_ip: str,
    kharej_ip: str,
    tcp_ports: Optional[List[int]] = None,
    udp_ports: Optional[List[int]] = None,
    float_ips: Optional[List[str]] = None,
    tcp_tunnel_port: int = 8443,
    udp_tunnel_port: int = 8444,
    mux_count: int = 8,
    use_proxy_protocol: bool = False,
    use_tls: bool = False,
    cert_path: Optional[str] = None,
    key_path: Optional[str] = None,
    xor_key: int = 90,
    custom_private_ip: Optional[str] = None,
    custom_private_ip_2: Optional[str] = None,
) -> Dict[str, Any]:
    """Generate unified Iran server BitSwap configuration.

    Auto-detects:
    - Single vs Multiple/Hybrid mode based on port counts.
    - Single-IP vs Multi-IP mode based on float_ips.
    """
    clean_iran = validate_ip(iran_ip)
    clean_kharej = validate_ip(kharej_ip)
    float_ips = [validate_ip(f) for f in (float_ips or [])]

    clean_tcp = [validate_port(p) for p in (tcp_ports or [])]
    clean_udp = [validate_port(p) for p in (udp_ports or [])]

    if not clean_tcp and not clean_udp:
        raise ValueError("At least one TCP or UDP port must be provided.")

    is_multi_ip = len(float_ips) > 0
    is_single_tcp = len(clean_tcp) == 1 and len(clean_udp) == 0
    is_single_udp = len(clean_tcp) == 0 and len(clean_udp) == 1
    is_single = is_single_tcp or is_single_udp

    # Subnets
    default_base = "10.30.0.1" if is_single_udp else "10.10.0.1"
    base_ip = custom_private_ip or default_base
    parts = base_ip.split(".")
    tun_ip1 = base_ip
    tun_ip2 = f"{parts[0]}.{parts[1]}.{parts[2]}.{int(parts[3]) + 1}"

    # Build variables
    variables: Dict[str, Any] = {
        "ip_server_iran": clean_iran,
    }

    if is_multi_ip:
        variables["ip_server_kharej_main"] = clean_kharej
        for idx, fip in enumerate(float_ips):
            variables[f"ip_server_kharej_float_{idx + 1}"] = fip
    else:
        variables["ip_server_kharej"] = clean_kharej

    if is_single_tcp:
        variables["port_to_listen"] = clean_tcp[0]
        variables["port_to_forward_to_kharej"] = tcp_tunnel_port
    elif is_single_udp:
        variables["port_to_listen"] = clean_udp[0]
        variables["port_to_forward_to_kharej"] = udp_tunnel_port
    else:
        # Multiple / Hybrid
        if clean_tcp:
            variables["ports_to_listen"] = clean_tcp
            variables["port_to_forward_to_kharej"] = tcp_tunnel_port
        if clean_udp:
            if len(clean_udp) == 1:
                variables["udp_port_to_listen"] = clean_udp[0]
                variables["udp_port_to_forward_to_kharej"] = udp_tunnel_port
            else:
                variables["udp_ports_to_listen"] = clean_udp
                variables["udp_port_to_forward_to_kharej"] = udp_tunnel_port

    variables.update(
        {
            "each_worker_mux_connections_count": mux_count,
            "tun_ip_1": tun_ip1,
            "tun_ip_2": tun_ip2,
        }
    )

    if use_tls and cert_path and key_path:
        variables["certificate_path"] = cert_path
        variables["key_path"] = key_path

    # Build nodes
    nodes: List[Dict[str, Any]] = []

    if is_single_tcp:
        entry_next = "mux-client"
        if use_proxy_protocol:
            entry_next = "proxy-header"
        if use_tls:
            entry_next = "tls_server_user_side_tls_termination"

        nodes.append(
            {
                "name": "users_inbound",
                "type": "TcpListener",
                "settings": {
                    "address": "0.0.0.0",
                    "port": "$port_to_listen$",
                    "nodelay": True,
                },
                "next": entry_next,
            }
        )
        if use_tls:
            nodes.append(
                {
                    "name": "tls_server_user_side_tls_termination",
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
                    "next": "proxy-header" if use_proxy_protocol else "mux-client",
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
                    "next": "mux-client",
                }
            )
        nodes.extend(
            [
                {
                    "name": "mux-client",
                    "type": "MuxClient",
                    "settings": {
                        "mode": "fixed-connections-count",
                        "per-worker-connections-count": "$each_worker_mux_connections_count$",
                    },
                    "next": "tcp-out",
                },
                {
                    "name": "tcp-out",
                    "type": "TcpConnector",
                    "settings": {
                        "address": "$tun_ip_2$",
                        "port": "$port_to_forward_to_kharej$",
                        "nodelay": True,
                    },
                },
            ]
        )

    elif is_single_udp:
        nodes.extend(
            [
                {
                    "name": "udp-users-inbound",
                    "type": "UdpListener",
                    "settings": {
                        "address": "0.0.0.0",
                        "port": "$port_to_listen$",
                    },
                    "next": "udp-over-tcp-client",
                },
                {
                    "name": "udp-over-tcp-client",
                    "type": "UdpOverTcpClient",
                    "settings": {},
                    "next": "mux-client",
                },
                {
                    "name": "mux-client",
                    "type": "MuxClient",
                    "settings": {
                        "mode": "fixed-connections-count",
                        "per-worker-connections-count": "$each_worker_mux_connections_count$",
                    },
                    "next": "tcp-out",
                },
                {
                    "name": "tcp-out",
                    "type": "TcpConnector",
                    "settings": {
                        "address": "$tun_ip_2$",
                        "port": "$port_to_forward_to_kharej$",
                        "nodelay": True,
                    },
                },
            ]
        )

    else:
        # Multiple / Hybrid services
        if clean_tcp:
            entry_next = "header-client"
            if use_tls:
                entry_next = "tls_server_user_side_tls_termination"
            elif use_proxy_protocol:
                entry_next = "proxy-header"

            nodes.append(
                {
                    "name": "users_inbound",
                    "type": "TcpListener",
                    "settings": {
                        "address": "0.0.0.0",
                        "port": "$ports_to_listen$",
                        "nodelay": True,
                    },
                    "next": entry_next,
                }
            )
            if use_tls:
                nodes.append(
                    {
                        "name": "tls_server_user_side_tls_termination",
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
                        "next": "proxy-header" if use_proxy_protocol else "header-client",
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
                        "next": "header-client",
                    }
                )
            nodes.extend(
                [
                    {
                        "name": "header-client",
                        "type": "HeaderClient",
                        "settings": {
                            "data": "src_context->port",
                        },
                        "next": "mux-client",
                    },
                    {
                        "name": "mux-client",
                        "type": "MuxClient",
                        "settings": {
                            "mode": "fixed-connections-count",
                            "per-worker-connections-count": "$each_worker_mux_connections_count$",
                        },
                        "next": "tcp-out",
                    },
                    {
                        "name": "tcp-out",
                        "type": "TcpConnector",
                        "settings": {
                            "address": "$tun_ip_2$",
                            "port": "$port_to_forward_to_kharej$",
                            "nodelay": True,
                        },
                    },
                ]
            )

        if clean_udp:
            if len(clean_udp) == 1:
                nodes.extend(
                    [
                        {
                            "name": "udp-users-inbound",
                            "type": "UdpListener",
                            "settings": {
                                "address": "0.0.0.0",
                                "port": "$udp_port_to_listen$",
                            },
                            "next": "udp-over-tcp-client",
                        },
                        {
                            "name": "udp-over-tcp-client",
                            "type": "UdpOverTcpClient",
                            "settings": {},
                            "next": "udp-mux-client",
                        },
                        {
                            "name": "udp-mux-client",
                            "type": "MuxClient",
                            "settings": {
                                "mode": "fixed-connections-count",
                                "per-worker-connections-count": "$each_worker_mux_connections_count$",
                            },
                            "next": "udp-tcp-out",
                        },
                        {
                            "name": "udp-tcp-out",
                            "type": "TcpConnector",
                            "settings": {
                                "address": "$tun_ip_2$",
                                "port": "$udp_port_to_forward_to_kharej$",
                                "nodelay": True,
                            },
                        },
                    ]
                )
            else:
                for idx, u_port in enumerate(clean_udp):
                    u_fwd = udp_tunnel_port + idx
                    nodes.extend(
                        [
                            {
                                "name": f"udp-users-inbound-{u_port}",
                                "type": "UdpListener",
                                "settings": {
                                    "address": "0.0.0.0",
                                    "port": u_port,
                                },
                                "next": f"udp-over-tcp-client-{u_port}",
                            },
                            {
                                "name": f"udp-over-tcp-client-{u_port}",
                                "type": "UdpOverTcpClient",
                                "settings": {},
                                "next": f"udp-mux-client-{u_port}",
                            },
                            {
                                "name": f"udp-mux-client-{u_port}",
                                "type": "MuxClient",
                                "settings": {
                                    "mode": "fixed-connections-count",
                                    "per-worker-connections-count": "$each_worker_mux_connections_count$",
                                },
                                "next": f"udp-tcp-out-{u_port}",
                            },
                            {
                                "name": f"udp-tcp-out-{u_port}",
                                "type": "TcpConnector",
                                "settings": {
                                    "address": "$tun_ip_2$",
                                    "port": u_fwd,
                                    "nodelay": True,
                                },
                            },
                        ]
                    )

    # Common Iran transport nodes (TUN + IPOverrider + Splitter + Obfuscator + RawSocket)
    target_dest_ip = "$ip_server_kharej_main$" if is_multi_ip else "$ip_server_kharej$"
    rd2_settings: Dict[str, Any] = {"capture-filter-mode": "source-ip"}
    if is_multi_ip:
        capture_list = ["$ip_server_kharej_main$"] + [
            f"$ip_server_kharej_float_{i + 1}$" for i in range(len(float_ips))
        ]
        rd2_settings["capture-ips"] = capture_list
    else:
        rd2_settings["capture-ip"] = "$ip_server_kharej$"

    nodes.extend(
        [
            {
                "name": "my tun",
                "type": "TunDevice",
                "settings": {
                    "device-name": config_name,
                    "device-ip": f"{tun_ip1}/24",
                },
                "next": "ipovsrc",
            },
            {
                "name": "ipovsrc",
                "type": "IpOverrider",
                "settings": {
                    "up": {
                        "source-ip": {"ipv4": "$ip_server_iran$"},
                        "dest-ip": {"ipv4": target_dest_ip},
                    },
                    "down": {
                        "source-ip": {"ipv4": "$tun_ip_2$"},
                        "dest-ip": {"ipv4": "$tun_ip_1$"},
                    },
                },
                "next": "splitter",
            },
            {
                "name": "splitter",
                "type": "PacketSplitStream",
                "settings": {
                    "up": "obfuscator-c",
                    "down": "obfuscator-s",
                },
            },
            {
                "name": "obfuscator-c",
                "type": "ObfuscatorClient",
                "settings": {
                    "method": "xor",
                    "xor_key": xor_key,
                    "skip": "transport",
                },
                "next": "ip-manipulator-up",
            },
            {
                "name": "ip-manipulator-up",
                "type": "IpManipulator",
                "settings": {
                    "up-tcp-bit-psh": "packet->cwr",
                    "up-tcp-bit-cwr": "packet->psh",
                },
                "next": "rd",
            },
            {
                "name": "rd",
                "type": "RawSocket",
                "settings": {
                    "capture-filter-mode": "source-ip",
                    "capture-ip": "12.12.12.12/32",
                },
            },
            {
                "name": "obfuscator-s",
                "type": "ObfuscatorServer",
                "settings": {
                    "method": "xor",
                    "xor_key": xor_key,
                    "skip": "transport",
                },
                "next": "ip-manipulator",
            },
            {
                "name": "ip-manipulator",
                "type": "IpManipulator",
                "settings": {
                    "dw-tcp-bit-psh": "packet->cwr",
                    "dw-tcp-bit-cwr": "packet->psh",
                },
                "next": "rd2",
            },
            {
                "name": "rd2",
                "type": "RawSocket",
                "settings": rd2_settings,
            },
        ]
    )

    return resolve_variables({
        "name": config_name,
        "variables": variables,
        "nodes": nodes,
    })


def generate_bitswap_kharej(
    config_name: str,
    iran_ip: str,
    kharej_ip: str,
    tcp_ports: Optional[List[int]] = None,
    udp_ports: Optional[List[int]] = None,
    float_ips: Optional[List[str]] = None,
    tcp_tunnel_port: int = 8443,
    udp_tunnel_port: int = 8444,
    final_ip: str = "127.0.0.1",
    xor_key: int = 90,
    custom_private_ip: Optional[str] = None,
    custom_private_ip_2: Optional[str] = None,
) -> Dict[str, Any]:
    """Generate unified Kharej server BitSwap configuration.

    Auto-detects:
    - Single vs Multiple/Hybrid mode based on port counts.
    - Single-IP vs Multi-IP mode based on float_ips.
    """
    clean_iran = validate_ip(iran_ip)
    clean_kharej = validate_ip(kharej_ip)
    float_ips = [validate_ip(f) for f in (float_ips or [])]

    clean_tcp = [validate_port(p) for p in (tcp_ports or [])]
    clean_udp = [validate_port(p) for p in (udp_ports or [])]

    if not clean_tcp and not clean_udp:
        raise ValueError("At least one TCP or UDP port must be provided.")

    is_multi_ip = len(float_ips) > 0
    is_single_tcp = len(clean_tcp) == 1 and len(clean_udp) == 0
    is_single_udp = len(clean_tcp) == 0 and len(clean_udp) == 1
    is_single = is_single_tcp or is_single_udp

    # Subnets
    default_base = "10.30.0.1" if is_single_udp else "10.10.0.1"
    base_ip = custom_private_ip or default_base
    parts = base_ip.split(".")
    tun_ip1 = base_ip
    tun_ip2 = f"{parts[0]}.{parts[1]}.{parts[2]}.{int(parts[3]) + 1}"
    tun2_ip1 = custom_private_ip_2 or f"{parts[0]}.{int(parts[1]) + 10}.{parts[2]}.{parts[3]}"

    # Variables
    variables: Dict[str, Any] = {
        "ip_server_iran": clean_iran,
    }

    if is_multi_ip:
        variables["ip_server_kharej_main"] = clean_kharej
        for idx, fip in enumerate(float_ips):
            variables[f"ip_server_kharej_float_{idx + 1}"] = fip
    else:
        variables["ip_server_kharej"] = clean_kharej

    if is_single_tcp:
        variables["port_to_listen"] = tcp_tunnel_port
        variables["final_ip"] = final_ip
        variables["final_port"] = clean_tcp[0]
    elif is_single_udp:
        variables["port_to_listen"] = udp_tunnel_port
        variables["final_ip"] = final_ip
        variables["final_port"] = clean_udp[0]
    else:
        # Multiple / Hybrid
        if clean_tcp:
            variables["port_to_listen"] = tcp_tunnel_port
        if clean_udp:
            variables["udp_port_to_listen"] = udp_tunnel_port
        variables["final_ip"] = final_ip
        if clean_tcp:
            variables["final_port"] = clean_tcp[0]
        if clean_udp:
            variables["udp_final_port"] = clean_udp[0]

    variables.update(
        {
            "tun_ip_1": tun_ip1,
            "tun_ip_2": tun_ip2,
            "tun2_ip_1": tun2_ip1,
        }
    )

    # Nodes
    nodes: List[Dict[str, Any]] = []

    if is_single_tcp:
        nodes.extend(
            [
                {
                    "name": "users_inbound",
                    "type": "TcpListener",
                    "settings": {
                        "address": "0.0.0.0",
                        "port": "$port_to_listen$",
                        "nodelay": True,
                        "initial-idle-timeout-ms": 3600000,
                        "active-idle-timeout-ms": 3600000,
                    },
                    "next": "mux-s",
                },
                {
                    "name": "mux-s",
                    "type": "MuxServer",
                    "settings": {},
                    "next": "tcp-out",
                },
                {
                    "name": "tcp-out",
                    "type": "TcpConnector",
                    "settings": {
                        "address": "$final_ip$",
                        "port": "$final_port$",
                        "nodelay": True,
                    },
                },
            ]
        )

    elif is_single_udp:
        nodes.extend(
            [
                {
                    "name": "users_inbound",
                    "type": "TcpListener",
                    "settings": {
                        "address": "0.0.0.0",
                        "port": "$port_to_listen$",
                        "nodelay": True,
                        "initial-idle-timeout-ms": 3600000,
                        "active-idle-timeout-ms": 3600000,
                    },
                    "next": "mux-s",
                },
                {
                    "name": "mux-s",
                    "type": "MuxServer",
                    "settings": {},
                    "next": "udp-over-tcp-server",
                },
                {
                    "name": "udp-over-tcp-server",
                    "type": "UdpOverTcpServer",
                    "settings": {},
                    "next": "udp-out",
                },
                {
                    "name": "udp-out",
                    "type": "UdpConnector",
                    "settings": {
                        "address": "$final_ip$",
                        "port": "$final_port$",
                    },
                },
            ]
        )

    else:
        # Multiple / Hybrid
        if clean_tcp:
            nodes.extend(
                [
                    {
                        "name": "users_inbound",
                        "type": "TcpListener",
                        "settings": {
                            "address": "0.0.0.0",
                            "port": "$port_to_listen$",
                            "nodelay": True,
                            "initial-idle-timeout-ms": 3600000,
                            "active-idle-timeout-ms": 3600000,
                        },
                        "next": "mux-s",
                    },
                    {
                        "name": "mux-s",
                        "type": "MuxServer",
                        "settings": {},
                        "next": "header-server",
                    },
                    {
                        "name": "header-server",
                        "type": "HeaderServer",
                        "settings": {
                            "override": "dest_context->port",
                        },
                        "next": "tcp-out",
                    },
                    {
                        "name": "tcp-out",
                        "type": "TcpConnector",
                        "settings": {
                            "address": "$final_ip$",
                            "port": "dest_context->port",
                            "nodelay": True,
                        },
                    },
                ]
            )

        if clean_udp:
            if len(clean_udp) == 1:
                nodes.extend(
                    [
                        {
                            "name": "udp-users-inbound",
                            "type": "TcpListener",
                            "settings": {
                                "address": "0.0.0.0",
                                "port": "$udp_port_to_listen$",
                                "nodelay": True,
                                "initial-idle-timeout-ms": 3600000,
                                "active-idle-timeout-ms": 3600000,
                            },
                            "next": "udp-mux-s",
                        },
                        {
                            "name": "udp-mux-s",
                            "type": "MuxServer",
                            "settings": {},
                            "next": "udp-over-tcp-server",
                        },
                        {
                            "name": "udp-over-tcp-server",
                            "type": "UdpOverTcpServer",
                            "settings": {},
                            "next": "udp-out",
                        },
                        {
                            "name": "udp-out",
                            "type": "UdpConnector",
                            "settings": {
                                "address": "$final_ip$",
                                "port": "$udp_final_port$",
                            },
                        },
                    ]
                )
            else:
                for idx, u_port in enumerate(clean_udp):
                    u_listen = udp_tunnel_port + idx
                    nodes.extend(
                        [
                            {
                                "name": f"udp-users-inbound-{u_port}",
                                "type": "TcpListener",
                                "settings": {
                                    "address": "0.0.0.0",
                                    "port": u_listen,
                                    "nodelay": True,
                                    "initial-idle-timeout-ms": 3600000,
                                    "active-idle-timeout-ms": 3600000,
                                },
                                "next": f"udp-mux-s-{u_port}",
                            },
                            {
                                "name": f"udp-mux-s-{u_port}",
                                "type": "MuxServer",
                                "settings": {},
                                "next": f"udp-over-tcp-server-{u_port}",
                            },
                            {
                                "name": f"udp-over-tcp-server-{u_port}",
                                "type": "UdpOverTcpServer",
                                "settings": {},
                                "next": f"udp-out-{u_port}",
                            },
                            {
                                "name": f"udp-out-{u_port}",
                                "type": "UdpConnector",
                                "settings": {
                                    "address": "$final_ip$",
                                    "port": u_port,
                                },
                            },
                        ]
                    )

    # Kharej tunnel chain (my tun2 -> ipcorrect -> obfuscator-s -> ip-manipulator-in -> rdin -> my tun -> ipovsrc -> obfuscator-c -> ip-manipulator -> rd)
    up_source_ip: Any = ["$ip_server_kharej_main$"] + [
        f"$ip_server_kharej_float_{i + 1}$" for i in range(len(float_ips))
    ] if is_multi_ip else "$ip_server_kharej$"

    nodes.extend(
        [
            {
                "name": "my tun2",
                "type": "TunDevice",
                "settings": {
                    "device-name": f"{config_name}2",
                    "device-ip": f"{tun2_ip1}/24",
                },
                "next": "ipcorrect",
            },
            {
                "name": "ipcorrect",
                "type": "IpOverrider",
                "settings": {
                    "up": {
                        "source-ip": {"ipv4": "$tun_ip_2$"},
                        "dest-ip": {"ipv4": "$tun_ip_1$"},
                    },
                    "down": {
                        "source-ip": {"ipv4": "$tun_ip_2$"},
                        "dest-ip": {"ipv4": "$tun_ip_1$"},
                    },
                },
                "next": "obfuscator-s",
            },
            {
                "name": "obfuscator-s",
                "type": "ObfuscatorServer",
                "settings": {
                    "method": "xor",
                    "xor_key": xor_key,
                    "skip": "transport",
                },
                "next": "ip-manipulator-in",
            },
            {
                "name": "ip-manipulator-in",
                "type": "IpManipulator",
                "settings": {
                    "dw-tcp-bit-psh": "packet->cwr",
                    "dw-tcp-bit-cwr": "packet->psh",
                },
                "next": "rdin",
            },
            {
                "name": "rdin",
                "type": "RawSocket",
                "settings": {
                    "capture-filter-mode": "source-ip",
                    "capture-ip": "$ip_server_iran$",
                },
            },
            {
                "name": "my tun",
                "type": "TunDevice",
                "settings": {
                    "device-name": config_name,
                    "device-ip": f"{tun_ip1}/24",
                },
                "next": "ipovsrc",
            },
            {
                "name": "ipovsrc",
                "type": "IpOverrider",
                "settings": {
                    "up": {
                        "source-ip": {"ipv4": up_source_ip},
                        "dest-ip": {"ipv4": "$ip_server_iran$"},
                    },
                    "down": {
                        "source-ip": {"ipv4": "$tun_ip_2$"},
                        "dest-ip": {"ipv4": "$tun_ip_1$"},
                    },
                },
                "next": "obfuscator-c",
            },
            {
                "name": "obfuscator-c",
                "type": "ObfuscatorClient",
                "settings": {
                    "method": "xor",
                    "xor_key": xor_key,
                    "skip": "transport",
                },
                "next": "ip-manipulator",
            },
            {
                "name": "ip-manipulator",
                "type": "IpManipulator",
                "settings": {
                    "up-tcp-bit-psh": "packet->cwr",
                    "up-tcp-bit-cwr": "packet->psh",
                },
                "next": "rd",
            },
            {
                "name": "rd",
                "type": "RawSocket",
                "settings": {
                    "capture-filter-mode": "source-ip",
                    "capture-ip": "12.13.12.13",
                },
            },
        ]
    )

    return resolve_variables({
        "name": config_name,
        "variables": variables,
        "nodes": nodes,
    })


# Backwards compatibility wrappers
def generate_bitswap_tcp_iran(
    config_name: str,
    iran_ip: str,
    kharej_ip: str,
    listen_port: int,
    forward_port: int,
    mode: str = "single",
    float_ips: Optional[List[str]] = None,
    mux_count: int = 8,
    use_proxy_protocol: bool = False,
    use_tls: bool = False,
    cert_path: Optional[str] = None,
    key_path: Optional[str] = None,
    xor_key: int = 90,
    custom_private_ip: Optional[str] = None,
) -> Dict[str, Any]:
    return generate_bitswap_iran(
        config_name=config_name,
        iran_ip=iran_ip,
        kharej_ip=kharej_ip,
        tcp_ports=[listen_port],
        float_ips=float_ips if mode == "multi" else (float_ips or []),
        tcp_tunnel_port=forward_port,
        mux_count=mux_count,
        use_proxy_protocol=use_proxy_protocol,
        use_tls=use_tls,
        cert_path=cert_path,
        key_path=key_path,
        xor_key=xor_key,
        custom_private_ip=custom_private_ip,
    )


def generate_bitswap_tcp_kharej(
    config_name: str,
    iran_ip: str,
    kharej_ip: str,
    listen_port: int,
    final_port: int,
    final_ip: str = "127.0.0.1",
    mode: str = "single",
    float_ips: Optional[List[str]] = None,
    xor_key: int = 90,
    custom_private_ip: Optional[str] = None,
) -> Dict[str, Any]:
    return generate_bitswap_kharej(
        config_name=config_name,
        iran_ip=iran_ip,
        kharej_ip=kharej_ip,
        tcp_ports=[final_port],
        float_ips=float_ips if mode == "multi" else (float_ips or []),
        tcp_tunnel_port=listen_port,
        final_ip=final_ip,
        xor_key=xor_key,
        custom_private_ip=custom_private_ip,
    )


def generate_bitswap_udp_iran(
    config_name: str,
    iran_ip: str,
    kharej_ip: str,
    listen_port: int,
    forward_port: int,
    mode: str = "single",
    float_ips: Optional[List[str]] = None,
    mux_count: int = 8,
    xor_key: int = 90,
    custom_private_ip: Optional[str] = None,
) -> Dict[str, Any]:
    return generate_bitswap_iran(
        config_name=config_name,
        iran_ip=iran_ip,
        kharej_ip=kharej_ip,
        udp_ports=[listen_port],
        float_ips=float_ips if mode == "multi" else (float_ips or []),
        udp_tunnel_port=forward_port,
        mux_count=mux_count,
        xor_key=xor_key,
        custom_private_ip=custom_private_ip,
    )


def generate_bitswap_udp_kharej(
    config_name: str,
    iran_ip: str,
    kharej_ip: str,
    listen_port: int,
    final_port: int,
    final_ip: str = "127.0.0.1",
    mode: str = "single",
    float_ips: Optional[List[str]] = None,
    xor_key: int = 90,
    custom_private_ip: Optional[str] = None,
) -> Dict[str, Any]:
    return generate_bitswap_kharej(
        config_name=config_name,
        iran_ip=iran_ip,
        kharej_ip=kharej_ip,
        udp_ports=[final_port],
        float_ips=float_ips if mode == "multi" else (float_ips or []),
        udp_tunnel_port=listen_port,
        final_ip=final_ip,
        xor_key=xor_key,
        custom_private_ip=custom_private_ip,
    )
