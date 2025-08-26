#!/bin/bash

# Enhanced NUT entrypoint with USB hotplug support
# Handles dynamic UPS detection, driver management, and configuration updates

set -e

# Configuration
NUT_CONF="/opt/nut/etc/nut.conf"
UPS_CONF="/opt/nut/etc/ups.conf"
UPSD_CONF="/opt/nut/etc/upsd.conf"
UPSD_USERS="/opt/nut/etc/upsd.users"
PID_DIR="/var/run/nut"
LOG_FILE="/var/log/nut/hotplug.log"
SCAN_INTERVAL=10
MAX_RETRIES=3

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Logging function
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg" >> "$LOG_FILE"
    echo "$msg" >&2  # Send to stderr instead of stdout
}

# Check if upsd is running
is_upsd_running() {
    pgrep -f "upsd.*-F" > /dev/null 2>&1
}

# Stop all UPS drivers safely
stop_all_drivers() {
    log "Stopping all UPS drivers..."
    
    # Stop drivers gracefully first
    /opt/nut/sbin/upsdrvctl stop || true
    sleep 2
    
    # Kill any remaining running drivers
    pkill -TERM -f "usbhid-ups" || true
    pkill -TERM -f "upsdrvctl" || true
    sleep 2
    
    # Force kill if still running
    pkill -KILL -f "usbhid-ups" || true
    pkill -KILL -f "upsdrvctl" || true
    
    # Clean up PID files and sockets
    find "$PID_DIR" -name "*.pid" -delete 2>/dev/null || true
    find "$PID_DIR" -name "usbhid-ups-*" -type s -delete 2>/dev/null || true
    find /var/run/nut/ -name "usbhid-ups-*" -type s -delete 2>/dev/null || true
    
    sleep 2
}

# Stop upsd
stop_upsd() {
    if is_upsd_running; then
        log "Stopping upsd..."
        pkill -TERM -f "upsd.*-F" || true
        sleep 2
        
        # Force kill if still running
        if is_upsd_running; then
            pkill -KILL -f "upsd.*-F" || true
            sleep 1
        fi
    fi
}

# Scan for USB UPS devices using NUT's native detection
scan_usb_devices() {
    local devices=()
    local temp_file="/tmp/nut_scan_output"
    
    # Use NUT's built-in scanner to detect USB UPS devices
    log "Scanning for USB UPS devices using NUT scanner..."
    
    # Try nut-scanner first (if available and working)
    if /opt/nut/bin/nut-scanner -U -q > "$temp_file" 2>/dev/null; then
        # Parse nut-scanner output for device sections
        local current_section=""
        local vendor_id=""
        local product_id=""
        local driver=""
        local desc=""
        
        while IFS= read -r line; do
            # Match section headers like [nutdev1]
            if [[ $line =~ ^\[([^\]]+)\]$ ]]; then
                # Save previous device if we have one
                if [[ -n "$current_section" && -n "$driver" && "$driver" == "usbhid-ups" ]]; then
                    local device_info="${vendor_id:-auto}:${product_id:-auto}|${desc:-USB UPS}"
                    devices+=("$device_info")
                    log "Found UPS device via nut-scanner: $desc (Driver: $driver)"
                fi
                
                # Start new section
                current_section="${BASH_REMATCH[1]}"
                vendor_id=""
                product_id=""
                driver=""
                desc=""
                
            elif [[ $line =~ ^[[:space:]]*driver[[:space:]]*=[[:space:]]*(.+)$ ]]; then
                driver="${BASH_REMATCH[1]//\"}"
            elif [[ $line =~ ^[[:space:]]*vendorid[[:space:]]*=[[:space:]]*(.+)$ ]]; then
                vendor_id="${BASH_REMATCH[1]//\"}"
            elif [[ $line =~ ^[[:space:]]*productid[[:space:]]*=[[:space:]]*(.+)$ ]]; then
                product_id="${BASH_REMATCH[1]//\"}"
            elif [[ $line =~ ^[[:space:]]*desc[[:space:]]*=[[:space:]]*(.+)$ ]]; then
                desc="${BASH_REMATCH[1]//\"}"
            fi
        done < "$temp_file"
        
        # Don't forget the last device
        if [[ -n "$current_section" && -n "$driver" && "$driver" == "usbhid-ups" ]]; then
            local device_info="${vendor_id:-auto}:${product_id:-auto}|${desc:-USB UPS}"
            devices+=("$device_info")
            log "Found UPS device via nut-scanner: $desc (Driver: $driver)"
        fi
        
    else
        # Fallback: Try to detect UPS by attempting to start usbhid-ups driver
        log "nut-scanner unavailable, using fallback detection method"
        
        # Create a temporary ups.conf for testing
        local test_conf="/tmp/test_ups.conf"
        cat > "$test_conf" << 'EOF'
[test-ups]
    driver = usbhid-ups
    port = auto
    desc = "Test UPS Detection"
EOF
        
        # Test if usbhid-ups can find any device
        if /opt/nut/sbin/usbhid-ups -a test-ups -c "$test_conf" -k > /dev/null 2>&1; then
            # If successful, there's at least one USB UPS connected
            # Get more details from lsusb for HID devices
            while read -r line; do
                if [[ $line =~ Bus\ ([0-9]+)\ Device\ ([0-9]+):\ ID\ ([0-9a-f]{4}):([0-9a-f]{4})\ (.+) ]]; then
                    local vendor_id="${BASH_REMATCH[3]}"
                    local product_id="${BASH_REMATCH[4]}"
                    local description="${BASH_REMATCH[5]}"
                    
                    # Check if this USB device has HID interface (common for UPS)
                    local device_path="/sys/bus/usb/devices"
                    if find "$device_path" -name "*${vendor_id}:${product_id}*" -exec grep -l "bInterfaceClass.*03" {}/*/bInterfaceClass \; 2>/dev/null | head -1 > /dev/null; then
                        device_info="$vendor_id:$product_id|$description"
                        devices+=("$device_info")
                        log "Found potential UPS device via fallback: $description (ID: $vendor_id:$product_id)"
                    fi
                fi
            done < <(lsusb)
            
            # If we still don't have specific devices, add a generic entry
            if [[ ${#devices[@]} -eq 0 ]]; then
                devices+=("auto:auto|Generic USB UPS")
                log "Found USB UPS device (generic detection)"
            fi
        fi
        
        rm -f "$test_conf"
    fi
    
    rm -f "$temp_file"
    printf '%s\n' "${devices[@]}"
}

# Update ups.conf only if devices have changed, always keeping 'my-ups' name
update_ups_conf() {
    local devices=("$@")
    local needs_update=false
    
    # Check if we need to update the configuration
    if [[ ! -f "$UPS_CONF" ]]; then
        needs_update=true
        log "ups.conf missing, creating new configuration"
    elif [[ ${#devices[@]} -eq 0 ]]; then
        # No devices detected - create minimal config that won't break dashboard
        log "No UPS devices detected, maintaining minimal my-ups config"
        cat > "$UPS_CONF" << 'EOF'
# No UPS devices currently connected
# Configuration maintained for dashboard compatibility

[my-ups]
    driver = dummy-ups
    port = /dev/null
    desc = "Waiting for UPS connection"
EOF
        chown nut:nut "$UPS_CONF"
        return 1
    else
        needs_update=true  # For now, always update when devices are present
    fi
    
    if ! $needs_update; then
        return 0
    fi
    
    log "Updating ups.conf for ${#devices[@]} device(s)..."
    
    # Always maintain 'my-ups' as primary device name for dashboard compatibility
    local primary_device="${devices[0]}"
    local vendor_product="${primary_device%|*}"
    local description="${primary_device#*|}"
    local vendor_id="${vendor_product%:*}"
    local product_id="${vendor_product#*:}"
    
    local conf_content="# Auto-generated NUT configuration
# Primary device always named 'my-ups' for dashboard compatibility
# Last updated: $(date '+%Y-%m-%d %H:%M:%S')

[my-ups]
    driver = usbhid-ups
    port = auto"
    
    # Only add vendor/product IDs if they're specific (not 'auto')
    if [[ "$vendor_id" != "auto" && "$product_id" != "auto" ]]; then
        conf_content+="
    vendorid = $vendor_id
    productid = $product_id"
    fi
    
    conf_content+="
    desc = \"$description\"
    # Hotplug-optimized settings
    pollinterval = 2
"
    
    # Add additional devices if present (secondary UPS units)
    if [[ ${#devices[@]} -gt 1 ]]; then
        conf_content+="
# Additional UPS devices"
        for i in $(seq 1 $((${#devices[@]} - 1))); do
            local device="${devices[$i]}"
            local vendor_product="${device%|*}"
            local description="${device#*|}"
            local vendor_id="${vendor_product%:*}"
            local product_id="${vendor_product#*:}"
            
            conf_content+="

[my-ups-$((i + 1))]
    driver = usbhid-ups
    port = auto"
            
            if [[ "$vendor_id" != "auto" && "$product_id" != "auto" ]]; then
                conf_content+="
    vendorid = $vendor_id
    productid = $product_id"
            fi
            
            conf_content+="
    desc = \"$description\"
    pollinterval = 2"
        done
    fi
    
    echo "$conf_content" > "$UPS_CONF"
    chown nut:nut "$UPS_CONF"
    
    log "Updated ups.conf with primary device as 'my-ups'"
    return 0
}

# Start UPS drivers
start_drivers() {
    local retry_count=0
    
    log "Starting UPS drivers..."
    
    while [[ $retry_count -lt $MAX_RETRIES ]]; do
        if /opt/nut/sbin/upsdrvctl -u root start; then
            log "UPS drivers started successfully"
            return 0
        else
            ((retry_count++))
            log "UPS driver start attempt $retry_count failed"
            
            if [[ $retry_count -lt $MAX_RETRIES ]]; then
                log "Retrying in 5 seconds..."
                sleep 5
            fi
        fi
    done
    
    log "Failed to start UPS drivers after $MAX_RETRIES attempts"
    return 1
}

# Start upsd
start_upsd() {
    log "Starting upsd..."
    
    # Start upsd in background with logging
    /opt/nut/sbin/upsd -D -F &
    local upsd_pid=$!
    
    # Wait a moment and check if it's still running
    sleep 2
    if kill -0 $upsd_pid 2>/dev/null; then
        log "upsd started successfully (PID: $upsd_pid)"
        return 0
    else
        log "upsd failed to start"
        return 1
    fi
}

# Initialize NUT configuration files
init_nut_config() {
    log "Initializing NUT configuration..."
    
    # Create nut.conf
    if [[ ! -f "$NUT_CONF" ]]; then
        echo "MODE=standalone" > "$NUT_CONF"
        chown nut:nut "$NUT_CONF"
    fi
    
    # Create basic upsd.conf
    if [[ ! -f "$UPSD_CONF" ]]; then
        cat > "$UPSD_CONF" << 'EOF'
MAXAGE 15
STATEPATH /var/run/nut
LISTEN 0.0.0.0 3493
LISTEN :: 3493
EOF
        chown nut:nut "$UPSD_CONF"
        chmod 640 "$UPSD_CONF"
    fi
    
    # Create basic upsd.users
    if [[ ! -f "$UPSD_USERS" ]]; then
        cat > "$UPSD_USERS" << 'EOF'
[admin]
    password = admin
    actions = SET
    instcmds = ALL
    
[monitor]
    password = monitor
    upsmon slave
EOF
        chown nut:nut "$UPSD_USERS"
        chmod 640 "$UPSD_USERS"
    fi
    
    # Ensure proper permissions on directories
    chown -R nut:nut "$PID_DIR"
    chmod 755 "$PID_DIR"
}

# Main monitoring loop
monitor_usb_devices() {
    local current_devices=()
    local previous_devices=()
    local devices_changed=false
    
    log "Starting USB device monitoring (scan interval: ${SCAN_INTERVAL}s)"
    
    while true; do
        # Scan for current devices
        readarray -t current_devices < <(scan_usb_devices)
        
        # Compare with previous scan
        devices_changed=false
        
        if [[ ${#current_devices[@]} -ne ${#previous_devices[@]} ]]; then
            devices_changed=true
        else
            for i in "${!current_devices[@]}"; do
                if [[ "${current_devices[i]}" != "${previous_devices[i]}" ]]; then
                    devices_changed=true
                    break
                fi
            done
        fi
        
        if $devices_changed; then
            log "USB device change detected!"
            
            # Stop everything
            stop_upsd
            stop_all_drivers
            
            # Reconfigure
            if update_ups_conf "${current_devices[@]}"; then
                # Start drivers and server
                if start_drivers; then
                    start_upsd
                    log "System reconfigured successfully"
                else
                    log "Failed to start drivers - will retry on next scan"
                fi
            else
                log "No devices detected - waiting for UPS connection"
            fi
            
            # Update previous devices
            previous_devices=("${current_devices[@]}")
        fi
        
        sleep "$SCAN_INTERVAL"
    done
}

# Signal handlers for graceful shutdown
cleanup() {
    log "Received shutdown signal, cleaning up..."
    stop_upsd
    stop_all_drivers
    exit 0
}

trap cleanup TERM INT

# Main execution
main() {
    # Prevent multiple instances with PID-based lock
    local LOCK_FILE="/var/run/nut/entrypoint.lock"
    local PID_FILE="/var/run/nut/entrypoint.pid"
    
    # Check if another instance is running
    if [[ -f "$PID_FILE" ]]; then
        local old_pid=$(cat "$PID_FILE" 2>/dev/null)
        if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
            echo "Another entrypoint instance is already running (PID: $old_pid)" >&2
            exit 1
        fi
    fi
    
    # Create lock and PID file
    mkdir -p "$(dirname "$LOCK_FILE")"
    echo $$ > "$PID_FILE"
    
    # Cleanup lock on exit
    trap 'rm -f "$LOCK_FILE" "$PID_FILE"; cleanup' TERM INT EXIT
    
    log "=== NUT Hotplug Entrypoint Started ==="
    log "Detected system: $(uname -a)"
    
    # Initialize configuration
    init_nut_config
    
    # Initial device scan and setup
    log "Performing initial device scan..."
    local initial_devices=()
    readarray -t initial_devices < <(scan_usb_devices)
    
    if update_ups_conf "${initial_devices[@]}"; then
        if start_drivers; then
            start_upsd
            log "Initial setup completed successfully"
        else
            log "Initial driver startup failed - will retry during monitoring"
        fi
    else
        log "No devices detected initially - entering monitoring mode"
    fi
    
    # Start monitoring loop
    monitor_usb_devices
}

# Run main function
main "$@"