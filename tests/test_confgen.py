"""Unit tests for ConfGen Python package."""

import unittest
from confgen.core.validator import validate_ip, validate_port, validate_ports_list
from confgen.generators.xray import generate_xray_iran_config, generate_xray_kharej_config
from confgen.generators.waterwall.reverse_reality import generate_reverse_reality_tcp_iran, generate_reverse_reality_tcp_kharej
from confgen.generators.waterwall.tls_reverse import generate_waterwall_tls_reverse_iran, generate_waterwall_tls_reverse_kharej
from confgen.generators.waterwall.simple import generate_simple_config


class TestValidator(unittest.TestCase):
    def test_validate_port(self):
        self.assertEqual(validate_port(80), 80)
        self.assertEqual(validate_port("443"), 443)
        with self.assertRaises(ValueError):
            validate_port(70000)
        with self.assertRaises(ValueError):
            validate_port(-1)

    def test_validate_ports_list(self):
        self.assertEqual(validate_ports_list("8085,8086, 8087"), [8085, 8086, 8087])
        self.assertEqual(validate_ports_list([80, 443]), [80, 443])

    def test_validate_ip(self):
        self.assertEqual(validate_ip("1.1.1.1"), "1.1.1.1")
        self.assertEqual(validate_ip("10.0.0.1/24"), "10.0.0.1/24")
        with self.assertRaises(ValueError):
            validate_ip("999.999.999.999")


class TestXrayGenerator(unittest.TestCase):
    def test_xray_iran_config(self):
        cfg = generate_xray_iran_config(
            listen_port=8443,
            tcp_ports=[8085, 8086],
            udp_ports=[8087],
            ws_path="/api/v3/live",
        )
        self.assertEqual(cfg["inbounds"][0]["port"], 8443)
        self.assertEqual(cfg["inbounds"][0]["streamSettings"]["network"], "ws")
        self.assertEqual(len(cfg["inbounds"]), 4)  # 1 portal + 2 tcp + 1 udp
        self.assertEqual(len(cfg["routing"]["rules"][0]["inboundTag"]), 3)

    def test_xray_kharej_config(self):
        cfg = generate_xray_kharej_config(
            iran_ip="109.94.164.214",
            connect_port=8443,
            ws_path="/api/v3/live",
            tls_sni="france.archlix.com",
        )
        bridge = cfg["outbounds"][1]
        self.assertEqual(bridge["settings"]["address"], "109.94.164.214")
        self.assertEqual(bridge["streamSettings"]["security"], "tls")
        self.assertEqual(bridge["streamSettings"]["tlsSettings"]["serverName"], "france.archlix.com")


class TestWaterwallGenerators(unittest.TestCase):
    def test_simple_config(self):
        cfg = generate_simple_config("test", "tcp", 80, 80, "1.1.1.1", 8080)
        self.assertEqual(cfg["name"], "test")
        self.assertEqual(cfg["nodes"][0]["type"], "TcpListener")
        self.assertEqual(cfg["nodes"][1]["type"], "TcpConnector")

    def test_reverse_reality_tcp(self):
        iran_cfg = generate_reverse_reality_tcp_iran(
            config_name="rr_test",
            iran_ip="1.1.1.1",
            kharej_ip="2.2.2.2",
            port=443,
            domain="example.com",
            white_ip="3.3.3.3",
            float_ips=["2.2.2.3", "2.2.2.4"],
        )
        self.assertEqual(iran_cfg["name"], "rr_test")
        self.assertIn("ip_server_kharej_float_1", iran_cfg["variables"])

    def test_tls_reverse(self):
        kharej_cfg = generate_waterwall_tls_reverse_kharej(
            config_name="tls_test",
            iran_ip="1.1.1.1",
            port=8443,
            sni="domain.com",
            final_port=8080,
        )
        self.assertEqual(kharej_cfg["name"], "tls_test")
        self.assertEqual(kharej_cfg["variables"]["domain_to_handshake_tls"], "domain.com")

    def test_bitswap_tcp_and_udp_legacy(self):
        from confgen.generators.waterwall.bitswap import (
            generate_bitswap_tcp_iran,
            generate_bitswap_tcp_kharej,
            generate_bitswap_udp_iran,
            generate_bitswap_udp_kharej,
        )
        i_tcp = generate_bitswap_tcp_iran("bs_i", "1.1.1.1", "2.2.2.2", 2087, 2087)
        self.assertEqual(i_tcp["variables"]["port_to_listen"], 2087)

        k_tcp = generate_bitswap_tcp_kharej("bs_k", "1.1.1.1", "2.2.2.2", 2087, 2087)
        self.assertEqual(k_tcp["variables"]["final_port"], 2087)

        i_udp = generate_bitswap_udp_iran("bs_u_i", "1.1.1.1", "2.2.2.2", 27015, 27015)
        self.assertEqual(i_udp["nodes"][0]["type"], "UdpListener")

        k_udp = generate_bitswap_udp_kharej("bs_u_k", "1.1.1.1", "2.2.2.2", 27015, 27015)
        self.assertEqual(k_udp["variables"]["port_to_listen"], 27015)

    def test_bitswap_unified_auto_detection(self):
        from confgen.generators.waterwall.bitswap import (
            generate_bitswap_iran,
            generate_bitswap_kharej,
        )
        # 1. Single TCP: auto-detected as single
        single_i = generate_bitswap_iran("s_i", "198.51.100.1", "203.0.113.1", tcp_ports=[443], tcp_tunnel_port=8443)
        self.assertEqual(single_i["variables"]["port_to_listen"], 443)
        self.assertEqual(single_i["variables"]["ip_server_kharej"], "203.0.113.1")
        self.assertEqual(single_i["nodes"][0]["type"], "TcpListener")
        self.assertEqual(single_i["nodes"][1]["type"], "MuxClient")  # Direct MUX, no HeaderClient

        # 2. Multi-TCP: auto-detected as multiple (with HeaderClient)
        multi_i = generate_bitswap_iran("m_i", "198.51.100.1", "203.0.113.1", tcp_ports=[6443, 2059], tcp_tunnel_port=8445)
        self.assertEqual(multi_i["variables"]["ports_to_listen"], [6443, 2059])
        self.assertEqual(multi_i["nodes"][1]["name"], "header-client")

        # 3. Hybrid TCP + UDP with Floating IPs (Multi-IP)
        hybrid_i = generate_bitswap_iran(
            "h_i",
            "198.51.100.1",
            "203.0.113.1",
            tcp_ports=[6443, 2059],
            udp_ports=[27015],
            float_ips=["203.0.113.2"],
            tcp_tunnel_port=8445,
            udp_tunnel_port=8446,
            use_proxy_protocol=True,
            use_tls=True,
            cert_path="/path/cert.pem",
            key_path="/path/key.pem",
        )
        self.assertIn("ip_server_kharej_main", hybrid_i["variables"])
        self.assertIn("ip_server_kharej_float_1", hybrid_i["variables"])
        self.assertEqual(hybrid_i["variables"]["udp_port_to_listen"], 27015)
        # Check node presence
        node_names = [n["name"] for n in hybrid_i["nodes"]]
        self.assertIn("tls_server_user_side_tls_termination", node_names)
        self.assertIn("proxy-header", node_names)
        self.assertIn("header-client", node_names)
        self.assertIn("udp-users-inbound", node_names)

        # 4. Kharej side hybrid
        hybrid_k = generate_bitswap_kharej(
            "h_k",
            "198.51.100.1",
            "203.0.113.1",
            tcp_ports=[6443, 2059],
            udp_ports=[27015],
            float_ips=["203.0.113.2"],
            tcp_tunnel_port=8445,
            udp_tunnel_port=8446,
        )
        self.assertIn("ip_server_kharej_main", hybrid_k["variables"])
        k_node_names = [n["name"] for n in hybrid_k["nodes"]]
        self.assertIn("header-server", k_node_names)
        self.assertIn("udp-users-inbound", k_node_names)

    def test_protoswap_unified_auto_detection(self):
        from confgen.generators.waterwall.protoswap import (
            generate_protoswap_iran,
            generate_protoswap_kharej,
        )
        # 1. Single TCP: auto-detected as single
        single_i = generate_protoswap_iran(
            "ps_s_i", "198.51.100.1", "203.0.113.1", tcp_ports=[443], tcp_tunnel_port=8443, protoswap_tcp=253
        )
        self.assertEqual(single_i["variables"]["port_to_listen"], 443)
        self.assertEqual(single_i["variables"]["ip_server_kharej"], "203.0.113.1")
        self.assertEqual(single_i["nodes"][0]["type"], "TcpListener")
        self.assertEqual(single_i["nodes"][1]["type"], "MuxClient")
        manipulator_nodes = [n for n in single_i["nodes"] if n["type"] == "IpManipulator"]
        self.assertEqual(single_i["variables"]["protoswap_tcp_to_number"], 253)
        self.assertEqual(manipulator_nodes[0]["settings"]["protoswap-tcp"], "$protoswap_tcp_to_number$")

        # 2. Multi-TCP: auto-detected as multiple (with HeaderClient)
        multi_i = generate_protoswap_iran(
            "ps_m_i", "198.51.100.1", "203.0.113.1", tcp_ports=[6443, 2059], tcp_tunnel_port=8445
        )
        self.assertEqual(multi_i["variables"]["ports_to_listen"], [6443, 2059])
        self.assertEqual(multi_i["nodes"][1]["name"], "header-client")

        # 3. Hybrid TCP + UDP with Floating IPs (Multi-IP) and custom protoswap numbers
        hybrid_i = generate_protoswap_iran(
            "ps_h_i",
            "198.51.100.1",
            "203.0.113.1",
            tcp_ports=[6443, 2059],
            udp_ports=[27015],
            float_ips=["203.0.113.2"],
            protoswap_tcp=250,
            protoswap_udp=251,
            tcp_tunnel_port=8445,
            udp_tunnel_port=8446,
            use_proxy_protocol=True,
            use_tls=True,
            cert_path="/path/cert.pem",
            key_path="/path/key.pem",
        )
        self.assertIn("ip_server_kharej_main", hybrid_i["variables"])
        self.assertIn("ip_server_kharej_float_1", hybrid_i["variables"])
        self.assertEqual(hybrid_i["variables"]["udp_port_to_listen"], 27015)
        node_names = [n["name"] for n in hybrid_i["nodes"]]
        self.assertIn("tls_server_user_side_tls_termination", node_names)
        self.assertIn("proxy-header", node_names)
        self.assertIn("header-client", node_names)
        self.assertIn("udp-users-inbound", node_names)

        # 4. Kharej side hybrid
        hybrid_k = generate_protoswap_kharej(
            "ps_h_k",
            "198.51.100.1",
            "203.0.113.1",
            tcp_ports=[6443, 2059],
            udp_ports=[27015],
            float_ips=["203.0.113.2"],
            protoswap_tcp=250,
            protoswap_udp=251,
            tcp_tunnel_port=8445,
            udp_tunnel_port=8446,
        )
        self.assertIn("ip_server_kharej_main", hybrid_k["variables"])
        k_node_names = [n["name"] for n in hybrid_k["nodes"]]
        self.assertIn("header-server", k_node_names)
        self.assertIn("udp-users-inbound", k_node_names)

        # 5. Invalid protocol validation
        with self.assertRaises(ValueError):
            generate_protoswap_iran("err", "198.51.100.1", "203.0.113.1", tcp_ports=[443], protoswap_tcp=6)
        with self.assertRaises(ValueError):
            generate_protoswap_iran("err", "198.51.100.1", "203.0.113.1", udp_ports=[53], protoswap_udp=17)
        with self.assertRaises(ValueError):
            generate_protoswap_iran("err", "198.51.100.1", "203.0.113.1", tcp_ports=[443], protoswap_tcp=250, protoswap_udp=250)

    def test_benchmark_generators(self):
        from confgen.generators.waterwall.benchmark import (
            generate_speedtest_server_config,
            generate_speedtest_client_config,
            generate_benchmark_suite,
        )
        # Server
        srv = generate_speedtest_server_config("srv", tcp_port=9000, udp_port=9001)
        self.assertEqual(len(srv["nodes"]), 4)  # 2 listeners + 2 servers
        self.assertEqual(srv["nodes"][0]["settings"]["port"], 9000)
        self.assertEqual(srv["nodes"][2]["settings"]["port"], 9001)

        # Client TCP
        c_tcp = generate_speedtest_client_config("c_tcp", "127.0.0.1", 6443, mode="tcp")
        self.assertEqual(c_tcp["nodes"][0]["settings"]["mode"], "tcp")
        self.assertEqual(c_tcp["nodes"][1]["type"], "TcpConnector")

        # Client UDP
        c_udp = generate_speedtest_client_config("c_udp", "127.0.0.1", 27015, mode="udp", udp_target_bits_per_sec=50000000)
        self.assertEqual(c_udp["nodes"][0]["settings"]["mode"], "udp")
        self.assertEqual(c_udp["nodes"][0]["settings"]["udp-target-bits-per-sec"], 50000000)
        self.assertEqual(c_udp["nodes"][1]["type"], "UdpConnector")

        # Suite
        suite = generate_benchmark_suite(
            iran_ip="198.51.100.10",
            kharej_ip="203.0.113.20",
            output_dir="/tmp/bench",
            tcp_ports=[6443],
            udp_ports=[27015],
        )
        self.assertIn("kharej_speedtest_server.json", suite)
        self.assertIn("client_test_tcp.json", suite)
        self.assertIn("client_test_udp.json", suite)
        self.assertIn("iran_bitswap.json", suite)
        self.assertIn("iran_protoswap_253.json", suite)
        self.assertIn("run_benchmark.py", suite)


class TestCLIFlags(unittest.TestCase):
    def test_cli_xray_flags(self):
        from confgen.cli import main
        import tempfile
        import os
        import json

        with tempfile.TemporaryDirectory() as tmpdir:
            out_file = os.path.join(tmpdir, "test-xray.json")
            ret = main(["xray", "reverse", "iran", "-n", "test-xray", "-p", "8443", "--tcp", "8085,8086", "-o", out_file])
            self.assertEqual(ret, 0)
            self.assertTrue(os.path.exists(out_file))
            with open(out_file) as f:
                data = json.load(f)
            self.assertEqual(data["inbounds"][0]["port"], 8443)

    def test_cli_bitswap_unified(self):
        from confgen.cli import main
        import tempfile
        import os
        import json

        with tempfile.TemporaryDirectory() as tmpdir:
            out_file = os.path.join(tmpdir, "test-bitswap.json")
            # Testing unified user command format without -m or --proto
            cmd = [
                "waterwall", "bitswap", "iran",
                "nuremberg-bit", "198.51.100.10", "203.0.113.20",
                "--tcp", "6443,2059",
                "--udp", "27015",
                "--private-ip", "10.50.0.1",
                "--tcp-tunnel-port", "8445",
                "--udp-tunnel-port", "8446",
                "--proxy-protocol",
                "--float", "203.0.113.21",
                "--tls", "/tmp/cert.pem", "/tmp/key.pem",
                "-o", out_file,
            ]
            ret = main(cmd)
            self.assertEqual(ret, 0)
            self.assertTrue(os.path.exists(out_file))
            with open(out_file) as f:
                data = json.load(f)
            self.assertEqual(data["variables"]["ip_server_kharej_main"], "203.0.113.20")
            self.assertEqual(data["variables"]["ip_server_kharej_float_1"], "203.0.113.21")
            self.assertEqual(data["variables"]["ports_to_listen"], [6443, 2059])
            self.assertEqual(data["variables"]["udp_port_to_listen"], 27015)

    def test_cli_protoswap_unified(self):
        from confgen.cli import main
        import tempfile
        import os
        import json

        with tempfile.TemporaryDirectory() as tmpdir:
            out_i = os.path.join(tmpdir, "test-protoswap-i.json")
            out_k = os.path.join(tmpdir, "test-protoswap-k.json")
            cmd_i = [
                "waterwall", "protoswap", "iran",
                "nuremberg-proto", "198.51.100.10", "203.0.113.20",
                "--tcp", "6443,2059",
                "--udp", "27015",
                "--protoswap-tcp", "253",
                "--protoswap-udp", "252",
                "--tcp-tunnel-port", "8445",
                "--udp-tunnel-port", "8446",
                "--proxy-protocol",
                "--float", "203.0.113.21",
                "--tls", "/tmp/cert.pem", "/tmp/key.pem",
                "-o", out_i,
            ]
            ret_i = main(cmd_i)
            self.assertEqual(ret_i, 0)
            self.assertTrue(os.path.exists(out_i))
            with open(out_i) as f:
                data_i = json.load(f)
            self.assertEqual(data_i["variables"]["ip_server_kharej_main"], "203.0.113.20")
            self.assertEqual(data_i["variables"]["ip_server_kharej_float_1"], "203.0.113.21")
            self.assertEqual(data_i["variables"]["ports_to_listen"], [6443, 2059])
            self.assertEqual(data_i["variables"]["udp_port_to_listen"], 27015)

            cmd_k = [
                "waterwall", "protoswap", "kharej",
                "nuremberg-proto", "198.51.100.10", "203.0.113.20",
                "--tcp", "6443,2059",
                "--udp", "27015",
                "--protoswap-tcp", "253",
                "--protoswap-udp", "252",
                "--tcp-tunnel-port", "8445",
                "--udp-tunnel-port", "8446",
                "--float", "203.0.113.21",
                "-o", out_k,
            ]
            ret_k = main(cmd_k)
            self.assertEqual(ret_k, 0)
            self.assertTrue(os.path.exists(out_k))
            with open(out_k) as f:
                data_k = json.load(f)
            self.assertEqual(data_k["variables"]["ip_server_kharej_main"], "203.0.113.20")
            self.assertEqual(data_k["variables"]["port_to_listen"], 8445)
            self.assertEqual(data_k["variables"]["udp_port_to_listen"], 8446)
            self.assertEqual(data_k["variables"]["udp_final_port"], 27015)
            k_node_names = [n["name"] for n in data_k["nodes"]]
            self.assertIn("header-server", k_node_names)

    def test_cli_benchmark(self):
        from confgen.cli import main
        import tempfile
        import os
        import json

        with tempfile.TemporaryDirectory() as tmpdir:
            # 1. Server CLI
            srv_file = os.path.join(tmpdir, "speedtest-server.json")
            ret = main(["waterwall", "benchmark", "server", "-p", "9000", "--udp-port", "9001", "-o", srv_file])
            self.assertEqual(ret, 0)
            self.assertTrue(os.path.exists(srv_file))

            # 2. Client CLI
            cli_file = os.path.join(tmpdir, "client-tcp.json")
            ret = main(["waterwall", "benchmark", "client", "-t", "127.0.0.1", "-p", "6443", "--mode", "tcp", "-o", cli_file])
            self.assertEqual(ret, 0)
            self.assertTrue(os.path.exists(cli_file))

            # 3. Suite CLI
            suite_dir = os.path.join(tmpdir, "bench_suite")
            ret = main([
                "waterwall", "benchmark", "suite",
                "-ii", "198.51.100.10",
                "-ki", "203.0.113.20",
                "--tcp", "6443",
                "--udp", "27015",
                "-o", suite_dir,
            ])
            self.assertEqual(ret, 0)
            self.assertTrue(os.path.isdir(suite_dir))
            self.assertTrue(os.path.exists(os.path.join(suite_dir, "kharej_speedtest_server.json")))
            self.assertTrue(os.path.exists(os.path.join(suite_dir, "client_test_tcp.json")))
            self.assertTrue(os.path.exists(os.path.join(suite_dir, "iran_bitswap.json")))
            self.assertTrue(os.path.exists(os.path.join(suite_dir, "run_benchmark.py")))


if __name__ == "__main__":
    unittest.main()
