//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

const wgpu = @import("wgpu");
const sdl3 = @import("sdl3");

pub fn bufferedPrint() !void {
    // Stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try stdout.flush(); // Don't forget to flush!
}

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try std.testing.expect(add(3, 7) == 10);
}

const fps = 60;
const screen_width = 640;
const screen_height = 480;

pub fn render() !void {
    defer sdl3.shutdown();

    const init_flags = sdl3.InitFlags{
        .video = true,
    };
    try sdl3.init(init_flags);
    defer sdl3.quit(init_flags);

    const window = try sdl3.video.Window.init(
        "Zig WGPU Window",
        screen_width,
        screen_height,
        .{ .open_gl = true, .vulkan = false },
    );
    defer window.deinit();

    var fps_capper = sdl3.extras.FramerateCapper(f32){ .mode = .{ .limited = fps } };

    var quit = false;
    while (!quit) {
        const dt = fps_capper.delay();
        _ = dt;

        const surface = try window.getSurface();
        _ = surface;

        while (sdl3.events.poll()) |event| {
            switch (event) {
                .quit, .terminating => {
                    quit = true;
                },
                else => {},
            }
        }
    }
}
