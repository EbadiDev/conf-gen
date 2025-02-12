# Load Balancer Configuration Generator

This script generates JSON configuration files for both server and Iran-side setups of a load balancer system.

## Quick Install & Usage

You can directly run the script with parameters using curl:

```bash
# Server Configuration (when all servers use the same port)
bash <(curl -Ls https://raw.githubusercontent.com/EbadiDev/conf-gen/main/create_lb_config.sh) server triple_tunnel -p 20631 192.168.1.100 10.0.0.50 2001:db8::1234

# Iran Configuration
bash <(curl -Ls https://raw.githubusercontent.com/EbadiDev/conf-gen/main/create_lb_config.sh) iran config1 14000 14999 192.168.1.100 13787
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

## Features

- Supports both IPv4 and IPv6 addresses
- Automatically detects address type and configures appropriate settings
  - IPv4: Uses "0.0.0.0" as listen address and /32 for whitelist
  - IPv6: Uses "::" as listen address and /128 for whitelist
- Creates load-balanced configurations for multiple servers
- Generates port range configurations for Iran-side setups
- Sets proper permissions (644) for generated files

## Output

The script generates a JSON configuration file named `<config_name>.json` in the current directory.

## Requirements

- Bash shell
- Write permissions in the current directory

## Error Handling

The script includes validation for:
- Required number of parameters
- Valid parameter pairs for server configuration
- Required parameters for Iran configuration
- Valid configuration type ('server' or 'iran')
