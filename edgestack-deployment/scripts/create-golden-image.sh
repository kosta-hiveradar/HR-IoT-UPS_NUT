#!/bin/bash

###############################################################################
# HiveRadar Edge Data Center - Golden Image Creation Script
###############################################################################
# Purpose: Create a customized Ubuntu Server image for Raspberry Pi
# Usage: ./create-golden-image.sh [output-filename]
# Requirements: sudo access, loop device support, ~10GB free space
###############################################################################

set -euo pipefail

# Configuration
UBUNTU_VERSION="24.04.2"
UBUNTU_IMAGE_URL="https://cdimage.ubuntu.com/releases/24.04/release/ubuntu-24.04.2-preinstalled-server-arm64+raspi.img.xz"
OUTPUT_DIR="./images"
TEMPLATE_DIR="../templates"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

check_requirements() {
    log "Checking requirements..."

    # Check if running as root or with sudo
    if [ "$EUID" -ne 0 ]; then
        error "This script must be run with sudo"
        exit 1
    fi

    # Check required commands
    local required_cmds=("curl" "xz" "losetup" "mount" "umount" "dd" "gzip")
    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            error "Required command not found: $cmd"
            error "Install with: sudo apt install curl xz-utils mount util-linux gzip"
            exit 1
        fi
    done

    # Check disk space (need at least 10GB)
    local available_space=$(df -BG "$OUTPUT_DIR" 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ -z "$available_space" ] || [ "$available_space" -lt 10 ]; then
        warn "Less than 10GB free space available. This might not be enough."
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi

    log "✓ All requirements met"
}

download_ubuntu_image() {
    local image_file="$OUTPUT_DIR/ubuntu-$UBUNTU_VERSION-base.img.xz"

    if [ -f "$image_file" ]; then
        log "Ubuntu image already downloaded: $image_file"
        read -p "Re-download? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "$image_file"
            return
        fi
    fi

    log "Downloading Ubuntu Server $UBUNTU_VERSION ARM64..."
    log "URL: $UBUNTU_IMAGE_URL"

    mkdir -p "$OUTPUT_DIR"

    if ! curl -L -o "$image_file" "$UBUNTU_IMAGE_URL"; then
        error "Failed to download Ubuntu image"
        exit 1
    fi

    log "✓ Download complete: $image_file"
    echo "$image_file"
}

extract_image() {
    local compressed_image="$1"
    local extracted_image="${compressed_image%.xz}"

    if [ -f "$extracted_image" ]; then
        log "Extracted image already exists: $extracted_image"
        read -p "Re-extract? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "$extracted_image"
            return
        fi
        rm "$extracted_image"
    fi

    log "Extracting image..."
    if ! xz -d -k "$compressed_image"; then
        error "Failed to extract image"
        exit 1
    fi

    log "✓ Extraction complete: $extracted_image"
    echo "$extracted_image"
}

customize_image() {
    local base_image="$1"
    local output_image="$2"

    log "Creating working copy..."
    cp "$base_image" "$output_image"

    log "Setting up loop device..."
    local loop_device=$(losetup -f --show -P "$output_image")

    if [ -z "$loop_device" ]; then
        error "Failed to create loop device"
        exit 1
    fi

    log "Loop device: $loop_device"

    # Wait for partition device nodes to appear
    sleep 2
    partprobe "$loop_device" 2>/dev/null || true
    sleep 1

    # Find the boot and root partitions
    local boot_partition="${loop_device}p1"
    local root_partition="${loop_device}p2"

    if [ ! -b "$boot_partition" ] || [ ! -b "$root_partition" ]; then
        error "Partition devices not found"
        error "Expected: $boot_partition and $root_partition"
        losetup -d "$loop_device"
        exit 1
    fi

    log "Boot partition: $boot_partition"
    log "Root partition: $root_partition"

    # Create mount points
    local boot_mount="/mnt/hiveradar-boot-$$"
    local root_mount="/mnt/hiveradar-root-$$"
    mkdir -p "$boot_mount" "$root_mount"

    # Cleanup function
    cleanup_mounts() {
        log "Cleaning up mounts..."
        umount "$boot_mount" 2>/dev/null || true
        umount "$root_mount" 2>/dev/null || true
        rmdir "$boot_mount" "$root_mount" 2>/dev/null || true
        losetup -d "$loop_device" 2>/dev/null || true
    }
    trap cleanup_mounts EXIT

    # Mount partitions
    log "Mounting boot partition..."
    if ! mount "$boot_partition" "$boot_mount"; then
        error "Failed to mount boot partition"
        exit 1
    fi

    log "Mounting root partition..."
    if ! mount "$root_partition" "$root_mount"; then
        error "Failed to mount root partition"
        exit 1
    fi

    # Customize cloud-init configuration
    log "Customizing cloud-init configuration..."

    if [ -f "$TEMPLATE_DIR/cloud-init-user-data.yaml" ]; then
        cp "$TEMPLATE_DIR/cloud-init-user-data.yaml" "$boot_mount/user-data"
        log "✓ Installed cloud-init user-data"
    else
        warn "cloud-init-user-data.yaml not found in templates"
    fi

    # Customize Raspberry Pi config
    log "Customizing Raspberry Pi config.txt..."

    if [ -f "$TEMPLATE_DIR/config.txt" ]; then
        # Backup original
        cp "$boot_mount/config.txt" "$boot_mount/config.txt.original"

        # Install our config
        cp "$TEMPLATE_DIR/config.txt" "$boot_mount/config.txt"
        log "✓ Installed custom config.txt (original backed up)"
    else
        warn "config.txt not found in templates"
    fi

    # Disable WiFi/Bluetooth in cmdline if not already done
    log "Checking cmdline.txt..."
    if [ -f "$boot_mount/cmdline.txt" ]; then
        # Add USB power management disable
        if ! grep -q "usbcore.autosuspend=-1" "$boot_mount/cmdline.txt"; then
            # Add to end of line (cmdline.txt is single line)
            sed -i 's/$/ usbcore.autosuspend=-1/' "$boot_mount/cmdline.txt"
            log "✓ Added USB power management settings to cmdline.txt"
        fi
    fi

    # Optional: Pre-install SSH keys (if you want to embed them in the image)
    # This is in addition to cloud-init - provides fallback access
    # Uncomment if needed:
    #
    # if [ -f "$root_mount/root/.ssh/authorized_keys" ]; then
    #     cat "$TEMPLATE_DIR/deployment-keys.pub" >> "$root_mount/root/.ssh/authorized_keys"
    #     log "✓ Added deployment SSH keys"
    # fi

    # Set image metadata
    log "Setting image metadata..."
    cat > "$root_mount/etc/hiveradar-image-info" << EOF
HiveRadar Edge Data Center Image
Build Date: $(date -Iseconds)
Base Image: Ubuntu Server $UBUNTU_VERSION ARM64
Image Version: 1.0
Customizations:
  - Cloud-init with HiveRadar provisioning
  - WiFi and Bluetooth disabled
  - Security hardened
  - Docker pre-configured
  - Portainer Edge Agent ready
EOF

    log "✓ Image customization complete"

    # Unmount
    cleanup_mounts
    trap - EXIT
}

compress_image() {
    local image_file="$1"
    local compressed_file="${image_file}.gz"

    if [ -f "$compressed_file" ]; then
        warn "Compressed image already exists: $compressed_file"
        read -p "Overwrite? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "$compressed_file"
            return
        fi
        rm "$compressed_file"
    fi

    log "Compressing image (this may take several minutes)..."

    if ! gzip -9 -c "$image_file" > "$compressed_file"; then
        error "Failed to compress image"
        exit 1
    fi

    log "✓ Compression complete: $compressed_file"

    # Calculate checksums
    log "Calculating checksums..."
    sha256sum "$compressed_file" > "$compressed_file.sha256"
    md5sum "$compressed_file" > "$compressed_file.md5"

    log "✓ Checksums created"
    echo "$compressed_file"
}

main() {
    local output_filename="${1:-hiveradar-edc-$(date +%Y%m%d).img}"

    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  HiveRadar Edge Data Center - Golden Image Creation         ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""

    check_requirements

    # Download base image
    local compressed_image=$(download_ubuntu_image)

    # Extract image
    local base_image=$(extract_image "$compressed_image")

    # Customize image
    local custom_image="$OUTPUT_DIR/$output_filename"
    customize_image "$base_image" "$custom_image"

    # Compress final image
    local final_image=$(compress_image "$custom_image")

    # Cleanup uncompressed image
    log "Cleaning up..."
    rm "$custom_image"

    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  ✓ Golden Image Created Successfully!                       ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Final image: $final_image"
    echo "Size: $(du -h "$final_image" | cut -f1)"
    echo ""
    echo "SHA256: $(cat "$final_image.sha256")"
    echo "MD5:    $(cat "$final_image.md5")"
    echo ""
    echo "Next steps:"
    echo "  1. Flash to SD card:"
    echo "     gunzip -c $final_image | sudo dd of=/dev/sdX bs=4M status=progress"
    echo ""
    echo "  2. Or use Raspberry Pi Imager / Balena Etcher"
    echo ""
    echo "  3. Before first boot, you may want to:"
    echo "     - Mount boot partition and edit user-data to add SSH keys"
    echo "     - Verify config.txt settings"
    echo ""
    echo "  4. During manufacturing:"
    echo "     - Write serial number to /opt/hiveradar/serial.txt"
    echo "     - Or use scripts/write-serial-number.sh"
    echo ""
}

# Run main function
main "$@"
