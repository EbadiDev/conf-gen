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
    )
    
    local total=${#modules[@]}
    echo "Downloading $total modules..."
    
    # Create waterwall directory
    mkdir -p "$WATERWALL_DIR"
    
    # Progress tracking
    local completed=0
    local failed=0
    
    # Download all modules in parallel with progress tracking
    local pids=()
    
    for module in "${modules[@]}"; do
        {
            if curl -s -m 10 -f -o "$WATERWALL_DIR/$module" "$base_url/$module" 2>/dev/null; then
                echo "DONE:$module" > "$WATERWALL_DIR/$module.status"
            else
                echo "FAIL:$module" > "$WATERWALL_DIR/$module.status"
            fi
        } &
        pids+=($!)
    done
    
    # Progress monitoring
    echo -n "Progress: [0/$total] "
    local spinner=('|' '/' '-' '\')
    local spin_idx=0
    
    while [ $completed -lt $total ]; do
        completed=0
        failed=0
        
        # Count completed downloads
        for module in "${modules[@]}"; do
            if [ -f "$WATERWALL_DIR/$module.status" ]; then
                if grep -q "DONE:" "$WATERWALL_DIR/$module.status" 2>/dev/null; then
                    ((completed++))
                elif grep -q "FAIL:" "$WATERWALL_DIR/$module.status" 2>/dev/null; then
                    ((completed++))
                    ((failed++))
                fi
            fi
        done
        
        # Update progress
        printf "\rProgress: [%d/%d] %s " "$completed" "$total" "${spinner[$spin_idx]}"
        spin_idx=$(( (spin_idx + 1) % 4 ))
        
        # Small delay
        sleep 0.1
    done
    
    # Wait for all background processes to complete
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null
    done
    
    echo # New line after progress
    
    # Show final results
    for module in "${modules[@]}"; do
        if [ -f "$WATERWALL_DIR/$module.status" ]; then
            if grep -q "DONE:" "$WATERWALL_DIR/$module.status" 2>/dev/null; then
                echo "✓ $module"
            else
                echo "✗ $module"
                failed=1
            fi
        else
            echo "✗ $module (timeout)"
            failed=1
        fi
    done
    
    # Clean up status files
    rm -f "$WATERWALL_DIR"/*.status
    
    if [ $failed -eq 1 ]; then
        return 1
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
        *)
            print_error "Unknown configuration type: $config_type"
            print_info "Supported types: server, client, simple, half, v2"
            print_info "For HAProxy integration: haproxy <type> <protocol> ..."
            show_help
            exit 1
            ;;
    esac
}

# Handle script interruption
trap 'print_error "Script interrupted by user"; exit 130' INT

# Run main function with all arguments
main "$@"
