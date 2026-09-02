//! Root module for `zig build check-wasm`. Forces md4c *and* the freestanding
//! libc shim to be compiled and linked for `wasm32-freestanding` — the target
//! fizzy's web build uses — so a missing header or unresolved libc symbol fails
//! the build instead of surfacing in a consumer. Not shipped.

const md4zig = @import("main.zig");

const Sink = struct {
    blocks: usize = 0,

    pub fn enterBlock(self: *Sink, _: md4zig.BlockInfo) !void {
        self.blocks += 1;
    }
    pub fn leaveBlock(_: *Sink, _: md4zig.BlockInfo) !void {}
    pub fn enterSpan(_: *Sink, _: md4zig.SpanInfo) !void {}
    pub fn leaveSpan(_: *Sink, _: md4zig.SpanInfo) !void {}
    pub fn textCallback(self: *Sink, text: md4zig.Text) !void {
        // Also drags in entity.c (and the strncmp its comparator needs), which
        // nothing else here would reference.
        if (text.text_type != .entity) return;
        var buf: [md4zig.entity.max_decoded_len]u8 = undefined;
        self.blocks += md4zig.entity.decode(text.text, &buf) orelse 0;
    }
};

export fn md4zig_wasm_check(ptr: [*]const u8, len: usize) usize {
    var sink: Sink = .{};
    var parser = md4zig.MD4CParser(Sink).init(.{ .flags = .github });
    parser.parse(&sink, ptr[0..len]) catch return 0;
    return sink.blocks;
}
