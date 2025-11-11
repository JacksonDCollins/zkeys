# Using Protobuf Files to Communicate with ZMK Keyboard over Bluetooth

This repository contains Protocol Buffer definitions for communicating with ZMK keyboards that support ZMK Studio functionality over Bluetooth Low Energy (BLE).

## Overview

ZMK Studio uses Protocol Buffers (protobuf) for structured communication between a host device and a ZMK keyboard. The communication happens over BLE GATT (Generic Attribute Profile) characteristics.

## Protocol Buffer Files

The protobuf definitions are located in `zig-out/proto/zmk/`:

- **`studio.proto`** - Top-level request/response wrapper messages
- **`core.proto`** - Core device functionality (device info, lock state, reset)
- **`behaviors.proto`** - Keyboard behavior information (key actions)
- **`keymap.proto`** - Keymap management (layers, bindings, physical layouts)
- **`meta.proto`** - Error handling and metadata

## Communication Protocol

### 1. BLE GATT Service

ZMK Studio exposes a custom GATT service with characteristics for:
- **Write characteristic**: Send protobuf-encoded `Request` messages
- **Read/Notify characteristic**: Receive protobuf-encoded `Response` messages

**Typical UUIDs** (check your keyboard's documentation):
- Service UUID: `00000000-0196-6107-c967-c5cfb1c2482a`
- RPC characteristic (write/notify): Check ZMK Studio documentation

### 2. Message Flow

```
Host -> Keyboard: Request (with unique request_id)
Keyboard -> Host: RequestResponse (matching request_id) OR Notification
```

## Request/Response Structure

### Top-Level Request
```protobuf
message Request {
    uint32 request_id = 1;  // Unique ID to match responses
    
    oneof subsystem {
        zmk.core.Request core = 3;
        zmk.behaviors.Request behaviors = 4;
        zmk.keymap.Request keymap = 5;
    }
}
```

### Top-Level Response
```protobuf
message Response {
    oneof type {
        RequestResponse request_response = 1;  // Reply to a request
        Notification notification = 2;          // Unsolicited update
    }
}
```

## Common Use Cases

### 1. Get Device Information

**Request:**
```protobuf
Request {
    request_id: 1
    core: {
        get_device_info: true
    }
}
```

**Response:**
```protobuf
Response {
    request_response: {
        request_id: 1
        core: {
            get_device_info: {
                name: "My Keyboard"
                serial_number: [0x01, 0x02, ...]
            }
        }
    }
}
```

### 2. Check Lock State

**Request:**
```protobuf
Request {
    request_id: 2
    core: {
        get_lock_state: true
    }
}
```

**Response:**
```protobuf
Response {
    request_response: {
        request_id: 2
        core: {
            get_lock_state: ZMK_STUDIO_CORE_LOCK_STATE_UNLOCKED
        }
    }
}
```

### 3. Get Keymap

**Request:**
```protobuf
Request {
    request_id: 3
    keymap: {
        get_keymap: true
    }
}
```

**Response:**
```protobuf
Response {
    request_response: {
        request_id: 3
        keymap: {
            get_keymap: {
                layers: [
                    {
                        id: 0
                        name: "Default"
                        bindings: [
                            { behavior_id: 1, param1: 0x04, param2: 0 },  // 'A' key
                            { behavior_id: 1, param1: 0x05, param2: 0 },  // 'B' key
                            ...
                        ]
                    },
                    ...
                ]
                available_layers: 8
                max_layer_name_length: 16
            }
        }
    }
}
```

### 4. List All Behaviors

**Request:**
```protobuf
Request {
    request_id: 4
    behaviors: {
        list_all_behaviors: true
    }
}
```

**Response:**
```protobuf
Response {
    request_response: {
        request_id: 4
        behaviors: {
            list_all_behaviors: {
                behaviors: [1, 2, 3, 4, ...]  // Behavior IDs
            }
        }
    }
}
```

### 5. Set a Key Binding

**Request:**
```protobuf
Request {
    request_id: 5
    keymap: {
        set_layer_binding: {
            layer_id: 0
            key_position: 10
            binding: {
                behavior_id: 1      // Key press behavior
                param1: 0x06        // HID usage (e.g., 'C')
                param2: 0
            }
        }
    }
}
```

**Response:**
```protobuf
Response {
    request_response: {
        request_id: 5
        keymap: {
            set_layer_binding: SET_LAYER_BINDING_RESP_OK
        }
    }
}
```

### 6. Save Changes

**Request:**
```protobuf
Request {
    request_id: 6
    keymap: {
        save_changes: true
    }
}
```

**Response:**
```protobuf
Response {
    request_response: {
        request_id: 6
        keymap: {
            save_changes: {
                ok: true
            }
        }
    }
}
```

## Implementation Steps

### Step 1: Generate Code from Protobufs

Use a protobuf compiler for your language:

**Python:**
```bash
protoc --python_out=. zig-out/proto/zmk/*.proto
```

**JavaScript/TypeScript:**
```bash
npm install protobufjs
pbjs -t static-module -w commonjs -o zmk.js zig-out/proto/zmk/*.proto
pbts -o zmk.d.ts zmk.js
```

**Go:**
```bash
protoc --go_out=. zig-out/proto/zmk/*.proto
```

**Zig (this repo uses):**
The build.zig already handles generating Zig code from the protos.

### Step 2: Connect to Keyboard via BLE

Use your platform's BLE library:

**Python (using bleak):**
```python
from bleak import BleakClient, BleakScanner

# Scan for your keyboard
devices = await BleakScanner.discover()
keyboard = next(d for d in devices if "YourKeyboard" in d.name)

# Connect
async with BleakClient(keyboard.address) as client:
    # Find the ZMK Studio service and characteristic
    service_uuid = "00000000-0196-6107-c967-c5cfb1c2482a"
    char_uuid = "00000001-0196-6107-c967-c5cfb1c2482a"
    
    # Subscribe to notifications
    await client.start_notify(char_uuid, notification_handler)
    
    # Send requests
    await client.write_gatt_char(char_uuid, request_bytes)
```

**JavaScript (using Web Bluetooth):**
```javascript
const device = await navigator.bluetooth.requestDevice({
    filters: [{ services: ['00000000-0196-6107-c967-c5cfb1c2482a'] }]
});

const server = await device.gatt.connect();
const service = await server.getPrimaryService('00000000-0196-6107-c967-c5cfb1c2482a');
const characteristic = await service.getCharacteristic('00000001-0196-6107-c967-c5cfb1c2482a');

// Subscribe to notifications
await characteristic.startNotifications();
characteristic.addEventListener('characteristicvaluechanged', handleResponse);

// Send request
await characteristic.writeValue(requestBytes);
```

### Step 3: Encode/Decode Messages

**Python example:**
```python
import zmk_pb2  # Generated from protos

# Create request
request = zmk_pb2.Request()
request.request_id = 1
request.core.get_device_info = True

# Encode to bytes
request_bytes = request.SerializeToString()

# Send via BLE
await client.write_gatt_char(char_uuid, request_bytes)

# Decode response
def notification_handler(sender, data):
    response = zmk_pb2.Response()
    response.ParseFromString(data)
    
    if response.HasField('request_response'):
        if response.request_response.request_id == 1:
            info = response.request_response.core.get_device_info
            print(f"Device: {info.name}")
```

### Step 4: Handle Request IDs

Keep track of request IDs to match responses:
```python
class ZMKStudioClient:
    def __init__(self):
        self.next_request_id = 1
        self.pending_requests = {}
    
    async def send_request(self, request):
        request_id = self.next_request_id
        self.next_request_id += 1
        
        request.request_id = request_id
        
        # Store callback/future for this request
        future = asyncio.Future()
        self.pending_requests[request_id] = future
        
        # Send
        await self.write(request.SerializeToString())
        
        # Wait for response
        return await future
    
    def handle_response(self, data):
        response = zmk_pb2.Response()
        response.ParseFromString(data)
        
        if response.HasField('request_response'):
            request_id = response.request_response.request_id
            if request_id in self.pending_requests:
                self.pending_requests[request_id].set_result(response)
                del self.pending_requests[request_id]
```

## Important Notes

1. **Lock State**: Some operations require the keyboard to be unlocked. Check and unlock if needed.

2. **Request IDs**: Always use unique request IDs to properly match responses.

3. **Save Changes**: Changes to keymap are temporary until you call `save_changes`.

4. **Notifications**: The keyboard can send unsolicited notifications (e.g., lock state changes).

5. **Error Handling**: Check for error responses in `meta.Response.simple_error`.

6. **MTU Size**: BLE has limited packet sizes (typically 20-512 bytes). Large messages may need fragmentation.

## Example Complete Workflow

```python
# 1. Connect to keyboard
client = await connect_to_keyboard()

# 2. Check if unlocked
lock_state = await client.get_lock_state()
if lock_state == LOCKED:
    await client.unlock()

# 3. Get current keymap
keymap = await client.get_keymap()
print(f"Layers: {len(keymap.layers)}")

# 4. Modify a binding
await client.set_layer_binding(
    layer_id=0,
    key_position=5,
    behavior_id=1,
    param1=0x04,  # 'A' key
    param2=0
)

# 5. Save changes
result = await client.save_changes()
if result.ok:
    print("Changes saved!")

# 6. Disconnect
await client.disconnect()
```

## Additional Resources

- **ZMK Documentation**: https://zmk.dev/
- **ZMK Studio**: Check the ZMK Studio repository for official client implementations
- **BLE GATT**: Understanding GATT services and characteristics is essential
- **Protocol Buffers**: https://protobuf.dev/

## Troubleshooting

- **Connection fails**: Ensure keyboard is in pairing mode and ZMK Studio is enabled in firmware
- **No response**: Check UUID values match your keyboard's implementation
- **Decode errors**: Verify you're using the correct protobuf version (proto3)
- **Permission denied**: Some operations require unlock state
