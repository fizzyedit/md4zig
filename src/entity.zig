//! HTML entity resolution, over md4c's own entity table (`vendor/md4c/entity.c`).
//!
//! md4c reports `&amp;` as a `.entity` text run holding the source bytes
//! verbatim — resolving it is the application's job. This is that job.

const std = @import("std");

const c = @import("c");

/// Longest UTF-8 an entity can decode to: two code points of 4 bytes each.
pub const max_decoded_len = 8;

/// Decodes one `.entity` text run — the whole `&...;`, delimiters included —
/// into `out` as UTF-8, returning the bytes written. Null means the run is not
/// an entity this table knows, in which case emit it verbatim, which is what a
/// CommonMark renderer is required to do.
pub fn decode(text: []const u8, out: *[max_decoded_len]u8) ?usize {
    if (text.len < 3 or text[0] != '&' or text[text.len - 1] != ';') return null;
    const body = text[1 .. text.len - 1];

    if (body[0] == '#') {
        const digits = body[1..];
        const radix: u8 = if (digits.len > 0 and (digits[0] | 0x20) == 'x') 16 else 10;
        const value = std.fmt.parseInt(u21, if (radix == 16) digits[1..] else digits, radix) catch return null;
        // CommonMark maps NUL and anything unencodable to the replacement char.
        const cp = if (value == 0 or !std.unicode.utf8ValidCodepoint(value)) 0xFFFD else value;
        return std.unicode.utf8Encode(cp, out) catch null;
    }

    const found = c.entity_lookup(text.ptr, text.len) orelse return null;
    var written: usize = 0;
    for (found.*.codepoints) |raw| {
        if (raw == 0) break;
        const cp = std.math.cast(u21, raw) orelse return null;
        written += std.unicode.utf8Encode(cp, out[written..]) catch return null;
    }
    return written;
}

const testing = std.testing;

test "decodes named, numeric and hex entities" {
    var buf: [max_decoded_len]u8 = undefined;
    try testing.expectEqualStrings("&", buf[0..decode("&amp;", &buf).?]);
    try testing.expectEqualStrings("\u{00A0}", buf[0..decode("&nbsp;", &buf).?]);
    try testing.expectEqualStrings("—", buf[0..decode("&mdash;", &buf).?]);
    try testing.expectEqualStrings("A", buf[0..decode("&#65;", &buf).?]);
    try testing.expectEqualStrings("√", buf[0..decode("&#x221A;", &buf).?]);
    // NUL becomes the replacement character, per CommonMark.
    try testing.expectEqualStrings("\u{FFFD}", buf[0..decode("&#0;", &buf).?]);
}

test "rejects what is not an entity, so callers can emit it verbatim" {
    var buf: [max_decoded_len]u8 = undefined;
    try testing.expectEqual(@as(?usize, null), decode("&notanentity;", &buf));
    try testing.expectEqual(@as(?usize, null), decode("&amp", &buf));
    try testing.expectEqual(@as(?usize, null), decode("&;", &buf));
}
