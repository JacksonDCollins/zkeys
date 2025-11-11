#!/bin/bash
# Comprehensive Bluetooth diagnostic tool

set -e

MAC="${1:-FC:82:CF:C8:47:32}"

echo "╔═══════════════════════════════════════════════════════════════════╗"
echo "║                                                                   ║"
echo "║         Bluetooth Device Diagnostic Tool                          ║"
echo "║                                                                   ║"
echo "╚═══════════════════════════════════════════════════════════════════╝"
echo ""
echo "Checking device: $MAC"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Not running as root"
    echo "Please run with sudo: sudo $0 $MAC"
    exit 1
fi

echo "✅ Running as root"
echo ""

# Check Bluetooth hardware
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. Checking Bluetooth Hardware"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -d /sys/class/bluetooth/hci0 ]; then
    echo "✅ Bluetooth adapter found (hci0)"
    
    # Check if powered
    if [ -f /sys/class/bluetooth/hci0/powered ]; then
        POWERED=$(cat /sys/class/bluetooth/hci0/powered)
        if [ "$POWERED" = "1" ]; then
            echo "✅ Adapter is powered on"
        else
            echo "❌ Adapter is powered OFF"
            echo "   Try: sudo rfkill unblock bluetooth"
            exit 1
        fi
    fi
else
    echo "❌ No Bluetooth adapter found"
    echo "   Make sure Bluetooth hardware is available"
    exit 1
fi

echo ""

# Check rfkill
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "2. Checking RF Kill Status"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if command -v rfkill &> /dev/null; then
    rfkill list bluetooth
    
    if rfkill list bluetooth | grep -q "Soft blocked: yes"; then
        echo "❌ Bluetooth is SOFT BLOCKED"
        echo "   Fix with: sudo rfkill unblock bluetooth"
        exit 1
    fi
    
    if rfkill list bluetooth | grep -q "Hard blocked: yes"; then
        echo "❌ Bluetooth is HARD BLOCKED (hardware switch)"
        echo "   Check physical Bluetooth switch or BIOS setting"
        exit 1
    fi
    
    echo "✅ Bluetooth is not blocked"
else
    echo "⚠️  rfkill command not found, skipping"
fi

echo ""

# Check pairing database
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "3. Checking Pairing Database"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

FOUND_DEVICE=false

if [ -d /var/lib/bluetooth ]; then
    for adapter in /var/lib/bluetooth/*; do
        if [ -d "$adapter/$MAC" ]; then
            echo "✅ Device IS paired"
            echo "   Location: $adapter/$MAC"
            
            if [ -f "$adapter/$MAC/info" ]; then
                NAME=$(grep "^Name=" "$adapter/$MAC/info" 2>/dev/null | cut -d= -f2)
                if [ -n "$NAME" ]; then
                    echo "   Device name: $NAME"
                fi
            fi
            
            FOUND_DEVICE=true
            break
        fi
    done
    
    if [ "$FOUND_DEVICE" = false ]; then
        echo "❌ Device is NOT paired"
        echo ""
        echo "   You need to pair the device first:"
        echo "   1. Put keyboard in pairing mode (usually hold a key combination)"
        echo "   2. Open System Settings → Bluetooth"
        echo "   3. Click on the keyboard when it appears"
        echo ""
        echo "   Or pair from command line (if available):"
        echo "   $ bluetoothctl"
        echo "   [bluetooth]# scan on"
        echo "   [bluetooth]# pair $MAC"
        echo "   [bluetooth]# trust $MAC"
        exit 1
    fi
else
    echo "⚠️  No pairing database found at /var/lib/bluetooth"
    echo "   This is unusual - bluetoothd may not be installed"
fi

echo ""

# Check connection status
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "4. Checking Connection Status"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

MAC_UNDERSCORE=$(echo "$MAC" | tr ':' '_' | tr '[:lower:]' '[:upper:]')
CONNECTED_FILE="/sys/class/bluetooth/hci0/dev_${MAC_UNDERSCORE}/connected"

if [ -f "$CONNECTED_FILE" ]; then
    CONNECTED=$(cat "$CONNECTED_FILE")
    if [ "$CONNECTED" = "1" ]; then
        echo "⚠️  Device IS connected via bluetoothd"
        echo ""
        echo "   This will BLOCK our direct L2CAP connection!"
        echo ""
        echo "   You need to disconnect it first:"
        echo "   $ bluetoothctl disconnect $MAC"
        echo ""
        echo "   Or stop bluetoothd temporarily:"
        echo "   $ sudo systemctl stop bluetooth"
        echo "   (remember to restart: sudo systemctl start bluetooth)"
        exit 1
    else
        echo "✅ Device is not connected via bluetoothd (good!)"
    fi
else
    echo "⚠️  Cannot determine connection status"
    echo "   Device may not be in range or powered on"
fi

echo ""

# Try to ping device
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "5. Testing Device Reachability"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if command -v l2ping &> /dev/null; then
    echo "Sending L2 ping to device..."
    if timeout 5 l2ping -c 1 "$MAC" &> /dev/null; then
        echo "✅ Device responded to L2 ping!"
        echo "   Device is reachable and powered on"
    else
        echo "❌ Device did NOT respond to L2 ping"
        echo ""
        echo "   Possible causes:"
        echo "   1. Device is powered OFF"
        echo "   2. Device is out of range"
        echo "   3. Device is connected to another device (phone, tablet, etc.)"
        echo "   4. Device's Bluetooth is disabled"
        echo ""
        echo "   Make sure:"
        echo "   • Keyboard is powered on"
        echo "   • Keyboard is within ~10 meters"
        echo "   • Keyboard is NOT connected to another device"
        echo "   • Try resetting the keyboard"
        exit 1
    fi
else
    echo "⚠️  l2ping not available, skipping reachability test"
fi

echo ""

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "✅ All checks passed!"
echo ""
echo "Your device should be ready to connect."
echo ""
echo "Try running:"
echo "  sudo zig build run-zmk -- $MAC"
echo ""
