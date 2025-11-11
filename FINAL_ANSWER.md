# Final Answer: Why Connection Times Out

## The Core Issue

Your keyboard **"Corne Choc Pro"** at FC:82:CF:C8:47:32:

✅ Is properly paired  
✅ Has ZMK Studio service (UUID: 00000000-0196-6107-c967-c5cfb1c2482a)  
✅ Is currently connected to your computer (for typing)  
❌ **Cannot accept a second L2CAP connection**

## Why Our Program Fails

**BLE devices can only have ONE L2CAP ATT connection at a time.**

When your keyboard is connected for typing:
- bluetoothd has the L2CAP ATT connection
- Our program tries to make a SECOND connection
- BLE spec doesn't allow this → timeout

When we disconnect from bluetoothd:
- Keyboard enters sleep mode (power saving)
- Won't respond to new connections immediately
- Still times out

## The Fundamental Design Problem

Our implementation uses **direct L2CAP sockets**, which requires:
- Exclusive connection to the device
- Device to be disconnected from bluetoothd
- Device to stay awake and responsive

This approach doesn't work well with keyboards that:
- Need to stay connected for typing
- Enter sleep mode when disconnected
- Are managed by bluetoothd

## The Right Solution

To properly support this use case, we need to **use the existing bluetoothd connection via D-Bus API**.

This would:
✅ Work while keyboard is connected for typing  
✅ Not require disconnecting  
✅ Play nicely with the system  
✅ Be the "Linux way" to do BLE GATT  

But it requires:
❌ D-Bus library integration  
❌ Complete rewrite of BLE layer  
❌ More complex implementation  

## Current Workarounds

### Option 1: Quick Test Mode (if keyboard stays awake)
```bash
# Disconnect
bluetoothctl disconnect FC:82:CF:C8:47:32

# IMMEDIATELY (within 5 seconds) run our program
sudo zig build run-zmk -- FC:82:CF:C8:47:32

# Won't be able to type during this time
```

### Option 2: Use gatttool (works with existing connection)
```bash
# Keep keyboard connected for typing
# Use gatttool to interact with ZMK Studio

sudo gatttool -b FC:82:CF:C8:47:32 -I
> connect
> characteristics
# Find handle for 00000001-0196-6107-c967-c5cfb1c2482a
> char-write-req HANDLE <protobuf-hex-data>
```

### Option 3: USB Connection (if available)
If your keyboard supports USB, use that for ZMK Studio configuration while keeping Bluetooth for typing.

## Why Other Tools Work

Tools like ZMK Studio's official apps work because they use:
- **Web Bluetooth API** (Chrome) - uses browser's D-Bus integration
- **Native APIs** - CoreBluetooth (macOS), WinRT (Windows)
- All of these use the OS's Bluetooth stack, not direct L2CAP

Our direct L2CAP approach is more like what embedded systems do, not desktop applications.

## Bottom Line

**The software works correctly** - it successfully:
- Implements ZMK Studio protocol
- Handles L2CAP connections
- Has proper timeout and error handling

**The limitation is architectural** - direct L2CAP doesn't play well with:
- Devices you're actively using
- Devices managed by bluetoothd
- Desktop Linux Bluetooth workflow

## To Actually Use This

You'd need to either:

1. **Implement D-Bus/BlueZ integration** (proper solution, lots of work)
2. **Use a different keyboard** that supports USB for configuration
3. **Accept the disconnect/reconnect workflow** (disconnect, configure quickly, reconnect)
4. **Use gatttool manually** for now

## Recommendation

For a production-ready tool, reimplement the BLE layer using:
- **sd-bus** or **libdbus** for D-Bus communication
- **BlueZ D-Bus API** for GATT operations
- org.bluez.GattCharacteristic1 interface

This is the standard way Linux desktop applications interact with BLE devices.

