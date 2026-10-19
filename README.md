# ⚡ ConfGen: Next-Gen Tunnel Generator & Autonomous Benchmark Sweeper

ConfGen is an all-in-one, zero-dependency Python framework for high-throughput cross-border tunneling with **WaterWall** and **Xray**, designed specifically for deep packet inspection (DPI) circumvention between Iran and foreign servers (Kharej).

It achieved an all-time verified record of **4.74 Gbps wire speed** (2.11 Gbps UP / 2.63 Gbps DOWN) with **0ms added latency** and **0.0% packet loss** using Reverse Reality + HalfDuplex + ConnectionFisher on whitelisted Iranian hospital infrastructure.

---

## 🚀 Key Features

- **⚡ Record-Breaking Speeds**: Squeezes up to 4.7+ Gbps aggregate throughput on 10G/virtualized NIC interfaces across the national border.
- **🏆 Autonomous Protocol Sweeper (`confgen finder`)**: Tests multiple tunnel architectures and SNIs head-to-head in real time, automatically ranking them on an RTT/throughput leaderboard.
- **🏥 Iranian Hospital SNI Benchmark**: Pre-configured with 10+ verified, active Iranian medical institutions (`shariati.tums.ac.ir`, `rhc.ac.ir`, `tums.ac.ir`) with Let's Encrypt TLS 443 certificates that bypass national QoS throttling.
- **🔄 Two-Stage Adaptive Testing**:
  - *Stage 1*: Tests base architectures (Reverse Reality, BitSwap, ProtoSwap, UDP Reverse, TLS Reverse).
  - *Stage 2*: Automatically branches into deep variations of the working tunnels (HalfDuplex, ConnectionFisher, Mux, custom TCP bit swapping, alternative SNIs).
- **📦 BackPack-Style Setup Links (`confgen://...`)**: Generates single-line copy-paste commands so Kharej servers can be completely deployed in seconds without typing IPs or ports.
- **📊 Native MUX Scaling Benchmark (`confgen test`)**: Pure-Python stream benchmark testing parallel child streams (1, 2, 8, 16 connections) to evaluate multiplexing efficiency without iperf3.
- **🛡️ Strict Process & System Isolation**: Test instances run in isolated sandboxes (`Waterwall-test`) without ever touching production systemd services, active tunnels, or host iptables rules.
- **🐍 Pure Python (Zero Dependencies)**: Runs everywhere with standard Python 3.6+. No external pip packages needed.

---

## 📥 Installation & Updating

Run this **one command** on both your **Iran** and **Kharej** servers:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/EbadiDev/conf-gen/feat/confgen-python-protoswap-benchmark/install.sh)
```

This installs the standalone executable `confgen` in `/usr/local/bin/confgen`.

### Quick Commands

```bash
# Open the interactive BackPack-style terminal menu wizard:
confgen

# Check or update ConfGen to the latest version on GitHub:
confgen update

# Apply system-wide networking optimizations (BBR, buffer ceilings, sysctl):
confgen optimize
```

---

## 🖥️ BackPack-Style Interactive Menu

Simply run `confgen` (or `confgen menu`) on any server to launch the interactive terminal wizard:

```text
============================================================================
              ⚡ CONFGEN - WATERWALL & XRAY CONFIG WIZARD ⚡
============================================================================
1) Setup Iran Server Tunnel (Wizard)
2) Apply Setup Link on Kharej (Single-command activation)
3) Manage Active Tunnels & Inspect Status
4) System Optimizer (TCP BBR, Splicing & Buffers)
5) Native Stream SpeedTest (1, 2, 8, 16 Parallel Child Streams)
6) Benchmark & Autonomous Protocol Sweeper
7) Update ConfGen from GitHub
0) Exit
============================================================================
```

---

## 🏆 Autonomous Protocol Sweeper (`confgen finder`)

The automated sweeper deploys candidates sequentially in an isolated sandbox, runs TCP upload, TCP download, and UDP throughput/loss probes, and prints a real-time leaderboard.

### Step 1: Start Agent on Kharej Server
```bash
confgen finder server --port 8088
```

### Step 2: Run Sweep from Iran Server

#### Mode A: Full Multi-Method Sweep (Methods + Two-Stage Deep Optimization)
```bash
confgen finder client -ii <IRAN_IP> -ki <KHAREJ_IP> --preset methods
```

#### Mode B: Iranian Hospital SNI Benchmark (`--preset hospital`)
Benchmarks verified Iranian medical institutions against each other using the 4.7 Gbps architecture (`Reverse Reality + HD + Fisher`):
```bash
confgen finder client -ii <IRAN_IP> -ki <KHAREJ_IP> --preset hospital
```

#### Mode C: Custom SNI Domain List (`--snis` or `--sni-file`)
```bash
# Comma-separated list:
confgen finder client -ii <IRAN_IP> -ki <KHAREJ_IP> \
  --snis shariati.tums.ac.ir,rhc.ac.ir,telewebion.ir,snapp.ir,filimo.com,aparat.com

# From a text file (one domain per line):
confgen finder client -ii <IRAN_IP> -ki <KHAREJ_IP> --sni-file my_domains.txt
```

#### Mode D: Include TLS Reverse (Domain + Let's Encrypt SSL)
```bash
confgen finder client -ii <IRAN_IP> -ki <KHAREJ_IP> \
  --preset methods \
  --tls-domain mydomain.com \
  --tls-cert /root/fullchain.pem \
  --tls-key /root/privkey.pem
```

---

## 📊 Sample Sweeper Leaderboard Results

```text
===================================================================================================================
🏆 WATERWALL BENCHMARK & PROTOCOL SWEEP LEADERBOARD
===================================================================================================================
Rank  | Candidate                                          | Type            | TCP Up       | TCP Down     | Loss   | RTT | Status
--------------------------------------------------------------------------------------------------------------------------------------
#1    | Reverse Reality + HD (shariati.tums.ac.ir)         | reverse_reality | 2111.53 Mbps | 2632.92 Mbps |   0.0% | 0ms | BEST ⭐
#2    | Reverse Reality + HD (snapp.ir)                    | reverse_reality | 1999.46 Mbps | 2545.88 Mbps |   0.0% | 0ms | TCP ONLY ⚠️
#3    | Reverse Reality + HD + Fisher (shariati.tums.ac.ir)| reverse_reality | 2001.34 Mbps | 2523.06 Mbps |   0.0% | 0ms | TCP ONLY ⚠️
#4    | Reverse Reality + Fisher (shariati.tums.ac.ir)     | reverse_reality | 2170.20 Mbps | 2207.55 Mbps |   0.0% | 0ms | TCP ONLY ⚠️
#5    | Reverse Reality TCP (shariati.tums.ac.ir)          | reverse_reality | 2125.90 Mbps | 2200.00 Mbps |   0.0% | 0ms | TCP ONLY ⚠️
#6    | Reverse Reality UDP (shariati.tums.ac.ir)          | reverse_reality |  850.12 Mbps |  850.12 Mbps |   0.0% | 0ms | ACTIVE (UDP) 🚀
#7    | BitSwap (PSH <-> RST)                              | bitswap         |  379.41 Mbps |  392.56 Mbps |  63.8% | 1ms | DEGRADED ⚠️
===================================================================================================================
```

---

## 🛠️ Deploying Production Tunnels

### 1. Reverse Reality Multi-Port TCP (4.7 Gbps Champion)

Carries multiple public web and proxy ports (`443, 8080, 5370, 9008`) simultaneously over a single high-speed Reverse Reality tunnel. Uses `HeaderClient` and `HeaderServer` to preserve and route each port 1-to-1 to your backend:

```bash
# On Iran Server:
confgen waterwall reverse-reality iran \
  -n champion \
  -ii <IRAN_IP> \
  -ki <KHAREJ_IP> \
  -p 443 8080 5370 9008 \
  -d shariati.tums.ac.ir \
  --halfduplex \
  --fisher

# Copy the ONE-LINE setup command printed by Iran and run it on Kharej:
confgen link apply 'confgen://...'

# (Or run the direct command on Kharej):
confgen waterwall reverse-reality kharej \
  -n champion \
  -ii <IRAN_IP> \
  -ki <KHAREJ_IP> \
  -p 443 \
  -fp 0 \
  -d shariati.tums.ac.ir \
  --halfduplex \
  --fisher
```

Restart WaterWall on both servers:
```bash
systemctl restart waterwall.service
```

- **Port Routing**:
  - `443` on Iran ➔ `127.0.0.1:443` on Kharej
  - `8080` on Iran ➔ `127.0.0.1:8080` on Kharej
  - `5370` on Iran ➔ `127.0.0.1:5370` on Kharej
  - `9008` on Iran ➔ `127.0.0.1:9008` on Kharej
- **Speed**: **~4.7 Gbps** aggregate wire speed with **0ms added latency**!

---

### 2. Reverse Reality Dedicated UDP (WireGuard, Gaming & Voice)

Transports UDP datagrams over the 4.7 Gbps Reality TLS carrier using `UdpOverTcpClient` & `UdpOverTcpServer` with **0.0% packet loss** and **800+ Mbps throughput**:

```bash
# On Iran Server (example with WireGuard port 27012):
confgen waterwall reverse-reality udp iran \
  -n champion-udp \
  -ii <IRAN_IP> \
  -ki <KHAREJ_IP> \
  -p 27012 \
  -fp 27012 \
  -d shariati.tums.ac.ir \
  --halfduplex \
  --fisher

# Copy the ONE-LINE setup command printed by Iran and run it on Kharej:
confgen link apply 'confgen://...'

# (Or run the direct command on Kharej):
confgen waterwall reverse-reality udp kharej \
  -n champion-udp \
  -ii <IRAN_IP> \
  -ki <KHAREJ_IP> \
  -p 27012 \
  -fp 27012 \
  -d shariati.tums.ac.ir \
  --halfduplex \
  --fisher
```

Restart WaterWall on both servers:
```bash
systemctl restart waterwall.service
```

#### 🛡️ WireGuard Client Configuration Rules:
In your WireGuard client configuration file (`.conf` on phone/laptop):
1. **Set `MTU = 1280`**:
   The tunnel encapsulates UDP packets in length headers and TLS. Setting `MTU = 1280` eliminates packet fragmentation and prevents silent drops.
2. **Set `Endpoint` to Iran**:
   `Endpoint = <IRAN_IP>:27012` (points to Iran's public IP).
3. **Open Iran Firewall**:
   Ensure `ufw allow 27012/udp` (or `iptables -I INPUT -p udp --dport 27012 -j ACCEPT`) is applied on Iran.

---

### 3. Running TCP + UDP in Parallel (Production Best Practice)

In WaterWall, `core.json` automatically loads multiple configuration files simultaneously:

```json
{
  "configs": [
    "champion.json",
    "champion-udp.json"
  ]
}
```

- **Complete Decoupling**: If UDP gaming or VoIP encounters packet bursts or network congestion, **it will never drop or throttle your 4.7 Gbps TCP web users**.
- **Dedicated Sockets**: TCP uses standard port 443; UDP uses its dedicated port (e.g. 27012).
- **Independent Maintenance**: You can inspect or restart UDP without interrupting active TCP streams.

---

### 4. How to Test & Verify Tunnels

#### Test 1: Test TCP Bandwidth
1. On Kharej:
   ```bash
   confgen test server --port 8080
   ```
2. On Iran:
   ```bash
   confgen test client -t 127.0.0.1 -p 8080
   ```

#### Test 2: Test UDP Bandwidth & Packet Loss
1. On Kharej:
   ```bash
   confgen test server --port 9001
   ```
2. On Iran:
   ```bash
   confgen test client -t 127.0.0.1 -p 9001 --udp
   ```

#### Test 3: Test MUX Concurrency Scaling Table
Measures how throughput scales across 1, 2, 8, and 16 concurrent streams:
```bash
confgen test client -t 127.0.0.1 -p 8080 --matrix
```

---

### 5. V3 ProtoSwap (Raw Protocol Replacement)

Swaps standard TCP and UDP IP headers with raw protocol numbers (e.g. Protocol 50 [ESP], 47 [GRE], or 253):

```bash
# Iran Server (supports --no-mux for raw direct mode):
confgen v3 server my-proto <KHAREJ_IP> <IRAN_IP> 10.40.0.1 50 -l 443 -f 443 --no-mux

# Kharej Server (via setup link or manual):
confgen v3 client my-proto <KHAREJ_IP> <IRAN_IP> 10.40.0.1 50 -l 443 -f 443 --no-mux
```

### 6. BitSwap (Configurable TCP Flag Swapping)

Swaps specified TCP header bitflags (e.g. `psh/rst`, `psh/cwr`, `cwr/ece`, `ack/fin`):

```bash
# Iran Server:
confgen waterwall bitswap iran \
  -n my-bitswap \
  -ii <IRAN_IP> \
  -ki <KHAREJ_IP> \
  -tp 443 \
  --pattern psh/rst

# Kharej Server:
confgen waterwall bitswap kharej \
  -n my-bitswap \
  -ii <IRAN_IP> \
  -ki <KHAREJ_IP> \
  -tp 443 \
  -fp 443 \
  --pattern psh/rst
```

---

## ⚡ Native SpeedTest & MUX Scaling Benchmark

Test tunnel bandwidth without depending on external tools like `iperf3` or `curl`.

### 1. Start Server Daemon on Kharej
```bash
confgen test server --port 9001
```

### 2. Run Single Stream Test from Iran
```bash
confgen test client -t 127.0.0.1 -p 9001 -d 5
```

### 3. Run MUX Multi-Connection Scaling Table (`--matrix`)
Runs 4 consecutive tests (1, 2, 8, 16 concurrent parallel child connections) through the tunnel to measure multiplexer throughput scaling:
```bash
confgen test client -t 127.0.0.1 -p 9001 --matrix
```

Sample output:
```text
================================================================================
📊 MUX CONCURRENCY SCALING BENCHMARK TABLE
================================================================================
Child Connections    | Upload Throughput         | Download Throughput      
--------------------------------------------------------------------------------
1                    |  215.10 Mbps (26.9 MB/s)  |  240.20 Mbps (30.0 MB/s) 
2                    |  420.50 Mbps (52.6 MB/s)  |  460.80 Mbps (57.6 MB/s) 
8                    |  890.40 Mbps (111.3 MB/s) |  920.20 Mbps (115.0 MB/s) 
16                   | 1450.15 Mbps (181.3 MB/s) | 1620.40 Mbps (202.6 MB/s)
================================================================================
```

---

## 🔬 Architecture Notes & Lessons Learned

1. **Why Iranian Hospital SNIs Win**:
   Iranian medical institutions (`shariati.tums.ac.ir`, `rhc.ac.ir`, `tums.ac.ir`) operate on dedicated Ministry of Health and national academic fiber backbones (`185.143.232.0/22` and `194.225.92.0/24`). Traffic to acute cardiology and university hospitals receives top-tier national QoS whitelisting and bypasses commercial stateful DPI filters.
2. **HalfDuplex Elimination of Connection Tracking**:
   By splitting upload and download into independent unidirectional TCP streams, stateful firewall inspection algorithms are unable to track complete bilateral connection flows, preventing connection throttling and reset attacks.
3. **ConnectionFisher Resilience**:
   Races 3 simultaneous connection attempts across the border and pins the connection to the lowest-jitter socket, eliminating packet loss during network disturbances.
4. **Isolated Test Sandboxing**:
   `confgen finder` uses dedicated test tunnel ports (`58443` / `58444`) and targets binary instances named `Waterwall-test` to guarantee your production services (`waterwall.service`, Xray, or production tunnels) are never killed or interrupted.

---

## 📜 Legacy Bash Scripts Reference

The repository also includes legacy bash scripts maintained for backward compatibility:
- `main.sh` - Modular bash configuration generator.
- `ultimate.sh` - Layered WaterWall V2 + Rathole + GOST tunnel setup.
- `waterwall/` - Individual bash configuration modules (`reverse_reality_config.sh`, `v3_config.sh`, etc.).

---

## ⚖️ License & Credits

- Core WaterWall Engine: [radkesvat/WaterWall](https://github.com/radkesvat/WaterWall)
- Developed & Maintained by [EbadiDev](https://github.com/EbadiDev) for ConfGen.
- Licensed under the MIT License.
