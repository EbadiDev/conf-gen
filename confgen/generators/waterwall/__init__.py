"""Waterwall Generator Modules Package."""

from .reverse_reality import (
    generate_reverse_reality_tcp_iran,
    generate_reverse_reality_tcp_kharej,
)
from .tls_reverse import (
    generate_waterwall_tls_reverse_iran,
    generate_waterwall_tls_reverse_kharej,
)
from .udp_reverse import (
    generate_udp_reverse_iran,
    generate_udp_reverse_kharej,
)
from .bitswap import (
    generate_bitswap_iran,
    generate_bitswap_kharej,
    generate_bitswap_tcp_iran,
    generate_bitswap_tcp_kharej,
    generate_bitswap_udp_iran,
    generate_bitswap_udp_kharej,
)
from .protoswap import (
    generate_protoswap_iran,
    generate_protoswap_kharej,
)
from .benchmark import (
    generate_speedtest_server_config,
    generate_speedtest_client_config,
    generate_benchmark_suite,
)
from .core import generate_core_config
from .simple import generate_simple_config

__all__ = [
    "generate_reverse_reality_tcp_iran",
    "generate_reverse_reality_tcp_kharej",
    "generate_waterwall_tls_reverse_iran",
    "generate_waterwall_tls_reverse_kharej",
    "generate_udp_reverse_iran",
    "generate_udp_reverse_kharej",
    "generate_bitswap_iran",
    "generate_bitswap_kharej",
    "generate_bitswap_tcp_iran",
    "generate_bitswap_tcp_kharej",
    "generate_bitswap_udp_iran",
    "generate_bitswap_udp_kharej",
    "generate_protoswap_iran",
    "generate_protoswap_kharej",
    "generate_speedtest_server_config",
    "generate_speedtest_client_config",
    "generate_benchmark_suite",
    "generate_core_config",
    "generate_simple_config",
]
