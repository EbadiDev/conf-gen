#!/bin/bash

# Rathole Service Monitor Script
# This script checks for connection timeout errors in rathole logs and restarts the service if needed
# Should be run via cron every 6 hours

# Error string to search for
error_string="Connection timed out (os error 110)"

# Function to log messages with timestamp
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Function to get all running rathole services
get_rathole_services() {
    systemctl list-units --type=service --state=running | grep -E "rathole[sc]@" | awk '{print $1}'
}

# Function to check service logs for errors
check_service_logs() {
    local service_name="$1"
    local logs
    
    # Get logs from the last 6 hours (since this runs every 6 hours)
    logs=$(journalctl -u "$service_name" --since "6 hours ago" --no-pager 2>/dev/null)
    
    # Check if error string exists in logs
    if grep -q "$error_string" <<< "$logs"; then
        return 0  # Error found
    else
        return 1  # No error found
    fi
}

# Function to restart rathole service
restart_rathole_service() {
    local service_name="$1"
    
    log_message "Restarting $service_name due to connection timeout errors..."
    
    if systemctl restart "$service_name"; then
        log_message "Service $service_name restarted successfully"
        
        # Wait a moment for service to start
        sleep 5
        
        # Check if service is running
        if systemctl is-active "$service_name" >/dev/null 2>&1; then
            log_message "Service $service_name is now running"
        else
            log_message "ERROR: Service $service_name failed to start after restart"
        fi
    else
        log_message "ERROR: Failed to restart service $service_name"
    fi
}

# Main execution
main() {
    log_message "Starting rathole service monitor check..."
    
    # Get all running rathole services
    services=$(get_rathole_services)
    
    if [ -z "$services" ]; then
        log_message "No running rathole services found"
        exit 0
    fi
    
    # Check each service
    for service in $services; do
        log_message "Checking service: $service"
        
        if check_service_logs "$service"; then
            log_message "Error '$error_string' found in $service logs"
            restart_rathole_service "$service"
        else
            log_message "No connection timeout errors found in $service - service is healthy"
        fi
    done
    
    log_message "Rathole service monitor check completed"
}

# Run main function
main "$@"
