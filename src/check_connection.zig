const std = @import("std");

pub fn main() !void {
    const args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.process.argsFree(std.heap.page_allocator, args);

    if (args.len < 2) {
        std.log.info("Usage: {s} MAC:ADDRESS", .{args[0]});
        std.log.info("Example: {s} FC:82:CF:C8:47:32", .{args[0]});
        return;
    }

    const mac_addr = args[1];
    
    std.log.info("Checking Bluetooth connection status for: {s}", .{mac_addr});
    std.log.info("", .{});

    // Check if bluetoothd is managing this connection
    const connected = try isConnectedViaBluetoothd(mac_addr);
    if (connected) {
        std.log.info("✅ Device is CONNECTED via bluetoothd", .{});
        std.log.info("", .{});
        std.log.info("This is why direct L2CAP connection times out!", .{});
        std.log.info("The Bluetooth daemon already has a connection.", .{});
        std.log.info("", .{});
        std.log.info("Solutions:", .{});
        std.log.info("", .{});
        std.log.info("1. Use gatttool to communicate:", .{});
        std.log.info("   sudo gatttool -b {s} -I", .{mac_addr});
        std.log.info("   > connect", .{});
        std.log.info("   > characteristics", .{});
        std.log.info("", .{});
        std.log.info("2. Disconnect from bluetoothd first:", .{});
        std.log.info("   sudo bluetoothctl disconnect {s}", .{mac_addr});
        std.log.info("   Then retry: sudo zig build run-zmk -- {s}", .{mac_addr});
        std.log.info("", .{});
        std.log.info("3. Use our helper script:", .{});
        std.log.info("   ./zmk-gatttool.sh {s}", .{mac_addr});
    } else {
        std.log.info("⚠️  Device is NOT currently connected via bluetoothd", .{});
        std.log.info("", .{});
        std.log.info("This might be why connection is timing out.", .{});
        std.log.info("", .{});
        std.log.info("Try connecting via bluetoothd first:", .{});
        std.log.info("  sudo bluetoothctl connect {s}", .{mac_addr});
        std.log.info("", .{});
        std.log.info("Or check if the device is powered on and in range.", .{});
    }
}

fn isConnectedViaBluetoothd(mac_addr: []const u8) !bool {
    // Try to check via /sys/class/bluetooth
    var buf: [256]u8 = undefined;
    
    // Find all bluetooth adapters
    const bt_path = "/sys/class/bluetooth";
    var dir = std.fs.openDirAbsolute(bt_path, .{ .iterate = true }) catch {
        std.log.warn("Cannot access {s}", .{bt_path});
        return false;
    };
    defer dir.close();

    // Format MAC for filesystem: AA:BB:CC:DD:EE:FF -> AA_BB_CC_DD_EE_FF
    var fs_mac: [17]u8 = undefined;
    var i: usize = 0;
    for (mac_addr) |c| {
        if (c == ':') {
            fs_mac[i] = '_';
        } else {
            fs_mac[i] = std.ascii.toUpper(c);
        }
        i += 1;
    }

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .sym_link) continue;
        
        // Check if this is our device (hciX)
        if (!std.mem.startsWith(u8, entry.name, "hci")) continue;
        
        // Check if device is connected
        const connected_path = try std.fmt.bufPrint(&buf, "{s}/{s}/dev_{s}/connected", .{ bt_path, entry.name, fs_mac[0..17] });
        
        const file = std.fs.openFileAbsolute(connected_path, .{}) catch continue;
        defer file.close();
        
        var content: [16]u8 = undefined;
        const bytes_read = try file.readAll(&content);
        
        if (bytes_read > 0 and content[0] == '1') {
            return true;
        }
    }
    
    return false;
}
