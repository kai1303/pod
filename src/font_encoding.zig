const std = @import("std");
pub const Code = @import("to_unicode.zig").Code;
pub const Candidate = struct { code: Code, text: []const u8 };

// Resolve ambiguous ligature prefixes backwards, preferring fewer source codes
// and then the lowest source code. Buckets bound work for larger CID encodings.
pub fn encode(a: std.mem.Allocator, text: []const u8, candidates: []const Candidate) ![]const u8 {
    if (!std.unicode.utf8ValidateSlice(text)) return error.UnsupportedEncoding;
    if (text.len > 1048576) return error.TextLimit;
    var counts: [256]usize = @splat(0);
    for (candidates) |entry| if (entry.text.len != 0) {
        counts[entry.text[0]] += 1;
    };
    var starts: [257]usize = undefined;
    starts[0] = 0;
    for (counts, 0..) |count, i| starts[i + 1] = starts[i] + count;
    var positions = starts;
    const grouped = try a.alloc(Candidate, starts[256]);
    defer a.free(grouped);
    for (candidates) |entry| if (entry.text.len != 0) {
        grouped[positions[entry.text[0]]] = entry;
        positions[entry.text[0]] += 1;
    };
    const costs = try a.alloc(u32, text.len + 1);
    defer a.free(costs);
    @memset(costs, std.math.maxInt(u32));
    costs[text.len] = 0;
    const choices = try a.alloc(usize, text.len);
    defer a.free(choices);
    var work: usize = 0;
    var at = text.len;
    while (at != 0) {
        at -= 1;
        for (starts[text[at]]..starts[@as(usize, text[at]) + 1]) |index| {
            const entry = grouped[index];
            work += 1;
            if (work > 32 * 1024 * 1024) return error.TextLimit;
            if (entry.text.len > text.len - at or costs[at + entry.text.len] == std.math.maxInt(u32)) continue;
            work += entry.text.len;
            if (work > 32 * 1024 * 1024) return error.TextLimit;
            const cost = costs[at + entry.text.len] + 1;
            if ((cost < costs[at] or (cost == costs[at] and entry.code.key() < grouped[choices[at]].code.key())) and std.mem.startsWith(u8, text[at..], entry.text)) {
                costs[at] = cost;
                choices[at] = index;
            }
        }
    }
    if (costs[0] == std.math.maxInt(u32)) return error.UnsupportedEncoding;
    var length: usize = 0;
    at = 0;
    while (at < text.len) {
        const entry = grouped[choices[at]];
        length += entry.code.length;
        at += entry.text.len;
    }
    const result = try a.alloc(u8, length);
    at = 0;
    var out: usize = 0;
    while (at < text.len) {
        const entry = grouped[choices[at]];
        var i: u8 = 0;
        while (i < entry.code.length) : (i += 1) {
            result[out] = @truncate(entry.code.value >> @as(u5, @intCast((entry.code.length - 1 - i) * 8)));
            out += 1;
        }
        at += entry.text.len;
    }
    return result;
}
