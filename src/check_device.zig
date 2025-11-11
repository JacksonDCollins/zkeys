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
    
    std.log.info("Checking Bluetooth device: {s}", .{mac_addr});
    std.log.info("", .{});

    // Check if device is paired
    const paired = try checkPaired(mac_addr);
    if (paired) {
        std.log.info("✅ Device is PAIRED", .{});
    } else {
        std.log.info("❌ Device is NOT paired", .{});
        std.log.info("", .{});
        std.log.info("To pair the device:", .{});
        std.log.info("  1. Open System Settings → Bluetooth", .{});
        std.log.info("  2. Make sure your keyboard is in pairing mode", .{});
        std.log.info("  3. Click on it to pair", .{});
        std.log.info("", .{});
        std.log.info("Or use bluetoothctl if available:", .{});
        std.log.info("  sudo bluetoothctl", .{});
        std.log.info("  scan on", .{});
        std.log.info("  pair {s}", .{mac_addr});
        std.log.info("  trust {s}", .{mac_addr});
        return;
    }

    // Check if device info exists
    const info_exists = try checkDeviceInfo(mac_addr);
    if (info_exists) {
        std.log.info("✅ Device info found", .{});
    } else {
        std.log.info("⚠️  Device info not found (might still work)", .{});
    }

    // Try to read device name
    if (try readDeviceName(mac_addr)) |name| {
        std.log.info("📱 Device name: {s}", .{name});
    }

    std.log.info("", .{});
    std.log.info("Device looks ready to connect!", .{});
    std.log.info("Try: sudo zig build run-zmk -- {s}", .{mac_addr});
}

fn checkPaired(mac_addr: []const u8) !bool {
    const path = try std.fmt.allocPrint(
        std.heap.page_allocator,
        "/var/lib/bluetooth",
        .{},
    );
    defer std.heap.page_allocator.free(path);

    var dir = std.fs.openDirAbsolute(path, .{ .iterate = true }) catch {
        std.log.warn("Cannot access {s} (need sudo?)", .{path});
        return false;
    };
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .directory) continue;

        // Check if this adapter has the device
        const device_path = try std.fmt.allocPrint(
            std.heap.page_allocator,
            "/var/lib/bluetooth/{s}/{s}",
            .{ entry.name, mac_addr },
        );
        defer std.heap.page_allocator.free(device_path);

        const stat = std.fs.cwd().statFile(device_path) catch continue;
        _ = stat;
        return true; // Found it!
    }

    return false;
}

fn checkDeviceInfo(mac_addr: []const u8) !bool {
    const path = try std.fmt.allocPrint(
        std.heap.page_allocator,
        "/var/lib/bluetooth",
        .{},
    );
    defer std.heap.page_allocator.free(path);

    var dir = std.fs.openDirAbsolute(path, .{ .iterate = true }) catch {
        return false;
    };
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .directory) continue;

        const info_path = try std.fmt.allocPrint(
            std.heap.page_allocator,
            "/var/lib/bluetooth/{s}/{s}/info",
            .{ entry.name, mac_addr },
        );
        defer std.heap.page_allocator.free(info_path);

        const stat = std.fs.cwd().statFile(info_path) catch continue;
        _ = stat;
        return true;
    }

    return false;
}

fn readDeviceName(mac_addr: []const u8) !?[]const u8 {
    const path = try std.fmt.allocPrint(
        std.heap.page_allocator,
        "/var/lib/bluetooth",
        .{},
    );
    defer std.heap.page_allocator.free(path);

    var dir = std.fs.openDirAbsolute(path, .{ .iterate = true }) catch {
        return null;
    };
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .directory) continue;

        const info_path = try std.fmt.allocPrint(
            std.heap.page_allocator,
            "/var/lib/bluetooth/{s}/{s}/info",
            .{ entry.name, mac_addr },
        );
        defer std.heap.page_allocator.free(info_path);

        const file = std.fs.cwd().openFile(info_path, .{}) catch continue;
        defer file.close();

        const content = try file.readToEndAlloc(std.heap.page_allocator, 4096);
        defer std.heap.page_allocator.free(content);

        // Parse for Name= line
        var lines = std.mem.splitSequence(u8, content, "\n");
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "Name=")) {
                const name = line[5..];
                return try std.heap.page_allocator.dupe(u8, name);
            }
        }
    }

    return null;
}
