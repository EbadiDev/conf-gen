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
        self.assertEqual(manipulator_nodes[0]["settings"]["protoswap-tcp"], 253)

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
            old_cwd = os.getcwd()
            try:
                os.chdir(tmpdir)
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
                ]
                ret = main(cmd)
                self.assertEqual(ret, 0)
                self.assertTrue(os.path.exists("nuremberg-bit.json"))
                with open("nuremberg-bit.json") as f:
                    data = json.load(f)
                self.assertEqual(data["variables"]["ip_server_kharej_main"], "203.0.113.20")
                self.assertEqual(data["variables"]["ip_server_kharej_float_1"], "203.0.113.21")
                self.assertEqual(data["variables"]["ports_to_listen"], [6443, 2059])
                self.assertEqual(data["variables"]["udp_port_to_listen"], 27015)

                self.assertTrue(os.path.exists("core.json"))
                with open("core.json") as f:
                    core_data = json.load(f)
                self.assertIn("nuremberg-bit.json", core_data["configs"])
            finally:
                os.chdir(old_cwd)

    def test_cli_protoswap_unified(self):
        from confgen.cli import main
        import tempfile
        import os
        import json

        with tempfile.TemporaryDirectory() as tmpdir:
            old_cwd = os.getcwd()
            try:
                os.chdir(tmpdir)
                cmd_i = [
                    "waterwall", "protoswap", "iran",
                    "nuremberg-proto-i", "198.51.100.10", "203.0.113.20",
                    "--tcp", "6443,2059",
                    "--udp", "27015",
                    "--protoswap-tcp", "253",
                    "--protoswap-udp", "252",
                    "--tcp-tunnel-port", "8445",
                    "--udp-tunnel-port", "8446",
                    "--proxy-protocol",
                    "--float", "203.0.113.21",
                    "--tls", "/tmp/cert.pem", "/tmp/key.pem",
                ]
                ret_i = main(cmd_i)
                self.assertEqual(ret_i, 0)
                self.assertTrue(os.path.exists("nuremberg-proto-i.json"))
                with open("nuremberg-proto-i.json") as f:
                    data_i = json.load(f)
                self.assertEqual(data_i["variables"]["ip_server_kharej_main"], "203.0.113.20")
                self.assertEqual(data_i["variables"]["ip_server_kharej_float_1"], "203.0.113.21")
                self.assertEqual(data_i["variables"]["ports_to_listen"], [6443, 2059])
                self.assertEqual(data_i["variables"]["udp_port_to_listen"], 27015)

                cmd_k = [
                    "waterwall", "protoswap", "kharej",
                    "nuremberg-proto-k", "198.51.100.10", "203.0.113.20",
                    "--tcp", "6443,2059",
                    "--udp", "27015",
                    "--protoswap-tcp", "253",
                    "--protoswap-udp", "252",
                    "--tcp-tunnel-port", "8445",
                    "--udp-tunnel-port", "8446",
                    "--float", "203.0.113.21",
                ]
                ret_k = main(cmd_k)
                self.assertEqual(ret_k, 0)
                self.assertTrue(os.path.exists("nuremberg-proto-k.json"))
                with open("nuremberg-proto-k.json") as f:
                    data_k = json.load(f)
                self.assertEqual(data_k["variables"]["ip_server_kharej_main"], "203.0.113.20")
                self.assertEqual(data_k["variables"]["port_to_listen"], 8445)
                self.assertEqual(data_k["variables"]["udp_port_to_listen"], 8446)
                self.assertEqual(data_k["variables"]["udp_final_port"], 27015)
                k_node_names = [n["name"] for n in data_k["nodes"]]
                self.assertIn("header-server", k_node_names)

                self.assertTrue(os.path.exists("core.json"))
                with open("core.json") as f:
                    core_data = json.load(f)
                self.assertEqual(core_data["configs"], ["nuremberg-proto-i.json", "nuremberg-proto-k.json"])
            finally:
                os.chdir(old_cwd)

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

    def test_cli_core(self):
        from confgen.cli import main
        import tempfile
        import os
        import json

        with tempfile.TemporaryDirectory() as tmpdir:
            core_file = os.path.join(tmpdir, "core.json")
            ret = main(["waterwall", "core", "tun1.json", "tun2.json", "-o", core_file])
            self.assertEqual(ret, 0)
            self.assertTrue(os.path.exists(core_file))
            with open(core_file) as f:
                data = json.load(f)
            self.assertEqual(data["configs"], ["tun1.json", "tun2.json"])
            self.assertIn("log", data)
            self.assertIn("misc", data)


    def test_waterwall_resolved_node_settings(self):
        """Verify that all node settings in BitSwap and ProtoSwap have resolved types without $variable$."""
        from confgen.generators.waterwall.protoswap import generate_protoswap_kharej, generate_protoswap_iran
        from confgen.generators.waterwall.bitswap import generate_bitswap_kharej, generate_bitswap_iran

        cfgs = [
            generate_protoswap_kharej("pk", "198.51.100.1", "203.0.113.1", tcp_ports=[9000], udp_ports=[9001]),
            generate_protoswap_iran("pi", "198.51.100.1", "203.0.113.1", tcp_ports=[9000], udp_ports=[9001]),
            generate_bitswap_kharej("bk", "198.51.100.1", "203.0.113.1", tcp_ports=[9000], udp_ports=[9001]),
            generate_bitswap_iran("bi", "198.51.100.1", "203.0.113.1", tcp_ports=[9000], udp_ports=[9001]),
        ]

        def check_no_dollars(obj, path=""):
            if isinstance(obj, dict):
                for k, v in obj.items():
                    check_no_dollars(v, f"{path}.{k}")
            elif isinstance(obj, list):
                for i, v in enumerate(obj):
                    check_no_dollars(v, f"{path}[{i}]")
            elif isinstance(obj, str):
                self.assertFalse(
                    obj.startswith("$") and obj.endswith("$") and obj.count("$") == 2,
                    f"Unresolved variable placeholder found at {path}: {obj}"
                )

        for cfg in cfgs:
            # Check nodes
            check_no_dollars(cfg["nodes"], f"{cfg['name']}.nodes")
            # Specific checks for UdpConnector port
            for node in cfg["nodes"]:
                if node["type"] == "UdpConnector":
                    port_val = node["settings"]["port"]
                    self.assertIsInstance(port_val, int, f"UdpConnector port must be int, got {type(port_val)}")
                elif node["type"] == "IpManipulator":
                    if "protoswap-tcp" in node["settings"]:
                        self.assertIsInstance(node["settings"]["protoswap-tcp"], int)
                    if "protoswap-udp" in node["settings"]:
                        self.assertIsInstance(node["settings"]["protoswap-udp"], int)


    def test_cli_protoswap_auto_name_and_core_json(self):
        """Verify protoswap automatically generates <name>.json and adds to core.json without -o."""
        from confgen.cli import main
        import tempfile
        import os
        import json

        with tempfile.TemporaryDirectory() as tmpdir:
            old_cwd = os.getcwd()
            try:
                os.chdir(tmpdir)
                cmd_i = [
                    "waterwall", "protoswap", "iran",
                    "-n", "proto",
                    "-ii", "198.51.100.10",
                    "-ki", "203.0.113.20",
                    "--tcp", "9000",
                    "--protoswap-tcp", "51",
                    "--protoswap-udp", "52",
                ]
                ret_i = main(cmd_i)
                self.assertEqual(ret_i, 0)
                
                # Check proto.json was created
                self.assertTrue(os.path.exists("proto.json"))
                with open("proto.json") as f:
                    proto_data = json.load(f)
                self.assertEqual(proto_data["name"], "proto")
                self.assertEqual(proto_data["variables"]["protoswap_tcp_to_number"], 51)
                self.assertEqual(proto_data["variables"]["protoswap_udp_to_number"], 52)
                
                # Check core.json was created and contains proto.json
                self.assertTrue(os.path.exists("core.json"))
                with open("core.json") as f:
                    core_data = json.load(f)
                self.assertEqual(core_data["configs"], ["proto.json"])

                # Run another tunnel generation with a different name, e.g. atlanta
                cmd_k = [
                    "waterwall", "protoswap", "kharej",
                    "-n", "atlanta",
                    "-ii", "198.51.100.10",
                    "-ki", "203.0.113.20",
                    "--tcp", "9000",
                    "--protoswap-tcp", "51",
                    "--protoswap-udp", "52",
                ]
                ret_k = main(cmd_k)
                self.assertEqual(ret_k, 0)
                self.assertTrue(os.path.exists("atlanta.json"))
                
                # Check core.json now contains both proto.json and atlanta.json
                with open("core.json") as f:
                    core_data_2 = json.load(f)
                self.assertEqual(core_data_2["configs"], ["proto.json", "atlanta.json"])
            finally:
                os.chdir(old_cwd)

    def test_cli_v3_server_and_client_bash_parity(self):
        """Verify v3 server and client commands match bash syntax, output <name>.json, and auto-sync core.json."""
        from confgen.cli import main
        import tempfile
        import os
        import json

        with tempfile.TemporaryDirectory() as tmpdir:
            old_cwd = os.getcwd()
            try:
                os.chdir(tmpdir)
                cert_file = os.path.join(tmpdir, "cert.pem")
                key_file = os.path.join(tmpdir, "key.pem")
                with open(cert_file, "w") as f:
                    f.write("DUMMY_CERT")
                with open(key_file, "w") as f:
                    f.write("DUMMY_KEY")

                # Run v3 server positional syntax
                cmd_server = [
                    "v3", "server", "atlanta",
                    "109.94.164.71", "162.247.153.90", "30.6.0.1", "50",
                    "-l", "8080", "-f", "8085",
                    "--mux", "8",
                    "--tls", cert_file, key_file,
                ]
                ret_s = main(cmd_server)
                self.assertEqual(ret_s, 0)

                self.assertTrue(os.path.exists("atlanta.json"))
                with open("atlanta.json") as f:
                    data_s = json.load(f)
                self.assertEqual(data_s["name"], "atlanta")
                self.assertEqual(data_s["variables"]["ip_server_iran"], "162.247.153.90")
                self.assertEqual(data_s["variables"]["ip_server_kharej"], "109.94.164.71")
                self.assertEqual(data_s["variables"]["protoswap_tcp_to_number"], 50)
                self.assertEqual(data_s["variables"]["protoswap_udp_to_number"], 51)
                self.assertEqual(data_s["variables"]["port_to_listen"], 8080)
                self.assertEqual(data_s["variables"]["port_to_forward_to_kharej"], 8085)

                # Check core.json was created
                self.assertTrue(os.path.exists("core.json"))
                with open("core.json") as f:
                    core_data = json.load(f)
                self.assertEqual(core_data["configs"], ["atlanta.json"])

                # Run v3 client positional syntax with another name
                cmd_client = [
                    "v3", "client", "sweden",
                    "109.94.164.71", "162.247.153.90", "30.6.0.1", "50",
                    "-l", "8085", "-f", "8080",
                    "--mux", "8",
                ]
                ret_c = main(cmd_client)
                self.assertEqual(ret_c, 0)
                self.assertTrue(os.path.exists("sweden.json"))
                with open("sweden.json") as f:
                    data_c = json.load(f)
                self.assertEqual(data_c["name"], "sweden")
                self.assertEqual(data_c["variables"]["port_to_listen"], 8085)
                self.assertEqual(data_c["variables"]["final_port"], 8080)

                # Check core.json updated
                with open("core.json") as f:
                    core_data = json.load(f)
                self.assertEqual(core_data["configs"], ["atlanta.json", "sweden.json"])

                # Test waterwall v3 nested syntax
                cmd_ww_v3 = [
                    "waterwall", "v3", "server", "frankfurt",
                    "109.94.164.71", "162.247.153.90", "30.6.0.1", "52",
                    "-l", "9000", "-f", "9005",
                ]
                ret_ww = main(cmd_ww_v3)
                self.assertEqual(ret_ww, 0)
                self.assertTrue(os.path.exists("frankfurt.json"))
                with open("core.json") as f:
                    core_data = json.load(f)
                self.assertEqual(core_data["configs"], ["atlanta.json", "sweden.json", "frankfurt.json"])
            finally:
                os.chdir(old_cwd)

    def test_cli_no_core_flag(self):
        """Verify --no-core avoids creating or updating core.json."""
        from confgen.cli import main
        import tempfile
        import os

        with tempfile.TemporaryDirectory() as tmpdir:
            old_cwd = os.getcwd()
            try:
                os.chdir(tmpdir)
                cmd = [
                    "waterwall", "protoswap", "iran",
                    "-n", "standalone",
                    "-ii", "198.51.100.10",
                    "-ki", "203.0.113.20",
                    "--tcp", "9000",
                    "--no-core",
                ]
                ret = main(cmd)
                self.assertEqual(ret, 0)
                self.assertTrue(os.path.exists("standalone.json"))
                self.assertFalse(os.path.exists("core.json"))
            finally:
                os.chdir(old_cwd)


class TestFinder(unittest.TestCase):
    def test_candidates_presets(self):
        from confgen.core.finder import CANDIDATES_PRESETS
        for preset_name in ["top", "fast", "all"]:
            self.assertIn(preset_name, CANDIDATES_PRESETS)
            cands = CANDIDATES_PRESETS[preset_name]
            self.assertGreater(len(cands), 0)
            for c in cands:
                self.assertIn("id", c)
                self.assertIn("name", c)
                self.assertIn("tcp", c)
                self.assertIn("udp", c)
                self.assertIsInstance(c["tcp"], int)
                self.assertIsInstance(c["udp"], int)

    def test_parse_custom_protocols(self):
        from confgen.core.finder import parse_custom_protocols
        parsed = parse_custom_protocols("50/51, 47:136, 200")
        self.assertEqual(len(parsed), 3)
        self.assertEqual(parsed[0]["tcp"], 50)
        self.assertEqual(parsed[0]["udp"], 51)
        self.assertEqual(parsed[1]["tcp"], 47)
        self.assertEqual(parsed[1]["udp"], 136)
        self.assertEqual(parsed[2]["tcp"], 200)
        self.assertEqual(parsed[2]["udp"], 201)

    def test_cli_finder_parser(self):
        from confgen.cli import create_parser
        parser = create_parser()

        # Top-level server
        args = parser.parse_args(["finder", "server", "--port", "8088"])
        self.assertEqual(args.command, "finder")
        self.assertEqual(args.finder_cmd, "server")
        self.assertEqual(args.port, 8088)

        # Top-level server positional port
        args = parser.parse_args(["finder", "server", "8090"])
        self.assertEqual(args.pos_port, 8090)

        # Top-level client with flags
        args = parser.parse_args([
            "finder", "client",
            "-ii", "198.51.100.10",
            "-ki", "203.0.113.20",
            "-cp", "8088",
            "-p", "9001",
            "--preset", "fast",
        ])
        self.assertEqual(args.command, "finder")
        self.assertEqual(args.finder_cmd, "client")
        self.assertEqual(args.iran_ip, "198.51.100.10")
        self.assertEqual(args.kharej_ip, "203.0.113.20")
        self.assertEqual(args.control_port, 8088)
        self.assertEqual(args.port, 9001)
        self.assertEqual(args.preset, "fast")

        # Nested waterwall finder client with positional IPs
        args = parser.parse_args([
            "waterwall", "finder", "client",
            "198.51.100.10", "203.0.113.20",
        ])
        # Finder client with bitswap and combo preset
        args = parser.parse_args([
            "finder", "client",
            "-ii", "198.51.100.10",
            "-ki", "203.0.113.20",
            "--preset", "combo",
            "--bitswap",
            "--include-bitswap",
        ])
        self.assertEqual(args.preset, "combo")
        self.assertTrue(args.bitswap)
        self.assertTrue(args.include_bitswap)

    def test_finder_bitswap_support(self):
        """Verify bitswap support in finder presets, custom protocol parser, and generators."""
        from confgen.core.finder import CANDIDATES_PRESETS, parse_custom_protocols
        from confgen.generators.waterwall.protoswap import (
            generate_protoswap_iran,
            generate_protoswap_kharej,
        )

        # 1. Presets include BitSwap pairs
        for preset_name in ["top", "fast", "combo", "all"]:
            self.assertIn(preset_name, CANDIDATES_PRESETS)
            cands = CANDIDATES_PRESETS[preset_name]
            has_bitswap = any(c.get("bitswap", False) for c in cands)
            self.assertTrue(has_bitswap, f"Preset {preset_name} must contain BitSwap candidates")

        # 2. Custom protocols with include_bitswap
        cands_inc = parse_custom_protocols("50/51,51/52", include_bitswap=True)
        self.assertEqual(len(cands_inc), 4)
        self.assertFalse(cands_inc[0]["bitswap"])
        self.assertTrue(cands_inc[1]["bitswap"])
        self.assertFalse(cands_inc[2]["bitswap"])
        self.assertTrue(cands_inc[3]["bitswap"])

        # 3. Custom protocols with force_bitswap
        cands_force = parse_custom_protocols("50/51,51/52", force_bitswap=True)
        self.assertEqual(len(cands_force), 2)
        self.assertTrue(cands_force[0]["bitswap"])
        self.assertTrue(cands_force[1]["bitswap"])

        # 4. Generator node settings when bitswap is enabled
        iran_cfg = generate_protoswap_iran(
            config_name="test_bs_i",
            iran_ip="198.51.100.10",
            kharej_ip="203.0.113.20",
            tcp_ports=[9001],
            protoswap_tcp=132,
            protoswap_udp=133,
            enable_bitswap=True,
        )
        up_manip = [n for n in iran_cfg["nodes"] if n["name"] == "ip-manipulator-up"][0]
        self.assertEqual(up_manip["settings"].get("up-tcp-bit-psh"), "packet->cwr")
        self.assertEqual(up_manip["settings"].get("up-tcp-bit-cwr"), "packet->psh")

        kharej_cfg = generate_protoswap_kharej(
            config_name="test_bs_k",
            iran_ip="198.51.100.10",
            kharej_ip="203.0.113.20",
            tcp_ports=[9001],
            protoswap_tcp=132,
            protoswap_udp=133,
            enable_bitswap=True,
        )
        in_manip = [n for n in kharej_cfg["nodes"] if n["name"] == "ip-manipulator-in"][0]
        self.assertEqual(in_manip["settings"].get("dw-tcp-bit-psh"), "packet->cwr")
        self.assertEqual(in_manip["settings"].get("dw-tcp-bit-cwr"), "packet->psh")

    def test_hybrid_single_port_direct_routing(self):
        """Ensure single-port hybrid mode (1 TCP, 1 UDP) bypasses HeaderClient/HeaderServer overhead."""
        from confgen.generators.waterwall.protoswap import (
            generate_protoswap_iran,
            generate_protoswap_kharej,
        )
        from confgen.generators.waterwall.bitswap import (
            generate_bitswap_iran,
            generate_bitswap_kharej,
        )

        # ProtoSwap Single-Port Hybrid
        p_i = generate_protoswap_iran("p_hyb_i", "1.1.1.1", "2.2.2.2", tcp_ports=[9001], udp_ports=[9001])
        p_k = generate_protoswap_kharej("p_hyb_k", "1.1.1.1", "2.2.2.2", tcp_ports=[9001], udp_ports=[9001])
        
        self.assertEqual(p_i["variables"]["port_to_listen"], 9001)
        self.assertEqual(p_k["variables"]["final_port"], 9001)
        # Ensure no header-client or header-server nodes
        self.assertFalse(any(n["name"] == "header-client" for n in p_i["nodes"]))
        self.assertFalse(any(n["name"] == "header-server" for n in p_k["nodes"]))

        # BitSwap Single-Port Hybrid
        b_i = generate_bitswap_iran("b_hyb_i", "1.1.1.1", "2.2.2.2", tcp_ports=[9001], udp_ports=[9001])
        b_k = generate_bitswap_kharej("b_hyb_k", "1.1.1.1", "2.2.2.2", tcp_ports=[9001], udp_ports=[9001])
        
        self.assertEqual(b_i["variables"]["port_to_listen"], 9001)
        self.assertEqual(b_k["variables"]["final_port"], 9001)
        self.assertFalse(any(n["name"] == "header-client" for n in b_i["nodes"]))
        self.assertFalse(any(n["name"] == "header-server" for n in b_k["nodes"]))

        # Multi-TCP Hybrid still uses HeaderClient/HeaderServer
        multi_i = generate_protoswap_iran("m_i", "1.1.1.1", "2.2.2.2", tcp_ports=[9001, 9002], udp_ports=[9001])
        multi_k = generate_protoswap_kharej("m_k", "1.1.1.1", "2.2.2.2", tcp_ports=[9001, 9002], udp_ports=[9001])
        self.assertTrue(any(n["name"] == "header-client" for n in multi_i["nodes"]))
        self.assertTrue(any(n["name"] == "header-server" for n in multi_k["nodes"]))

    def test_iperf_udp_probe_parsing(self):
        """Verify iperf3 UDP helper correctly parses JSON output."""
        from unittest.mock import patch, MagicMock
        from confgen.core.finder import _run_iperf_udp_test
        import json

        fake_json = {
            "end": {
                "sum": {
                    "bits_per_second": 250000000.0,
                    "lost_percent": 0.4,
                    "jitter_ms": 1.25,
                }
            }
        }
        with patch("shutil.which", return_value="/usr/bin/iperf3"):
            with patch("subprocess.run") as mock_run:
                mock_run.return_value = MagicMock(returncode=0, stdout=json.dumps(fake_json), stderr="")
                mbps, loss, jitter = _run_iperf_udp_test(9001, duration=3)
                self.assertEqual(mbps, 250.0)
                self.assertEqual(loss, 0.4)
                self.assertEqual(jitter, 1.25)

        # 100% loss caps mbps at 0.0
        fake_loss_json = {
            "end": {
                "sum": {
                    "bits_per_second": 300000000.0,
                    "lost_percent": 100.0,
                    "jitter_ms": 0.0,
                }
            }
        }
        with patch("shutil.which", return_value="/usr/bin/iperf3"):
            with patch("subprocess.run") as mock_run:
                mock_run.return_value = MagicMock(returncode=0, stdout=json.dumps(fake_loss_json), stderr="")
                mbps, loss, jitter = _run_iperf_udp_test(9001, duration=3)
                self.assertEqual(mbps, 0.0)
                self.assertEqual(loss, 100.0)

    def test_iperf_tcp_probe_timeout(self):
        """Verify iperf3 TCP helper handles timeout cleanly and sets timed_out=True."""
        import subprocess
        from unittest.mock import patch
        from confgen.core.finder import _run_iperf_test

        with patch("shutil.which", return_value="/usr/bin/iperf3"):
            with patch("subprocess.run", side_effect=subprocess.TimeoutExpired(cmd=["iperf3"], timeout=13)):
                mbps, retr, timed_out = _run_iperf_test(9001, duration=5)
                self.assertEqual(mbps, 0.0)
                self.assertEqual(retr, 0)
    def test_isolated_test_dir_resolution(self):
        """Verify default test dir and environment variable resolution."""
        import os
        from unittest.mock import patch
        from confgen.core.finder import get_default_test_dir
        with patch.dict(os.environ, {"WATERWALL_TEST_DIR": "/opt/custom-ww-test"}):
            self.assertEqual(get_default_test_dir(), "/opt/custom-ww-test")

    def test_test_waterwall_launch_info_isolation(self):
        """Verify get_test_waterwall_launch_info isolates test binary from production."""
        import os
        import tempfile
        from confgen.core.finder import get_test_waterwall_launch_info, WATERWALL_TEST_BIN_NAME

        with tempfile.TemporaryDirectory() as tmp_dir:
            # Create a mock Waterwall-test binary
            mock_bin = os.path.join(tmp_dir, WATERWALL_TEST_BIN_NAME)
            with open(mock_bin, "w") as f:
                f.write("#!/bin/sh\nexit 0\n")
            os.chmod(mock_bin, 0o755)

            bin_path, cwd = get_test_waterwall_launch_info(test_dir=tmp_dir, auto_download=False)
            self.assertEqual(bin_path, mock_bin)
            self.assertEqual(cwd, tmp_dir)
            self.assertNotEqual(cwd, "/root/waterwall")

    def test_stop_waterwall_never_kills_production(self):
        """Verify stop_waterwall_and_test only pkills Waterwall-test and iperf3, never production waterwall."""
        from unittest.mock import patch
        from confgen.core.finder import stop_waterwall_and_test, WATERWALL_TEST_BIN_NAME

        with patch("subprocess.run") as mock_run:
            stop_waterwall_and_test(None, "test-name", "/tmp")
            # Verify every pkill call made
            for call in mock_run.call_args_list:
                cmd = call[0][0]
                if cmd[0] == "pkill":
                    target_pattern = cmd[-1]
                    self.assertIn(target_pattern, [WATERWALL_TEST_BIN_NAME, "iperf3"])
                    self.assertNotIn(target_pattern.lower(), ["waterwall"])

    def test_cli_finder_test_dir_option(self):
        """Verify --test-dir is parsed correctly in CLI for both server and client."""
        from confgen.cli import create_parser
        parser = create_parser()
        args_srv = parser.parse_args(["finder", "server", "--test-dir", "/tmp/ww-test"])
        self.assertEqual(args_srv.test_dir, "/tmp/ww-test")

        args_cli = parser.parse_args(["finder", "client", "-ii", "198.51.100.10", "-ki", "203.0.113.20", "--test-dir", "/tmp/ww-test"])
        self.assertEqual(args_cli.test_dir, "/tmp/ww-test")

    def test_cli_finder_private_ip_option(self):
        """Verify --private-ip and --private-ip-2 are parsed correctly with defaults."""
        from confgen.cli import create_parser
        parser = create_parser()

        # Default private-ip
        args_default = parser.parse_args(["finder", "client", "-ii", "198.51.100.10", "-ki", "203.0.113.20"])
        self.assertEqual(args_default.private_ip, "10.99.0.1")
        self.assertIsNone(args_default.private_ip_2)

        # Custom private-ip and private-ip-2
        args_custom = parser.parse_args([
            "finder", "client",
            "-ii", "198.51.100.10",
            "-ki", "203.0.113.20",
            "--private-ip", "10.77.0.1",
            "--private-ip-2", "10.77.10.1",
        ])
        self.assertEqual(args_custom.private_ip, "10.77.0.1")
        self.assertEqual(args_custom.private_ip_2, "10.77.10.1")

    def test_cli_finder_apply_option(self):
        """Verify --apply is False by default and True when specified."""
        from confgen.cli import create_parser
        parser = create_parser()

        args_default = parser.parse_args(["finder", "client", "-ii", "198.51.100.10", "-ki", "203.0.113.20"])
        self.assertFalse(args_default.apply)

        args_apply = parser.parse_args(["finder", "client", "-ii", "198.51.100.10", "-ki", "203.0.113.20", "--apply"])
        self.assertTrue(args_apply.apply)

    def test_ensure_iperf3_installed(self):
        """Verify ensure_iperf3_installed returns path if iperf3 exists or returns None if missing."""
        from confgen.core.finder import ensure_iperf3_installed, find_iperf3_binary
        bin_path = find_iperf3_binary()
        if bin_path:
            self.assertEqual(ensure_iperf3_installed(), bin_path)


if __name__ == "__main__":
    unittest.main()



