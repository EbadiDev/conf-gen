# Load Balancer Configuration Generator

This script generates JSON configuration files for server and Iran-side setups of a load balancer system with support for multiple configuration types including simple port forwarding and advanced Reality/gRPC tunneling.

## Quick Install & Usage

You can directly run the script with parameters using curl:

```bash
# Server Configuration (when all servers use the same port)
bash <(curl -Ls https://raw.githubusercontent.com/EbadiDev/conf-gen/main/create_lb_config.sh) server triple_tunnel -p 20631 192.168.1.100 10.0.0.50 2001:db8::1234

# Iran Configuration
bash <(curl -Ls https://raw.githubusercontent.com/EbadiDev/conf-gen/main/create_lb_config.sh) iran config1 14000 14999 192.168.1.100 13787

# Simple TCP Port Forwarding
bash <(curl -Ls https://raw.githubusercontent.com/EbadiDev/conf-gen/main/create_lb_config.sh) simple tcp iran tr 300 399 10.10.0.11 10410

# Half Reality/gRPC Configuration (Iran side)
bash <(curl -Ls https://raw.githubusercontent.com/EbadiDev/conf-gen/main/create_lb_config.sh) half web-cdn.snapp.ir mypassword iran ru 100 199 20.10.0.4 10010
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

The script supports four main configuration types:

1. **Server Configuration** - Load-balanced server setups
2. **Iran Configuration** - Iran-side reverse proxy setups  
3. **Simple Configuration** - Direct port-to-port forwarding
4. **Half Configuration** - Reality/gRPC tunneling with advanced features

## Usage

```bash
./create_lb_config.sh <type> <config_name> [parameters...]
```

### Server Configuration

For creating a server-side configuration with multiple balanced servers:

```bash
# When servers have different ports
./create_lb_config.sh server <config_name> <server1_address> <server1_port> [<server2_address> <server2_port> ...]

# When all servers use the same port
./create_lb_config.sh server <config_name> -p <port> <server1_address> [<server2_address> ...]
```

Example:
```bash
# Example with both IPv4 and IPv6 servers using the same port
./create_lb_config.sh server triple_tunnel -p 20631 192.168.1.100 10.0.0.50 2001:db8::1234
```

This will create a load-balanced configuration with three servers.

### Iran Configuration

For creating an Iran-side configuration:

```bash
./create_lb_config.sh iran <config_name> <start_port> <end_port> <kharej_ip> <kharej_port>
```

Example:
```bash
# Example with IPv4
./create_lb_config.sh iran config1 14000 14999 192.168.1.100 13787
```

This will create a configuration with:
- Port range for incoming connections: 14000-14999
- Connection to kharej server at 192.168.1.100:13787

### Simple Configuration

For creating simple port-to-port forwarding configurations:

```bash
# TCP forwarding (explicit protocol)
./create_lb_config.sh simple tcp iran <config_name> <start_port> <end_port> <destination_ip> <destination_port>

# UDP forwarding (explicit protocol)
./create_lb_config.sh simple udp iran <config_name> <start_port> <end_port> <destination_ip> <destination_port>

# TCP forwarding (default protocol)
./create_lb_config.sh simple iran <config_name> <start_port> <end_port> <destination_ip> <destination_port>
```

Examples:
```bash
# Forward TCP traffic from ports 300-399 to 10.10.0.11:10410
./create_lb_config.sh simple tcp iran tr 300 399 10.10.0.11 10410

# Forward UDP traffic from ports 500-599 to 10.10.0.11:10510  
./create_lb_config.sh simple udp iran tr_udp 500 599 10.10.0.11 10510
```

### Half Configuration (Reality/gRPC)

For creating advanced Reality/gRPC tunneling configurations:

#### Iran Side:
```bash
# With explicit protocol
./create_lb_config.sh half <website> <password> [tcp|udp] iran <config_name> <start_port> <end_port> <kharej_ip> <kharej_port>

# With default TCP protocol
./create_lb_config.sh half <website> <password> iran <config_name> <start_port> <end_port> <kharej_ip> <kharej_port>
```

#### Server Side:
```bash
# With explicit protocol
./create_lb_config.sh half <website> <password> [tcp|udp] server <config_name> -p <port> <iran_ip>

# With default TCP protocol
./create_lb_config.sh half <website> <password> server <config_name> -p <port> <iran_ip>
```

Examples:
```bash
# Iran side Reality/gRPC configuration
./create_lb_config.sh half web-cdn.snapp.ir mypassword123 iran reverse_reality_iran 100 199 20.10.0.4 10010

# Server side Reality/gRPC configuration
./create_lb_config.sh half web-cdn.snapp.ir mypassword123 server reverse_reality_server -p 10010 188.213.197.166
```

## Features

- **Multi-Protocol Support**: Supports both TCP and UDP protocols for simple and half configurations
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

## Output

The script generates:
- A JSON configuration file named `<config_name>.json` in the current directory
- Automatic firewall rules for required ports
- Integration with existing core.json configuration

## Requirements

- Bash shell
- Write permissions in the current directory
- Root/sudo access for firewall configuration (optional but recommended)
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
