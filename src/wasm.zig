const std = @import("std");

pub extern "host" fn console_log(msg: [*]const u8, msg_len: usize) void;
pub extern "host" fn console_error(msg: [*]const u8, msg_len: usize) void;

var buffer: [1024]u8 = undefined;

fn myfmt(comptime format: []const u8, args: anytype) []const u8 {
    if (comptime std.mem.eql(u8, format, "{s}")) {
        const ret = args.@"0";
        return switch (@TypeOf(ret)) {
            [*:0]const u8 => std.mem.span(ret),
            else => ret,
        };
    }
    return std.fmt.bufPrint(&buffer, format, args) catch unreachable;
}

pub inline fn jslog(comptime format: []const u8, args: anytype) void {
    const msg = myfmt(format, args);
    console_log(msg.ptr, msg.len);
}

pub inline fn jserror(comptime format: []const u8, args: anytype) void {
    const msg = myfmt(format, args);
    console_log(msg.ptr, msg.len);
}

export fn debug_log(msg: [*:0]const u8) void {
    jslog("{s}", .{msg});
}

export fn debug_log_num(msg: [*:0]const u8, value: c_int) void {
    jslog("{s} {}", .{ msg, value });
}

pub const FileDescriptor = enum(c_int) {
    invalid,
    _,
};

pub extern "host" fn get_time() f64;
pub extern "host" fn fill_random(buffer: [*]u8, size: usize) void;
pub extern "host" fn fs_access(filename: [*]const u8, length: usize, flags: c_int) bool;
pub extern "host" fn fs_open(filename: [*]const u8, length: usize, flags: c_int) FileDescriptor;
pub extern "host" fn fs_close(fd: FileDescriptor) void;
pub extern "host" fn fs_delete(filename: [*]const u8, length: usize) bool;
pub extern "host" fn fs_read(fd: FileDescriptor, buffer: [*]u8, length: usize, offset: usize) c_int;
pub extern "host" fn fs_write(fd: FileDescriptor, buffer: [*]const u8, length: usize, offset: usize) void;
pub extern "host" fn fs_truncate(fd: FileDescriptor, length: usize) void;
pub extern "host" fn fs_filesize(fd: FileDescriptor) usize;

pub extern "session" fn session_filter(ctx: usize, name: [*:0]const u8) c_int;
pub extern "session" fn session_conflict(ctx: usize, kind: c_int, iter: *c_void) c_int;