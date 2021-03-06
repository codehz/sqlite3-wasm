const std = @import("std");
const wasm = @import("./wasm.zig");

pub fn init() void {}

var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
var allocator = gpa.allocator();
const pointersize = @sizeOf(usize);

export fn strcmp(a: [*:0]const u8, b: [*:0]const u8) c_int {
    return @as(c_int, std.cstr.cmp(a, b));
}

export fn memcpy(dest: [*]u8, src: [*]const u8, len: usize) [*]u8 {
    std.mem.copy(u8, dest[0..len], src[0..len]);
    return dest;
}

export fn strlen(src: [*:0]u8) usize {
    return std.mem.len(src);
}

export fn memset(ptr: [*]u8, c: u8, byte_count: usize) [*]u8 {
    std.mem.set(u8, ptr[0..byte_count], c);
    return ptr;
}

export fn memcmp(a: [*]const u8, b: [*]const u8, len: usize) c_int {
    return switch (std.mem.order(u8, a[0..len], b[0..len])) {
        .gt => 1,
        .lt => -1,
        .eq => 0,
    };
}

export fn strcspn(dest: [*:0]const u8, src: [*:0]const u8) usize {
    const dspan = std.mem.span(dest);
    return std.mem.indexOfAny(u8, dspan, std.mem.span(src)) orelse dspan.len;
}

export fn memmove(dest: [*]u8, src: [*]const u8, len: usize) [*]u8 {
    switch (std.math.order(@ptrToInt(dest), @ptrToInt(src))) {
        .lt => std.mem.copy(u8, dest[0..len], src[0..len]),
        .gt => std.mem.copyBackwards(u8, dest[0..len], src[0..len]),
        .eq => {},
    }
    return dest;
}

export fn strncmp(a: [*:0]const u8, b: [*:0]const u8, len: usize) c_int {
    const alen = std.math.min(std.mem.len(a), len);
    const blen = std.math.min(std.mem.len(b), len);
    return switch (std.mem.order(u8, a[0..alen], b[0..blen])) {
        .gt => 1,
        .lt => -1,
        .eq => 0,
    };
}

export fn strrchr(src: [*:0]const u8, char: u8) ?[*:0]const u8 {
    const pos = std.mem.lastIndexOfScalar(u8, std.mem.span(src), char) orelse return null;
    return @intToPtr(?[*:0]const u8, @ptrToInt(src) + pos);
}

pub export fn malloc(size: usize) ?*anyopaque {
    const ret = allocator.alloc(u8, size + pointersize) catch return null;
    const ptr = @ptrToInt(ret.ptr);
    @intToPtr(*usize, ptr).* = size;
    return @intToPtr(*anyopaque, ptr + pointersize);
}

pub export fn free(ptr: ?*anyopaque) void {
    if (ptr == null) {
        return;
    }
    const addr = @ptrToInt(ptr) - pointersize;
    const len = @intToPtr(*usize, addr).*;
    allocator.free(@intToPtr([*]u8, addr)[0..len]);
}

pub export fn malloc_usable_size(ptr: ?*anyopaque) usize {
    if (ptr == null) {
        return 0;
    }
    const addr = @ptrToInt(ptr) - pointersize;
    return @intToPtr(*usize, addr).*;
}

inline fn toRawPtr(ptr: []u8) *anyopaque {
    const addr = @ptrToInt(ptr.ptr);
    @intToPtr(*usize, addr).* = ptr.len - pointersize;
    return @intToPtr(*anyopaque, addr + pointersize);
}

pub export fn realloc(ptr: ?*anyopaque, size: usize) ?*anyopaque {
    if (ptr == null) {
        return null;
    }
    const addr = @ptrToInt(ptr) - pointersize;
    const old_size = @intToPtr(*usize, addr).*;
    const orig = @intToPtr([*]u8, addr)[0 .. old_size + pointersize];
    if (old_size > size) {
        return toRawPtr(allocator.shrink(orig, size + pointersize));
    } else {
        if (allocator.resize(orig, size + pointersize)) |ret| {
            return toRawPtr(ret);
        } else {
            defer allocator.free(orig);
            const ret = allocator.alloc(u8, size + pointersize) catch return null;
            std.mem.copy(u8, ret[pointersize .. old_size + pointersize], orig[pointersize .. old_size + pointersize]);
            return toRawPtr(ret);
        }
    }
}

export fn trunc(input: f64) f64 {
    return @trunc(input);
}

export fn exp(input: f64) f64 {
    return std.math.exp(input);
}

export fn pow(base: f64, exponent: f64) f64 {
    return std.math.pow(f64, base, exponent);
}

export fn fmod(a: f64, b: f64) f64 {
    return @mod(a, b);
}

export fn acos(a: f64) f64 {
    return std.math.acos(a);
}

export fn asin(a: f64) f64 {
    return std.math.asin(a);
}

export fn atan(a: f64) f64 {
    return std.math.atan(a);
}

export fn atan2(y: f64, x: f64) f64 {
    return std.math.atan2(f64, y, x);
}

export fn cos(a: f64) f64 {
    return std.math.cos(a);
}

export fn sin(a: f64) f64 {
    return std.math.sin(a);
}

export fn tan(a: f64) f64 {
    return std.math.tan(a);
}

export fn cosh(a: f64) f64 {
    return std.math.cosh(a);
}

export fn sinh(a: f64) f64 {
    return std.math.sinh(a);
}

export fn tanh(a: f64) f64 {
    return std.math.tanh(a);
}

export fn acosh(a: f64) f64 {
    return std.math.acosh(a);
}

export fn asinh(a: f64) f64 {
    return std.math.asinh(a);
}

export fn atanh(a: f64) f64 {
    return std.math.atanh(a);
}

export fn sqrt(a: f64) f64 {
    return std.math.sqrt(a);
}

export fn ceil(a: f64) f64 {
    return std.math.ceil(a);
}

export fn floor(a: f64) f64 {
    return std.math.floor(a);
}

export fn log(a: f64) f64 {
    return std.math.log(f64, a, std.math.e);
}
