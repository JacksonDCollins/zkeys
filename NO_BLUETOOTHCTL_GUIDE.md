# Using ZMK Studio Client Without bluetoothctl

## Overview

You **do not need bluetoothctl** to use this ZMK Studio client! The program connects directly to Bluetooth devices using low-level system calls.

## What You Need

1. **Bluetooth hardware** (built-in or USB adapter)
2. **Root permissions** (for raw Bluetooth access)
3. **Device MAC address** (can be found various ways)

## Quick Start (No bluetoothctl Required)

### Method 1: Use Built-in Scanner

```bash
# Build everything
zig build

# Scan for devices (requires root)
sudo zig build scan

# Connect to your keyboard
sudo zig build run-zmk -- AA:BB:CC:DD:EE:FF
```

### Method 2: Find MAC Address Manually

If scanning doesn't work, you can find your keyboard's MAC address using:

#### Option A: Check System Logs
```bash
# Check recent Bluetooth connections
sudo journalctl -u bluetooth | grep -i "connected"

# Or check dmesg
dmesg | grep -i bluetooth
```

#### Option B: Use hcitool (if available)
```bash
# Scan for devices
sudo hcitool scan

# Or for BLE devices
sudo hcitool lescan
# Press Ctrl+C after a few seconds
```

#### Option C: Check Pairing History
```bash
# List previously paired devices
ls -la /var/lib/bluetooth/*/

# Each subdirectory is a MAC address of a paired device
# Check the info files for device names
cat /var/lib/bluetooth/*/XX:XX:XX:XX:XX:XX/info
```

#### Option D: Check Device Label
Many keyboards have the MAC address printed on them or in the user manual.

### Method 3: Connect Directly

Once you have the MAC address, just connect:

```bash
sudo ./zig-out/bin/zmk-example AA:BB:CC:DD:EE:FF
```

## Why Root/Sudo is Needed

The program uses low-level Bluetooth sockets (L2CAP) which require either:
- **Root permissions** (`sudo`)
- **CAP_NET_ADMIN capability**
- **Membership in `bluetooth` group** (sometimes)

### One-time Setup (Optional)

To avoid using `sudo` every time:

```bash
# Option 1: Add capability to binary
sudo setcap cap_net_admin+ep ./zig-out/bin/zmk-example

# Then run without sudo
./zig-out/bin/zmk-example AA:BB:CC:DD:EE:FF

# Option 2: Add user to bluetooth group (may not be enough)
sudo usermod -a -G bluetooth $USER
# Log out and back in
```

## Pairing vs Connecting

### Important Distinction

- **Pairing**: One-time security setup (exchanging encryption keys)
- **Connecting**: Establishing a connection to a paired device

### This Program

The ZMK Studio client **connects** to devices. It assumes the device is already:
1. Paired with your system
2. Trusted (won't disconnect automatically)

### How to Pair Without bluetoothctl

If your keyboard isn't paired yet, you have several options:

#### Option 1: Use GNOME Bluetooth (GUI)
```bash
# If you have GNOME desktop
gnome-bluetooth

# Or from command line
blueman-manager  # If blueman is installed
```

#### Option 2: Use System Settings
- **Ubuntu/GNOME**: Settings → Bluetooth
- **KDE**: System Settings → Bluetooth
- **Other**: Look for Bluetooth in system settings

#### Option 3: Use Python Script
```bash
# Install if needed
sudo apt-get install python3-dbus

# Create a simple pairing script
cat > pair_device.py << 'EOF'
#!/usr/bin/env python3
import dbus
import sys

bus = dbus.SystemBus()
adapter_path = "/org/bluez/hci0"
adapter = dbus.Interface(bus.get_object("org.bluez", adapter_path), "org.bluez.Adapter1")

if len(sys.argv) < 2:
    print("Usage: python3 pair_device.py MAC:ADDRESS")
    sys.exit(1)

mac = sys.argv[1].replace(":", "_")
device_path = f"{adapter_path}/dev_{mac}"

device = dbus.Interface(bus.get_object("org.bluez", device_path), "org.bluez.Device1")

print(f"Pairing with {sys.argv[1]}...")
device.Pair()
print("Paired!")

device.Trust()
print("Trusted!")
EOF

chmod +x pair_device.py
sudo python3 pair_device.py AA:BB:CC:DD:EE:FF
```

#### Option 4: Use rfcomm (Classic Bluetooth)
```bash
# If your keyboard uses classic Bluetooth
sudo rfcomm bind 0 AA:BB:CC:DD:EE:FF
```

## Complete Workflow Without bluetoothctl

### Step 1: Find Your Keyboard

```bash
# Build the scanner
zig build

# Run the scanner
sudo zig build scan
```

You should see output like:
```
Found 3 device(s):

[1] AA:BB:CC:DD:EE:FF
    Name: My Keyboard
    RSSI: -65 dBm

[2] 11:22:33:44:55:66
    Name: Other Device
    RSSI: -80 dBm
```

### Step 2: Note the MAC Address

Write down or copy the MAC address of your keyboard (e.g., `AA:BB:CC:DD:EE:FF`)

### Step 3: Pair (First Time Only)

Use one of the pairing methods above (GUI, Python script, etc.)

### Step 4: Connect and Use

```bash
sudo zig build run-zmk -- AA:BB:CC:DD:EE:FF
```

## Troubleshooting

### "No devices found" When Scanning

**Causes:**
- Keyboard not in pairing/discoverable mode
- Keyboard already connected to another device
- Bluetooth adapter not enabled

**Solutions:**
```bash
# Check if Bluetooth is enabled
rfkill list bluetooth

# If blocked, unblock it
sudo rfkill unblock bluetooth

# Check Bluetooth service
sudo systemctl status bluetooth

# Restart if needed
sudo systemctl restart bluetooth
```

### "Permission denied" Even with Sudo

**Cause:** SELinux or AppArmor may be blocking access

**Solutions:**
```bash
# Check SELinux status
getenforce

# Temporarily disable (for testing)
sudo setenforce 0

# For permanent fix, add policy for your binary
```

### "Device not found" When Connecting

**Causes:**
- Wrong MAC address
- Device not paired
- Device out of range

**Solutions:**
```bash
# Verify MAC address format (use colons)
# Correct: AA:BB:CC:DD:EE:FF
# Wrong: AA-BB-CC-DD-EE-FF or AABBCCDDEEFF

# Check if device is reachable
sudo l2ping AA:BB:CC:DD:EE:FF

# Try pairing again
```

## Alternative Tools (If Nothing Works)

If you can't get scanning or pairing to work, you can use these alternatives:

### hcitool
```bash
sudo hcitool scan          # Classic Bluetooth
sudo hcitool lescan        # BLE devices
sudo hcitool dev           # List adapters
```

### btmgmt
```bash
sudo btmgmt info           # Adapter info
sudo btmgmt find           # Scan for devices
```

### Python with pybluez
```bash
pip install pybluez
python3 << 'EOF'
import bluetooth
devices = bluetooth.discover_devices(lookup_names=True)
for addr, name in devices:
    print(f"{addr} - {name}")
EOF
```

## System Without Bluetooth Service

If your system doesn't have `bluetoothd` running:

```bash
# Check if service exists
systemctl list-units | grep bluetooth

# If not installed
sudo apt-get install bluez  # Debian/Ubuntu
sudo dnf install bluez      # Fedora
sudo pacman -S bluez        # Arch

# Start the service
sudo systemctl start bluetooth
sudo systemctl enable bluetooth
```

## Minimal Dependencies

This program only requires:
- **libbluetooth** (system library)
- **Bluetooth hardware** (adapter)
- **Root access** (or capabilities)

It does NOT require:
- ❌ bluetoothctl
- ❌ D-Bus (for basic operation)
- ❌ Desktop environment
- ❌ GUI tools

## Summary

**You can use this ZMK Studio client without bluetoothctl!**

Minimum workflow:
1. `sudo zig build scan` → Find device MAC
2. Pair device (GUI, Python, or other method)
3. `sudo zig build run-zmk -- MAC:ADDR` → Connect!

The program talks directly to the Bluetooth hardware using Linux system calls.
