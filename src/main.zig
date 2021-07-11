const std = @import("std");
const wasm = @import("./wasm.zig");
const polyfill = @import("./polyfill.zig");
const vfs = @import("./vfs.zig");
const helper = @import("./helper.zig");

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace) noreturn {
    _ = error_return_trace;
    wasm.jserror("{s}", .{msg});
    @breakpoint();
    unreachable;
}

export fn sqlite3_os_init() c_int {
    polyfill.init();
    vfs.init();
    helper.init();
    return 0;
}

export fn sqlite3_os_end() c_int {
    return 0;
}
