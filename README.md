# Configuration Generators

This repository contains configuration generators for various tunneling and load balancing solutions.

## Scripts

### 1. Load Balancer Configuration Generator (`create_lb_config.sh`)

This script generates JSON configuration files for cliExample:
```bash
# Example with IPv4
./create_lb_config.sh iran config1 14000 Examples:
```bash
# Iran side Reality/gRPC configuration
./create_lb_config.sh half web-cdn.snapp.ir mypassword123 iran reverse_reality_iran 100 199 198.51.100.4 10010

# Server side Reality/gRPC configuration with HAProxy
./create_lb_config.sh half haproxy web-cdn.snapp.ir mypassword123 tcp server reverse_reality_server -p 10010 203.0.113.50 11010
```2.168.1.100 13787

# Example with HAProxy (tunnel connects to HAProxy, which forwards to your service)
./create_lb_config.sh haproxy iran tcp config1 14000 14999 192.168.1.100 13787 15000
```

This will create a configuration with:
- Port range for incoming connections: 14000-14999
- Connection to kharej server at 192.168.1.100:13787
- With HAProxy: traffic flows from tunnel → HAProxy (port 15000) → your service (port 14000)r-side setups of a load balancer system with support for multiple configuration types including simple port forwarding and advanced Reality/gRPC tunneling. Now includes optional HAProxy integration for real IP forwarding and load balancing.

### 2. Rathole Configuration Generator (`rathole.sh`)

This script generates rathole server and client configurations with systemd services and optional HAProxy integration for real IP logging and load balancing.

---

## Rathole Configuration Generator

The `rathole.sh` script provides an easy way to generate rathole tunnel configurations with automatic key generation, systemd service creation, and optional HAProxy integration for real IP preservation.

### Features

- **Automatic Key Generation**: Uses rathole binary to generate secure noise protocol keys
- **Interactive Setup**: Guides you through the configuration process
- **Systemd Integration**: Automatically creates and installs systemd service files
- **HAProxy Support**: Optional HAProxy integration for real IP logging and load balancing
- **Multi-Service Management**: Supports multiple services in a single HAProxy configuration
- **Performance Optimized**: HAProxy configurations are optimized for maximum speed
- **Automatic Backup**: Creates timestamped backups before modifying existing configurations

### Prerequisites

- `rathole` binary in the current directory
- Root/sudo access for system configuration
- HAProxy installed (if using haproxy option)

### Usage

```bash
# Server Configuration
./rathole.sh server <name> <port> <default_token> <client_port> <tcp|udp> <nodelay> [haproxy]

# Client Configuration  
./rathole.sh client <name> <domain/ip:port> <default_token> <client_port> <tcp|udp> <nodelay> [haproxy]
```

### Parameters

- `name` - Configuration name (used for files and service names)
- `port` - Server bind port (server only)
- `domain/ip:port` - Server address (client only)
- `default_token` - Authentication token (must match on both sides)
- `client_port` - Client service port
- `tcp|udp` - Protocol type
- `nodelay` - Enable/disable TCP nodelay (true/false)
- `haproxy` - Optional: Enable HAProxy integration

### Examples

#### Basic Configuration

**Server:**
```bash
./rathole.sh server myapp 2333 mysecrettoken 8080 tcp true
```

**Client:**
```bash
./rathole.sh client myapp example.com:2333 mysecrettoken 8080 tcp false
```

#### With HAProxy (Real IP Logging)

**Server:**
```bash
./rathole.sh server webapp 2333 mysecrettoken 8080 tcp true haproxy
```

**Client:**
```bash
./rathole.sh client webapp example.com:2333 mysecrettoken 8080 tcp false haproxy
```

### HAProxy Integration

When using the `haproxy` option, the script:

1. **Server Side:**
   - External clients connect to port 8080 (HAProxy)
   - HAProxy forwards to rathole on port 9080
   - Real client IPs are logged in HAProxy logs

2. **Client Side:**
   - Rathole forwards to HAProxy on port 9080
   - HAProxy forwards to your service on port 8080
   - Your service receives traffic normally

3. **Configuration Management:**
   - Creates/updates `/etc/haproxy/haproxy.cfg`
   - Supports multiple services in one config
   - Overwrites existing service with same name
   - Creates timestamped backups

### Multi-Service Example

```bash
# First service
./rathole.sh server webapp1 2333 secret1 8080 tcp true haproxy

# Second service (adds to existing HAProxy config)
./rathole.sh server webapp2 2334 secret2 8081 tcp true haproxy

# Update first service (overwrites webapp1 config)
./rathole.sh server webapp1 2333 newsecret1 8080 tcp true haproxy
```

### Generated Files

- `<name>_server.toml` or `<name>_client.toml` - Rathole configuration
- `/etc/rathole/<name>_server.toml` - Installed rathole config
- `/etc/systemd/system/ratholes@.service` - Server systemd template
- `/etc/systemd/system/ratholec@.service` - Client systemd template
- `/etc/haproxy/haproxy.cfg` - HAProxy configuration (if enabled)

### Service Management

```bash
# Check service status
sudo systemctl status ratholes@myapp
sudo systemctl status ratholec@myapp

# View logs
sudo journalctl -u ratholes@myapp -f
sudo journalctl -u ratholec@myapp -f

# Start/stop/restart
sudo systemctl start ratholes@myapp
sudo systemctl stop ratholes@myapp
sudo systemctl restart ratholes@myapp
```

### HAProxy Performance Optimizations

The generated HAProxy configurations include:

- **Multi-threading**: Uses all available CPU cores
- **Memory optimization**: Larger buffers (32KB, 256KB receive/send buffers)
- **TCP optimizations**: Smart accept/connect, keep-alive
- **Fast timeouts**: 2s connect, aggressive health checks
- **Disabled logging**: For maximum performance (can be re-enabled)
- **Load balancing**: Optimized roundrobin algorithm

---

## Load Balancer Configuration Generator

This script generates JSON configuration files for client and server-side setups of a load balancer system with support for multiple configuration types including simple port forwarding and advanced Reality/gRPC tunneling.

## Quick Install & Usage

You can directly run the script with parameters using curl:

```bash
# Client Configuration (when all servers use the same port)
bash <(curl -Ls https://raw.githubusercontent.com/EbadiDev/conf-gen/main/create_lb_config.sh) client triple_tunnel -p 20631 192.168.1.100 10.0.0.50 2001:db8::1234

# Client Configuration with HAProxy
bash <(curl -Ls https://raw.githubusercontent.com/EbadiDev/conf-gen/main/create_lb_config.sh) haproxy client tcp triple_tunnel -p 20631 192.168.1.100

# Server Configuration
bash <(curl -Ls https://raw.githubusercontent.com/EbadiDev/conf-gen/main/create_lb_config.sh) server config1 14000 14999 192.168.1.100 13787

# Server Configuration with HAProxy
bash <(curl -Ls https://raw.githubusercontent.com/EbadiDev/conf-gen/main/create_lb_config.sh) haproxy server tcp config1 14000 14999 192.168.1.100 13787

# Simple TCP Port Forwarding
bash <(curl -Ls https://raw.githubusercontent.com/EbadiDev/conf-gen/main/create_lb_config.sh) simple tcp server tr 300 399 10.0.0.10 10410

# Half Reality/gRPC Configuration (Server side)
bash <(curl -Ls https://raw.githubusercontent.com/EbadiDev/conf-gen/main/create_lb_config.sh) half web-cdn.snapp.ir mypassword server ru 100 199 198.51.100.4 10010

# Half Reality/gRPC Configuration with HAProxy
bash <(curl -Ls https://raw.githubusercontent.com/EbadiDev/conf-gen/main/create_lb_config.sh) half haproxy web-cdn.snapp.ir mypassword tcp server ru 100 199 198.51.100.4 10010

# V2 Server Configuration (Advanced TUN + IP Manipulation)
bash <(curl -Ls https://raw.githubusercontent.com/EbadiDev/conf-gen/main/create_lb_config.sh) v2 server v2_config 100 199 203.0.113.100 10.80.0.1 10.80.0.2 10010 146

# V2 Server Configuration with HAProxy
bash <(curl -Ls https://raw.githubusercontent.com/EbadiDev/conf-gen/main/create_lb_config.sh) v2 haproxy server v2_config 100 199 203.0.113.100 10.80.0.1 10.80.0.2 10010 146

# V2 Client Configuration (Advanced TUN + IP Manipulation)
bash <(curl -Ls https://raw.githubusercontent.com/EbadiDev/conf-gen/main/create_lb_config.sh) v2 client v2_client 203.0.113.100 10.80.0.1 10.10.0.1 10311 146 10310

# V2 Client Configuration with HAProxy
bash <(curl -Ls https://raw.githubusercontent.com/EbadiDev/conf-gen/main/create_lb_config.sh) v2 haproxy client v2_client 203.0.113.100 10.80.0.1 10.10.0.1 10311 146 10310
```

Or you can download and use the script locally:

```bash
# Clone the repository
git clone https://github.com/EbadiDev/conf-gen.git
cd conf-gen
chmod +x create_lb_config.sh

# Then use as normal
./create_lb_config.sh <type> <config_name> [parameters...]
```

## Configuration Types

The script supports five main configuration types:

1. **Client Configuration** - Load-balanced client setups
2. **Server Configuration** - Server-side reverse proxy setups  
3. **Simple Configuration** - Direct port-to-port forwarding
4. **Half Configuration** - Reality/gRPC tunneling with advanced features
5. **V2 Configuration** - Advanced TUN device with IP manipulation and packet capture

## Usage

```bash
./create_lb_config.sh <type> <config_name> [parameters...]

# With HAProxy integration (for supported configurations):
./create_lb_config.sh haproxy <type> <protocol> <config_name> [parameters...]
./create_lb_config.sh v2 haproxy <type> <config_name> [parameters...]
./create_lb_config.sh half haproxy <website> <password> <protocol> <type> <config_name> [parameters...]
```

### Client Configuration

For creating a client-side configuration with multiple balanced servers:

```bash
# When servers have different ports
./create_lb_config.sh client <config_name> <server1_address> <server1_port> [<server2_address> <server2_port> ...]

# When all servers use the same port
./create_lb_config.sh client <config_name> -p <port> <server1_address> [<server2_address> ...]

# With HAProxy integration (recommended for production)
./create_lb_config.sh haproxy client tcp <config_name> -p <port> <server_address> [haproxy_port]
```

Example:
```bash
# Example with both IPv4 and IPv6 servers using the same port
./create_lb_config.sh server triple_tunnel -p 20631 192.168.1.100 10.0.0.50 2001:db8::1234

# Example with HAProxy for real IP preservation
./create_lb_config.sh haproxy server tcp myapp -p 8080 192.168.1.100 9080
```

This will create a load-balanced configuration with multiple servers. With HAProxy, clients connect to the external port, HAProxy handles load balancing and forwards to the waterwall with real IP information.

### Server Configuration

For creating a server-side configuration:

```bash
./create_lb_config.sh server <config_name> <start_port> <end_port> <kharej_ip> <kharej_port>

# With HAProxy integration for client IP preservation
./create_lb_config.sh haproxy server tcp <config_name> <start_port> <end_port> <kharej_ip> <kharej_port> [haproxy_port]
```

Example:
```bash
# Example with IPv4
./create_lb_config.sh server config1 14000 14999 192.168.1.100 13787

# Example with HAProxy (tunnel connects to HAProxy, which forwards to your service)
./create_lb_config.sh haproxy server tcp config1 14000 14999 192.168.1.100 13787 15000
```

This will create a configuration with:
- Port range for incoming connections: 14000-14999
- Connection to kharej server at 192.168.1.100:13787
- With HAProxy: traffic flows from tunnel → HAProxy (port 15000) → your service (port 14000)

### Simple Configuration

For creating simple port-to-port forwarding configurations:

```bash
# TCP forwarding (explicit protocol)
./create_lb_config.sh simple tcp server <config_name> <start_port> <end_port> <destination_ip> <destination_port>

# UDP forwarding (explicit protocol)
./create_lb_config.sh simple udp server <config_name> <start_port> <end_port> <destination_ip> <destination_port>

# TCP forwarding (default protocol)
./create_lb_config.sh simple server <config_name> <start_port> <end_port> <destination_ip> <destination_port>
```

Examples:
```bash
# Forward TCP traffic from ports 300-399 to 10.0.0.10:10410
./create_lb_config.sh simple tcp server tr 300 399 10.0.0.10 10410

# Forward UDP traffic from ports 500-599 to 10.0.0.10:10510  
./create_lb_config.sh simple udp server tr_udp 500 599 10.0.0.10 10510
```

### Half Configuration (Reality/gRPC)

For creating advanced Reality/gRPC tunneling configurations:

#### Server Side:
```bash
# With explicit protocol
./create_lb_config.sh half <website> <password> [tcp|udp] server <config_name> <start_port> <end_port> <kharej_ip> <kharej_port>

# With default TCP protocol
./create_lb_config.sh half <website> <password> server <config_name> <start_port> <end_port> <kharej_ip> <kharej_port>

# With HAProxy integration
./create_lb_config.sh half haproxy <website> <password> [tcp|udp] server <config_name> <start_port> <end_port> <kharej_ip> <kharej_port> [haproxy_port]
```

#### Client Side:
```bash
# With explicit protocol
./create_lb_config.sh half <website> <password> [tcp|udp] client <config_name> -p <port> <iran_ip>

# With default TCP protocol
./create_lb_config.sh half <website> <password> client <config_name> -p <port> <iran_ip>

# With HAProxy integration
./create_lb_config.sh half haproxy <website> <password> [tcp|udp] client <config_name> -p <port> <iran_ip> [haproxy_port]
```

Examples:
```bash
# Server side Reality/gRPC configuration
./create_lb_config.sh half web-cdn.snapp.ir mypassword123 server reverse_reality_server 100 199 20.10.0.4 10010

# Client side Reality/gRPC configuration with HAProxy
./create_lb_config.sh half haproxy web-cdn.snapp.ir mypassword123 tcp client reverse_reality_client -p 10010 1.1.1.1 11010
```

### V2 Configuration (Advanced TUN + IP Manipulation)

For creating advanced V2 configurations with TUN devices, IP manipulation, and packet capture:

#### V2 Server Side:
```bash
./create_lb_config.sh v2 server <config_name> <start_port> <end_port> <non_iran_ip> <iran_ip> <private_ip> <haproxy_port> <protocol>

# With HAProxy integration
./create_lb_config.sh v2 haproxy server <config_name> <start_port> <end_port> <non_iran_ip> <iran_ip> <private_ip> <haproxy_port> <protocol>
```

#### V2 Client Side:
```bash
./create_lb_config.sh v2 client <config_name> <non_iran_ip> <iran_ip> <private_ip> <haproxy_port> <protocol> <app_port>

# With HAProxy integration
./create_lb_config.sh v2 haproxy client <config_name> <non_iran_ip> <iran_ip> <private_ip> <haproxy_port> <protocol> <app_port>
```

Examples:
```bash
# V2 Server configuration with TUN device and IP manipulation
./create_lb_config.sh v2 server v2_config 100 199 203.0.113.50 10.80.0.1 10.80.0.2 10311 146

# V2 Client configuration with HAProxy and TUN device (HAProxy binds to private IP)
./create_lb_config.sh v2 haproxy client v2_client 203.0.113.50 10.80.0.1 10.10.0.1 10311 146 10310
```

**V2 Configuration Features:**
- **TUN Device**: Creates a virtual network interface with the config name
- **IP Manipulation**: Uses IpOverrider and IpManipulator for packet modification
- **Raw Socket Capture**: Captures packets based on source IP filtering
- **Automatic IP Calculation**: Automatically calculates PRIVATE_IP+1 for internal routing
- **Configurable Protocol Swapping**: Uses protoswap-tcp with your desired protocol number (e.g., 146)
- **HAProxy Integration**: Optional real IP forwarding with automatic port management
- **Private IP Binding**: V2 Client HAProxy binds to private IP instead of wildcard
- **Simplified Parameters**: V2 Server - removed redundant endpoint_port, V2 Client - cleaner parameter structure
- **No Interactive Prompts**: All parameters are provided via command line

### V2 Configuration Details

**V2 Server Side:**
- Listens on port range (e.g., 450-499) for incoming connections
- With HAProxy: External range → HAProxy → Waterwall (internal haproxy_port)
- Without HAProxy: External range → Waterwall directly
- `haproxy_port` serves as the internal waterwall listen port

**V2 Client Side:**
- HAProxy binds to private IP (e.g., `10.80.0.1:10311`) instead of `*:10311`
- Traffic flow: Tunnel → HAProxy (private_ip:haproxy_port) → Application (127.0.0.1:app_port)
- Uses accept-proxy for real IP preservation from tunnel

## Features

- **Multi-Protocol Support**: Supports both TCP and UDP protocols for simple and half configurations
- **Advanced V2 Configuration**: TUN devices with IP manipulation, packet capture, and protocol swapping
- **HAProxy Integration**: Optional real IP forwarding and load balancing with multi-service support
  - Real client IP preservation using PROXY protocol
  - Automatic service management and port allocation
  - Multi-service HAProxy configurations
  - Firewall integration for opened ports
- **IPv4/IPv6 Support**: Automatically detects address type and configures appropriate settings
  - IPv4: Uses "0.0.0.0" as listen address and /32 for whitelist
  - IPv6: Uses "::" as listen address and /128 for whitelist
- **Load Balancing**: Creates load-balanced configurations for multiple servers
- **Port Range Support**: Generates port range configurations for Iran-side setups
- **Automatic Firewall Management**: Automatically opens required ports using:
  - UFW (Ubuntu/Debian)
  - firewalld (CentOS/RHEL/Fedora)  
  - iptables (Generic Linux)
- **Reality/gRPC Tunneling**: Advanced tunneling with website masquerading
- **Core Integration**: Automatically adds configurations to core.json
- **Proper Permissions**: Sets correct file permissions (644) for generated files

## HAProxy Integration

The script now includes optional HAProxy integration for all configuration types, providing real IP forwarding and load balancing capabilities.

### HAProxy Benefits

- **Real IP Preservation**: Client IPs are forwarded to your application using PROXY protocol
- **Load Balancing**: Distribute traffic across multiple backend services
- **SSL Termination**: Can handle SSL/TLS termination if needed
- **Health Checks**: Monitor backend service health
- **Performance**: Optimized for high-throughput scenarios

### HAProxy Traffic Flow

#### Client Side (serving clients)
```
Internet Clients → HAProxy (external port) → Waterwall (internal port) → [Tunnel] → Server Side
```

#### Server Side (connecting to services)  
```
[Tunnel] → Waterwall → HAProxy (tunnel port) → Your Application (service port)
```

**Note:** V2 Client configurations bind HAProxy to the private IP instead of wildcard (*) for better security and network isolation.

### HAProxy Port Parameters

- `haproxy_port` - Optional parameter for custom HAProxy internal port
- **Default**: `external_port + 1000` for most configurations
- **Default**: `start_port + 1000` for server configurations  
- **Purpose**: Allows fine-tuning of internal port allocation to avoid conflicts

### HAProxy Configuration Management

- Creates/updates `/etc/haproxy/haproxy.cfg`
- Supports multiple services in one configuration
- Preserves existing services when adding new ones
- Automatic service start/reload
- Firewall ports automatically opened

### Example HAProxy Setups

```bash
# V2 Client with HAProxy - clients connect to port 10311 on private IP, forwards to app on 10310
./create_lb_config.sh v2 haproxy client myapp 203.0.113.50 198.51.100.20 192.168.1.100 10311 142 10310

# Legacy Server with HAProxy - tunnel forwards to HAProxy on 15000, HAProxy forwards to service on 14000  
./create_lb_config.sh haproxy server tcp config1 14000 14999 192.168.1.100 13787 15000

# Half Client with HAProxy - external clients → HAProxy (10010) → waterwall (11010)
./create_lb_config.sh half haproxy web-cdn.snapp.ir mypass tcp client myapp -p 10010 192.168.1.100 11010
```

## Output

The script generates:
- A JSON configuration file named `<config_name>.json` in the current directory
- HAProxy configuration file `/etc/haproxy/haproxy.cfg` (if using haproxy option)
- Automatic firewall rules for required ports
- Integration with existing core.json configuration
- Systemd service management for HAProxy (if applicable)

## Requirements

- Bash shell
- Write permissions in the current directory
- Root/sudo access for firewall configuration (optional but recommended)
- HAProxy installed (if using haproxy option)
- Network connectivity for curl-based installation

## Error Handling

The script includes comprehensive validation for:
- Required number of parameters for each configuration type
- Valid parameter pairs for server configuration
- Protocol validation (tcp/udp)
- IPv4/IPv6 address detection
- Required parameters for all configuration types
- Valid configuration type validation
- Firewall system detection and fallback
