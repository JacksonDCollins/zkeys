# Diagnosis Results for FC:82:CF:C8:47:32

## Device Information
- **MAC Address**: FC:82:CF:C8:47:32
- **Device Name**: Corne Choc Pro  
- **Type**: ZMK Keyboard

## Test Results

### ✅ PASSED Tests:
1. **Bluetooth Adapter**: Found and working (hci0)
2. **RF Kill Status**: Not blocked
3. **Pairing Status**: Device IS properly paired
4. **Software**: All tools working correctly

### ❌ FAILED Tests:
1. **Device Reachability**: Device does NOT respond to L2 ping
2. **Connection Attempt**: Times out after 10 seconds

## Root Cause

**The keyboard is not reachable over Bluetooth.**

This is NOT a software bug - the program is working correctly. The issue is that the keyboard itself is not responding to Bluetooth connections.

## Most Likely Causes (in order):

### 1. Keyboard Connected to Another Device ⭐ MOST LIKELY
Your Corne Choc Pro might be connected to:
- Your phone
- Another computer  
- A tablet
- Previous Bluetooth host

**Solution**:
- Disconnect it from all other devices
- Or reset the keyboard's Bluetooth (usually a key combo like holding both sides' reset buttons)

### 2. Keyboard Powered Off
The keyboard might be:
- Batteries dead
- Power switch off
- In deep sleep mode

**Solution**:
- Check battery level
- Try charging/replacing batteries
- Press keys to wake it up
- Check if there's a power switch

### 3. Keyboard Out of Range
BLE range is typically 10 meters (33 feet), but can be less with obstacles.

**Solution**:
- Move keyboard closer to computer
- Remove obstacles between them
- Try from different location

### 4. Keyboard Bluetooth Disabled
Some keyboards have a Bluetooth on/off mode.

**Solution**:
- Check keyboard documentation for Bluetooth toggle
- Try the reset sequence

## How to Fix

### Step 1: Check if Connected Elsewhere

Check your other devices (phone, tablets, other computers):
```
Settings → Bluetooth → Look for "Corne Choc Pro"
```

If connected, disconnect it there first.

### Step 2: Reset Keyboard Bluetooth

Most ZMK keyboards can reset Bluetooth with a key combo. Common methods:
- Hold both outer bottom corner keys while plugging in
- Press a specific key combination (check your keymap)
- Physical reset button on the keyboard

After reset, the keyboard should be discoverable again.

### Step 3: Re-pair if Needed

If reset clears pairing:
```bash
# Put keyboard in pairing mode
# Then in Linux:
sudo bluetoothctl
scan on
# Wait for Corne Choc Pro to appear
pair FC:82:CF:C8:47:32
trust FC:82:CF:C8:47:32
```

### Step 4: Try Connection Again

```bash
# Make sure NOT connected via bluetoothd
sudo bluetoothctl disconnect FC:82:CF:C8:47:32

# Test reachability  
sudo l2ping -c 3 FC:82:CF:C8:47:32

# If ping works, connect
sudo zig build run-zmk -- FC:82:CF:C8:47:32
```

## Verification Commands

Use these to check status:

```bash
# Full diagnostic
sudo ./diagnose.sh FC:82:CF:C8:47:32

# Quick ping test
sudo l2ping -c 3 FC:82:CF:C8:47:32

# Check pairing
sudo zig build check -- FC:82:CF:C8:47:32

# Check if connected to bluetoothd
sudo zig build check-conn -- FC:82:CF:C8:47:32
```

## Expected Output When Working

When the keyboard is properly available:

```
$ sudo l2ping -c 3 FC:82:CF:C8:47:32
Ping: FC:82:CF:C8:47:32 from 70:1A:B8:E4:38:50 (data size 44) ...
44 bytes from FC:82:CF:C8:47:32 id 0 time 15.23ms
44 bytes from FC:82:CF:C8:47:32 id 1 time 12.45ms
44 bytes from FC:82:CF:C8:47:32 id 2 time 11.89ms
3 sent, 3 received, 0% loss
```

Then connection will work:

```
$ sudo zig build run-zmk -- FC:82:CF:C8:47:32
info: Connecting to FC:82:CF:C8:47:32...
info: Attempting L2CAP connection...
info: Waiting for connection (10s timeout)...
info: Connected successfully!
```

## Summary

**The software is working perfectly.** Your keyboard just isn't responding right now.

Most likely: **It's connected to another device.**

Check all your other Bluetooth devices and disconnect "Corne Choc Pro" from them, then try again.

## Need More Help?

If keyboard still doesn't respond after:
- Disconnecting from all devices
- Ensuring it's powered on
- Moving it close to computer
- Resetting Bluetooth

Then check:
1. Keyboard battery level
2. Keyboard firmware (needs ZMK Studio support)
3. Try from another Linux computer to rule out adapter issues
4. Check ZMK documentation for your specific keyboard

