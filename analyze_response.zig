const std = @import("std");

pub fn main() !void {
    // Unframed protobuf: { 10, 6, 8, 1, 26, 2, 16, 1 }
    const data = [_]u8{ 10, 6, 8, 1, 26, 2, 16, 1 };
    
    std.debug.print("Protobuf bytes: {any}\n", .{data});
    std.debug.print("As hex: ", .{});
    for (data) |byte| {
        std.debug.print("{X:0>2} ", .{byte});
    }
    std.debug.print("\n\n", .{});
    
    // Parse wire format
    std.debug.print("Field analysis:\n", .{});
    var i: usize = 0;
    while (i < data.len) {
        const tag = data[i];
        const field_num = tag >> 3;
        const wire_type = tag & 0x7;
        std.debug.print("  Byte {d}: 0x{X:0>2} -> Field#{d}, WireType{d}", .{i, tag, field_num, wire_type});
        
        if (wire_type == 0) { // Varint
            i += 1;
            std.debug.print(" (varint: {d})\n", .{data[i]});
        } else if (wire_type == 2) { // Length-delimited
            i += 1;
            const len = data[i];
            std.debug.print(" (length: {d}, data: {any})\n", .{len, data[i+1..@min(i+1+len, data.len)]});
            i += len;
        } else {
            std.debug.print("\n", .{});
        }
        i += 1;
    }
}
