const std = @import("std");
const wasm = @import("./wasm.zig");

const IoMethods = extern struct {
    version: c_int = 1,
    x_close: fn (self: *File) callconv(.C) c_int,
    x_read: fn (self: *File, buf: [*:0]u8, count: c_int, offset: i64) callconv(.C) c_int,
    x_write: fn (self: *File, buf: [*:0]const u8, count: c_int, offset: i64) callconv(.C) c_int,
    x_truncate: fn (self: *File, size: i64) callconv(.C) c_int,
    x_sync: fn (self: *File, flag: c_int) callconv(.C) c_int,
    x_size: fn (self: *File, p_size: *i64) callconv(.C) c_int,
    x_lock: fn (self: *File, flag: c_int) callconv(.C) c_int,
    x_unlock: fn (self: *File, flag: c_int) callconv(.C) c_int,
    x_check_reserved_lock: fn (self: *File, p_result: *c_int) callconv(.C) c_int,
    x_control: fn (self: *File, op: c_int, arg: *anyopaque) callconv(.C) c_int,
    x_sector_size: fn (self: *File) callconv(.C) c_int,
    x_device_characteristics: fn (self: *File) callconv(.C) c_int,
};

const File = extern struct {
    io_methods: *const IoMethods,
    fd: wasm.FileDescriptor,
};

fn vfs_file_close(self: *File) callconv(.C) c_int {
    wasm.fs_close(self.fd);
    return 0;
}

fn vfs_file_read(self: *File, buf: [*]u8, count: c_int, offset: i64) callconv(.C) c_int {
    const len = wasm.fs_read(self.fd, buf, @intCast(usize, count), @intCast(usize, offset));
    if (len < count) {
        std.mem.set(u8, buf[@intCast(usize, len)..@intCast(usize, count)], 0);
        return 522;
    } else if (len != count) {
        return 266;
    } else {
        return 0;
    }
}

fn vfs_file_write(self: *File, buf: [*]const u8, count: c_int, offset: i64) callconv(.C) c_int {
    wasm.fs_write(self.fd, buf, @intCast(usize, count), @intCast(usize, offset));
    return 0;
}

fn vfs_file_truncate(self: *File, size: i64) callconv(.C) c_int {
    wasm.fs_truncate(self.fd, @intCast(usize, size));
    return 0;
}

fn vfs_file_size(self: *File, p_size: *i64) callconv(.C) c_int {
    p_size.* = @intCast(i64, wasm.fs_filesize(self.fd));
    return 0;
}

fn vfs_file_dummy(self: *File, flag: c_int) callconv(.C) c_int {
    _ = self;
    _ = flag;
    return 0;
}

fn vfs_file_dummy_check(self: *File, p_result: *c_int) callconv(.C) c_int {
    _ = self;
    _ = p_result;
    return 0;
}

fn vfs_file_control(self: *File, op: c_int, arg: *anyopaque) callconv(.C) c_int {
    _ = self;
    _ = op;
    _ = arg;
    return 12; // SQLITE_NOTFOUND
}

fn vfs_file_dummy_sector(self: *File) callconv(.C) c_int {
    _ = self;
    return 0;
}

fn vfs_device_characteristics(self: *File) callconv(.C) c_int {
    _ = self;
    return 1; // SQLITE_IOCAP_ATOMIC
}

const base_methods = IoMethods{
    .x_close = vfs_file_close,
    .x_read = vfs_file_read,
    .x_write = vfs_file_write,
    .x_truncate = vfs_file_truncate,
    .x_sync = vfs_file_dummy,
    .x_size = vfs_file_size,
    .x_lock = vfs_file_dummy,
    .x_unlock = vfs_file_dummy,
    .x_check_reserved_lock = vfs_file_dummy_check,
    .x_control = vfs_file_control,
    .x_sector_size = vfs_file_dummy_sector,
    .x_device_characteristics = vfs_device_characteristics,
};

const VFS = extern struct {
    const Self = @This();

    version: c_int = 1,
    file_size: c_int,
    max_pathname: c_int,
    next: usize = 0,
    name: [*:0]const u8,
    appdata: ?*anyopaque,
    x_open: fn (self: *Self, name: [*:0]const u8, file: *File, flags: c_int, out_flags: *c_int) callconv(.C) c_int,
    x_delete: fn (self: *Self, name: [*:0]const u8, sync_dir: c_int) callconv(.C) c_int,
    x_access: fn (self: *Self, name: [*:0]const u8, flags: c_int, out_flags: *c_int) callconv(.C) c_int,
    x_fullname: fn (self: *Self, name: [*:0]const u8, n_out: c_int, out_name: [*:0]u8) callconv(.C) c_int,
    x_dlopen: usize = 0,
    x_dlerror: usize = 0,
    x_dlsym: usize = 0,
    x_dlclose: usize = 0,
    x_random: fn (self: *Self, size: usize, buf: [*:0]u8) callconv(.C) c_int,
    x_sleep: fn (self: *Self, microseconds: c_int) callconv(.C) c_int,
    x_current_time: fn (self: *Self, p_time: *f64) callconv(.C) c_int,
};

fn vfs_open(self: *VFS, name: [*:0]const u8, file: *File, flags: c_int, out_flags: *c_int) callconv(.C) c_int {
    _ = self;
    out_flags.* = 0;
    const fd = wasm.fs_open(name, std.mem.len(name), flags);
    if (fd == .invalid) {
        return 1;
    }
    file.io_methods = &base_methods;
    file.fd = fd;
    return 0;
}

fn vfs_delete(self: *VFS, name: [*:0]const u8, sync_dir: c_int) callconv(.C) c_int {
    _ = self;
    _ = sync_dir;
    if (wasm.fs_delete(name, std.mem.len(name))) {
        return 0;
    } else {
        return 1;
    }
}

fn vfs_access(self: *VFS, name: [*:0]const u8, flags: c_int, out_flags: *c_int) callconv(.C) c_int {
    _ = self;
    _ = flags;
    if (wasm.fs_access(name, std.mem.len(name), flags)) {
        out_flags.* = 1;
    } else {
        out_flags.* = 0;
    }
    return 0;
}

fn vfs_fullname(self: *VFS, name: [*:0]const u8, n_out: c_int, out_name: [*:0]u8) callconv(.C) c_int {
    _ = self;
    const len = std.math.min(std.mem.len(name), @intCast(usize, n_out));
    @memcpy(out_name, name, len);
    return 0;
}

fn vfs_random(self: *VFS, size: usize, buf: [*]u8) callconv(.C) c_int {
    _ = self;
    wasm.fill_random(buf, size);
    return 0;
}

fn vfs_sleep(self: *VFS, microseconds: c_int) callconv(.C) c_int {
    _ = self;
    _ = microseconds;
    return 0;
}

fn vfs_current_time(self: *VFS, p_time: *f64) callconv(.C) c_int {
    _ = self;
    p_time.* = wasm.get_time();
    return 0;
}

const vfs = VFS{
    .version = 1,
    .file_size = @as(c_int, @sizeOf(File)),
    .max_pathname = 128,
    .name = "wasm",
    .appdata = null,
    .x_open = vfs_open,
    .x_delete = vfs_delete,
    .x_access = vfs_access,
    .x_fullname = vfs_fullname,
    .x_random = vfs_random,
    .x_sleep = vfs_sleep,
    .x_current_time = vfs_current_time,
};

extern fn sqlite3_vfs_register(vfs: *const VFS, make_default: c_int) c_int;

pub fn init() void {
    _ = sqlite3_vfs_register(&vfs, 1);
}
