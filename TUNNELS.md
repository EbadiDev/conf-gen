# 🔧 Tunnel Inventory

> **Last updated:** 2026-06-29  
> **Maintained by:** arch

---

## 🇮🇷 Iran 1 (`95.38.130.213`)

### Configured Tunnels & Targets

| Proto | Config Name | Target Kharej Server | Kharej Main IP | Kharej Floating IPs | Port | SNI | Target Dest / Port | Flags |
|-------|-------------|----------------------|----------------|---------------------|------|-----|--------------------|-------|
| TCP | `uae` ↔ `dour5` | **dour5** (UAE) | `89.36.162.43` | — | `443` | `telewebion.ir` | `185.165.205.129` / `8443` | `--proxy-protocol` |
| UDP | `uae-wg` ↔ `dour5-wg` | **dour5** (UAE) | `89.36.162.43` | — | `27016` | `telewebion.ir` | `185.165.205.129` / `27015` | — |

### Deployment Commands

#### Tunnel 1: TCP Reverse Reality (`uae` ↔ `dour5`)
```bash
# On Iran 1 (95.38.130.213):
bash <(curl -Ls https://raw.githubusercontent.com/EbadiDev/conf-gen/main/main.sh) \
  reverse-reality tcp iran uae \
  95.38.130.213 89.36.162.43 443 telewebion.ir 185.165.205.129 arch123net --proxy-protocol

# On Kharej (dour5 - 89.36.162.43):
bash <(curl -Ls https://raw.githubusercontent.com/EbadiDev/conf-gen/main/main.sh) \
  reverse-reality tcp kharej dour5 \
  95.38.130.213 89.36.162.43 443 telewebion.ir 8443 arch123net
```

#### Tunnel 2: UDP Reverse Reality (`uae-wg` ↔ `dour5-wg`)
```bash
# On Iran 1 (95.38.130.213):
bash <(curl -Ls https://raw.githubusercontent.com/EbadiDev/conf-gen/main/main.sh) \
  reverse-reality udp iran uae-wg \
  95.38.130.213 89.36.162.43 27016 telewebion.ir 185.165.205.129 arch123net

# On Kharej (dour5 - 89.36.162.43):
bash <(curl -Ls https://raw.githubusercontent.com/EbadiDev/conf-gen/main/main.sh) \
  reverse-reality udp kharej dour5-wg \
  95.38.130.213 89.36.162.43 27016 telewebion.ir 27015 arch123net
```

---

## 🇮🇷 Iran 2 (`95.38.130.216`)

### Configured Tunnels & Targets

| Proto | Config Name | Target Kharej Server | Kharej Main IP | Kharej Floating IPs | Port | SNI | Target Dest / Port | Flags |
|-------|-------------|----------------------|----------------|---------------------|------|-----|--------------------|-------|
| TCP | `tr` ↔ `dour4` | **dour4** (Turkey) | `89.36.162.43` | `212.87.198.210`, `212.87.199.206` | `443` | `telewebion.ir` | `185.165.205.129` / `8443` | `--proxy-protocol`, `--float` |

### Deployment Commands

#### Tunnel 1: TCP Reverse Reality with Floating IPs (`tr` ↔ `dour4`)
```bash
# On Iran 2 (95.38.130.216):
bash <(curl -Ls https://raw.githubusercontent.com/EbadiDev/conf-gen/main/main.sh) \
  reverse-reality tcp iran tr \
  95.38.130.216 89.36.162.43 443 telewebion.ir 185.165.205.129 arch123net \
  --proxy-protocol --float 212.87.198.210 212.87.199.206

# On Kharej (dour4 - 89.36.162.43 + Floats):
bash <(curl -Ls https://raw.githubusercontent.com/EbadiDev/conf-gen/main/main.sh) \
  reverse-reality tcp kharej dour4 \
  95.38.130.216 89.36.162.43 443 telewebion.ir 8443 arch123net \
  --float 212.87.198.210 212.87.199.206
```

---

## 🇮🇷 Iran 3 (`<IRAN_3_IP>`)

*(Template for configuring Iran 3 server)*

### Configured Tunnels & Targets

| Proto | Config Name | Target Kharej Server | Kharej Main IP | Kharej Floating IPs | Port | SNI | Target Dest / Port | Flags |
|-------|-------------|----------------------|----------------|---------------------|------|-----|--------------------|-------|
| TCP | `name-iran` ↔ `name-kharej` | **Kharej Server Name** | `IP` | — | `443` | `domain.com` | `Target IP` / `Port` | — |

---

## 💡 How Floating IPs Work in Reverse Reality
When running with `--float <ip1> <ip2>`:
- **Iran side**: Automatically adds the main Kharej IP and all floating IPs to the `TcpListener` whitelist.
- **Kharej side**: Automatically creates an `addresses` array in `TcpConnector` with weighted load balancing across `source_ip` entries for all floating IPs connecting back to Iran.
