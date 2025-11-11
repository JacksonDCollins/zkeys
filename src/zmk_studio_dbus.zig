const std = @import("std");
const protobuf = @import("protobuf");
const studio_pb = @import("proto/zmk/studio.pb.zig");
const core_pb = @import("proto/zmk/core.pb.zig");
const dbus_ble = @import("dbus_ble.zig");

pub const ZMKStudioError = error{
    NotConnected,
    BluetoothError,
    ProtocolError,
    Timeout,
    InvalidResponse,
    UnexpectedResponse,
};

// ZMK Studio RPC framing bytes
const SOF: u8 = 0xAB; // Start of Frame
const EOF: u8 = 0xAD; // End of Frame
const ESC: u8 = 0xAC; // Escape byte

pub const DeviceInfo = struct {
    response: studio_pb.Response,
    allocator: std.mem.Allocator,

    name: []const u8,
    version: []const u8,
    serial_number: []const u8,

    pub fn deinit(self: *DeviceInfo) void {
        self.response.deinit(self.allocator);
    }
};

pub const LockState = enum {
    locked,
    unlocked,
};

pub const ZMKStudioClient = struct {
    allocator: std.mem.Allocator,
    dbus_conn: dbus_ble.DBusConnection,
    device_path: ?[]const u8,
    char: ?dbus_ble.GattCharacteristic,
    next_request_id: u32,
    connected: bool,

    const ZMK_STUDIO_RPC_CHAR_UUID = "00000001-0196-6107-c967-c5cfb1c2482a";

    pub fn init(allocator: std.mem.Allocator) !ZMKStudioClient {
        const dbus_conn = try dbus_ble.DBusConnection.init(allocator);

        return ZMKStudioClient{
            .allocator = allocator,
            .dbus_conn = dbus_conn,
            .device_path = null,
            .char = null,
            .next_request_id = 1,
            .connected = false,
        };
    }

    pub fn deinit(self: *ZMKStudioClient) void {
        if (self.char) |*char| {
            _ = char.stopNotify() catch {};
            self.dbus_conn.allocator.free(char.char_path);
        }

        if (self.device_path) |path| {
            self.allocator.free(path);
        }

        self.dbus_conn.deinit();
    }

    pub fn connect(self: *ZMKStudioClient, device_address: []const u8) !void {
        std.log.info("Connecting to device via D-Bus: {s}", .{device_address});

        const device_path = try dbus_ble.findDevice(&self.dbus_conn, device_address);
        self.device_path = device_path;

        std.log.info("Found device at: {s}", .{device_path});

        const char_path = try dbus_ble.findCharacteristic(&self.dbus_conn, device_path, ZMK_STUDIO_RPC_CHAR_UUID);

        std.log.info("Found characteristic at: {s}", .{char_path});

        self.char = dbus_ble.GattCharacteristic{
            .conn = &self.dbus_conn,
            .device_path = device_path,
            .char_path = char_path,
            .uuid = ZMK_STUDIO_RPC_CHAR_UUID,
            .allocator = self.allocator,
            .match_rule = null,
        };

        try self.char.?.startNotify();

        self.connected = true;
        std.log.info("Successfully connected via D-Bus!", .{});
    }

    pub fn disconnect(self: *ZMKStudioClient) !void {
        if (self.char) |*char| {
            _ = char.stopNotify() catch {};
        }
        self.connected = false;
    }

    fn getNextRequestId(self: *ZMKStudioClient) u32 {
        const id = self.next_request_id;
        self.next_request_id += 1;
        return id;
    }

    fn frameMessage(allocator: std.mem.Allocator, payload: []const u8) ![]u8 {
        // Calculate worst-case size: SOF + escaped payload (max 2x) + EOF
        var framed = try std.ArrayList(u8).initCapacity(allocator, 2 + payload.len * 2);
        errdefer framed.deinit(allocator);

        // Add Start of Frame
        try framed.append(allocator, SOF);

        // Add payload with escaping
        for (payload) |byte| {
            if (byte == SOF or byte == EOF or byte == ESC) {
                try framed.append(allocator, ESC);
            }
            try framed.append(allocator, byte);
        }

        // Add End of Frame
        try framed.append(allocator, EOF);

        std.log.debug("Framed message: {d} bytes -> {d} bytes", .{ payload.len, framed.items.len });

        return framed.toOwnedSlice(allocator);
    }

    fn unframeMessage(allocator: std.mem.Allocator, framed: []const u8) ![]u8 {
        if (framed.len < 2) {
            return ZMKStudioError.ProtocolError;
        }

        if (framed[framed.len - 1] != EOF) {
            std.log.err("Missing EOF byte, got 0x{X:0>2}", .{framed[framed.len - 1]});
            return ZMKStudioError.ProtocolError;
        }

        // Unescape the payload
        var unframed = try std.ArrayList(u8).initCapacity(allocator, framed.len - 2);
        errdefer unframed.deinit(allocator);

        var i: usize = 0;
        // Skip SOF
        if (framed[0] == SOF) {
            i = 1;
        }
        while (i < framed.len - 1) { // Skip EOF
            const byte = framed[i];
            if (byte == ESC) {
                i += 1;
                if (i >= framed.len - 1) {
                    return ZMKStudioError.ProtocolError;
                }
                try unframed.append(allocator, framed[i]);
            } else {
                try unframed.append(allocator, byte);
            }
            i += 1;
        }

        std.log.debug("Unframed message: {d} bytes -> {d} bytes", .{ framed.len, unframed.items.len });

        return unframed.toOwnedSlice(allocator);
    }

    fn sendRequest(self: *ZMKStudioClient, request: studio_pb.Request) !studio_pb.Response {
        if (!self.connected) {
            return ZMKStudioError.NotConnected;
        }

        // Encode protobuf message
        var writer = std.io.Writer.Allocating.init(self.allocator);
        defer writer.deinit();
        try request.encode(&writer.writer, self.allocator);

        std.log.debug("Encoded protobuf: {d} bytes", .{writer.written().len});

        // Frame the message with SOF/EOF for BLE GATT transport
        const framed_msg = try frameMessage(self.allocator, writer.written());
        defer self.allocator.free(framed_msg);

        std.log.info("Sending framed request ({d} bytes)", .{framed_msg.len});
        std.log.debug("Framed data: {any}", .{framed_msg});

        // Set up listener BEFORE sending to avoid race condition
        try self.char.?.beginRead();
        defer self.char.?.endRead();

        try self.char.?.writeValue(framed_msg);

        std.log.debug("Waiting for indication...", .{});

        // Wait for indication via D-Bus signal
        var response_buf: [1024]u8 = undefined;
        var written: usize = try self.char.?.readValue(&response_buf);
        if (written == 0) {
            return ZMKStudioError.Timeout;
        }
        while (response_buf[written - 1] != EOF or std.mem.eql(u8, response_buf[written - 2 .. written - 1], &.{ ESC, EOF })) : (written += try self.char.?.readValue(response_buf[written..])) {
            if (written >= response_buf.len) {
                return ZMKStudioError.ProtocolError;
            }
        }

        std.log.info("Received response ({d} bytes)", .{written});
        if (written > 0) {
            std.log.debug("Response data: {any}", .{response_buf[0..written]});
        }

        if (written == 0) {
            return ZMKStudioError.Timeout;
        }

        // Unframe the response
        const unframed_msg = msg: {
            break :msg unframeMessage(self.allocator, response_buf[0..written]) catch {
                break :msg self.allocator.dupe(u8, response_buf[0..written]) catch {
                    return ZMKStudioError.ProtocolError;
                };
            };
        };
        defer self.allocator.free(unframed_msg);

        std.log.debug("Unframed protobuf: {d} bytes", .{unframed_msg.len});

        var reader = std.io.Reader.fixed(unframed_msg);
        const response = try studio_pb.Response.decode(&reader, self.allocator);

        return response;
    }

    pub fn getDeviceInfo(self: *ZMKStudioClient) !DeviceInfo {
        const request = studio_pb.Request{
            .request_id = self.getNextRequestId(),
            .subsystem = .{
                .core = .{
                    .request_type = .{ .get_device_info = true },
                },
            },
        };

        const response = try self.sendRequest(request);

        if (response.type) |t| {
            switch (t) {
                .request_response => |rr| {
                    if (rr.subsystem) |sub| {
                        if (sub == .core) {
                            if (sub.core.response_type) |rt| {
                                if (rt == .get_device_info) {
                                    return DeviceInfo{
                                        .response = response,
                                        .allocator = self.allocator,
                                        .name = rt.get_device_info.name,
                                        .version = "",
                                        .serial_number = rt.get_device_info.serial_number,
                                    };
                                }
                            }
                        }
                    }
                },
                else => {
                    return ZMKStudioError.UnexpectedResponse;
                },
            }
        }
        return ZMKStudioError.InvalidResponse;
    }

    pub fn getLockState(self: *ZMKStudioClient) !LockState {
        const request = studio_pb.Request{
            .request_id = self.getNextRequestId(),
            .subsystem = .{
                .core = .{
                    .request_type = .{ .get_lock_state = true },
                },
            },
        };

        var response = try self.sendRequest(request);
        defer response.deinit(self.allocator);

        if (response.type) |t| {
            switch (t) {
                .request_response => |rr| {
                    if (rr.subsystem) |sub| {
                        if (sub == .core) {
                            if (sub.core.response_type) |rt| {
                                if (rt == .get_lock_state) {
                                    return if (rt.get_lock_state == .ZMK_STUDIO_CORE_LOCK_STATE_LOCKED) .locked else .unlocked;
                                }
                            }
                        }
                    }
                },
                .notification => |notif| {
                    if (notif.subsystem) |sub| {
                        if (sub == .core) {
                            if (sub.core.lock_state_changed == .ZMK_STUDIO_CORE_LOCK_STATE_UNLOCKED) {
                                return .unlocked;
                            } else if (sub.core.lock_state_changed == .ZMK_STUDIO_CORE_LOCK_STATE_LOCKED) {
                                return .locked;
                            }
                        }
                    }
                },
            }
        }
        return ZMKStudioError.InvalidResponse;
    }

    pub fn unlock(self: *ZMKStudioClient) !void {
        const request = studio_pb.Request{
            .request_id = self.getNextRequestId(),
            .subsystem = .{
                .core = .{
                    .request_type = .{ .request_reset_settings = true },
                },
            },
        };

        _ = try self.sendRequest(request);
        std.log.info("Device unlocked", .{});
    }
};
