#!/bin/bash

# Smart NUT hotplug entrypoint with reliable device detection
# Only restarts when there are actual USB device changes

set -e

# Configuration
NUT_CONF="/opt/nut/etc/nut.conf"
UPS_CONF="/opt/nut/etc/ups.conf"
PID_DIR="/var/run/nut"
LOG_FILE="/var/log/nut/hotplug.log"
SCAN_INTERVAL=${SCAN_INTERVAL:-60}  # Much longer default interval
MAX_RETRIES=3

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Logging function
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg" >> "$LOG_FILE"
    echo "$msg" >&2
}

# Get USB device fingerprint (only UPS devices)
get_ups_fingerprint() {
    # Create a reliable fingerprint of connected UPS devices
    local fingerprint=""
    
    # Method 1: Try nut-scanner first (most reliable)
    if /opt/nut/bin/nut-scanner -U -q 2>/dev/null | grep -q "driver.*=.*usbhid-ups"; then
        fingerprint=$(lsusb | grep -E "(UPS|EcoFlow|APC|Tripp|CyberPower)" | sort)
        if [[ -n "$fingerprint" ]]; then
            echo "scanner:$fingerprint"
            return 0
        fi
    fi
    
    # Method 2: Fallback to lsusb HID devices that might be UPS
    fingerprint=$(lsusb | grep -E "(3746:ffff|UPS|Power)" | sort)
    if [[ -n "$fingerprint" ]]; then
        echo "lsusb:$fingerprint"
    else
        echo "none"
    fi
}

# Check if upsd is running
is_upsd_running() {
    pgrep -f "upsd.*-F" > /dev/null 2>&1
}

# Stop all services cleanly
stop_all_services() {
    log "Stopping all NUT services..."
    
    # Stop upsd first
    if is_upsd_running; then
        pkill -TERM -f "upsd.*-F" || true
        sleep 2
    fi
    
    # Stop drivers
    /opt/nut/sbin/upsdrvctl stop || true
    sleep 2
    
    # Cleanup any remaining processes
    pkill -KILL -f "usbhid-ups" || true
    pkill -KILL -f "upsd" || true
    
    # Clean up files
    find "$PID_DIR" -name "*.pid" -delete 2>/dev/null || true
    find "$PID_DIR" -name "usbhid-ups-*" -type s -delete 2>/dev/null || true
    
    sleep 2
}

# Create ups.conf for detected devices
create_ups_conf() {
    local fingerprint="$1"
    
    if [[ "$fingerprint" == "none" ]]; then
        # No UPS detected - create dummy config
        log "No UPS detected - creating placeholder config"
        cat > "$UPS_CONF" << 'EOF'
# No UPS devices currently connected
# Configuration maintained for compatibility

[my-ups]
    driver = dummy-ups
    port = /dev/null
    desc = "Waiting for UPS connection"
EOF
        return 1
    else
        # UPS detected - create working config
        log "Creating ups.conf for detected UPS"
        cat > "$UPS_CONF" << 'EOF'
# Auto-generated configuration for detected UPS
# Device detected via smart hotplug system

[my-ups]
    driver = usbhid-ups
    port = auto
    desc = "Auto-detected USB UPS"
    pollinterval = 2
EOF
        return 0
    fi
    
    chown nut:nut "$UPS_CONF"
}

# Start NUT services
start_nut_services() {
    local retry_count=0
    
    log "Starting NUT services..."
    
    # Try to start drivers
    while [[ $retry_count -lt $MAX_RETRIES ]]; do
        if /opt/nut/sbin/upsdrvctl -u root start 2>/dev/null; then
            log "UPS drivers started successfully"
            break
        else
            ((retry_count++))
            if [[ $retry_count -lt $MAX_RETRIES ]]; then
                log "Driver start attempt $retry_count failed, retrying..."
                sleep 5
            else
                log "Failed to start drivers after $MAX_RETRIES attempts"
                return 1
            fi
        fi
    done
    
    # Start upsd
    sleep 2
    /opt/nut/sbin/upsd -D -F &
    local upsd_pid=$!
    
    sleep 3
    if kill -0 $upsd_pid 2>/dev/null && is_upsd_running; then
        log "NUT services started successfully"
        return 0
    else
        log "Failed to start upsd"
        return 1
    fi
}

# Main execution with PID lock
main() {
    local PID_FILE="/var/run/nut/smart-hotplug.pid"
    
    # Simple PID lock
    if [[ -f "$PID_FILE" ]]; then
        local old_pid=$(cat "$PID_FILE" 2>/dev/null)
        if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
            log "Another hotplug instance already running (PID: $old_pid)"
            exit 1
        fi
    fi
    
    echo $$ > "$PID_FILE"
    trap 'rm -f "$PID_FILE"; stop_all_services; exit 0' TERM INT EXIT
    
    log "=== NUT Smart Hotplug Started ==="
    log "Scan interval: ${SCAN_INTERVAL}s"
    
    # Fix USB permissions
    chmod -R 666 /dev/bus/usb/*/* 2>/dev/null || true
    
    local current_fingerprint=""
    local previous_fingerprint="__initial__"
    
    # Initial setup
    current_fingerprint=$(get_ups_fingerprint)
    log "Initial device fingerprint: $current_fingerprint"
    
    if create_ups_conf "$current_fingerprint"; then
        start_nut_services
    else
        log "No UPS detected initially - waiting for device"
    fi
    
    previous_fingerprint="$current_fingerprint"
    
    # Main monitoring loop
    while true; do
        sleep "$SCAN_INTERVAL"
        
        current_fingerprint=$(get_ups_fingerprint)
        
        if [[ "$current_fingerprint" != "$previous_fingerprint" ]]; then
            log "USB device change detected!"
            log "Previous: $previous_fingerprint"
            log "Current:  $current_fingerprint"
            
            # Stop everything
            stop_all_services
            
            # Reconfigure and restart
            if create_ups_conf "$current_fingerprint"; then
                start_nut_services
                log "System reconfigured successfully"
            else
                log "No UPS detected - waiting for connection"
            fi
            
            previous_fingerprint="$current_fingerprint"
        fi
    done
}

# Run main function
main "$@"