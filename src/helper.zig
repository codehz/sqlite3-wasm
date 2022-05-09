const std = @import("std");
const wasm = @import("./wasm.zig");

export var helper_errno: c_int = 0;
export var helper_swap: [32]c_int = [1]c_int{0} ** 32;

extern fn sqlite3_open(filename: [*:0]const u8, out: *?*anyopaque) c_int;
extern fn sqlite3_exec(
    db: ?*anyopaque,
    sql: [*:0]const u8,
    callback: ?*anyopaque,
    payload: ?*anyopaque,
    errmsg: ?*?[*:0]const u8,
) c_int;

export fn helper_open(filename: [*:0]const u8) ?*anyopaque {
    var ret: ?*anyopaque = null;
    helper_errno = sqlite3_open(filename, &ret);
    if (helper_errno == 0) {
        helper_errno = sqlite3_exec(ret, "PRAGMA journal_mode=OFF", null, null, null);
        helper_errno = sqlite3_exec(ret, "PRAGMA synchronous=OFF", null, null, null);
    }
    return ret;
}

extern fn sqlite3_prepare_v3(
    db: *anyopaque,
    sql: [*:0]const u8,
    nbytes: c_int,
    flags: u32,
    pstmt: *?*anyopaque,
    ptail: ?*?[*:0]const u8,
) c_int;

export fn helper_prepare(db: *anyopaque, sql: [*:0]const u8, flags: u32) ?*anyopaque {
    var ret: ?*anyopaque = null;
    helper_errno = sqlite3_prepare_v3(db, sql, -1, flags, &ret, null);
    return ret;
}

extern fn sqlite3_bind_blob(
    stmt: *anyopaque,
    idx: c_int,
    data: [*]const u8,
    len: c_int,
    dealloc: isize,
) c_int;

export fn helper_bind_blob(stmt: *anyopaque, idx: c_int, data: [*]const u8, len: c_int) void {
    helper_errno = sqlite3_bind_blob(stmt, idx, data, len, -1);
}

extern fn sqlite3_bind_text(
    stmt: *anyopaque,
    idx: c_int,
    data: [*]const u8,
    len: c_int,
    dealloc: isize,
) c_int;

export fn helper_bind_text(stmt: *anyopaque, idx: c_int, data: [*]const u8, len: c_int) void {
    helper_errno = sqlite3_bind_text(stmt, idx, data, len, -1);
}

extern fn sqlite3session_create(db: *anyopaque, name: [*:0]const u8, out: *?*anyopaque) c_int;

export fn helper_session_create(db: *anyopaque, name: [*:0]const u8) ?*anyopaque {
    var ret: ?*anyopaque = null;
    helper_errno = sqlite3session_create(db, name, &ret);
    return ret;
}

extern fn sqlite3session_changeset(
    session: *anyopaque,
    p_length: *c_int,
    p_buffer: *?[*]const u8,
) c_int;

export fn helper_session_changeset(session: *anyopaque) ?[*]const u8 {
    var ret: ?[*]const u8 = null;
    helper_errno = sqlite3session_changeset(session, &helper_swap[0], &ret);
    return ret;
}

extern fn sqlite3session_patchset(
    session: *anyopaque,
    p_length: *c_int,
    p_buffer: *?[*]const u8,
) c_int;

export fn helper_session_patchset(session: *anyopaque) ?[*]const u8 {
    var ret: ?[*]const u8 = null;
    helper_errno = sqlite3session_patchset(session, &helper_swap[0], &ret);
    return ret;
}

extern fn sqlite3changeset_start(iter: *?*anyopaque, length: c_int, buffer: [*]const u8) c_int;

export fn helper_changeset_start(buffer: [*]const u8, length: c_int) ?*anyopaque {
    var ret: ?*anyopaque = null;
    helper_errno = sqlite3changeset_start(&ret, length, buffer);
    return ret;
}

extern fn sqlite3changeset_op(
    iter: *anyopaque,
    name: *?[*:0]const u8,
    p_col: *c_int,
    p_op: *c_int,
    p_indirect: *c_int,
) c_int;

export fn helper_changeset_op(iter: *anyopaque) ?[*:0]const u8 {
    var ret: ?[*:0]const u8 = null;
    helper_errno = sqlite3changeset_op(
        iter,
        &ret,
        &helper_swap[0],
        &helper_swap[1],
        &helper_swap[2],
    );
    return ret;
}

extern fn sqlite3changeset_new(iter: *anyopaque, col: c_int, out: *?*anyopaque) c_int;

export fn helper_changeset_new(iter: *anyopaque, col: c_int) ?*anyopaque {
    var ret: ?*anyopaque = null;
    helper_errno = sqlite3changeset_new(iter, col, &ret);
    return ret;
}

extern fn sqlite3changeset_old(iter: *anyopaque, col: c_int, out: *?*anyopaque) c_int;

export fn helper_changeset_old(iter: *anyopaque, col: c_int) ?*anyopaque {
    var ret: ?*anyopaque = null;
    helper_errno = sqlite3changeset_old(iter, col, &ret);
    return ret;
}

extern fn sqlite3changeset_apply(
    db: *anyopaque,
    length: c_int,
    buffer: [*]const u8,
    filter: fn (ctx: usize, name: [*:0]const u8) callconv(.C) c_int,
    conflict: fn (ctx: usize, kind: c_int, iter: *anyopaque) callconv(.C) c_int,
    ctx: usize,
) c_int;

export fn helper_changeset_apply(
    db: *anyopaque,
    buffer: [*]const u8,
    length: c_int,
    ctx: usize,
) void {
    helper_errno = sqlite3changeset_apply(
        db,
        length,
        buffer,
        wasm.session_filter,
        wasm.session_conflict,
        ctx,
    );
}

extern fn sqlite3changeset_conflict(iter: *anyopaque, column: c_int, value: *?*anyopaque) c_int;

export fn helper_changeset_conflict(iter: *anyopaque, column: c_int) ?*anyopaque {
    var ret: ?*anyopaque = null;
    helper_errno = sqlite3changeset_conflict(iter, column, &ret);
    return ret;
}

extern fn sqlite3_config(id: c_int, ...) c_int;

fn sqllog(_: *anyopaque, errcode: i32, msg: [*:0]const u8) callconv(.C) void {
    wasm.jserror("SQL ERROR({}): {s}", .{ errcode, msg });
}

pub fn init() void {
    const SQLITE_CONFIG_LOG = 16;
    _ = sqlite3_config(SQLITE_CONFIG_LOG, sqllog, @as(usize, 0));
}
