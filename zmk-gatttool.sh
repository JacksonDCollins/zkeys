#!/bin/bash
# Simple wrapper to connect to ZMK keyboard using gatttool
# This works even if bluetoothd has the connection

set -e

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 MAC:ADDRESS"
    echo "Example: $0 FC:82:CF:C8:47:32"
    exit 1
fi

MAC="$1"

echo "═══════════════════════════════════════════════════════════════"
echo "  ZMK Studio via gatttool (Alternative Method)"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Device: $MAC"
echo ""

# Check if gatttool is available
if ! command -v gatttool &> /dev/null; then
    echo "❌ gatttool not found"
    echo ""
    echo "Install it with:"
    echo "  sudo apt-get install bluez-tools    # Debian/Ubuntu"
    echo "  sudo dnf install bluez-tools        # Fedora"
    echo "  sudo pacman -S bluez-utils          # Arch"
    exit 1
fi

echo "✅ gatttool found"
echo ""
echo "Connecting to $MAC..."
echo ""

# Try to connect and list characteristics
echo "Discovering GATT characteristics..."
gatttool -b "$MAC" --characteristics 2>&1 | grep -i "0000000" || {
    echo ""
    echo "❌ Failed to connect or no ZMK Studio service found"
    echo ""
    echo "Make sure:"
    echo "  1. Device is powered on"
    echo "  2. Device is in range"
    echo "  3. Device is not connected to another host"
    echo "  4. Try: sudo gatttool -b $MAC -I"
    echo ""
    exit 1
}

echo ""
echo "✅ Found ZMK Studio service!"
echo ""
echo "To interact manually, run:"
echo "  sudo gatttool -b $MAC -I"
echo ""
echo "Then:"
echo "  > connect"
echo "  > char-write-req 0x0010 <protobuf-hex-data>"
echo ""
