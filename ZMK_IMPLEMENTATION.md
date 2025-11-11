# ZMK Studio Bluetooth Communication (Zig Implementation)

This project implements a Zig client for communicating with ZMK keyboards over Bluetooth using the ZMK Studio protocol.

## Project Structure

```
src/
├── main.zig              # Main SDL3 application (original)
├── zmk_studio.zig        # ZMK Studio client library
├── zmk_example.zig       # Example program demonstrating ZMK communication
├── linux_ble.zig         # Linux BLE helper utilities
└── proto/
    └── zmk/              # Generated protobuf Zig code
        ├── studio.pb.zig
        ├── core.pb.zig
        ├── behaviors.pb.zig
        ├── keymap.pb.zig
        └── meta.pb.zig
```

## Features

The ZMK Studio client (`zmk_studio.zig`) provides:

- **Device Discovery**: Scan for ZMK keyboards
- **Connection Management**: Connect/disconnect via Bluetooth
- **Device Information**: Query keyboard name, serial number
- **Lock State Management**: Check and unlock keyboard
- **Keymap Operations**:
  - Get current keymap configuration
  - Modify key bindings
  - Save changes to keyboard
- **Behavior Queries**: List available keyboard behaviors

## Building

### Prerequisites

1. **Zig** (version 0.11.0 or later)
2. **Bluetooth tools** (Linux):
   ```bash
   sudo apt-get install bluez bluez-tools
   ```

### Generate Protocol Buffer Code

```bash
zig build gen-proto
```

This generates Zig code from the protobuf definitions in `src/proto/zmk/`.

### Build All

```bash
zig build
```

### Build and Run Main App

```bash
zig build run
```

### Build and Run ZMK Example

```bash
zig build run-zmk
```

Or with a specific device address:

```bash
zig build run-zmk -- XX:XX:XX:XX:XX:XX
```

## Usage

### Quick Start

1. **Pair your ZMK keyboard** using `bluetoothctl`:

```bash
bluetoothctl
[bluetooth]# power on
[bluetooth]# scan on
# Wait for your keyboard to appear
[bluetooth]# scan off
[bluetooth]# pair XX:XX:XX:XX:XX:XX
[bluetooth]# trust XX:XX:XX:XX:XX:XX
[bluetooth]# connect XX:XX:XX:XX:XX:XX
[bluetooth]# exit
```

2. **Run the example**:

```bash
zig build run-zmk -- XX:XX:XX:XX:XX:XX
```

### Using the Library

```zig
const std = @import("std");
const zmk = @import("zmk_studio.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create client
    const client = try zmk.ZMKStudioClient.init(allocator);
    defer client.deinit();

    // Connect to keyboard
    try client.connect("XX:XX:XX:XX:XX:XX");
    defer client.disconnect() catch {};

    // Get device info
    const info = try client.getDeviceInfo();
    std.log.info("Keyboard: {s}", .{info.name});

    // Check lock state
    const lock_state = try client.getLockState();
    if (lock_state == .locked) {
        try client.unlock();
    }

    // Get keymap
    const keymap = try client.getKeymap();
    std.log.info("Layers: {d}", .{keymap.layers.len});

    // Modify a key binding
    const binding = zmk.keymap_pb.BehaviorBinding{
        .behavior_id = 1,    // Key press behavior
        .param1 = 0x04,      // HID usage for 'A' key
        .param2 = 0,
    };
    try client.setLayerBinding(0, 10, binding);

    // Save changes
    try client.saveChanges();
}
```

## API Reference

### ZMKStudioClient

```zig
pub const ZMKStudioClient = struct {
    pub fn init(allocator: std.mem.Allocator) !*Self;
    pub fn deinit(self: *Self) void;
    
    pub fn scanDevices(self: *Self, timeout_ms: u32) ![]DeviceInfo;
    pub fn connect(self: *Self, device_address: []const u8) !void;
    pub fn disconnect(self: *Self) !void;
    
    pub fn getDeviceInfo(self: *Self) !DeviceInfo;
    pub fn getLockState(self: *Self) !LockState;
    pub fn unlock(self: *Self) !void;
    
    pub fn getKeymap(self: *Self) !keymap_pb.Keymap;
    pub fn listBehaviors(self: *Self) ![]u32;
    pub fn setLayerBinding(
        self: *Self,
        layer_id: u32,
        key_position: i32,
        binding: keymap_pb.BehaviorBinding,
    ) !void;
    pub fn saveChanges(self: *Self) !void;
};
```

### Types

```zig
pub const DeviceInfo = struct {
    name: []const u8,
    serial_number: []const u8,
    address: []const u8,
};

pub const LockState = enum {
    locked,
    unlocked,
};
```

## Protocol Details

### ZMK Studio Protocol

ZMK Studio uses Protocol Buffers over Bluetooth LE GATT for communication:

- **Service UUID**: `00000000-0196-6107-c967-c5cfb1c2482a`
- **RPC Characteristic UUID**: `00000001-0196-6107-c967-c5cfb1c2482a`

### Message Flow

1. Client encodes a `Request` message with unique `request_id`
2. Client writes encoded bytes to GATT characteristic
3. Keyboard processes request
4. Keyboard sends `Response` message via GATT notification
5. Client matches response by `request_id`

### Request Types

- **Core**: Device info, lock state, settings reset
- **Behaviors**: List and query keyboard behaviors
- **Keymap**: Get/modify layers, bindings, save changes

## Implementation Status

### ✅ Implemented

- Protocol Buffer integration
- Request/response handling with request ID tracking
- High-level API for all ZMK Studio operations
- Example program demonstrating usage

### ⚠️ Partial Implementation

- **BLE Communication**: Currently uses placeholders
  - Scanning, connecting, and GATT operations need platform-specific implementation
  - See `linux_ble.zig` for implementation notes

### Platform-Specific BLE Implementation

The current implementation provides a framework but requires actual BLE integration.

#### Linux Options

**Option 1: D-Bus + BlueZ** (Recommended)
```zig
// Use D-Bus to communicate with BlueZ daemon
// Service: org.bluez
// Interfaces: Device1, GattCharacteristic1, etc.
```

**Option 2: gatttool** (Simple but deprecated)
```bash
# Read characteristic
gatttool -b XX:XX:XX:XX:XX:XX --char-read -u <uuid>

# Write characteristic  
gatttool -b XX:XX:XX:XX:XX:XX --char-write-req -u <uuid> -n <hex-data>
```

**Option 3: C Library Bindings**
```zig
// Link to libbluetooth
// Use @cImport to bind C headers
```

#### Implementing BLE Support

To complete the BLE implementation:

1. **Choose a method** (D-Bus recommended for Linux)
2. **Implement platform-specific functions** in `zmk_studio.zig`:
   - `platformScanDevices()`
   - `platformConnect()`
   - `platformDisconnect()`
   - `platformWriteData()`
3. **Add notification handling** to receive responses from keyboard
4. **Test with real hardware**

Example D-Bus implementation structure:

```zig
const dbus = @import("dbus"); // Use a D-Bus library

fn platformConnect(impl: *anyopaque, device_address: []const u8, client: *BLEClient) !void {
    // 1. Get BlueZ device object path
    const device_path = try std.fmt.allocPrint(
        allocator,
        "/org/bluez/hci0/dev_{s}",
        .{formatMacForDBus(device_address)},
    );
    
    // 2. Connect to device
    try dbus.call("org.bluez", device_path, "org.bluez.Device1", "Connect");
    
    // 3. Discover services
    try dbus.call("org.bluez", device_path, "org.bluez.Device1", "DiscoverServices");
    
    // 4. Find ZMK Studio characteristic
    const char_path = try findCharacteristic(device_path, ZMK_STUDIO_RPC_CHAR_UUID);
    
    // 5. Subscribe to notifications
    try dbus.call("org.bluez", char_path, "org.bluez.GattCharacteristic1", "StartNotify");
}
```

## Testing

### Manual Testing with bluetoothctl

```bash
# Connect to keyboard
bluetoothctl connect XX:XX:XX:XX:XX:XX

# List GATT services (requires menu gatt)
menu gatt
list-attributes XX:XX:XX:XX:XX:XX

# Find ZMK Studio service (00000000-0196-6107-c967-c5cfb1c2482a)
# Find RPC characteristic (00000001-0196-6107-c967-c5cfb1c2482a)
```

### Testing with gatttool

```bash
# Interactive mode
gatttool -b XX:XX:XX:XX:XX:XX -I

# Connect
connect

# Read characteristic
char-read-uuid 00000001-0196-6107-c967-c5cfb1c2482a

# Write characteristic (protobuf-encoded request)
char-write-req 0x0010 <hex-encoded-protobuf>
```

## Troubleshooting

### Connection Issues

**Problem**: Cannot connect to keyboard
```bash
# Check Bluetooth status
bluetoothctl show

# Restart Bluetooth service
sudo systemctl restart bluetooth

# Check if device is paired
bluetoothctl paired-devices

# Remove and re-pair if needed
bluetoothctl remove XX:XX:XX:XX:XX:XX
```

**Problem**: Device connects but no GATT services
```bash
# Try connecting with gatttool
gatttool -b XX:XX:XX:XX:XX:XX -I
[XX:XX:XX:XX:XX:XX][LE]> connect
[XX:XX:XX:XX:XX:XX][LE]> primary
```

### Protocol Issues

**Problem**: Keyboard not responding to requests

- Ensure keyboard firmware has ZMK Studio enabled
- Check if keyboard is locked (try unlocking)
- Verify GATT characteristic UUIDs match your keyboard
- Enable debug logging to see raw messages

**Problem**: Decode errors

- Verify protocol buffer definitions match keyboard firmware version
- Check that encoded/decoded messages are valid protobuf format
- Use protobuf debugging tools to inspect messages

## Resources

- **ZMK Documentation**: https://zmk.dev/
- **ZMK Studio Protocol**: Check the protobuf definitions in `zig-out/proto/zmk/`
- **BlueZ Documentation**: http://www.bluez.org/
- **Protocol Buffers**: https://protobuf.dev/

## Contributing

To contribute BLE implementation:

1. Fork the repository
2. Implement platform-specific BLE functions
3. Test with real ZMK hardware
4. Submit a pull request

Priority areas:
- Linux D-Bus integration for BlueZ
- macOS Core Bluetooth bindings
- Windows BLE API bindings
- Cross-platform GATT abstraction

## License

See LICENSE file for details.
