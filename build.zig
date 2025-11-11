const std = @import("std");
const zemscripten = @import("zemscripten");
const protobuf = @import("protobuf");

fn buildBin(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) !void {
    const pbuf_dep = b.dependency("pbufzmk", .{});
    const proto_files = b.addInstallDirectory(.{
        .source_dir = pbuf_dep.path("proto"),
        .install_dir = .prefix,
        .install_subdir = "proto",
    });

    // first create a build for the dependency
    const protobuf_dep = b.dependency("protobuf", .{
        .target = target,
        .optimize = optimize,
    });
    const gen_proto = b.step("gen-proto", "generates zig files from protocol buffer definitions");

    const dir = b.pathJoin(
        &.{ b.getInstallPath(
            proto_files.options.install_dir,
            proto_files.options.install_subdir,
        ), "zmk" },
    );
    const protoc_step = protobuf.RunProtocStep.create(protobuf_dep.builder, target, .{
        // out directory for the generated zig files
        .destination_directory = b.path("src/proto"),
        .source_files = files: {
            var adir = try std.fs.openDirAbsolute(dir, .{ .iterate = true });
            defer adir.close();

            var it = try adir.walk(b.allocator);
            defer it.deinit();

            var files = try std.ArrayList([]const u8).initCapacity(b.allocator, 16);
            while (try it.next()) |entry| {
                if (entry.kind != .file) continue;
                if (std.mem.endsWith(u8, entry.path, ".proto")) {
                    const file_path = b.pathJoin(&.{ dir, entry.path });
                    try files.append(b.allocator, file_path);
                    std.debug.print(
                        "Found proto file: {s}\n",
                        .{
                            file_path,
                        },
                    );
                }
            }
            break :files try files.toOwnedSlice(b.allocator);
        },
        .include_directories = &.{dir},
    });
    protoc_step.step.dependOn(&proto_files.step);
    gen_proto.dependOn(&protoc_step.step);

    // Build main SDL3 application
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const exe = b.addExecutable(.{
        .name = "template",
        .root_module = exe_mod,
    });

    const sdl3 = b.dependency("sdl3", .{
        .target = target,
        .optimize = optimize,
        .callbacks = true,
        .ext_image = true,
    });
    exe.root_module.addImport("sdl3", sdl3.module("sdl3"));
    exe.root_module.addImport("protobuf", protobuf_dep.module("protobuf"));
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Build ZMK Studio D-Bus example
    const zmk_dbus_mod = b.createModule(.{
        .root_source_file = b.path("src/zmk_example_dbus.zig"),
        .target = target,
        .optimize = optimize,
    });
    const zmk_dbus = b.addExecutable(.{
        .name = "zmk-dbus",
        .root_module = zmk_dbus_mod,
    });

    zmk_dbus.root_module.addImport("protobuf", protobuf_dep.module("protobuf"));
    zmk_dbus.linkLibC();
    zmk_dbus.linkSystemLibrary("dbus-1");
    b.installArtifact(zmk_dbus);

    const run_dbus_cmd = b.addRunArtifact(zmk_dbus);
    run_dbus_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_dbus_cmd.addArgs(args);
    }

    const run_dbus_step = b.step("run-dbus", "Run the ZMK Studio example (D-Bus version)");
    run_dbus_step.dependOn(&run_dbus_cmd.step);

    // Build device scanner
    const scan_mod = b.createModule(.{
        .root_source_file = b.path("src/scan_devices.zig"),
        .target = target,
        .optimize = optimize,
    });
    const scan_exe = b.addExecutable(.{
        .name = "scan-devices",
        .root_module = scan_mod,
    });

    scan_exe.linkLibC();
    scan_exe.linkSystemLibrary("bluetooth");
    b.installArtifact(scan_exe);

    const run_scan_cmd = b.addRunArtifact(scan_exe);
    run_scan_cmd.step.dependOn(b.getInstallStep());

    const run_scan_step = b.step("scan", "Scan for Bluetooth devices");
    run_scan_step.dependOn(&run_scan_cmd.step);

    // Build device checker
    const check_mod = b.createModule(.{
        .root_source_file = b.path("src/check_device.zig"),
        .target = target,
        .optimize = optimize,
    });
    const check_exe = b.addExecutable(.{
        .name = "check-device",
        .root_module = check_mod,
    });

    b.installArtifact(check_exe);

    const run_check_cmd = b.addRunArtifact(check_exe);
    run_check_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_check_cmd.addArgs(args);
    }

    const run_check_step = b.step("check", "Check if a device is paired");
    run_check_step.dependOn(&run_check_cmd.step);

    // Build connection checker
    const conn_mod = b.createModule(.{
        .root_source_file = b.path("src/check_connection.zig"),
        .target = target,
        .optimize = optimize,
    });
    const conn_exe = b.addExecutable(.{
        .name = "check-connection",
        .root_module = conn_mod,
    });

    b.installArtifact(conn_exe);

    const run_conn_cmd = b.addRunArtifact(conn_exe);
    run_conn_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_conn_cmd.addArgs(args);
    }

    const run_conn_step = b.step("check-conn", "Check if device is connected via bluetoothd");
    run_conn_step.dependOn(&run_conn_cmd.step);
}

fn buildWeb(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) !void {
    const activateEmsdk = zemscripten.activateEmsdkStep(b);
    b.default_step.dependOn(activateEmsdk);

    const wasm = b.addLibrary(.{
        .name = "template",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
        .linkage = .static,
    });

    const zemscripten_dep = b.dependency("zemscripten", .{});
    wasm.root_module.addImport("zemscripten", zemscripten_dep.module("root"));

    const emsdk_dep = b.dependency("emsdk", .{});
    const emsdk_sysroot_path = emsdk_dep.path("upstream/emscripten/cache/sysroot");
    const emsdk_sysroot_include_path = emsdk_dep.path("upstream/emscripten/cache/sysroot/include");

    const sdl3 = b.dependency("sdl3", .{
        .target = target,
        .optimize = optimize,
        .callbacks = true,
        .ext_image = true,
        .sdl_system_include_path = emsdk_sysroot_include_path,
        .sdl_sysroot_path = emsdk_sysroot_path,
    });

    wasm.root_module.addSystemIncludePath(emsdk_sysroot_include_path);

    const sdl_module = sdl3.module("sdl3");
    sdl_module.addSystemIncludePath(emsdk_sysroot_include_path);
    wasm.root_module.addImport("sdl3", sdl3.module("sdl3"));
    wasm.addSystemIncludePath(emsdk_sysroot_include_path);

    const emcc_flags = zemscripten.emccDefaultFlags(b.allocator, .{
        .optimize = optimize,
        .fsanitize = true,
    });

    var emcc_settings = zemscripten.emccDefaultSettings(b.allocator, .{
        .optimize = optimize,
    });
    try emcc_settings.put("ALLOW_MEMORY_GROWTH", "1");
    emcc_settings.put("USE_SDL", "3") catch unreachable;

    const emcc_step = zemscripten.emccStep(
        b,
        wasm,
        .{
            .optimize = optimize,
            .flags = emcc_flags, // Pass the modified flags
            .settings = emcc_settings,
            .use_preload_plugins = true,
            .embed_paths = &.{},
            .preload_paths = &.{},
            .install_dir = .{ .custom = "web" },
            .shell_file_path = b.path("src/html/shell.html"),
        },
    );

    b.getInstallStep().dependOn(emcc_step);

    const base_name = if (wasm.name_only_filename) |n| n else wasm.name;

    // Create filename with extension
    const html_file = try std.fmt.allocPrint(b.allocator, "{s}.html", .{base_name});
    defer b.allocator.free(html_file);

    std.debug.print("HTML FILE: {s}\n", .{html_file});

    // output set in emcc_step
    const html_path = b.pathJoin(&.{ "zig-out", "web", html_file });

    std.debug.print("HTML PATH: {s}\n", .{html_path});

    // Absolute path to emrun
    const emrun_path = emsdk_dep.path("upstream/emscripten/emrun");

    // System command
    const emrun_cmd = b.addSystemCommand(&.{
        emrun_path.getPath(b),
        "--port",
        b.fmt("{d}", .{b.option(u16, "port", "Port to run the webapp on (default: 8080)") orelse 8080}),
        html_path,
    });

    emrun_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app (via emrun)");
    run_step.dependOn(&emrun_cmd.step);

    if (b.args) |args| {
        emrun_cmd.addArgs(args);
    }
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const os = target.result.os.tag;
    if (os == .emscripten) {
        try buildWeb(b, target, optimize);
    } else {
        try buildBin(b, target, optimize);
    }
}
