const std = @import("std");

/// C bindings for BlueZ Bluetooth operations
pub const c = @cImport({
    @cInclude("bluetooth/bluetooth.h");
    @cInclude("bluetooth/hci.h");
    @cInclude("bluetooth/hci_lib.h");
    @cInclude("bluetooth/l2cap.h");
    @cInclude("unistd.h");
    @cInclude("sys/socket.h");
    @cInclude("fcntl.h");
    @cInclude("poll.h");
    @cDefine("_GNU_SOURCE", "1");
    @cInclude("string.h");
});

fn getErrno() c_int {
    return std.c._errno().*;
}

fn getErrorString(errno_val: c_int) [*:0]const u8 {
    return c.strerror(errno_val);
}

// ATT CID constant (not always available in headers)
const ATT_CID: u16 = 4;

// Error constants from errno.h
const EAGAIN = 11;
const EWOULDBLOCK = EAGAIN;
const EINPROGRESS = 115;

pub const BluetoothError = error{
    DeviceNotFound,
    ConnectionFailed,
    ScanFailed,
    SocketError,
    BindError,
    WriteError,
    ReadError,
    InvalidAddress,
    Timeout,
};

pub const BDAddr = struct {
    b: [6]u8,

    pub fn fromString(addr_str: []const u8) !BDAddr {
        var addr: BDAddr = undefined;
        var parts = std.mem.splitSequence(u8, addr_str, ":");
        var i: usize = 0;

        while (parts.next()) |part| : (i += 1) {
            if (i >= 6) return BluetoothError.InvalidAddress;
            addr.b[5 - i] = try std.fmt.parseInt(u8, part, 16);
        }

        if (i != 6) return BluetoothError.InvalidAddress;
        return addr;
    }

    pub fn toString(self: BDAddr, buffer: []u8) ![]const u8 {
        return std.fmt.bufPrint(buffer, "{X:0>2}:{X:0>2}:{X:0>2}:{X:0>2}:{X:0>2}:{X:0>2}", .{
            self.b[5], self.b[4], self.b[3], self.b[2], self.b[1], self.b[0],
        });
    }
};

pub const ScanResult = struct {
    addr: BDAddr,
    name: [248]u8,
    name_len: usize,
    rssi: i8,
};

/// Scan for Bluetooth LE devices
pub fn scanDevices(allocator: std.mem.Allocator, timeout_seconds: u32) ![]ScanResult {
    _ = timeout_seconds;

    // Open HCI device
    const dev_id = c.hci_get_route(null);
    if (dev_id < 0) {
        std.log.err("Failed to get HCI device: {s}", .{getErrorString(getErrno())});
        return BluetoothError.DeviceNotFound;
    }

    const sock = c.hci_open_dev(dev_id);
    if (sock < 0) {
        std.log.err("Failed to open HCI device: {s}", .{getErrorString(getErrno())});
        return BluetoothError.DeviceNotFound;
    }
    defer _ = c.close(sock);

    std.log.info("Scanning for Bluetooth LE devices...", .{});
    std.log.info("Note: BLE scanning requires root privileges or CAP_NET_ADMIN", .{});
    std.log.info("Run with: sudo ./zmk-example or use bluetoothctl", .{});

    // For now, return empty list and suggest using bluetoothctl
    // Full LE scanning implementation requires more complex HCI commands
    return allocator.alloc(ScanResult, 0);
}

/// Connect to a Bluetooth LE device and return L2CAP socket for ATT protocol
pub fn connectDevice(addr_str: []const u8) !c_int {
    const addr = try BDAddr.fromString(addr_str);

    std.log.info("Connecting to {s}...", .{addr_str});

    // Create L2CAP socket for ATT protocol (BLE GATT)
    const sock = c.socket(c.AF_BLUETOOTH, c.SOCK_SEQPACKET, c.BTPROTO_L2CAP);
    if (sock < 0) {
        std.log.err("Failed to create socket: {s}", .{getErrorString(getErrno())});
        return BluetoothError.SocketError;
    }
    errdefer _ = c.close(sock);

    // Set up local address (bind to any local adapter)
    var local_addr: c.sockaddr_l2 = std.mem.zeroes(c.sockaddr_l2);
    local_addr.l2_family = c.AF_BLUETOOTH;
    local_addr.l2_cid = @as(c_ushort, @bitCast(ATT_CID));
    local_addr.l2_bdaddr_type = c.BDADDR_LE_PUBLIC;

    if (c.bind(sock, @ptrCast(&local_addr), @sizeOf(c.sockaddr_l2)) < 0) {
        std.log.err("Failed to bind socket: {s}", .{getErrorString(getErrno())});
        return BluetoothError.BindError;
    }

    // Set up remote address
    var remote_addr: c.sockaddr_l2 = std.mem.zeroes(c.sockaddr_l2);
    remote_addr.l2_family = c.AF_BLUETOOTH;
    remote_addr.l2_cid = @as(c_ushort, @bitCast(ATT_CID));
    remote_addr.l2_bdaddr_type = c.BDADDR_LE_PUBLIC;
    @memcpy(&remote_addr.l2_bdaddr.b, &addr.b);

    // Connect to remote device
    std.log.info("Attempting L2CAP connection...", .{});
    
    // Set socket to non-blocking for timeout
    const old_flags = c.fcntl(sock, c.F_GETFL, @as(c_int, 0));
    _ = c.fcntl(sock, c.F_SETFL, old_flags | c.O_NONBLOCK);
    
    const connect_result = c.connect(sock, @ptrCast(&remote_addr), @sizeOf(c.sockaddr_l2));
    
    if (connect_result < 0) {
        const err = getErrno();
        
        // EINPROGRESS is expected for non-blocking
        if (err != EINPROGRESS) {
            std.log.err("Failed to connect: {s} (errno: {d})", .{ getErrorString(@intCast(err)), err });

            // Try with BDADDR_LE_RANDOM if public address fails
            std.log.info("Retrying with LE Random address...", .{});
            remote_addr.l2_bdaddr_type = c.BDADDR_LE_RANDOM;
            
            const retry = c.connect(sock, @ptrCast(&remote_addr), @sizeOf(c.sockaddr_l2));
            if (retry < 0 and getErrno() != EINPROGRESS) {
                std.log.err("Failed with random address: {s}", .{getErrorString(getErrno())});
                std.log.info("", .{});
                std.log.info("Device might not be paired. Pair it first:", .{});
                std.log.info("  - System Settings → Bluetooth", .{});
                std.log.info("  - sudo bluetoothctl (if available)", .{});
                return BluetoothError.ConnectionFailed;
            }
        }
    }
    
    // Wait for connection with timeout
    std.log.info("Waiting for connection (10s timeout)...", .{});
    var fds: [1]c.struct_pollfd = undefined;
    fds[0].fd = sock;
    fds[0].events = c.POLLOUT;
    fds[0].revents = 0;

    const poll_result = c.poll(&fds, 1, 10000); // 10 second timeout
    
    if (poll_result < 0) {
        std.log.err("Poll failed: {s}", .{getErrorString(getErrno())});
        return BluetoothError.ConnectionFailed;
    }
    
    if (poll_result == 0) {
        std.log.err("Connection timeout after 10 seconds", .{});
        std.log.info("", .{});
        std.log.info("Device is not responding. Possible causes:", .{});
        std.log.info("  1. Device not paired (pair it first)", .{});
        std.log.info("  2. Device connected to another host", .{});
        std.log.info("  3. Device out of range or powered off", .{});
        std.log.info("  4. Wrong MAC address", .{});
        return BluetoothError.Timeout;
    }

    // Check connection result
    var so_error: c_int = 0;
    var len: c.socklen_t = @sizeOf(c_int);
    if (c.getsockopt(sock, c.SOL_SOCKET, c.SO_ERROR, @ptrCast(&so_error), &len) < 0) {
        std.log.err("getsockopt failed: {s}", .{getErrorString(getErrno())});
        return BluetoothError.ConnectionFailed;
    }

    if (so_error != 0) {
        std.log.err("Connection failed: {s}", .{getErrorString(so_error)});
        std.log.info("", .{});
        std.log.info("Device needs to be paired first.", .{});
        std.log.info("Pair through System Settings → Bluetooth", .{});
        return BluetoothError.ConnectionFailed;
    }

    // Set back to blocking
    _ = c.fcntl(sock, c.F_SETFL, old_flags);

    std.log.info("Connected successfully!", .{});
    return sock;
}

/// Disconnect from device
pub fn disconnectDevice(sock: c_int) void {
    _ = c.close(sock);
    std.log.info("Disconnected from device", .{});
}

/// ATT protocol opcodes
pub const ATT = struct {
    pub const OP_ERROR = 0x01;
    pub const OP_MTU_REQ = 0x02;
    pub const OP_MTU_RESP = 0x03;
    pub const OP_FIND_INFO_REQ = 0x04;
    pub const OP_FIND_INFO_RESP = 0x05;
    pub const OP_READ_BY_TYPE_REQ = 0x08;
    pub const OP_READ_BY_TYPE_RESP = 0x09;
    pub const OP_READ_REQ = 0x0A;
    pub const OP_READ_RESP = 0x0B;
    pub const OP_WRITE_REQ = 0x12;
    pub const OP_WRITE_RESP = 0x13;
    pub const OP_WRITE_CMD = 0x52;
    pub const OP_HANDLE_NOTIFY = 0x1B;
    pub const OP_HANDLE_IND = 0x1D;
    pub const OP_HANDLE_CONF = 0x1E;

    pub const UUID_PRIMARY_SERVICE: [2]u8 = .{ 0x00, 0x28 };
    pub const UUID_CHARACTERISTIC: [2]u8 = .{ 0x03, 0x28 };
    pub const UUID_CLIENT_CHAR_CONFIG: [2]u8 = .{ 0x02, 0x29 };
};

/// UUID structure for BLE
pub const UUID128 = struct {
    value: [16]u8,

    pub fn fromString(uuid_str: []const u8) !UUID128 {
        var uuid: UUID128 = undefined;
        var hex_str: [32]u8 = undefined;
        var hex_idx: usize = 0;

        // Remove dashes
        for (uuid_str) |ch| {
            if (ch != '-') {
                if (hex_idx >= 32) return error.InvalidUUID;
                hex_str[hex_idx] = ch;
                hex_idx += 1;
            }
        }

        if (hex_idx != 32) return error.InvalidUUID;

        // Parse hex pairs in reverse order (little-endian)
        var i: usize = 0;
        while (i < 16) : (i += 1) {
            const byte_str = hex_str[i * 2 .. i * 2 + 2];
            uuid.value[15 - i] = try std.fmt.parseInt(u8, byte_str, 16);
        }

        return uuid;
    }

    pub fn toBytes(self: UUID128) []const u8 {
        return &self.value;
    }
};

/// Exchange MTU (negotiate maximum transmission unit)
pub fn exchangeMTU(sock: c_int, mtu: u16) !u16 {
    var req: [3]u8 = undefined;
    req[0] = ATT.OP_MTU_REQ;
    req[1] = @truncate(mtu & 0xFF);
    req[2] = @truncate((mtu >> 8) & 0xFF);

    const sent = c.send(sock, &req, req.len, 0);
    if (sent < 0) {
        return BluetoothError.WriteError;
    }

    var resp: [3]u8 = undefined;
    const received = c.recv(sock, &resp, resp.len, 0);
    if (received < 0) {
        return BluetoothError.ReadError;
    }

    if (resp[0] != ATT.OP_MTU_RESP) {
        std.log.err("Unexpected MTU response: 0x{X:0>2}", .{resp[0]});
        return BluetoothError.ReadError;
    }

    const negotiated_mtu = @as(u16, resp[1]) | (@as(u16, resp[2]) << 8);
    std.log.info("Negotiated MTU: {d}", .{negotiated_mtu});
    return negotiated_mtu;
}

/// Find characteristic by UUID
pub fn findCharacteristic(sock: c_int, service_uuid: UUID128, char_uuid: UUID128) !u16 {
    _ = service_uuid;
    _ = char_uuid;

    // This is a simplified implementation
    // A full implementation would:
    // 1. Discover primary services
    // 2. Find service matching service_uuid
    // 3. Discover characteristics in that service
    // 4. Return handle for matching char_uuid

    std.log.warn("findCharacteristic: simplified implementation", .{});
    std.log.info("You may need to manually determine the characteristic handle", .{});
    std.log.info("Use 'gatttool -b XX:XX:XX:XX:XX:XX --characteristics' to find handles", .{});

    // For ZMK Studio, the RPC characteristic handle is typically around 0x0010-0x0020
    // This would need to be discovered properly in a full implementation
    _ = sock;
    return 0x0010; // Placeholder - should be discovered
}

/// Write to characteristic
pub fn writeCharacteristic(sock: c_int, handle: u16, data: []const u8) !void {
    if (data.len > 512) return BluetoothError.WriteError;

    var buffer: [515]u8 = undefined;
    buffer[0] = ATT.OP_WRITE_REQ;
    buffer[1] = @truncate(handle & 0xFF);
    buffer[2] = @truncate((handle >> 8) & 0xFF);
    @memcpy(buffer[3 .. 3 + data.len], data);

    const sent = c.send(sock, &buffer, 3 + data.len, 0);
    if (sent < 0) {
        std.log.err("Write failed: {s}", .{getErrorString(getErrno())});
        return BluetoothError.WriteError;
    }

    // Wait for write response
    var resp: [1]u8 = undefined;
    const received = c.recv(sock, &resp, resp.len, 0);
    if (received < 0) {
        return BluetoothError.ReadError;
    }

    if (resp[0] != ATT.OP_WRITE_RESP) {
        std.log.err("Unexpected write response: 0x{X:0>2}", .{resp[0]});
        return BluetoothError.WriteError;
    }

    std.log.info("Write successful ({d} bytes)", .{data.len});
}

/// Read from characteristic
pub fn readCharacteristic(sock: c_int, handle: u16, buffer: []u8) !usize {
    var req: [3]u8 = undefined;
    req[0] = ATT.OP_READ_REQ;
    req[1] = @truncate(handle & 0xFF);
    req[2] = @truncate((handle >> 8) & 0xFF);

    const sent = c.send(sock, &req, req.len, 0);
    if (sent < 0) {
        return BluetoothError.WriteError;
    }

    var resp: [512]u8 = undefined;
    const received = c.recv(sock, &resp, resp.len, 0);
    if (received < 0) {
        return BluetoothError.ReadError;
    }

    if (resp[0] != ATT.OP_READ_RESP) {
        std.log.err("Unexpected read response: 0x{X:0>2}", .{resp[0]});
        return BluetoothError.ReadError;
    }

    const data_len = @as(usize, @intCast(received)) - 1;
    if (data_len > buffer.len) return BluetoothError.ReadError;

    @memcpy(buffer[0..data_len], resp[1..received]);
    return data_len;
}

/// Enable notifications for a characteristic
pub fn enableNotifications(sock: c_int, handle: u16) !void {
    // To enable notifications, we write 0x0001 to the Client Characteristic Configuration descriptor
    // The CCCD handle is typically handle + 1
    const cccd_handle = handle + 1;

    var buffer: [5]u8 = undefined;
    buffer[0] = ATT.OP_WRITE_REQ;
    buffer[1] = @truncate(cccd_handle & 0xFF);
    buffer[2] = @truncate((cccd_handle >> 8) & 0xFF);
    buffer[3] = 0x01; // Enable notifications
    buffer[4] = 0x00;

    const sent = c.send(sock, &buffer, buffer.len, 0);
    if (sent < 0) {
        return BluetoothError.WriteError;
    }

    var resp: [1]u8 = undefined;
    const received = c.recv(sock, &resp, resp.len, 0);
    if (received < 0) {
        return BluetoothError.ReadError;
    }

    if (resp[0] != ATT.OP_WRITE_RESP) {
        std.log.err("Failed to enable notifications: 0x{X:0>2}", .{resp[0]});
        return BluetoothError.WriteError;
    }

    std.log.info("Notifications enabled for handle 0x{X:0>4}", .{handle});
}

/// Read notification (non-blocking with timeout)
pub fn readNotification(sock: c_int, buffer: []u8, timeout_ms: u32) !?usize {
    // Set socket timeout
    var tv: c.struct_timeval = undefined;
    tv.tv_sec = @intCast(timeout_ms / 1000);
    tv.tv_usec = @intCast((timeout_ms % 1000) * 1000);

    if (c.setsockopt(sock, c.SOL_SOCKET, c.SO_RCVTIMEO, @ptrCast(&tv), @sizeOf(c.struct_timeval)) < 0) {
        return BluetoothError.SocketError;
    }

    var resp: [515]u8 = undefined;
    const received = c.recv(sock, &resp, resp.len, 0);

    if (received < 0) {
        const err = getErrno();
        if (err == EAGAIN or err == EWOULDBLOCK) {
            return null; // Timeout
        }
        return BluetoothError.ReadError;
    }

    if (received < 1) return null;

    // Check if it's a notification or indication
    if (resp[0] == ATT.OP_HANDLE_NOTIFY or resp[0] == ATT.OP_HANDLE_IND) {
        if (received < 3) return null;

        const received_usize: usize = @intCast(received);
        const data_len = received_usize - 3;
        if (data_len > buffer.len) return BluetoothError.ReadError;

        @memcpy(buffer[0..data_len], resp[3..received_usize]);

        // Send confirmation for indications
        if (resp[0] == ATT.OP_HANDLE_IND) {
            var conf: [1]u8 = .{ATT.OP_HANDLE_CONF};
            _ = c.send(sock, &conf, conf.len, 0);
        }

        return data_len;
    }

    return null;
}
