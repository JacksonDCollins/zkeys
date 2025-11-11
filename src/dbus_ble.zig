const std = @import("std");

/// D-Bus bindings for BlueZ communication
pub const c = @cImport({
    @cInclude("dbus/dbus.h");
    @cInclude("stdlib.h");
});

pub const DBusError = error{
    ConnectionFailed,
    MessageError,
    ReadError,
    WriteError,
    NotFound,
    Timeout,
    NoReply,
    InvalidArgs,
};

// DBusError is 32 bytes on most systems
const DBUS_ERROR_SIZE = 32;

pub const DBusConnection = struct {
    conn: ?*c.DBusConnection,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !DBusConnection {
        // Allocate DBusError with known size
        const err: *c.DBusError = @ptrCast(@alignCast(c.malloc(DBUS_ERROR_SIZE)));
        defer c.free(err);
        
        c.dbus_error_init(err);

        const conn = c.dbus_bus_get(c.DBUS_BUS_SYSTEM, err);
        if (c.dbus_error_is_set(err) != 0) {
            std.log.err("D-Bus connection error", .{});
            c.dbus_error_free(err);
            return DBusError.ConnectionFailed;
        }

        if (conn == null) {
            return DBusError.ConnectionFailed;
        }

        return DBusConnection{
            .conn = conn,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DBusConnection) void {
        if (self.conn) |conn| {
            c.dbus_connection_unref(conn);
        }
    }
};

pub const GattCharacteristic = struct {
    conn: *DBusConnection,
    device_path: []const u8,
    char_path: []const u8,
    uuid: []const u8,
    allocator: std.mem.Allocator,
    match_rule: ?[]u8,

    pub fn writeValue(self: *GattCharacteristic, data: []const u8) !void {
        const msg = c.dbus_message_new_method_call(
            "org.bluez",
            self.char_path.ptr,
            "org.bluez.GattCharacteristic1",
            "WriteValue",
        ) orelse return DBusError.MessageError;
        defer c.dbus_message_unref(msg);

        // Create array of bytes
        var iter: c.DBusMessageIter = undefined;
        c.dbus_message_iter_init_append(msg, &iter);

        // Add byte array argument
        var array_iter: c.DBusMessageIter = undefined;
        const array_sig = "y";
        if (c.dbus_message_iter_open_container(&iter, c.DBUS_TYPE_ARRAY, array_sig.ptr, &array_iter) == 0) {
            return DBusError.MessageError;
        }

        for (data) |byte| {
            var b = byte;
            if (c.dbus_message_iter_append_basic(&array_iter, c.DBUS_TYPE_BYTE, &b) == 0) {
                return DBusError.MessageError;
            }
        }

        if (c.dbus_message_iter_close_container(&iter, &array_iter) == 0) {
            return DBusError.MessageError;
        }

        // Add empty options dict
        var dict_iter: c.DBusMessageIter = undefined;
        const dict_sig = "{sv}";
        if (c.dbus_message_iter_open_container(&iter, c.DBUS_TYPE_ARRAY, dict_sig.ptr, &dict_iter) == 0) {
            return DBusError.MessageError;
        }
        if (c.dbus_message_iter_close_container(&iter, &dict_iter) == 0) {
            return DBusError.MessageError;
        }

        // Send message
        const err: *c.DBusError = @ptrCast(@alignCast(c.malloc(DBUS_ERROR_SIZE)));
        defer c.free(err);
        c.dbus_error_init(err);

        const reply = c.dbus_connection_send_with_reply_and_block(
            self.conn.conn.?,
            msg,
            5000, // 5 second timeout
            err,
        );

        if (c.dbus_error_is_set(err) != 0) {
            std.log.err("WriteValue error", .{});
            c.dbus_error_free(err);
            return DBusError.WriteError;
        }

        if (reply != null) {
            c.dbus_message_unref(reply);
        }
    }

    pub fn beginRead(self: *GattCharacteristic) !void {
        // Add a match rule for PropertiesChanged signals
        const match_rule = try std.fmt.allocPrint(self.allocator,
            "type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',path='{s}'\x00",
            .{self.char_path});
        
        const err: *c.DBusError = @ptrCast(@alignCast(c.malloc(DBUS_ERROR_SIZE)));
        defer c.free(err);
        c.dbus_error_init(err);
        
        c.dbus_bus_add_match(self.conn.conn.?, match_rule.ptr, err);
        if (c.dbus_error_is_set(err) != 0) {
            c.dbus_error_free(err);
            self.allocator.free(match_rule);
            return DBusError.ReadError;
        }

        self.match_rule = match_rule;
        c.dbus_connection_flush(self.conn.conn.?);
    }

    pub fn endRead(self: *GattCharacteristic) void {
        if (self.match_rule) |rule| {
            c.dbus_bus_remove_match(self.conn.conn.?, rule.ptr, null);
            self.allocator.free(rule);
            self.match_rule = null;
        }
    }

    pub fn readValue(self: *GattCharacteristic, buffer: []u8) !usize {
        std.log.debug("Waiting for indication via D-Bus signal...", .{});
        
        // Wait for signal
        const timeout_ms: i64 = 5000;
        const start_time = std.time.milliTimestamp();
        
        while (std.time.milliTimestamp() - start_time < timeout_ms) {
            // Try reading and dispatching with a short timeout
            _ = c.dbus_connection_read_write_dispatch(self.conn.conn.?, 100);
            
            const msg = c.dbus_connection_pop_message(self.conn.conn.?);
            if (msg == null) {
                continue;
            }
            defer c.dbus_message_unref(msg);
            
            if (c.dbus_message_is_signal(msg, "org.freedesktop.DBus.Properties", "PropertiesChanged") == 0) {
                continue;
            }
            
            std.log.debug("Got PropertiesChanged signal", .{});
            
            var iter: c.DBusMessageIter = undefined;
            if (c.dbus_message_iter_init(msg, &iter) == 0) {
                continue;
            }
            
            // Skip interface name
            _ = c.dbus_message_iter_next(&iter);
            
            if (c.dbus_message_iter_get_arg_type(&iter) != c.DBUS_TYPE_ARRAY) {
                continue;
            }
            
            var dict_iter: c.DBusMessageIter = undefined;
            c.dbus_message_iter_recurse(&iter, &dict_iter);
            
            while (c.dbus_message_iter_get_arg_type(&dict_iter) == c.DBUS_TYPE_DICT_ENTRY) {
                var entry_iter: c.DBusMessageIter = undefined;
                c.dbus_message_iter_recurse(&dict_iter, &entry_iter);
                
                var prop_name: [*:0]const u8 = undefined;
                if (c.dbus_message_iter_get_arg_type(&entry_iter) == c.DBUS_TYPE_STRING) {
                    c.dbus_message_iter_get_basic(&entry_iter, @ptrCast(&prop_name));
                }
                
                if (!std.mem.eql(u8, std.mem.span(prop_name), "Value")) {
                    _ = c.dbus_message_iter_next(&dict_iter);
                    continue;
                }
                
                std.log.debug("Found Value property in signal", .{});
                
                _ = c.dbus_message_iter_next(&entry_iter);
                
                if (c.dbus_message_iter_get_arg_type(&entry_iter) != c.DBUS_TYPE_VARIANT) {
                    _ = c.dbus_message_iter_next(&dict_iter);
                    continue;
                }
                
                var variant_iter: c.DBusMessageIter = undefined;
                c.dbus_message_iter_recurse(&entry_iter, &variant_iter);
                
                if (c.dbus_message_iter_get_arg_type(&variant_iter) != c.DBUS_TYPE_ARRAY) {
                    _ = c.dbus_message_iter_next(&dict_iter);
                    continue;
                }
                
                var array_iter: c.DBusMessageIter = undefined;
                c.dbus_message_iter_recurse(&variant_iter, &array_iter);
                
                var idx: usize = 0;
                while (c.dbus_message_iter_get_arg_type(&array_iter) == c.DBUS_TYPE_BYTE) {
                    if (idx >= buffer.len) {
                        return DBusError.ReadError;
                    }
                    
                    var byte: u8 = undefined;
                    c.dbus_message_iter_get_basic(&array_iter, @ptrCast(&byte));
                    buffer[idx] = byte;
                    idx += 1;
                    
                    _ = c.dbus_message_iter_next(&array_iter);
                }
                
                std.log.debug("Read {d} bytes from indication", .{idx});
                return idx;
            }
        }
        
        std.log.warn("Timeout waiting for indication", .{});
        return 0;
    }

    pub fn startNotify(self: *GattCharacteristic) !void {
        const msg = c.dbus_message_new_method_call(
            "org.bluez",
            self.char_path.ptr,
            "org.bluez.GattCharacteristic1",
            "StartNotify",
        ) orelse return DBusError.MessageError;
        defer c.dbus_message_unref(msg);

        const err: *c.DBusError = @ptrCast(@alignCast(c.malloc(DBUS_ERROR_SIZE)));
        defer c.free(err);
        c.dbus_error_init(err);

        const reply = c.dbus_connection_send_with_reply_and_block(
            self.conn.conn.?,
            msg,
            5000,
            err,
        );

        if (c.dbus_error_is_set(err) != 0) {
            std.log.err("StartNotify error", .{});
            c.dbus_error_free(err);
            return DBusError.WriteError;
        }

        if (reply != null) {
            c.dbus_message_unref(reply);
        }

        std.log.info("Notifications enabled", .{});
    }

    pub fn stopNotify(self: *GattCharacteristic) !void {
        const msg = c.dbus_message_new_method_call(
            "org.bluez",
            self.char_path.ptr,
            "org.bluez.GattCharacteristic1",
            "StopNotify",
        ) orelse return DBusError.MessageError;
        defer c.dbus_message_unref(msg);

        const err: *c.DBusError = @ptrCast(@alignCast(c.malloc(DBUS_ERROR_SIZE)));
        defer c.free(err);
        c.dbus_error_init(err);

        const reply = c.dbus_connection_send_with_reply_and_block(
            self.conn.conn.?,
            msg,
            5000,
            err,
        );

        if (c.dbus_error_is_set(err) != 0) {
            c.dbus_error_free(err);
            return DBusError.WriteError;
        }

        if (reply != null) {
            c.dbus_message_unref(reply);
        }
    }
};

pub fn findDevice(conn: *DBusConnection, mac_address: []const u8) ![]const u8 {
    // Convert MAC address to BlueZ format: dev_XX_XX_XX_XX_XX_XX
    var dev_name: [25]u8 = undefined;
    var idx: usize = 0;
    @memcpy(dev_name[0..4], "dev_");
    idx = 4;

    for (mac_address) |ch| {
        if (ch == ':') {
            dev_name[idx] = '_';
        } else {
            dev_name[idx] = std.ascii.toUpper(ch);
        }
        idx += 1;
    }

    const dev_name_str = dev_name[0..idx];

    // Get managed objects
    const msg = c.dbus_message_new_method_call(
        "org.bluez",
        "/",
        "org.freedesktop.DBus.ObjectManager",
        "GetManagedObjects",
    ) orelse return DBusError.MessageError;
    defer c.dbus_message_unref(msg);

    const err: *c.DBusError = @ptrCast(@alignCast(c.malloc(DBUS_ERROR_SIZE)));
    defer c.free(err);
    c.dbus_error_init(err);

    const reply = c.dbus_connection_send_with_reply_and_block(
        conn.conn.?,
        msg,
        5000,
        err,
    );

    if (c.dbus_error_is_set(err) != 0) {
        std.log.err("GetManagedObjects error", .{});
        c.dbus_error_free(err);
        return DBusError.MessageError;
    }

    if (reply == null) {
        return DBusError.NoReply;
    }
    defer c.dbus_message_unref(reply);

    // Parse reply to find device path
    var reply_iter: c.DBusMessageIter = undefined;
    if (c.dbus_message_iter_init(reply, &reply_iter) == 0) {
        return DBusError.NotFound;
    }

    if (c.dbus_message_iter_get_arg_type(&reply_iter) != c.DBUS_TYPE_ARRAY) {
        return DBusError.NotFound;
    }

    var array_iter: c.DBusMessageIter = undefined;
    c.dbus_message_iter_recurse(&reply_iter, &array_iter);

    while (c.dbus_message_iter_get_arg_type(&array_iter) == c.DBUS_TYPE_DICT_ENTRY) {
        var dict_iter: c.DBusMessageIter = undefined;
        c.dbus_message_iter_recurse(&array_iter, &dict_iter);

        // Get object path
        if (c.dbus_message_iter_get_arg_type(&dict_iter) == c.DBUS_TYPE_OBJECT_PATH) {
            var path: [*:0]const u8 = undefined;
            c.dbus_message_iter_get_basic(&dict_iter, @ptrCast(&path));

            const path_slice = std.mem.span(path);
            if (std.mem.indexOf(u8, path_slice, dev_name_str) != null) {
                // Found the device!
                return conn.allocator.dupe(u8, path_slice);
            }
        }

        _ = c.dbus_message_iter_next(&array_iter);
    }

    return DBusError.NotFound;
}

pub fn findCharacteristic(conn: *DBusConnection, device_path: []const u8, char_uuid: []const u8) ![]const u8 {
    // Get managed objects
    const msg = c.dbus_message_new_method_call(
        "org.bluez",
        "/",
        "org.freedesktop.DBus.ObjectManager",
        "GetManagedObjects",
    ) orelse return DBusError.MessageError;
    defer c.dbus_message_unref(msg);

    const err: *c.DBusError = @ptrCast(@alignCast(c.malloc(DBUS_ERROR_SIZE)));
    defer c.free(err);
    c.dbus_error_init(err);

    const reply = c.dbus_connection_send_with_reply_and_block(
        conn.conn.?,
        msg,
        5000,
        err,
    );

    if (c.dbus_error_is_set(err) != 0) {
        c.dbus_error_free(err);
        return DBusError.MessageError;
    }

    if (reply == null) {
        return DBusError.NoReply;
    }
    defer c.dbus_message_unref(reply);

    // Parse to find characteristic with matching UUID under device path
    var reply_iter: c.DBusMessageIter = undefined;
    if (c.dbus_message_iter_init(reply, &reply_iter) == 0) {
        return DBusError.NotFound;
    }

    if (c.dbus_message_iter_get_arg_type(&reply_iter) != c.DBUS_TYPE_ARRAY) {
        return DBusError.NotFound;
    }

    var objects_iter: c.DBusMessageIter = undefined;
    c.dbus_message_iter_recurse(&reply_iter, &objects_iter);

    // Iterate over objects
    while (c.dbus_message_iter_get_arg_type(&objects_iter) == c.DBUS_TYPE_DICT_ENTRY) {
        var object_entry: c.DBusMessageIter = undefined;
        c.dbus_message_iter_recurse(&objects_iter, &object_entry);

        // Get object path (key)
        var path: [*:0]const u8 = undefined;
        if (c.dbus_message_iter_get_arg_type(&object_entry) == c.DBUS_TYPE_OBJECT_PATH) {
            c.dbus_message_iter_get_basic(&object_entry, @ptrCast(&path));
        }
        const path_slice = std.mem.span(path);

        // Only look at paths under our device
        if (!std.mem.startsWith(u8, path_slice, device_path)) {
            _ = c.dbus_message_iter_next(&objects_iter);
            continue;
        }

        // Move to interfaces dict (value)
        _ = c.dbus_message_iter_next(&object_entry);
        
        var interfaces_iter: c.DBusMessageIter = undefined;
        if (c.dbus_message_iter_get_arg_type(&object_entry) == c.DBUS_TYPE_ARRAY) {
            c.dbus_message_iter_recurse(&object_entry, &interfaces_iter);

            // Look for GattCharacteristic1 interface
            while (c.dbus_message_iter_get_arg_type(&interfaces_iter) == c.DBUS_TYPE_DICT_ENTRY) {
                var iface_entry: c.DBusMessageIter = undefined;
                c.dbus_message_iter_recurse(&interfaces_iter, &iface_entry);

                var iface_name: [*:0]const u8 = undefined;
                if (c.dbus_message_iter_get_arg_type(&iface_entry) == c.DBUS_TYPE_STRING) {
                    c.dbus_message_iter_get_basic(&iface_entry, @ptrCast(&iface_name));
                }

                const iface_name_slice = std.mem.span(iface_name);
                
                if (std.mem.eql(u8, iface_name_slice, "org.bluez.GattCharacteristic1")) {
                    // Found characteristic interface, now check UUID
                    _ = c.dbus_message_iter_next(&iface_entry);
                    
                    var props_iter: c.DBusMessageIter = undefined;
                    if (c.dbus_message_iter_get_arg_type(&iface_entry) == c.DBUS_TYPE_ARRAY) {
                        c.dbus_message_iter_recurse(&iface_entry, &props_iter);

                        // Look for UUID property
                        while (c.dbus_message_iter_get_arg_type(&props_iter) == c.DBUS_TYPE_DICT_ENTRY) {
                            var prop_entry: c.DBusMessageIter = undefined;
                            c.dbus_message_iter_recurse(&props_iter, &prop_entry);

                            var prop_name: [*:0]const u8 = undefined;
                            if (c.dbus_message_iter_get_arg_type(&prop_entry) == c.DBUS_TYPE_STRING) {
                                c.dbus_message_iter_get_basic(&prop_entry, @ptrCast(&prop_name));
                            }

                            if (std.mem.eql(u8, std.mem.span(prop_name), "UUID")) {
                                _ = c.dbus_message_iter_next(&prop_entry);
                                
                                var variant_iter: c.DBusMessageIter = undefined;
                                if (c.dbus_message_iter_get_arg_type(&prop_entry) == c.DBUS_TYPE_VARIANT) {
                                    c.dbus_message_iter_recurse(&prop_entry, &variant_iter);

                                    var uuid: [*:0]const u8 = undefined;
                                    if (c.dbus_message_iter_get_arg_type(&variant_iter) == c.DBUS_TYPE_STRING) {
                                        c.dbus_message_iter_get_basic(&variant_iter, @ptrCast(&uuid));
                                    }

                                    const uuid_slice = std.mem.span(uuid);
                                    
                                    // Compare UUIDs (case-insensitive)
                                    if (std.ascii.eqlIgnoreCase(uuid_slice, char_uuid)) {
                                        return conn.allocator.dupe(u8, path_slice);
                                    }
                                }
                            }

                            _ = c.dbus_message_iter_next(&props_iter);
                        }
                    }
                }

                _ = c.dbus_message_iter_next(&interfaces_iter);
            }
        }

        _ = c.dbus_message_iter_next(&objects_iter);
    }

    return DBusError.NotFound;
}
