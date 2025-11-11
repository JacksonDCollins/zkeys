# ZMK Studio Client - Quick Reference

## 🚀 Quick Start

```bash
# Build everything
zig build

# Run example (after pairing keyboard)
zig build run-zmk -- AA:BB:CC:DD:EE:FF
```

## 📖 Documentation Files

- **README.md** - Main documentation, API reference, quick start
- **ZMK_IMPLEMENTATION.md** - Detailed implementation guide
- **BLUETOOTH_COMMUNICATION_GUIDE.md** - Protocol and BLE details
- **IMPLEMENTATION_SUMMARY.txt** - What was implemented

## 🔧 Build Commands

```bash
# Generate protobuf code
zig build gen-proto

# Build all
zig build

# Run SDL3 app (original)
zig build run

# Run ZMK example
zig build run-zmk

# Run ZMK example with device address
zig build run-zmk -- AA:BB:CC:DD:EE:FF
```

## 📱 Pairing Your Keyboard

```bash
bluetoothctl
[bluetooth]# power on
[bluetooth]# scan on
# Wait for keyboard to appear...
[bluetooth]# scan off
[bluetooth]# pair AA:BB:CC:DD:EE:FF
[bluetooth]# trust AA:BB:CC:DD:EE:FF
[bluetooth]# connect AA:BB:CC:DD:EE:FF
[bluetooth]# exit
```

## 💻 Code Example

```zig
const zmk = @import("zmk_studio.zig");

// Create and connect
const client = try zmk.ZMKStudioClient.init(allocator);
defer client.deinit();
try client.connect("AA:BB:CC:DD:EE:FF");

// Get device info
const info = try client.getDeviceInfo();
std.log.info("Keyboard: {s}", .{info.name});

// Check lock state
const lock_state = try client.getLockState();
if (lock_state == .locked) try client.unlock();

// Get keymap
const keymap = try client.getKeymap();
for (keymap.layers.items) |layer| {
    std.log.info("Layer: {s}", .{layer.name});
}

// Modify key binding
const binding = zmk.keymap_pb.BehaviorBinding{
    .behavior_id = 1,
    .param1 = 0x04,  // 'A' key
    .param2 = 0,
};
try client.setLayerBinding(0, 10, binding);

// Save
try client.saveChanges();
```

## 🗂️ Project Structure

```
src/
├── zmk_studio.zig       # Main client library (576 lines)
├── zmk_example.zig      # Example program (140 lines)
├── linux_ble.zig        # BLE utilities (177 lines)
├── main.zig             # Original SDL3 app (194 lines)
└── proto/zmk/           # Generated protobuf code (3,529 lines)
    ├── studio.pb.zig
    ├── core.pb.zig
    ├── behaviors.pb.zig
    ├── keymap.pb.zig
    └── meta.pb.zig
```

## 📋 API Reference

### Client Lifecycle
- `ZMKStudioClient.init(allocator)` - Create client
- `client.deinit()` - Cleanup

### Connection
- `client.scanDevices(timeout_ms)` - Scan for devices
- `client.connect(address)` - Connect to keyboard
- `client.disconnect()` - Disconnect

### Device Info
- `client.getDeviceInfo()` - Get name, serial number
- `client.getLockState()` - Check lock state
- `client.unlock()` - Unlock keyboard

### Keymap Operations
- `client.getKeymap()` - Get full keymap
- `client.setLayerBinding(layer, pos, binding)` - Modify key
- `client.saveChanges()` - Persist changes

### Behaviors
- `client.listBehaviors()` - Get behavior IDs

## ⚠️ Important Notes

1. **BLE Implementation**: Currently uses placeholders - needs platform-specific BLE code
2. **Lock State**: Many operations require keyboard to be unlocked
3. **Save Changes**: Modifications are temporary until `saveChanges()` is called
4. **Request IDs**: Automatically tracked - no manual management needed

## 🔗 Protocol Details

- **Service UUID**: `00000000-0196-6107-c967-c5cfb1c2482a`
- **RPC Characteristic**: `00000001-0196-6107-c967-c5cfb1c2482a`
- **Encoding**: Protocol Buffers (proto3)
- **Transport**: BLE GATT notifications

## 🐛 Troubleshooting

**Cannot find keyboard**
```bash
# Check Bluetooth
systemctl status bluetooth
sudo systemctl restart bluetooth

# Verify pairing
bluetoothctl paired-devices
```

**Permission denied**
```bash
sudo usermod -a -G bluetooth $USER
# Log out and back in
```

**Build errors**
```bash
# Clean build
rm -rf .zig-cache zig-out
zig build gen-proto
zig build
```

## 📚 Learn More

- See README.md for full API documentation
- See ZMK_IMPLEMENTATION.md for BLE implementation guide
- See BLUETOOTH_COMMUNICATION_GUIDE.md for protocol details

## ✨ Features

✅ Full protobuf support
✅ Type-safe API
✅ Request/response matching
✅ Thread-safe operations
✅ Comprehensive error handling
✅ Working example code
⚠️ BLE layer needs implementation

## 🎯 Next Steps

To use with real hardware:
1. Implement BLE functions (see ZMK_IMPLEMENTATION.md)
2. Test with ZMK keyboard
3. Extend as needed

---
Built with Zig 0.15.2 | Total Code: 893 lines | Docs: 29KB
