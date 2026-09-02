//! The libc subset `vendor/md4c/md4c.c` needs, for freestanding wasm where there
//! is no libc to link. Declared in `include/freestanding/`, and only pulled into
//! the compilation on that target (see the comptime gate in `main.zig`).
//!
//! `memcpy`/`memmove`/`memset`/`memcmp` are deliberately absent — Zig's
//! compiler_rt already exports those for freestanding targets.

const std = @import("std");

/// md4c allocates only for the duration of one `md_parse` call.
const allocator = std.heap.wasm_allocator;

/// Bytes reserved ahead of each returned pointer to record the block's total
/// size, since `free`/`realloc` receive no length. 16 also over-aligns every
/// allocation to `max_align_t`, which C callers are entitled to assume.
const header = 16;

fn blockOf(ptr: *anyopaque) []align(header) u8 {
    const base: [*]align(header) u8 = @ptrFromInt(@intFromPtr(ptr) - header);
    return base[0..std.mem.readInt(usize, base[0..@sizeOf(usize)], .little)];
}

fn finish(buf: []align(header) u8, total: usize) *anyopaque {
    std.mem.writeInt(usize, buf[0..@sizeOf(usize)], total, .little);
    return @ptrCast(buf.ptr + header);
}

export fn malloc(size: usize) ?*anyopaque {
    const total = header + size;
    const buf = allocator.alignedAlloc(u8, .fromByteUnits(header), total) catch return null;
    return finish(buf, total);
}

export fn realloc(ptr: ?*anyopaque, size: usize) ?*anyopaque {
    const p = ptr orelse return malloc(size);
    const total = header + size;
    const buf = allocator.realloc(blockOf(p), total) catch return null;
    return finish(buf, total);
}

export fn free(ptr: ?*anyopaque) void {
    allocator.free(blockOf(ptr orelse return));
}

export fn strlen(s: [*:0]const u8) usize {
    return std.mem.len(s);
}

export fn strchr(s: [*:0]const u8, ch: c_int) ?[*:0]const u8 {
    const needle: u8 = @truncate(@as(c_uint, @bitCast(ch)));
    var i: usize = 0;
    // A `ch` of 0 matches the terminator, so compare before testing for the end.
    while (true) : (i += 1) {
        if (s[i] == needle) return s + i;
        if (s[i] == 0) return null;
    }
}

export fn strncmp(a: [*:0]const u8, b: [*:0]const u8, n: usize) c_int {
    for (0..n) |i| {
        if (a[i] != b[i]) return @as(c_int, a[i]) - @as(c_int, b[i]);
        if (a[i] == 0) break;
    }
    return 0;
}

const Compare = *const fn (?*const anyopaque, ?*const anyopaque) callconv(.c) c_int;

/// Heapsort: in-place, so an allocation failure can never turn a sort into a
/// crash, and O(n log n) regardless of input. md4c only sorts its link-label and
/// footnote tables, so the constant factor is irrelevant.
export fn qsort(base: ?*anyopaque, nmemb: usize, size: usize, compare: Compare) void {
    if (nmemb < 2 or size == 0) return;
    const bytes: [*]u8 = @ptrCast(base orelse return);

    var start = nmemb / 2;
    var end = nmemb;
    while (end > 1) {
        if (start > 0) {
            start -= 1;
        } else {
            end -= 1;
            swap(bytes, size, 0, end);
        }
        siftDown(bytes, size, compare, start, end);
    }
}

export fn bsearch(
    key: ?*const anyopaque,
    base: ?*const anyopaque,
    nmemb: usize,
    size: usize,
    compare: Compare,
) ?*const anyopaque {
    const bytes: [*]const u8 = @ptrCast(base orelse return null);
    var lo: usize = 0;
    var hi = nmemb;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const at = bytes + mid * size;
        const order = compare(key, at);
        if (order < 0) {
            hi = mid;
        } else if (order > 0) {
            lo = mid + 1;
        } else {
            return at;
        }
    }
    return null;
}

fn elem(bytes: [*]u8, size: usize, i: usize) [*]u8 {
    return bytes + i * size;
}

fn less(bytes: [*]u8, size: usize, compare: Compare, a: usize, b: usize) bool {
    return compare(elem(bytes, size, a), elem(bytes, size, b)) < 0;
}

fn swap(bytes: [*]u8, size: usize, a: usize, b: usize) void {
    if (a == b) return;
    const x = elem(bytes, size, a);
    const y = elem(bytes, size, b);
    for (0..size) |i| std.mem.swap(u8, &x[i], &y[i]);
}

fn siftDown(bytes: [*]u8, size: usize, compare: Compare, root_start: usize, end: usize) void {
    var root = root_start;
    while (root * 2 + 1 < end) {
        var child = root * 2 + 1;
        if (child + 1 < end and less(bytes, size, compare, child, child + 1)) child += 1;
        if (!less(bytes, size, compare, root, child)) return;
        swap(bytes, size, root, child);
        root = child;
    }
}
