#!/bin/bash

# Main Waterwall Configuration Generator
# Modular script that delegates to specific configuration modules

# Detect if running from pipe (curl) and use temp directory
if [[ "${BASH_SOURCE[0]}" == "/dev/fd/"* ]] || [[ "${BASH_SOURCE[0]}" == *"/fd/"* ]]; then
    # Running from pipe, use temp directory
    SCRIPT_DIR="/tmp/waterwall_$(date +%s)_$$"
    mkdir -p "$SCRIPT_DIR"
    WATERWALL_DIR="$SCRIPT_DIR/waterwall"
    RUNNING_FROM_PIPE=true
else
    # Running from file, use normal directory
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    WATERWALL_DIR="$SCRIPT_DIR/waterwall"
    RUNNING_FROM_PIPE=false
fi

# Auto-download functionality for curl execution
AUTO_DOWNLOADED=false

# Function to download required modules
download_modules() {
    local base_url="https://raw.githubusercontent.com/EbadiDev/conf-gen/main/waterwall"
    local modules=(
        "common.sh"
        "server_client_config.sh"
        "simple_config.sh"
        "half_config.sh"
        "v2_config.sh"
        "haproxy.sh"
    "caddy.sh"
    "gost.sh"
    )
    
    local total=${#modules[@]}
    echo "Downloading $total modules..."
    
    # Create waterwall directory
    mkdir -p "$WATERWALL_DIR"
    
    # Progress tracking
    local completed=0
    local failed=0
    
    # Try multiple download methods for Iran network compatibility
    echo -n "Progress: "
    for module in "${modules[@]}"; do
        echo -n "[$((completed + 1))/$total] $module... "
        
        # Method 1: curl with IPv4 only and specific user agent
        if curl -4 -s -m 10 -f -L --user-agent "Mozilla/5.0" \
           -H "Accept: text/plain" -o "$WATERWALL_DIR/$module" \
           "$base_url/$module" 2>/dev/null && \
           [ -f "$WATERWALL_DIR/$module" ] && [ -s "$WATERWALL_DIR/$module" ] && \
           head -1 "$WATERWALL_DIR/$module" 2>/dev/null | grep -q "#!/bin/bash"; then
            echo "✓"
            ((completed++))
            continue
        fi
        
        # Method 2: wget with IPv4 only
        if command -v wget >/dev/null 2>&1; then
            if wget -4 --quiet --timeout=10 --tries=2 \
               --user-agent="Mozilla/5.0" -O "$WATERWALL_DIR/$module" \
               "$base_url/$module" 2>/dev/null && \
               [ -f "$WATERWALL_DIR/$module" ] && [ -s "$WATERWALL_DIR/$module" ] && \
               head -1 "$WATERWALL_DIR/$module" 2>/dev/null | grep -q "#!/bin/bash"; then
                echo "✓"
                ((completed++))
                continue
            fi
        fi
        
        # Method 3: Alternative domains/mirrors (using other CDNs)
        local alt_urls=(
            "https://cdn.jsdelivr.net/gh/EbadiDev/conf-gen@main/waterwall/$module"
            "https://gitcdn.xyz/repo/EbadiDev/conf-gen/main/waterwall/$module"
        )
        
        local success=false
        for alt_url in "${alt_urls[@]}"; do
            if curl -4 -s -m 8 -f -L --user-agent "Mozilla/5.0" \
               -o "$WATERWALL_DIR/$module" "$alt_url" 2>/dev/null && \
               [ -f "$WATERWALL_DIR/$module" ] && [ -s "$WATERWALL_DIR/$module" ] && \
               head -1 "$WATERWALL_DIR/$module" 2>/dev/null | grep -q "#!/bin/bash"; then
                success=true
                break
            fi
        done
        
        if [ "$success" = true ]; then
            echo "✓"
            ((completed++))
        else
            echo "✗"
            rm -f "$WATERWALL_DIR/$module" 2>/dev/null
            ((failed++))
        fi
    done
    
    echo
    echo "Summary:"
    for module in "${modules[@]}"; do
        if [ -f "$WATERWALL_DIR/$module" ] && [ -s "$WATERWALL_DIR/$module" ]; then
            echo "✓ $module"
        else
            echo "✗ $module"
            failed=1
        fi
    done
    
    if [ $failed -eq 1 ]; then
        echo "Some downloads failed. Trying fallback methods..."
        # Final retry with different approach
        for module in "${modules[@]}"; do
            if [ ! -f "$WATERWALL_DIR/$module" ] || [ ! -s "$WATERWALL_DIR/$module" ] || \
               ! head -1 "$WATERWALL_DIR/$module" 2>/dev/null | grep -q "#!/bin/bash"; then
                echo -n "Final retry $module... "
                
                # Try with minimal curl options for maximum compatibility
                if curl -4 -s -m 15 --retry 2 --retry-delay 1 \
                   -o "$WATERWALL_DIR/$module" \
                   "$base_url/$module" 2>/dev/null && \
                   [ -f "$WATERWALL_DIR/$module" ] && [ -s "$WATERWALL_DIR/$module" ]; then
                    echo "✓"
                    failed=0
                else
                    echo "✗"
                    return 1
                fi
            fi
        done
    fi
    
    AUTO_DOWNLOADED=true
    echo "All modules ready!"
}

# Function to cleanup downloaded modules
cleanup_modules() {
    if [ "$AUTO_DOWNLOADED" = true ] && [ "$RUNNING_FROM_PIPE" = true ]; then
        echo "Cleaning up downloaded modules..."
        rm -rf "$SCRIPT_DIR"
        echo "Cleanup completed."
    fi
}

# Trap to ensure cleanup on exit
trap 'cleanup_modules; exit' EXIT INT TERM

# Check if modules exist, if not download them
if [ ! -d "$WATERWALL_DIR" ] || [ ! -f "$WATERWALL_DIR/common.sh" ]; then
    if ! download_modules; then
        echo "Error: Failed to download required modules"
        exit 1
    fi
fi

# Source common functions
source "$WATERWALL_DIR/common.sh"

# Display banner
show_banner() {
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════════╗
║                     Waterwall Configuration Generator                        ║
║                              Modular Edition                                 ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
}

# Main function to route to appropriate configuration module
main() {
    # Show banner
    show_banner
    
    # Check minimum arguments
    if [ $# -lt 1 ]; then
        show_help
        exit 1
    fi
    
    # Handle help requests
    if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
        if [ -n "$2" ]; then
            show_detailed_help "$2"
        else
            show_help
        fi
        exit 0
    fi
    
    local config_type="$1"
    
    # Route to appropriate configuration module
    case "$config_type" in
        "server")
            source "$WATERWALL_DIR/server_client_config.sh"
            handle_server_config "$@"
            ;;
        "client")
            source "$WATERWALL_DIR/server_client_config.sh"
            handle_client_config "$@"
            ;;
        "simple")
            source "$WATERWALL_DIR/simple_config.sh"
            handle_simple_config "$@"
            ;;
        "half")
            source "$WATERWALL_DIR/half_config.sh"
            handle_half_config "$@"
            ;;
        "v2")
            source "$WATERWALL_DIR/v2_config.sh"
            handle_v2_config "$@"
            ;;
        "haproxy")
            # HAProxy-enabled configurations
            local sub_type="$2"
            case "$sub_type" in
                "server")
                    source "$WATERWALL_DIR/server_client_config.sh"
                    handle_server_config "$@"
                    ;;
                "client")
                    source "$WATERWALL_DIR/server_client_config.sh"
                    handle_client_config "$@"
                    ;;
                *)
                    print_error "Invalid HAProxy configuration type: $sub_type"
                    print_info "Supported HAProxy types: server, client"
                    exit 1
                    ;;
            esac
            ;;
        "caddy")
            # Caddy-enabled configurations
            local sub_type="$2"
            case "$sub_type" in
                "server")
                    source "$WATERWALL_DIR/server_client_config.sh"
                    handle_server_config "$@"
                    ;;
                "client")
                    source "$WATERWALL_DIR/server_client_config.sh"
                    handle_client_config "$@"
                    ;;
                *)
                    print_error "Invalid Caddy configuration type: $sub_type"
                    print_info "Supported Caddy types: server, client"
                    exit 1
                    ;;
            esac
            ;;
        *)
            print_error "Unknown configuration type: $config_type"
            print_info "Supported types: server, client, simple, half, v2"
            print_info "For HAProxy integration: haproxy <type> <protocol> ..."
            print_info "For Caddy integration: caddy <type> <protocol> ..."
            show_help
            exit 1
            ;;
    esac
}

# Handle script interruption
trap 'print_error "Script interrupted by user"; exit 130' INT

# Run main function with all arguments
main "$@"
