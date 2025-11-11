# Troubleshooting: Connection Timeout

## Problem: Device Times Out Even Though It's Paired

If you're getting a connection timeout even though the device is paired, it's likely because **bluetoothd (the Bluetooth daemon) already has a connection to your device**, which blocks our direct L2CAP connection.

### Quick Diagnosis

Run these commands to understand what's happening:

```bash
# Check if device is paired
sudo zig build check -- FC:82:CF:C8:47:32

# Check if device is connected via bluetoothd
sudo zig build check-conn -- FC:82:CF:C8:47:32
```

### Solution 1: Disconnect from bluetoothd First (Recommended)

```bash
# Disconnect the device from bluetoothd
sudo bluetoothctl disconnect FC:82:CF:C8:47:32

# Now try our program
sudo zig build run-zmk -- FC:82:CF:C8:47:32
```

### Solution 2: Use gatttool (Works with existing connections)

If you want to use the existing bluetoothd connection:

```bash
# Install gatttool if needed
sudo apt-get install bluez-tools  # Debian/Ubuntu

# Use our helper script
./zmk-gatttool.sh FC:82:CF:C8:47:32

# Or manually
sudo gatttool -b FC:82:CF:C8:47:32 -I
> connect
> characteristics
# Look for handle of 00000001-0196-6107-c967-c5cfb1c2482a
> char-write-req 0x0010 <protobuf-hex>
```

### Solution 3: Stop bluetoothd Temporarily

```bash
# Stop the Bluetooth service
sudo systemctl stop bluetooth

# Now try our program
sudo zig build run-zmk -- FC:82:CF:C8:47:32

# Don't forget to restart it later
sudo systemctl start bluetooth
```

## Why This Happens

**Bluetooth LE devices can only have ONE active L2CAP ATT connection at a time.**

When you "connect" to a device through your system's Bluetooth settings or bluetoothctl:
- bluetoothd creates an L2CAP ATT connection
- This connection stays active
- Our program can't create a second connection
- Connection attempt times out

## The Root Cause

There are two ways to communicate with BLE devices on Linux:

1. **Direct L2CAP Sockets** (what our program tries to do)
   - Low-level, direct access
   - Fast and efficient
   - Requires exclusive connection
   - **Fails if bluetoothd is already connected**

2. **Through bluetoothd via D-Bus** (standard Linux approach)
   - Uses existing connection
   - Works alongside bluetoothd
   - More complex to implement
   - **Would work even if device is "connected"**

Our current implementation uses method #1 (direct L2CAP), which is why it conflicts with bluetoothd.

## Long-term Solutions

### Option A: Use D-Bus Instead of Direct L2CAP

We could rewrite the BLE layer to communicate through bluetoothd via D-Bus. This would:
- ✅ Work even when device is "connected"
- ✅ Play nicely with system Bluetooth
- ✅ Not require disconnecting
- ❌ More complex implementation
- ❌ Requires D-Bus library

### Option B: Hybrid Approach

Keep current approach but add detection:
- Check if device is already connected via bluetoothd
- If yes: use D-Bus to communicate
- If no: use direct L2CAP (faster)

## Immediate Workaround

For now, just disconnect the device from bluetoothd before using our program:

```bash
# One-time setup script
cat > ~/connect-zmk.sh << 'SCRIPT'
#!/bin/bash
MAC="$1"
sudo bluetoothctl disconnect "$MAC" 2>/dev/null
sleep 1
sudo zig build run-zmk -- "$MAC"
SCRIPT

chmod +x ~/connect-zmk.sh

# Use it
~/connect-zmk.sh FC:82:CF:C8:47:32
```

## Detailed Steps for Your Device

### Step 1: Check Current Status

```bash
sudo zig build check-conn -- FC:82:CF:C8:47:32
```

If it says "Device is CONNECTED via bluetoothd", that's the problem!

### Step 2: Disconnect

```bash
sudo bluetoothctl disconnect FC:82:CF:C8:47:32
```

You should see: `Successful disconnected`

### Step 3: Connect with Our Program

```bash
sudo zig build run-zmk -- FC:82:CF:C8:47:32
```

Now it should work!

## Alternative: Keep Device Connected to bluetoothd

If you want to keep the device connected to bluetoothd (e.g., for other apps), use gatttool:

```bash
# This works WITH bluetoothd connection
./zmk-gatttool.sh FC:82:CF:C8:47:32
```

## Understanding the Connection State

Your Bluetooth device can be in several states:

1. **Paired but not connected**
   - Device is in pairing database
   - No active connection
   - ✅ Our program works

2. **Paired and connected via bluetoothd**
   - Device shows as "connected" in Bluetooth settings
   - bluetoothd has active L2CAP connection
   - ❌ Our program times out (can't make second connection)

3. **Paired and connected via our program**
   - Device may not show as "connected" in settings
   - Our program has exclusive L2CAP connection
   - ✅ ZMK Studio works

4. **Not paired**
   - Device not in pairing database
   - ❌ Connection fails immediately with "permission denied"

## Quick Reference

```bash
# Is it paired?
sudo zig build check -- MAC:ADDR

# Is it connected via bluetoothd?
sudo zig build check-conn -- MAC:ADDR

# Disconnect from bluetoothd
sudo bluetoothctl disconnect MAC:ADDR

# Connect with our program
sudo zig build run-zmk -- MAC:ADDR

# Or use gatttool if device must stay connected
./zmk-gatttool.sh MAC:ADDR
```

## Debug Commands

```bash
# See all paired devices
bluetoothctl paired-devices

# See connected devices
bluetoothctl devices Connected

# Check connection in sysfs
ls -la /sys/class/bluetooth/hci0/

# Check specific device connection status
cat /sys/class/bluetooth/hci0/dev_FC_82_CF_C8_47_32/connected
# 1 = connected, 0 = not connected

# Monitor Bluetooth events
sudo btmon
```

## Future Implementation Note

To properly support this scenario, we should implement D-Bus communication with bluetoothd. This would require:

1. D-Bus library for Zig (or C bindings)
2. BlueZ D-Bus API implementation
3. GATT operations via org.bluez.GattCharacteristic1
4. Notification subscriptions via PropertiesChanged signal

This is a significant undertaking but would make the program more user-friendly.
