const std = @import("std");
const zmk = @import("zmk_studio_dbus.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.log.info("Usage: {s} MAC:ADDRESS", .{args[0]});
        std.log.info("Example: {s} FC:82:CF:C8:47:32", .{args[0]});
        return;
    }

    const device_address = args[1];

    std.log.info("ZMK Studio Client (D-Bus version)", .{});
    std.log.info("===================================", .{});
    std.log.info("", .{});
    std.log.info("Device: {s}", .{device_address});
    std.log.info("", .{});
    std.log.info("This version uses the existing bluetoothd connection.", .{});
    std.log.info("You can keep typing while using this program!", .{});
    std.log.info("", .{});

    // Initialize client
    var client = try zmk.ZMKStudioClient.init(allocator);
    defer client.deinit();

    // Connect
    std.log.info("[1] Connecting to device...", .{});
    try client.connect(device_address);
    defer client.disconnect() catch {};

    std.log.info("", .{});
    std.log.info("[2] Checking lock state...", .{});
    const lock_state = client.getLockState() catch |err| {
        std.log.err("Failed to check lock state: {}", .{err});
        std.log.info("", .{});
        std.log.info("⚠️  Device may not have ZMK Studio support enabled.", .{});
        std.log.info("", .{});
        std.log.info("To enable ZMK Studio:", .{});
        std.log.info("  1. Add to your keyboard's .conf file:", .{});
        std.log.info("     CONFIG_ZMK_STUDIO=y", .{});
        std.log.info("  2. Rebuild and flash your firmware", .{});
        std.log.info("", .{});
        return err;
    };
    std.log.info("   Lock state: {s}", .{@tagName(lock_state)});

    if (lock_state == .locked) {
        std.log.info("", .{});
        std.log.info("🔒 Device is LOCKED", .{});
        std.log.info("", .{});
        std.log.info("To unlock your keyboard:", .{});
        std.log.info("  1. Press your unlock key combination (usually Layer + RCtrl + Backspace)", .{});
        std.log.info("  2. Run this program again", .{});
        std.log.info("", .{});
        std.log.info("If you don't have an unlock key:", .{});
        std.log.info("  1. Add '&studio_unlock' to your keymap", .{});
        std.log.info("  2. Or reflash with CONFIG_ZMK_STUDIO_LOCKING=n to disable locking", .{});
        std.log.info("", .{});
        return;
    }

    std.log.info("", .{});
    std.log.info("[3] Getting device info...", .{});
    var device_info = try client.getDeviceInfo();
    defer device_info.deinit();
    std.log.info("   Name: {s}", .{device_info.name});
    std.log.info("   Serial: {s}", .{device_info.serial_number});

    std.log.info("", .{});
    std.log.info("✅ Success! D-Bus communication working!", .{});
    std.log.info("", .{});
    std.log.info("The keyboard stayed connected the entire time.", .{});
}
