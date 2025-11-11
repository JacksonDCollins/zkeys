const std = @import("std");

pub fn main() !void {
    // The response we got: { 182, 129, 4, 181, 229, 44, 175, 59 }
    // In hex: { 0xB6, 0x81, 0x04, 0xB5, 0xE5, 0x2C, 0xAF, 0x3B }
    
    const data = [_]u8{ 182, 129, 4, 181, 229, 44, 175, 59 };
    
    std.debug.print("Raw bytes: {any}\n", .{data});
    std.debug.print("As hex: ", .{});
    for (data) |byte| {
        std.debug.print("{X:0>2} ", .{byte});
    }
    std.debug.print("\n", .{});
    
    // Check if this looks like protobuf
    // Protobuf wire format: tag = (field_number << 3) | wire_type
    // 0xB6 = 182 = 10110110 binary
    // field_number = 182 >> 3 = 22
    // wire_type = 182 & 0x7 = 6
    
    std.debug.print("\nFirst byte analysis:\n", .{});
    std.debug.print("  Byte: 0x{X:0>2} = {d}\n", .{data[0], data[0]});
    std.debug.print("  Field number: {d}\n", .{data[0] >> 3});
    std.debug.print("  Wire type: {d}\n", .{data[0] & 0x7});
}
