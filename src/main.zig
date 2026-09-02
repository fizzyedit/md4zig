const std = @import("std");
const builtin = @import("builtin");

const c = @cImport({
    @cInclude("md4c.h");
});

comptime {
    // Freestanding wasm links no libc; `libc.zig` exports the subset md4c needs.
    if (builtin.target.cpu.arch.isWasm() and builtin.target.os.tag == .freestanding) {
        _ = @import("libc.zig");
    }
}

pub const entity = @import("entity.zig");

pub const TextType = enum(u32) {
    // Normal text.
    normal = 0,

    // NULL character. CommonMark requires replacing NULL character with
    // the replacement char U+FFFD, so this allows caller to do that easily.
    nullchar,

    // Line breaks.
    // Note these are not sent from blocks with verbatim output (MD_BLOCK_CODE
    // or MD_BLOCK_HTML). In such cases, '\n' is part of the text itself.
    br, // <br> (hard break)
    softbar, // '\n' in source text where it is not semantically meaningful (soft break)

    // Entity.
    // (a) Named entity, e.g. &nbsp;
    //     (Note MD4C does not have a list of known entities.
    //     Anything matching the regexp /&[A-Za-z][A-Za-z0-9]{1,47};/ is
    //     treated as a named entity.)
    // (b) Numerical entity, e.g. &#1234;
    // (c) Hexadecimal entity, e.g. &#x12AB;
    //
    // As MD4C is mostly encoding agnostic, application gets the verbatim
    // entity text into the MD_PARSER::text_callback().
    entity,

    // Text in a code block (inside MD_BLOCK_CODE) or inlined code (`code`).
    // If it is inside MD_BLOCK_CODE, it includes spaces for indentation and
    // '\n' for new lines. MD_TEXT_BR and MD_TEXT_SOFTBR are not sent for this
    // kind of text.
    code,

    // Text is a raw HTML. If it is contents of a raw HTML block (i.e. not
    // an inline raw HTML), then MD_TEXT_BR and MD_TEXT_SOFTBR are not used.
    // The text contains verbatim '\n' for the new lines.
    html,

    // Text is inside an equation. This is processed the same way as inlined code
    // spans (`code`).
    latex,
};

pub const Text = struct {
    text: []const u8,
    text_type: TextType,
};

/// Bit-exact mirror of the `MD_FLAG_*` values in `vendor/md4c/md4c.h`. The
/// reserved gap at bit 7 is load-bearing: md4c jumps from `NOHTMLSPANS` (0x40)
/// straight to `TABLES` (0x100).
pub const Flags = packed struct(u32) {
    /// In `.normal` text, collapse non-trivial whitespace into a single ' '.
    collapsewhitespace: bool = true,
    /// Do not require a space in ATX headers (`###header`).
    permissiveatxheaders: bool = false,
    /// Recognize URLs as autolinks even without '<', '>'.
    permissiveurlautolinks: bool = false,
    /// Recognize e-mails as autolinks even without '<', '>' and 'mailto:'.
    permissiveemailautolinks: bool = false,
    /// Disable indented code blocks. (Only fenced code works.)
    noindentedcodeblocks: bool = false,
    /// Disable raw HTML blocks.
    nohtmlblocks: bool = false,
    /// Disable raw HTML (inline).
    nohtmlspans: bool = false,
    _reserved: bool = false,
    /// Enable tables extension.
    tables: bool = false,
    /// Enable strikethrough extension.
    strikethrough: bool = false,
    /// Enable WWW autolinks (even without a scheme, if they begin with 'www.').
    permissivewwwautolinks: bool = false,
    /// Enable task list extension.
    tasklists: bool = false,
    /// Enable $ and $$ containing LaTeX equations.
    latexmathspans: bool = false,
    /// Enable wiki links extension.
    wikilinks: bool = false,
    /// Enable underline extension (and disable '_' for normal emphasis).
    underline: bool = false,
    /// Force all soft breaks to act as hard breaks.
    hard_soft_breaks: bool = false,
    /// Enable ||hidden text|| spoiler spans.
    spoilers: bool = false,
    /// Enable ^superscript^ spans.
    superscripts: bool = false,
    /// Enable ~subscript~ spans.
    subscripts: bool = false,
    /// Enable admonitions extension.
    admonitions: bool = false,
    /// Enable [^label] footnote references.
    footnotes: bool = false,
    /// Enable ==highlight== spans.
    highlight: bool = false,
    /// Report blank line runs as `.blank` blocks.
    preserveblanklines: bool = false,
    /// Enable insert extension.
    insert: bool = false,
    _: u8 = 0,

    /// What GitHub actually renders in a `.md` file: CommonMark plus tables,
    /// strikethrough, task lists, bare autolinks, footnotes and `> [!NOTE]`
    /// alerts. Everything md4c offers beyond that (`underline`, `spoilers`,
    /// `superscripts`, `subscripts`, `highlight`, `insert`, `latexmathspans`,
    /// `wikilinks`, `permissiveatxheaders`) is a non-GFM dialect and stays off —
    /// `underline` especially, since it would stop `_emphasis_` from working.
    pub const github: Flags = .{
        .tables = true,
        .strikethrough = true,
        .tasklists = true,
        .permissiveurlautolinks = true,
        .permissiveemailautolinks = true,
        .permissivewwwautolinks = true,
        .footnotes = true,
        .admonitions = true,
    };
};

fn promoteTo(comptime T: type, ptr: ?*anyopaque) ?T {
    const p = ptr orelse return null;
    const t_ptr: *T = @ptrCast(@alignCast(p));
    return t_ptr.*;
}

pub const Attribute = struct {
    c_data: c.MD_ATTRIBUTE,
    index: usize = 0,

    /// Get all of the text in the attribute
    pub fn all(a: Attribute) []const u8 {
        if (a.c_data.size == 0) return "";
        return a.c_data.text[0..a.c_data.size];
    }

    pub fn next(_: *Attribute) ?Text {
        @compileError("Not implemented yet");
    }
};

/// Mirrors `MD_ALIGN`. Only meaningful on `.th`/`.td` blocks.
pub const Alignment = enum(u32) { default = 0, left, center, right };

pub const BlockInfo = union(enum(u32)) {
    // <body>...</body>
    doc: void,

    // <blockquote>...</blockquote>
    quote: void,

    // <ul>...</ul>
    // Detail: Structure MD_BLOCK_UL_DETAIL.
    ul: struct {
        // Non-zero if tight list, zero if loose.
        is_tight: bool,
        // Item bullet character in MarkDown source of the list, e.g. '-', '+', '*'.
        mark: u8,
    },

    // <ol>...</ol>
    // Detail: Structure MD_BLOCK_OL_DETAIL.
    ol: struct {
        // Start index of the ordered list
        start: usize,
        // Non-zero if tight list, zero if loose.
        is_tight: bool,
        // Item bullet character in MarkDown source of the list, e.g. '-', '+', '*'.
        mark_delimiter: u8,
    },

    // <li>...</li>
    // Detail: Structure MD_BLOCK_LI_DETAIL.
    li: struct {
        // Can be non-zero only with MD_FLAG_TASKLISTS
        is_task: bool,
        // If is_task, then one of 'x', 'X' or ' '. Undefined otherwise.
        task_mark: u8,
        // If is_task, then offset in the input of the char between '[' and ']'.
        task_mark_offset: usize,
    },

    // <hr>
    hr: void,

    // <h1>...</h1> (for levels up to 6)
    // Detail: Structure MD_BLOCK_H_DETAIL.
    h: struct {
        level: usize,
    },

    // <pre><code>...</code></pre>
    // Note the text lines within code blocks are terminated with '\n'
    // instead of explicit MD_TEXT_BR.
    code: struct {
        info: Attribute,
        lang: Attribute,
        fence_char: u8,
    },

    // Raw HTML block. This itself does not correspond to any particular HTML
    // tag. The contents of it _is_ raw HTML source intended to be put
    // in verbatim form to the HTML output.
    html: void,

    // <p>...</p>
    p: void,

    // <table>...</table> and its contents.
    // Detail: Structure MD_BLOCK_TABLE_DETAIL (for MD_BLOCK_TABLE),
    //         structure MD_BLOCK_TD_DETAIL (for MD_BLOCK_TH and MD_BLOCK_TD)
    // Note all of these are used only if extension MD_FLAG_TABLES is enabled.
    table: struct {
        column_count: usize,
        head_row_count: usize,
        body_row_count: usize,
    },
    thead: void,
    tbody: void,
    tr: void,
    th: struct {
        alignment: Alignment,
    },
    td: struct {
        alignment: Alignment,
    },

    // <section class="footnotes">...</section>
    // Note: Emitted only when MD_FLAG_FOOTNOTES is enabled.
    footnote_def_section: void,

    // <li id="fn:1">...</li>
    // Detail: Structure MD_BLOCK_FOOTNOTE_DEF_DETAIL.
    // Note: Emitted only when MD_FLAG_FOOTNOTES is enabled.
    footnote_def: struct {
        // 1-based identifier of this footnote.
        id: usize,
        // Number of references to this footnote.
        ref_count: usize,
        // Raw label text, e.g. "1" or "note".
        label: Attribute,
    },

    // GitHub-style admonition (> [!NOTE], ...).
    // Note: Recognized only when MD_FLAG_ADMONITIONS is enabled.
    admonition: struct {
        // One of "note", "tip", "important", "warning", "caution".
        type: Attribute,
    },

    // A run of blank lines separating two blocks. Has no contents.
    // Note: Emitted only when MD_FLAG_PRESERVEBLANKLINES is enabled.
    blank: struct {
        line_count: usize,
    },

    pub fn init_c(b: c.MD_BLOCKTYPE, details: ?*anyopaque) BlockInfo {
        // Unreachable unless md4c reports a type this wrapper's tag list is
        // missing — i.e. `vendor/md4c` was updated without updating BlockInfo.
        const tag = std.enums.fromInt(
            std.meta.Tag(BlockInfo),
            @as(u32, @intCast(b)),
        ).?;

        switch (tag) {
            .ul => {
                const d = promoteTo(c.MD_BLOCK_UL_DETAIL, details).?;
                return .{ .ul = .{ .is_tight = d.is_tight != 0, .mark = d.mark } };
            },
            .ol => {
                const d = promoteTo(c.MD_BLOCK_OL_DETAIL, details).?;
                return .{ .ol = .{
                    .start = d.start,
                    .is_tight = d.is_tight != 0,
                    .mark_delimiter = d.mark_delimiter,
                } };
            },
            .li => {
                const d = promoteTo(c.MD_BLOCK_LI_DETAIL, details).?;
                return .{ .li = .{
                    .is_task = d.is_task != 0,
                    .task_mark = d.task_mark,
                    .task_mark_offset = d.task_mark_offset,
                } };
            },
            .h => {
                const d = promoteTo(c.MD_BLOCK_H_DETAIL, details).?;
                return .{ .h = .{
                    .level = d.level,
                } };
            },
            .code => {
                const d = promoteTo(c.MD_BLOCK_CODE_DETAIL, details).?;
                return .{ .code = .{
                    .info = .{ .c_data = d.info },
                    .lang = .{ .c_data = d.lang },
                    .fence_char = d.fence_char,
                } };
            },
            .table => {
                const d = promoteTo(c.MD_BLOCK_TABLE_DETAIL, details).?;
                return .{ .table = .{
                    .column_count = d.col_count,
                    .head_row_count = d.head_row_count,
                    .body_row_count = d.body_row_count,
                } };
            },
            .th, .td => {
                const d = promoteTo(c.MD_BLOCK_TD_DETAIL, details).?;
                const a: Alignment = @enumFromInt(d.@"align");
                return if (tag == .th) .{ .th = .{ .alignment = a } } else .{ .td = .{ .alignment = a } };
            },
            .footnote_def => {
                const d = promoteTo(c.MD_BLOCK_FOOTNOTE_DEF_DETAIL, details).?;
                return .{ .footnote_def = .{
                    .id = d.id,
                    .ref_count = d.ref_count,
                    .label = .{ .c_data = d.label },
                } };
            },
            .admonition => {
                const d = promoteTo(c.MD_BLOCK_ADMONITION_DETAIL, details).?;
                return .{ .admonition = .{ .type = .{ .c_data = d.type } } };
            },
            .blank => {
                const d = promoteTo(c.MD_BLOCK_BLANK_DETAIL, details).?;
                return .{ .blank = .{ .line_count = d.line_count } };
            },
            inline else => |t| return @unionInit(BlockInfo, @tagName(t), {}),
        }
    }
};

pub const SpanInfo = union(enum(u32)) {
    // <em>...</em>
    em: void,

    // <strong>...</strong>
    strong: void,

    // <a href="xxx">...</a>
    // Detail: Structure MD_SPAN_A_DETAIL.
    a: struct {
        href: Attribute,
        title: Attribute,
        autolink: bool,
    },

    // <img src="xxx">...</a>
    // Detail: Structure MD_SPAN_IMG_DETAIL.
    // Note: Image text can contain nested spans and even nested images.
    // If rendered into ALT attribute of HTML <IMG> tag, it's responsibility
    // of the parser to deal with it.
    img: struct {
        src: Attribute,
        title: Attribute,
    },

    // <code>...</code>
    code: void,

    // <ins>...</ins>
    // Note: Recognized only when MD_FLAG_INSERT is enabled.
    ins: void,

    // <del>...</del>
    // Note: Recognized only when MD_FLAG_STRIKETHROUGH is enabled.
    del: void,

    // For recognizing inline ($) and display ($$) equations
    // Note: Recognized only when MD_FLAG_LATEXMATHSPANS is enabled.
    latexmath: void,
    latexmath_display: void,

    // Wiki links
    // Note: Recognized only when MD_FLAG_WIKILINKS is enabled.
    wikilink: struct {
        target: Attribute,
    },

    // <u>...</u>
    // Note: Recognized only when MD_FLAG_UNDERLINE is enabled.
    u: void,

    // ||hidden text||
    // Note: Recognized only when MD_FLAG_SPOILERS is enabled.
    spoiler: void,

    // <sup>...</sup>
    // Note: Recognized only when MD_FLAG_SUPERSCRIPTS is enabled.
    superscript: void,

    // <sub>...</sub>
    // Note: Recognized only when MD_FLAG_SUBSCRIPTS is enabled.
    subscript: void,

    // <sup><a href="#fn:1">1</a></sup>
    // Detail: Structure MD_SPAN_FOOTNOTE_REF_DETAIL.
    // Note: Recognized only when MD_FLAG_FOOTNOTES is enabled.
    footnote_ref: struct {
        // 1-based identifier of the referenced footnote.
        id: usize,
        // 1-based identifier of this reference among references to the same footnote.
        ref_id: usize,
        // Raw label text, e.g. "1" or "note".
        label: Attribute,
    },

    // <mark>...</mark>
    // Note: Recognized only when MD_FLAG_HIGHLIGHT is enabled.
    mark: void,

    pub fn init_c(b: c.MD_SPANTYPE, details: ?*anyopaque) SpanInfo {
        // Unreachable unless md4c reports a type this wrapper's tag list is
        // missing — i.e. `vendor/md4c` was updated without updating SpanInfo.
        const tag = std.enums.fromInt(
            std.meta.Tag(SpanInfo),
            @as(u32, @intCast(b)),
        ).?;

        switch (tag) {
            .a => {
                const d = promoteTo(c.MD_SPAN_A_DETAIL, details).?;
                return .{ .a = .{
                    .href = .{ .c_data = d.href },
                    .title = .{ .c_data = d.title },
                    .autolink = d.is_autolink != 0,
                } };
            },
            .img => {
                const d = promoteTo(c.MD_SPAN_IMG_DETAIL, details).?;
                return .{ .img = .{
                    .src = .{ .c_data = d.src },
                    .title = .{ .c_data = d.title },
                } };
            },
            .wikilink => {
                const d = promoteTo(c.MD_SPAN_WIKILINK_DETAIL, details).?;
                return .{ .wikilink = .{
                    .target = .{ .c_data = d.target },
                } };
            },
            .footnote_ref => {
                const d = promoteTo(c.MD_SPAN_FOOTNOTE_REF_DETAIL, details).?;
                return .{ .footnote_ref = .{
                    .id = d.id,
                    .ref_id = d.ref_id,
                    .label = .{ .c_data = d.label },
                } };
            },
            inline else => |t| return @unionInit(SpanInfo, @tagName(t), {}),
        }
    }
};

/// Compile time wrapper of md4c
pub fn MD4CParser(comptime Implementation: type) type {
    return struct {
        const Self = @This();

        pub const Options = struct {
            flags: Flags = .{},
        };

        c_parser: c.MD_PARSER,

        fn enter_block(
            block_type: c.MD_BLOCKTYPE,
            details: ?*anyopaque,
            data: ?*anyopaque,
        ) callconv(.c) c_int {
            const _field_name = "enterBlock";
            if (@hasDecl(Implementation, _field_name)) {
                const block = BlockInfo.init_c(block_type, details);
                const impl: *Implementation = @ptrCast(@alignCast(data.?));
                @field(Implementation, _field_name)(
                    impl,
                    block,
                ) catch return 1;
            } else @compileError("Missing field: " ++ _field_name);
            return 0;
        }

        fn leave_block(
            block_type: c.MD_BLOCKTYPE,
            details: ?*anyopaque,
            data: ?*anyopaque,
        ) callconv(.c) c_int {
            const _field_name = "leaveBlock";
            if (@hasDecl(Implementation, _field_name)) {
                const block = BlockInfo.init_c(block_type, details);
                const impl: *Implementation = @ptrCast(@alignCast(data.?));
                @field(Implementation, _field_name)(
                    impl,
                    block,
                ) catch return 1;
            } else @compileError("Missing field: " ++ _field_name);
            return 0;
        }

        fn enter_span(
            span_type: c.MD_SPANTYPE,
            details: ?*anyopaque,
            data: ?*anyopaque,
        ) callconv(.c) c_int {
            const _field_name = "enterSpan";
            if (@hasDecl(Implementation, _field_name)) {
                const span = SpanInfo.init_c(span_type, details);
                const impl: *Implementation = @ptrCast(@alignCast(data.?));
                @field(Implementation, _field_name)(
                    impl,
                    span,
                ) catch return 1;
            } else @compileError("Missing field: " ++ _field_name);
            return 0;
        }

        fn leave_span(
            span_type: c.MD_SPANTYPE,
            details: ?*anyopaque,
            data: ?*anyopaque,
        ) callconv(.c) c_int {
            const _field_name = "leaveSpan";
            if (@hasDecl(Implementation, _field_name)) {
                const span = SpanInfo.init_c(span_type, details);
                const impl: *Implementation = @ptrCast(@alignCast(data.?));
                @field(Implementation, _field_name)(
                    impl,
                    span,
                ) catch return 1;
            } else @compileError("Missing field: " ++ _field_name);
            return 0;
        }

        fn text_callback(
            t: c.MD_TEXTTYPE,
            ptr: [*c]const c.MD_CHAR,
            len: c.MD_SIZE,
            data: ?*anyopaque,
        ) callconv(.c) c_int {
            const _field_name = "textCallback";
            if (@hasDecl(Implementation, _field_name)) {
                const impl: *Implementation = @ptrCast(@alignCast(data.?));
                @field(Implementation, _field_name)(impl, Text{
                    .text = ptr[0..len],
                    .text_type = @as(TextType, @enumFromInt(t)),
                }) catch return 1;
            } else @compileError("Missing field: " ++ _field_name);
            return 0;
        }

        fn promoteSelf(ptr: ?*anyopaque) *Self {
            const p = ptr.?;
            return @ptrCast(@alignCast(p));
        }

        /// Initialize a parser.
        pub fn init(opts: Options) Self {
            const parser: c.MD_PARSER = .{
                .abi_version = 0,
                .flags = @as(c_uint, @bitCast(opts.flags)),
                .enter_block = Self.enter_block,
                .leave_block = Self.leave_block,
                .enter_span = Self.enter_span,
                .leave_span = Self.leave_span,
                .text = Self.text_callback,
            };
            return .{
                .c_parser = parser,
            };
        }

        /// Parse a given text
        pub fn parse(p: *Self, impl: *Implementation, text: []const u8) !void {
            const errno = c.md_parse(
                text.ptr,
                @intCast(text.len),
                &p.c_parser,
                @ptrCast(@alignCast(impl)),
            );

            switch (errno) {
                0 => return,
                else => return error.MD4CUnknownError,
            }
        }
    };
}

const testing = std.testing;

test {
    _ = entity;
}

// The tag values of `BlockInfo`/`SpanInfo`/`TextType` *are* the md4c enum
// ordinals — md4c passes them straight into `init_c`. A vendored-md4c bump that
// inserts a type (as `MD_SPAN_INS` once did) silently reinterprets every tag
// after it, so pin them here rather than trusting the declaration order.
test "tag values match the vendored md4c enums" {
    try testing.expectEqual(c.MD_BLOCK_DOC, @intFromEnum(BlockInfo.doc));
    try testing.expectEqual(c.MD_BLOCK_TD, @intFromEnum(std.meta.Tag(BlockInfo).td));
    try testing.expectEqual(c.MD_BLOCK_FOOTNOTE_DEF, @intFromEnum(std.meta.Tag(BlockInfo).footnote_def));
    try testing.expectEqual(c.MD_BLOCK_ADMONITION, @intFromEnum(std.meta.Tag(BlockInfo).admonition));
    try testing.expectEqual(c.MD_BLOCK_BLANK, @intFromEnum(BlockInfo.blank));

    try testing.expectEqual(c.MD_SPAN_INS, @intFromEnum(SpanInfo.ins));
    try testing.expectEqual(c.MD_SPAN_DEL, @intFromEnum(SpanInfo.del));
    try testing.expectEqual(c.MD_SPAN_WIKILINK, @intFromEnum(std.meta.Tag(SpanInfo).wikilink));
    try testing.expectEqual(c.MD_SPAN_FOOTNOTE_REF, @intFromEnum(std.meta.Tag(SpanInfo).footnote_ref));
    try testing.expectEqual(c.MD_SPAN_MARK, @intFromEnum(SpanInfo.mark));

    try testing.expectEqual(c.MD_TEXT_SOFTBR, @intFromEnum(TextType.softbar));
    try testing.expectEqual(c.MD_TEXT_LATEXMATH, @intFromEnum(TextType.latex));
}

// md4c leaves bit 7 unused, so a packed struct without the reserved field maps
// `tables` onto 0x80 and shifts every later extension by one bit.
test "flag bits match the vendored MD_FLAG_ values" {
    try testing.expectEqual(@as(u32, c.MD_FLAG_TABLES), @as(u32, @bitCast(Flags{ .collapsewhitespace = false, .tables = true })));
    try testing.expectEqual(@as(u32, c.MD_FLAG_FOOTNOTES), @as(u32, @bitCast(Flags{ .collapsewhitespace = false, .footnotes = true })));
    try testing.expectEqual(@as(u32, c.MD_FLAG_INSERT), @as(u32, @bitCast(Flags{ .collapsewhitespace = false, .insert = true })));

    const expected: u32 = c.MD_FLAG_COLLAPSEWHITESPACE | c.MD_FLAG_TABLES | c.MD_FLAG_STRIKETHROUGH |
        c.MD_FLAG_TASKLISTS | c.MD_FLAG_PERMISSIVEAUTOLINKS | c.MD_FLAG_FOOTNOTES | c.MD_FLAG_ADMONITIONS;
    try testing.expectEqual(expected, @as(u32, @bitCast(Flags.github)));
}

/// Collects the callback stream as a flat trace, which is the shape every
/// consumer builds on top of.
const Trace = struct {
    out: std.ArrayList(u8) = .empty,
    allocator: std.mem.Allocator,

    pub fn enterBlock(self: *Trace, block: BlockInfo) !void {
        try self.out.print(self.allocator, "+{s} ", .{@tagName(block)});
    }
    pub fn leaveBlock(self: *Trace, block: BlockInfo) !void {
        try self.out.print(self.allocator, "-{s} ", .{@tagName(block)});
    }
    pub fn enterSpan(self: *Trace, span: SpanInfo) !void {
        try self.out.print(self.allocator, "+{s} ", .{@tagName(span)});
    }
    pub fn leaveSpan(self: *Trace, span: SpanInfo) !void {
        try self.out.print(self.allocator, "-{s} ", .{@tagName(span)});
    }
    pub fn textCallback(self: *Trace, text: Text) !void {
        try self.out.print(self.allocator, "'{s}' ", .{text.text});
    }

    fn run(allocator: std.mem.Allocator, src: []const u8, flags: Flags) ![]u8 {
        var self: Trace = .{ .allocator = allocator };
        var parser = MD4CParser(Trace).init(.{ .flags = flags });
        try parser.parse(&self, src);
        return self.out.toOwnedSlice(allocator);
    }
};

test "parses CommonMark structure" {
    const trace = try Trace.run(testing.allocator, "# Hi\n\nHow are *you*!", .{});
    defer testing.allocator.free(trace);
    try testing.expectEqualStrings("+doc +h 'Hi' -h +p 'How are ' +em 'you' -em '!' -p -doc ", trace);
}

test "github preset enables tables, strikethrough and footnotes" {
    const trace = try Trace.run(testing.allocator, "a ~~b~~ [^n]\n\n[^n]: c", Flags.github);
    defer testing.allocator.free(trace);
    try testing.expect(std.mem.indexOf(u8, trace, "+del") != null);
    try testing.expect(std.mem.indexOf(u8, trace, "+footnote_ref") != null);
    try testing.expect(std.mem.indexOf(u8, trace, "+footnote_def") != null);
}
