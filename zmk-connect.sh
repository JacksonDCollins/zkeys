#!/bin/bash
# Practical workaround: Use keyboard via bluetoothd for ZMK Studio

MAC="${1:-FC:82:CF:C8:47:32}"

echo "═══════════════════════════════════════════════════════════════"
echo "  ZMK Studio Connection Helper"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Your keyboard is currently connected for typing."
echo "The direct L2CAP approach won't work while bluetoothd"
echo "has the connection."
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  CURRENT STATUS"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Check current connection
if bluetoothctl info "$MAC" 2>/dev/null | grep -q "Connected: yes"; then
    echo "✅ Keyboard is CONNECTED (can type)"
    echo ""
    echo "For ZMK Studio configuration, you have these options:"
    echo ""
    echo "Option 1: Use Web Browser (RECOMMENDED)"
    echo "  https://zmk.studio"
    echo "  - Works with Web Bluetooth API"
    echo "  - No disconnection needed"
    echo "  - Can configure while typing"
    echo ""
    echo "Option 2: USB Connection"
    echo "  - Plug in via USB cable"
    echo "  - Configure over USB"
    echo "  - Keep Bluetooth for typing"
    echo ""
    echo "Option 3: Disconnect & Use Our Tool (typing will stop)"
    read -p "  Try option 3 now? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        echo "Disconnecting keyboard..."
        bluetoothctl disconnect "$MAC"
        echo ""
        echo "Waiting 2 seconds for device to respond..."
        sleep 2
        echo ""
        echo "Attempting connection..."
        sudo ./zig-out/bin/zmk-example "$MAC"
        echo ""
        echo "Reconnecting for typing..."
        bluetoothctl connect "$MAC"
    fi
else
    echo "⚠️  Keyboard is NOT connected"
    echo ""
    echo "Starting connection..."
    bluetoothctl connect "$MAC"
fi
