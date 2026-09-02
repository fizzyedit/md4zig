# md4zig

A Zig wrapper around [md4c](https://github.com/mity/md4c) for parsing Markdown.
Fork of [fjebaker/md4zig](https://github.com/fjebaker/md4zig), maintained for
[fizzy](https://github.com/fizzyedit/fizzy)'s markdown plugin.

## What this fork changes

- **Builds for `wasm32-freestanding`.** md4c is vendored under `vendor/md4c` and
  compiled with shim headers (`include/freestanding`) plus a small libc subset
  (`src/libc.zig`), since that target ships no libc — not even headers.
  `zig build check-wasm` compiles and links it.
- **Tag values match the vendored md4c.** Upstream predates `MD_SPAN_INS`, which
  shifted every span type after `code` by one, and lacks the footnote,
  admonition and blank block types.
- **Flag bits match `MD_FLAG_*`.** md4c leaves bit 7 unused; upstream's packed
  struct did not, so everything from `tables` on was off by one bit.
- **`Flags.github`** — the GFM feature set, so callers don't hand-assemble it.
- **`entity.decode`** — resolves `&amp;` and friends over md4c's own HTML5 table,
  which md4c compiles but does not use (it reports entities verbatim).
- Zig 0.16; `md4c_flag_t` is now `pub const Flags`.

## Usage

```zig
const md4zig = @import("md4zig");

const Impl = struct {
    pub fn enterBlock(_: *Impl, block: md4zig.BlockInfo) !void { _ = block; }
    pub fn leaveBlock(_: *Impl, block: md4zig.BlockInfo) !void { _ = block; }
    pub fn enterSpan(_: *Impl, span: md4zig.SpanInfo) !void { _ = span; }
    pub fn leaveSpan(_: *Impl, span: md4zig.SpanInfo) !void { _ = span; }
    pub fn textCallback(_: *Impl, text: md4zig.Text) !void { _ = text; }
};

var impl: Impl = .{};
var parser = md4zig.MD4CParser(Impl).init(.{ .flags = .github });
try parser.parse(&impl, "# Hello World\nHow are *you*!");
```

md4c is a push parser: it reports the document as a stream of block/span
enter+leave pairs and text runs. It does **not** report source line or column
positions — derive them from `Text.text`, whose pointer for `.normal` runs falls
inside the input buffer.

## Including in a project

```bash
zig fetch --save=md4zig https://github.com/fizzyedit/md4zig/archive/main.tar.gz
```

```zig
const md4zig = b.dependency("md4zig", .{
    .optimize = optimize,
    .target = target,
}).module("md4zig");

exe.root_module.addImport("md4zig", md4zig);
```

The module carries md4c's C source and include paths, so nothing else is needed.

## Vendored md4c

`vendor/md4c` is pinned to md4c `61f5ce76`, which is **ahead of release 0.5.3**:
footnotes, admonitions, `MD_SPAN_INS` and `MD_SPAN_MARK` are all unreleased
upstream, and footnotes in particular are needed for GFM parity. Bumping it means
re-checking the enums — `zig build test` pins every ordinal this wrapper depends
on against the vendored header.

## Licence

MIT, as upstream. Vendored md4c is MIT — see `vendor/md4c/LICENSE.md`.
