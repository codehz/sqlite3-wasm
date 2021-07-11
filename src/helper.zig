const std = @import("std");
const wasm = @import("./wasm.zig");

export var helper_errno: c_int = 0;

extern fn sqlite3_open(filename: [*:0]const u8, out: *?*c_void) c_int;
extern fn sqlite3_exec(
    db: ?*c_void,
    sql: [*:0]const u8,
    callback: ?*c_void,
    payload: ?*c_void,
    errmsg: ?*?[*:0]const u8,
) c_int;

export fn helper_open(filename: [*:0]const u8) ?*c_void {
    var ret: ?*c_void = null;
    helper_errno = sqlite3_open(filename, &ret);
    if (helper_errno == 0) {
        helper_errno = sqlite3_exec(ret, "PRAGMA journal_mode=OFF", null, null, null);
        helper_errno = sqlite3_exec(ret, "PRAGMA synchronous=OFF", null, null, null);
    }
    return ret;
}

extern fn sqlite3_prepare_v3(
    db: *c_void,
    sql: [*:0]const u8,
    nbytes: c_int,
    flags: u32,
    pstmt: *?*c_void,
    ptail: ?*?[*:0]const u8,
) c_int;

export fn helper_prepare(db: *c_void, sql: [*:0]const u8, flags: u32) ?*c_void {
    var ret: ?*c_void = null;
    helper_errno = sqlite3_prepare_v3(db, sql, -1, flags, &ret, null);
    return ret;
}

extern fn sqlite3_bind_blob(
    stmt: *c_void,
    idx: c_int,
    data: [*]const u8,
    len: c_int,
    dealloc: isize,
) c_int;

export fn helper_bind_blob(stmt: *c_void, idx: c_int, data: [*]const u8, len: c_int) void {
    helper_errno = sqlite3_bind_blob(stmt, idx, data, len, -1);
}

extern fn sqlite3_bind_text(
    stmt: *c_void,
    idx: c_int,
    data: [*]const u8,
    len: c_int,
    dealloc: isize,
) c_int;

export fn helper_bind_text(stmt: *c_void, idx: c_int, data: [*]const u8, len: c_int) void {
    helper_errno = sqlite3_bind_text(stmt, idx, data, len, -1);
}

extern fn sqlite3_config(id: c_int, ...) c_int;

fn sqllog(_: *c_void, errcode: i32, msg: [*:0]const u8) callconv(.C) void {
    wasm.jserror("SQL ERROR({}): {s}", .{ errcode, msg });
}

pub fn init() void {
    const SQLITE_CONFIG_LOG = 16;
    _ = sqlite3_config(SQLITE_CONFIG_LOG, sqllog, @as(usize, 0));
}
