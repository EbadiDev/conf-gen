# ⚡ ConfGen

A modular, dependency-free Python CLI for generating deterministic anti-censorship tunnel configurations (**Xray VLESS Reverse**, **Waterwall Reality/TLS/UDP**, **BitSwap MUX**).

* **Zero External Dependencies:** Standard Library only (`pip`-free).
* **Cross-Platform:** Works on any Linux VPS with Python 3.10+.

---

## 🚀 Quick Start

Run directly via the standalone wrapper:
```bash
./confgen.py --help
```
Or as a module:
```bash
python3 -m confgen --help
```

---

## 📖 Command Reference & Flags

### 1. Xray VLESS Reverse Tunnel

Creates a reverse tunnel where the remote server dials into the local server, exposing local ports backwards.

#### Flags:
| Flag | Name | Required | Default | Description |
| :--- | :--- | :---: | :--- | :--- |
| `-n`, `--name` | Config Name | Yes | `xray-config` | Configuration filename |
| `-ii`, `--iran-ip` | Server IP | Kharej only | — | Local listener IP address |
| `-p`, `--port` | Listener Port | No | `8443` | Inbound transport port |
| `--tcp` | TCP Ports | No | `8085,8086` | Comma-separated TCP ports to forward |
| `--udp` | UDP Ports | No | — | Comma-separated UDP ports to forward |
| `-u`, `--uuid` | UUID | No | Random/Default | VLESS client authentication UUID |
| `--path` | WS Path | No | `/api/v3/live` | WebSocket endpoint path |
| `--ed` | Early Data | No | `2560` | Early Data threshold for 0-RTT |
| `--tls-cert` | TLS Cert | Iran only | — | Path to TLS certificate (`fullchain.pem`) |
| `--tls-key` | TLS Key | Iran only | — | Path to TLS private key (`privkey.pem`) |
| `--tls`, `--sni` | TLS SNI | Kharej only | — | SNI hostname for TLS verification |
| `-o`, `--output` | Output File | No | `<name>.json` | Custom output filepath |

#### Examples:

**Plain WebSocket (High Throughput):**
```bash
# On Iran Server:
./confgen.py xray reverse iran -n xray-iran -p 8443 --tcp 8085,8086 --udp 8087 --path /api/v3/live

# On Remote (Kharej) Server:
./confgen.py xray reverse kharej -n xray-kharej -ii 198.51.100.10 -p 8443 --path /api/v3/live
```

**WebSocket + TLS:**
```bash
# On Iran Server (Listener terminates TLS):
./confgen.py xray reverse iran -n xray-iran -p 8443 --tcp 8085,8086 \
  --tls-cert /etc/ssl/certs/fullchain.pem --tls-key /etc/ssl/certs/privkey.pem

# On Remote (Kharej) Server (Client validates TLS):
./confgen.py xray reverse kharej -n xray-kharej -ii 198.51.100.10 -p 8443 --tls cdn.example.com
```

---

### 2. Waterwall Reverse Reality (TCP)

Reverse tunneling using Reality SNI camouflage and optional multi-IP load balancing.

#### Flags:
| Flag | Name | Required | Default | Description |
| :--- | :--- | :---: | :--- | :--- |
| `-n`, `--name` | Config Name | Yes | — | Configuration name |
| `-ii`, `--iran-ip` | Iran IP | Yes | — | Iran server public IP |
| `-ki`, `--kharej-ip` | Kharej IP | Yes | — | Kharej main server IP |
| `-p`, `--port` | Port | No | `443` | Reverse transport port |
| `-d`, `--domain` | SNI Domain | No | `example.com` | Reality camouflage domain |
| `-wi`, `--white-ip` | White IP | Iran only | — | Real IP behind the SNI domain |
| `-fp`, `--final-port` | Target Port | Kharej only | — | Local application port on Kharej |
| `--pass` | Password | No | `secret123` | Reality shared password |
| `--float` | Floating IPs | No | — | Additional Kharej IPs for load balancing |
| `--proxy-protocol` | Proxy Protocol | No | `false` | Inject Proxy Protocol header |
| `--halfduplex` | HalfDuplex | No | `false` | Enable stream-splitting protection |
| `--fisher` | Fisher | No | `false` | Enable ConnectionFisher server/client |

#### Examples:

```bash
# On Iran Server:
./confgen.py waterwall reverse-reality iran \
  -n rev-iran \
  -ii 198.51.100.10 \
  -ki 203.0.113.20 \
  -p 443 \
  -d example.com \
  -wi 192.0.2.1 \
  --float 203.0.113.21 203.0.113.22 \
  --proxy-protocol

# On Kharej Server:
./confgen.py waterwall reverse-reality kharej \
  -n rev-kharej \
  -ii 198.51.100.10 \
  -ki 203.0.113.20 \
  -p 443 \
  -d example.com \
  -fp 8443 \
  --float 203.0.113.21 203.0.113.22
```

---

### 3. Waterwall TLS Reverse

Reverse TLS tunneling with IP whitelisting.

#### Flags:
| Flag | Name | Side | Description |
| :--- | :--- | :--- | :--- |
| `-n`, `--name` | Config Name | Both | Configuration name |
| `-ii`, `--iran-ip` | Iran IP | Both | Iran server public IP |
| `-p`, `--port` | Port | Both | Tunnel port (default: `8443`) |
| `--cert` / `--key` | Cert & Key | Iran | Path to TLS certificate and key |
| `-ki`, `--kharej-ips`| Whitelist IPs | Iran | Whitelisted remote IP addresses |
| `-d`, `--sni` | SNI Domain | Kharej | SNI domain for TLS handshake |
| `-fp`, `--final-port`| Target Port | Kharej | Destination service port |

#### Examples:
```bash
# On Iran Server:
./confgen.py waterwall tls-reverse iran \
  -n tls-iran -ii 198.51.100.10 -p 8443 \
  --cert /etc/ssl/cert.pem --key /etc/ssl/key.pem \
  -ki 203.0.113.20 203.0.113.21

# On Kharej Server:
./confgen.py waterwall tls-reverse kharej \
  -n tls-kharej -ii 198.51.100.10 -p 8443 \
  -d cdn.example.com -fp 8080
```

---

### 4. Waterwall UDP Reverse (RawSocket + XOR)

Low-latency UDP reverse tunnel using raw sockets, XOR obfuscation, and TUN devices.

#### Flags:
| Flag | Name | Description |
| :--- | :--- | :--- |
| `-n`, `--name` | Config Name | Configuration name |
| `-ii`, `--iran-ip` | Iran IP | Iran public IP |
| `-ki`, `--kharej-ip` | Kharej IP | Kharej public IP |
| `-lp`, `--listen-port` | Listen Port | Public inbound UDP port (Iran only) |
| `-fp`, `--target-port` | Target Port | Local application UDP port (Kharej only) |
| `-tp`, `--tunnel-port` | Tunnel Port | Internal transport port (default: `443`) |
| `--xor-key` | XOR Key | Obfuscation key integer (default: `153`) |

#### Examples:
```bash
# On Iran Server:
./confgen.py waterwall udp-reverse iran -n udp-iran -ii 198.51.100.10 -ki 203.0.113.20 -lp 11040 -tp 443

# On Kharej Server:
./confgen.py waterwall udp-reverse kharej -n udp-kharej -ii 198.51.100.10 -ki 203.0.113.20 -fp 11040 -tp 443
```

---

### 5. Waterwall BitSwap MUX (Unified Single / Multi / Hybrid)

Advanced MUX tunneling with TCP flag bit-swapping (`PSH <-> CWR`), XOR obfuscation, TUN devices, and multi-IP floating egress.

* **Auto-Detects Mode:** Single-IP by default; automatically switches to Multi-IP when `--float` is provided.
* **Auto-Detects Service Type:** If 1 TCP or 1 UDP port is specified, builds dedicated single-service routing; if multiple ports or both TCP and UDP are specified, automatically builds the multi-service hybrid pipeline with `HeaderClient`/`HeaderServer` port preservation.
* **Zero `-m` or `--proto` flags needed.**

#### Flags:
| Flag | Name | Required | Default | Description |
| :--- | :--- | :---: | :--- | :--- |
| `-n`, `--name` | Config Name | Yes | — | Configuration name (or 1st positional) |
| `-ii`, `--iran-ip` | Iran IP | Yes | — | Iran server public IP (or 2nd positional) |
| `-ki`, `--kharej-ip` | Kharej IP | Yes | — | Kharej server main IP (or 3rd positional) |
| `--tcp` | TCP Ports | No | — | TCP service port(s), e.g. `--tcp 6443,2059` or `--tcp 443` |
| `--udp` | UDP Ports | No | — | UDP service port(s), e.g. `--udp 27015` |
| `--tcp-tunnel-port` | TCP Transport Port | No | `8443` / `8445` | Internal transport port for TCP MUX |
| `--udp-tunnel-port` | UDP Transport Port | No | `8444` / `8446` | Internal transport port for UDP-over-TCP |
| `--float` | Floating IPs | No | — | Additional floating IPs on Kharej (triggers multi-IP) |
| `--proxy-protocol` | Proxy Protocol | No | `false` | Inject Proxy Protocol v2 header on Iran side |
| `--tls-cert` / `--tls-key` | TLS Termination | No | — | Certificate and key paths for Iran side TLS termination |
| `--tls` | TLS Pair | No | — | Alternative: `--tls <cert> <key>` |
| `--mux-count` | MUX Connections | No | `8` | Worker MUX connections count |
| `--xor-key` | XOR Key | No | `90` | XOR obfuscation key |
| `--private-ip` | Subnet Base | No | `10.10.0.1` | Base internal private IP subnet |
| `--final-ip` | Target IP | No | `127.0.0.1` | Destination service IP on Kharej |

#### Examples:

**1. Multi-Service Hybrid with Floating IPs, Proxy Protocol & TLS:**
```bash
# On Iran Server:
./confgen.py waterwall bitswap iran \
  -n nuremberg-bit \
  -ii 198.51.100.10 \
  -ki 203.0.113.20 \
  --tcp 6443,2059 \
  --udp 27015 \
  --tcp-tunnel-port 8445 \
  --udp-tunnel-port 8446 \
  --private-ip 10.50.0.1 \
  --float 203.0.113.21 \
  --proxy-protocol \
  --tls /etc/ssl/cert.pem /etc/ssl/key.pem

# On Kharej Server:
./confgen.py waterwall bitswap kharej \
  -n nuremberg-bit \
  -ii 198.51.100.10 \
  -ki 203.0.113.20 \
  --tcp 6443,2059 \
  --udp 27015 \
  --tcp-tunnel-port 8445 \
  --udp-tunnel-port 8446 \
  --private-ip 10.50.0.1 \
  --float 203.0.113.21
```

**2. Positional Quick Syntax:**
```bash
./confgen.py waterwall bitswap iran nuremberg-bit 198.51.100.10 203.0.113.20 \
  --tcp 6443,2059 --udp 27015 --float 203.0.113.21
```

**3. Single TCP Port (Auto-detected Single Mode):**
```bash
# On Iran Server:
./confgen.py waterwall bitswap iran -n bit-single -ii 198.51.100.10 -ki 203.0.113.20 --tcp 443 --tcp-tunnel-port 8443

# On Kharej Server:
./confgen.py waterwall bitswap kharej -n bit-single -ii 198.51.100.10 -ki 203.0.113.20 --tcp 443 --tcp-tunnel-port 8443
```

**4. Single UDP Port (Auto-detected Single Mode):**
```bash
# On Iran Server:
./confgen.py waterwall bitswap iran -n bit-udp -ii 198.51.100.10 -ki 203.0.113.20 --udp 27015 --udp-tunnel-port 8444

# On Kharej Server:
./confgen.py waterwall bitswap kharej -n bit-udp -ii 198.51.100.10 -ki 203.0.113.20 --udp 27015 --udp-tunnel-port 8444
```

---

### 6. Waterwall ProtoSwap (Layer-3 Protocol Byte Swapping)

Next-generation anti-censorship tunnel using Layer-3 protocol field manipulation (`IpManipulator` byte swapping) to evade protocol-based packet inspection (e.g. TCP `6` $\rightarrow$ `253`, UDP `17` $\rightarrow$ `252`).

* **Symmetric Layer-3 Mutation:** Rewrites IPv4 `Protocol` header bytes on the wire while preserving internal packet structures, checksum integrity, and end-to-end reliability.
* **Unified Auto-Detection:** Automatically switches between single service and multi-service MUX (`HeaderClient`/`HeaderServer`), as well as single-IP and multi-IP floating egress.
* **Optional BitSwap Layering:** Pass `--bitswap` to simultaneously swap Layer-4 TCP flags (`PSH <-> CWR`) alongside Layer-3 protocol swapping for maximum stealth.

#### Flags:
| Flag | Name | Required | Default | Description |
| :--- | :--- | :---: | :--- | :--- |
| `-n`, `--name` | Config Name | Yes | — | Configuration name (or 1st positional) |
| `-ii`, `--iran-ip` | Iran IP | Yes | — | Iran server public IP (or 2nd positional) |
| `-ki`, `--kharej-ip` | Kharej IP | Yes | — | Kharej server main IP (or 3rd positional) |
| `--tcp` | TCP Ports | No | — | TCP service port(s), e.g. `--tcp 6443,2059` or `--tcp 443` |
| `--udp` | UDP Ports | No | — | UDP service port(s), e.g. `--udp 27015` |
| `--protoswap-tcp` | TCP Proto Num | No | `253` | Replacement protocol number for TCP (0-255, $\ne 6$) |
| `--protoswap-udp` | UDP Proto Num | No | `252` | Replacement protocol number for UDP (0-255, $\ne 17$) |
| `--tcp-tunnel-port` | TCP Transport Port | No | `8443` / `8445` | Internal transport port for TCP MUX |
| `--udp-tunnel-port` | UDP Transport Port | No | `8444` / `8446` | Internal transport port for UDP-over-TCP |
| `--float` | Floating IPs | No | — | Additional floating IPs on Kharej (triggers multi-IP) |
| `--proxy-protocol` | Proxy Protocol | No | `false` | Inject Proxy Protocol v2 header on Iran side |
| `--tls-cert` / `--tls-key` | TLS Termination | No | — | Certificate and key paths for Iran side TLS termination |
| `--tls` | TLS Pair | No | — | Alternative: `--tls <cert> <key>` |
| `--bitswap` | BitSwap Combo | No | `false` | Also enable Layer-4 TCP bit-swapping |
| `--mux-count` | MUX Connections | No | `8` | Worker MUX connections count |
| `--xor-key` | XOR Key | No | `90` | XOR obfuscation key |
| `--private-ip` | Subnet Base | No | `10.10.0.1` | Base internal private IP subnet |
| `--final-ip` | Target IP | No | `127.0.0.1` | Destination service IP on Kharej |

#### Examples:

**1. Multi-Service Hybrid with Custom Protocol Numbers, Floating IPs & TLS:**
```bash
# On Iran Server:
./confgen.py waterwall protoswap iran \
  -n nuremberg-proto \
  -ii 198.51.100.10 \
  -ki 203.0.113.20 \
  --tcp 6443,2059 \
  --udp 27015 \
  --protoswap-tcp 253 \
  --protoswap-udp 252 \
  --tcp-tunnel-port 8445 \
  --udp-tunnel-port 8446 \
  --float 203.0.113.21 \
  --proxy-protocol \
  --tls /etc/ssl/cert.pem /etc/ssl/key.pem

# On Kharej Server:
./confgen.py waterwall protoswap kharej \
  -n nuremberg-proto \
  -ii 198.51.100.10 \
  -ki 203.0.113.20 \
  --tcp 6443,2059 \
  --udp 27015 \
  --protoswap-tcp 253 \
  --protoswap-udp 252 \
  --tcp-tunnel-port 8445 \
  --udp-tunnel-port 8446 \
  --float 203.0.113.21
```

**2. Positional Quick Syntax:**
```bash
./confgen.py waterwall protoswap iran nuremberg-proto 198.51.100.10 203.0.113.20 \
  --tcp 6443,2059 --udp 27015 --float 203.0.113.21
```

**3. Single TCP Port (Auto-detected Single Mode):**
```bash
# On Iran Server:
./confgen.py waterwall protoswap iran -n proto-single -ii 198.51.100.10 -ki 203.0.113.20 --tcp 443

# On Kharej Server:
./confgen.py waterwall protoswap kharej -n proto-single -ii 198.51.100.10 -ki 203.0.113.20 --tcp 443
```

---

### 7. Waterwall Simple Forwarding

Direct port-to-port TCP or UDP forwarder.

#### Flags:
| Flag | Name | Description |
| :--- | :--- | :--- |
| `-n`, `--name` | Config Name | Configuration name |
| `--proto` | Protocol | `tcp` or `udp` |
| `-sp` / `-ep` | Port Range | Starting and ending port numbers |
| `-di`, `--dest-ip` | Target IP | Destination IP address |
| `-dp`, `--dest-port` | Target Port | Destination port |

#### Example:
```bash
./confgen.py waterwall simple -n fwd-dns --proto udp -sp 53 -ep 53 -di 192.0.2.1 -dp 53
```

---

### 8. Waterwall Benchmarking & SpeedTest Suite

Built-in synthetic benchmarking tools using native WaterWall [`SpeedTestClient`](https://radkesvat.github.io/WaterWall-Docs/docs/noderefs/SpeedTestClient) and [`SpeedTestServer`](https://radkesvat.github.io/WaterWall-Docs/docs/noderefs/SpeedTestServer) nodes. Allows measuring cross-border TCP & UDP throughput, latency, and packet loss to objectively determine the highest-performing tunnel (BitSwap vs. ProtoSwap candidates: 253, 50, 47, Combo).

#### Subcommands:
* `server`: Generates a local `SpeedTestServer` for the remote (Kharej) target.
* `client`: Generates an injecting `SpeedTestClient` for the local (Iran) inbound.
* `suite`: Automatically generates a complete multi-candidate test directory with all tunnel configurations and an automated benchmark runner (`run_benchmark.py`).

#### 1. Generate Full Automated Comparison Suite
```bash
./confgen.py waterwall benchmark suite \
  -ii 198.51.100.10 \
  -ki 203.0.113.20 \
  --tcp 6443 \
  --udp 27015 \
  -o bench_suite
```
This generates:
* `kharej_speedtest_server.json` (Target server on ports 9000 TCP & 9001 UDP)
* `client_test_tcp.json` & `client_test_udp.json` (Synthetic traffic injectors)
* All tunnel candidate variants:
  * `iran_bitswap.json` / `kharej_bitswap.json`
  * `iran_protoswap_253.json` / `kharej_protoswap_253.json` (RFC 3692)
  * `iran_protoswap_esp.json` / `kharej_protoswap_esp.json` (IPsec ESP 50/51)
  * `iran_protoswap_gre.json` / `kharej_protoswap_gre.json` (GRE 47 / UDPLite 136)
  * `iran_protoswap_combo.json` / `kharej_protoswap_combo.json` (ProtoSwap + BitSwap)
* `run_benchmark.py` (Automated orchestrator that runs each candidate sequentially and prints a ranked leaderboard)

#### 2. Standalone Server & Client Generation
```bash
# On Kharej Server (Target listener):
./confgen.py waterwall benchmark server -p 9000 --udp-port 9001 -o speedtest-server.json

# On Iran Server (Inject synthetic TCP test into tunnel entry):
./confgen.py waterwall benchmark client -t 127.0.0.1 -p 6443 --mode tcp --direction bidirectional -o client-tcp.json

# On Iran Server (Inject synthetic UDP probe into tunnel entry):
./confgen.py waterwall benchmark client -t 127.0.0.1 -p 27015 --mode udp --direction upload --udp-rate 50000000 -o client-udp.json
```

---

## 🧪 Running Tests

Verify the entire suite in sub-second time:
```bash
python3 -m unittest discover tests
```
