# Quick Update: bluetoothctl is Optional!

## TL;DR

You **do NOT need bluetoothctl** to use this program!

### Quick Start (Without bluetoothctl)

```bash
# 1. Build
zig build

# 2. Scan for your keyboard (requires sudo)
sudo zig build scan

# 3. Connect using the MAC address found
sudo zig build run-zmk -- AA:BB:CC:DD:EE:FF
```

## What Changed

Added a built-in device scanner (`scan-devices`) that finds Bluetooth devices without requiring `bluetoothctl`.

## New Build Commands

- `zig build scan` - Scan for Bluetooth devices
- `zig build run-zmk -- MAC:ADDR` - Connect to keyboard

## How to Find Your Keyboard

### Option 1: Use Built-in Scanner
```bash
sudo zig build scan
```

### Option 2: Check System Logs
```bash
sudo journalctl -u bluetooth | grep -i connected
```

### Option 3: Use hcitool (if available)
```bash
sudo hcitool scan
```

### Option 4: Check Device Manually
MAC address may be printed on your keyboard or in its manual.

## Pairing

The device should still be paired with your system first. You can use:
- System Settings → Bluetooth (GUI)
- GNOME Bluetooth / Blueman
- Python script (see NO_BLUETOOTHCTL_GUIDE.md)

## Complete Documentation

See `NO_BLUETOOTHCTL_GUIDE.md` for detailed instructions on using the program without bluetoothctl.

## Why Sudo?

The program uses low-level Bluetooth sockets that require root permissions for security. This is normal for direct Bluetooth access.

---

**The program works independently of bluetoothctl!**

It communicates directly with the Bluetooth hardware using system calls.
