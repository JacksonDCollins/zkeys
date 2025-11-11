const std = @import("std");
const bluez = @import("bluez_ble.zig");

/// Simple tool to scan for BLE devices without bluetoothctl
/// Requires root permissions
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("BLE Device Scanner", .{});
    std.log.info("==================", .{});
    std.log.info("", .{});
    std.log.info("Note: This requires root permissions", .{});
    std.log.info("Run with: sudo zig build scan", .{});
    std.log.info("", .{});

    // Check if we have permissions
    const euid = std.os.linux.geteuid();
    if (euid != 0) {
        std.log.err("This program requires root permissions", .{});
        std.log.info("Run with: sudo zig build scan", .{});
        return error.PermissionDenied;
    }

    std.log.info("Scanning for BLE devices (10 seconds)...", .{});
    std.log.info("", .{});

    const devices = bluez.scanDevices(allocator, 10) catch |err| {
        std.log.err("Scan failed: {}", .{err});
        std.log.info("", .{});
        std.log.info("Alternative methods to find your keyboard:", .{});
        std.log.info("  1. Check pairing history: ls /var/lib/bluetooth/*/", .{});
        std.log.info("  2. Check system logs: sudo journalctl -u bluetooth", .{});
        std.log.info("  3. Use hcitool: sudo hcitool lescan", .{});
        return err;
    };
    defer allocator.free(devices);

    if (devices.len == 0) {
        std.log.info("No devices found.", .{});
        std.log.info("", .{});
        std.log.info("Make sure your keyboard is:", .{});
        std.log.info("  1. Powered on", .{});
        std.log.info("  2. In pairing/discoverable mode", .{});
        std.log.info("  3. Not already connected to another device", .{});
        return;
    }

    std.log.info("Found {} device(s):", .{devices.len});
    std.log.info("", .{});

    for (devices, 0..) |device, i| {
        var addr_buf: [18]u8 = undefined;
        const addr_str = try device.addr.toString(&addr_buf);
        
        std.log.info("[{}] {s}", .{ i + 1, addr_str });
        if (device.name_len > 0) {
            std.log.info("    Name: {s}", .{device.name[0..device.name_len]});
        }
        std.log.info("    RSSI: {} dBm", .{device.rssi});
        std.log.info("", .{});
    }

    std.log.info("To connect to a device, run:", .{});
    std.log.info("  sudo zig build run-zmk -- MAC:ADDRESS:HERE", .{});
}
