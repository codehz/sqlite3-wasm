const std = @import("std");

fn setArguments(step: *std.build.LibExeObjStep, args: []const u8) void {
    var iter = std.mem.split(u8, args, "\n");
    while (iter.next()) |line| {
        var eq = std.mem.split(u8, line, "=");
        const key = eq.next() orelse unreachable;
        const value = eq.next();
        step.defineCMacro(key[2..], value);
    }
}

pub fn build(b: *std.build.Builder) void {
    const mode = .ReleaseSmall;
    const target = std.zig.CrossTarget.parse(.{ .arch_os_abi = "wasm32-freestanding-musl" }) catch unreachable;

    const envlib = b.addObject("env", "src/main.zig");
    envlib.strip = true;
    envlib.setBuildMode(mode);
    envlib.setTarget(target);

    const lib = b.addSharedLibrary("sqlite3", null, .unversioned);
    setArguments(lib, @embedFile("arguments.txt"));
    lib.strip = true;
    lib.linkLibC();
    lib.addObject(envlib);
    lib.addCSourceFile("sqlite3/sqlite3.c", &.{});
    lib.setBuildMode(mode);
    lib.setTarget(target);
    lib.install();
}
