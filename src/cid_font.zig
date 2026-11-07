const std = @import("std");
const d = @import("document.zig");
const s = @import("syntax.zig");
const tt = @import("font.zig");
const unicode = @import("to_unicode.zig");
const encoding = @import("font_encoding.zig");
const cmap = @import("encoding_cmap.zig");
const WidthRange = struct {
    first: u16,
    last: u16,
    values: []const f64 = &.{},
    constant: f64 = 0,
    fn less(_: void, a: WidthRange, b: WidthRange) bool {
        return a.first < b.first;
    }
};
const VerticalRange = struct {
    first: u16,
    last: u16,
    values: []const [3]f64 = &.{},
    constant: [3]f64 = .{ 0, 0, 0 },
    fn less(_: void, a: VerticalRange, b: VerticalRange) bool {
        return a.first < b.first;
    }
};
pub const Font = struct {
    program: tt.Font,
    cmap: cmap.Map,
    gid_map: ?[]const u8,
    widths: []const WidthRange,
    default_width: f64,
    vertical_ranges: []const VerticalRange,
    default_vertical: [2]f64,
    ascent: f64,
    descent: f64,
    mapping: unicode.Map,
    candidates: []const encoding.Candidate,
    pub fn glyph(self: *const Font, source: cmap.Code) !u16 {
        const code = self.cmap.cid(source);
        const id = if (self.gid_map) |map| blk: {
            const offset = @as(usize, code) * 2;
            if (offset >= map.len) return error.MissingGlyph;
            break :blk std.mem.readInt(u16, map[offset..][0..2], .big);
        } else code;
        if (id >= self.program.glyphs) return error.InvalidFont;
        if (id == 0) return error.MissingGlyph;
        return id;
    }
    pub fn width(self: *const Font, source: cmap.Code) f64 {
        const code = self.cmap.cid(source);
        var lo: usize = 0;
        var hi = self.widths.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            const range = self.widths[mid];
            if (code < range.first) hi = mid else if (code > range.last) lo = mid + 1 else return if (range.values.len == 0) range.constant else range.values[code - range.first];
        }
        return self.default_width;
    }
    pub fn bounds(self: *const Font, code: cmap.Code) ![4]f64 {
        const box = try self.program.glyphBounds(try self.glyph(code));
        return .{ @min(0, box[0] / self.program.units), @min(self.descent / 1000, box[1] / self.program.units), @max(self.width(code) / 1000, box[2] / self.program.units), @max(self.ascent / 1000, box[3] / self.program.units) };
    }
    // W2 triples are displacement-y, origin-x, origin-y in thousandths of an em.
    pub fn verticalMetrics(self: *const Font, source: cmap.Code) [3]f64 {
        const code = self.cmap.cid(source);
        var lo: usize = 0;
        var hi = self.vertical_ranges.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            const range = self.vertical_ranges[mid];
            if (code < range.first) hi = mid else if (code > range.last) lo = mid + 1 else return if (range.values.len == 0) range.constant else range.values[code - range.first];
        }
        return .{ self.default_vertical[1], self.width(source) / 2, self.default_vertical[0] };
    }
};
fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
fn field(doc: *d.Document, value: s.Value, key: []const u8) !s.Value {
    return doc.resolve(s.get(value, key) orelse .null);
}
fn cidValue(value: s.Value) !u16 {
    const n = s.uint(value) catch return error.InvalidCIDFont;
    if (n > 65535) return error.InvalidCIDFont;
    return @intCast(n);
}
fn widthValue(value: s.Value) !f64 {
    const n = try s.number(value);
    if (!std.math.isFinite(n) or n < 0 or n > 1e6) return error.InvalidFontWidth;
    return n;
}
fn verticalValue(value: s.Value) !f64 {
    const n = try s.number(value);
    if (!std.math.isFinite(n) or @abs(n) > 1e6) return error.InvalidFontWidth;
    return n;
}
pub fn load(doc: *d.Document, parent: s.Value) !*const Font {
    const a = doc.allocator();
    const code_map = try cmap.load(doc, s.get(parent, "Encoding") orelse return error.InvalidCMap);
    const descendants = try field(doc, parent, "DescendantFonts");
    if (descendants != .array or descendants.array.len != 1) return error.InvalidCIDFont;
    const child = try doc.resolve(descendants.array[0]);
    if (child != .dict) return error.InvalidCIDFont;
    const subtype = try field(doc, child, "Subtype");
    if (subtype != .name or !eq(subtype.name, "CIDFontType2")) return error.UnsupportedFont;
    const info = try field(doc, child, "CIDSystemInfo");
    if (info != .dict or try field(doc, info, "Registry") != .string or try field(doc, info, "Ordering") != .string) return error.InvalidCIDFont;
    _ = s.uint(try field(doc, info, "Supplement")) catch return error.InvalidCIDFont;
    const descriptor = try field(doc, child, "FontDescriptor");
    if (descriptor != .dict) return error.InvalidCIDFont;
    const program = try loadProgram(doc, descriptor);
    var gid_map: ?[]const u8 = null;
    if (s.get(child, "CIDToGIDMap")) |raw| {
        const value = try doc.resolve(raw);
        if (value == .name) {
            if (!eq(value.name, "Identity")) return error.InvalidCIDFont;
        } else if (raw == .ref) {
            const object = try doc.object(raw.ref);
            const bytes = try doc.streamData(object);
            if (bytes.len % 2 != 0 or bytes.len > 131072) return error.InvalidCIDFont;
            var pos: usize = 0;
            while (pos < bytes.len) : (pos += 2) if (std.mem.readInt(u16, bytes[pos..][0..2], .big) >= program.glyphs) return error.InvalidFont;
            gid_map = bytes;
        } else return error.InvalidCIDFont;
    }
    const dw = try field(doc, child, "DW");
    const default_width = if (dw == .null) 1000 else try widthValue(dw);
    var ranges: std.ArrayList(WidthRange) = .empty;
    const w = try field(doc, child, "W");
    if (w != .null) {
        if (w != .array or w.array.len > 196608) return error.InvalidCIDFont;
        var i: usize = 0;
        var entries: usize = 0;
        while (i < w.array.len) {
            if (w.array.len - i < 2) return error.InvalidCIDFont;
            const first = try cidValue(try doc.resolve(w.array[i]));
            const item = try doc.resolve(w.array[i + 1]);
            var range = WidthRange{ .first = first, .last = first };
            if (item == .array) {
                if (item.array.len == 0 or item.array.len > 65536 - @as(usize, first)) return error.InvalidCIDFont;
                entries += item.array.len;
                if (entries > 65536) return error.FontLimit;
                const values = try a.alloc(f64, item.array.len);
                for (values, item.array) |*value, raw| value.* = try widthValue(try doc.resolve(raw));
                range.last = @intCast(@as(usize, first) + values.len - 1);
                range.values = values;
                i += 2;
            } else {
                if (w.array.len - i < 3) return error.InvalidCIDFont;
                range.last = try cidValue(item);
                if (range.last < first) return error.InvalidCIDFont;
                entries += @as(usize, range.last) - first + 1;
                if (entries > 65536) return error.FontLimit;
                range.constant = try widthValue(try doc.resolve(w.array[i + 2]));
                i += 3;
            }
            try ranges.append(a, range);
        }
        std.mem.sort(WidthRange, ranges.items, {}, WidthRange.less);
        for (ranges.items, 0..) |range, index| if (index != 0 and range.first <= ranges.items[index - 1].last) return error.InvalidCIDFont;
    }
    var default_vertical: [2]f64 = .{ 880, -1000 };
    var vertical_ranges: std.ArrayList(VerticalRange) = .empty;
    if (code_map.vertical) {
        const dw2 = try field(doc, child, "DW2");
        if (dw2 != .null) {
            if (dw2 != .array or dw2.array.len != 2) return error.InvalidCIDFont;
            for (&default_vertical, dw2.array) |*value, raw| value.* = try verticalValue(try doc.resolve(raw));
        }
        const w2 = try field(doc, child, "W2");
        if (w2 != .null) {
            if (w2 != .array or w2.array.len > 327680) return error.InvalidCIDFont;
            var i: usize = 0;
            var entries: usize = 0;
            while (i < w2.array.len) {
                if (w2.array.len - i < 2) return error.InvalidCIDFont;
                const first = try cidValue(try doc.resolve(w2.array[i]));
                const item = try doc.resolve(w2.array[i + 1]);
                var range = VerticalRange{ .first = first, .last = first };
                if (item == .array) {
                    const count = item.array.len / 3;
                    if (count == 0 or item.array.len % 3 != 0 or count > 65536 - @as(usize, first)) return error.InvalidCIDFont;
                    entries += count;
                    if (entries > 65536) return error.FontLimit;
                    const values = try a.alloc([3]f64, count);
                    for (values, 0..) |*triple, j| for (triple, item.array[3 * j ..][0..3]) |*value, raw| {
                        value.* = try verticalValue(try doc.resolve(raw));
                    };
                    range.last = @intCast(@as(usize, first) + count - 1);
                    range.values = values;
                    i += 2;
                } else {
                    if (w2.array.len - i < 5) return error.InvalidCIDFont;
                    range.last = try cidValue(item);
                    if (range.last < first) return error.InvalidCIDFont;
                    entries += @as(usize, range.last) - first + 1;
                    if (entries > 65536) return error.FontLimit;
                    for (&range.constant, w2.array[i + 2 ..][0..3]) |*value, raw| value.* = try verticalValue(try doc.resolve(raw));
                    i += 5;
                }
                try vertical_ranges.append(a, range);
            }
            std.mem.sort(VerticalRange, vertical_ranges.items, {}, VerticalRange.less);
            for (vertical_ranges.items, 0..) |range, index| if (index != 0 and range.first <= vertical_ranges.items[index - 1].last) return error.InvalidCIDFont;
        }
    }
    const ascent = try s.number(try field(doc, descriptor, "Ascent"));
    const descent = try s.number(try field(doc, descriptor, "Descent"));
    if (!std.math.isFinite(ascent) or !std.math.isFinite(descent) or @abs(ascent) > 1e6 or @abs(descent) > 1e6 or descent > ascent) return error.InvalidFont;
    const mapping = try unicode.load(doc, s.get(parent, "ToUnicode") orelse return error.UnsupportedEncoding);
    const result = try a.create(Font);
    result.* = .{ .program = program, .cmap = code_map, .gid_map = gid_map, .widths = try ranges.toOwnedSlice(a), .default_width = default_width, .vertical_ranges = try vertical_ranges.toOwnedSlice(a), .default_vertical = default_vertical, .ascent = ascent, .descent = descent, .mapping = mapping, .candidates = &.{} };
    var candidates: std.ArrayList(encoding.Candidate) = .empty;
    var it = mapping.entries.iterator();
    while (it.next()) |entry| {
        const code = cmap.Code{ .value = @truncate(entry.key_ptr.*), .length = @intCast(entry.key_ptr.* >> 32) };
        if (!code_map.contains(code)) return error.InvalidCMap;
        _ = result.glyph(code) catch continue;
        try candidates.append(a, .{ .code = code, .text = entry.value_ptr.* });
    }
    result.candidates = try candidates.toOwnedSlice(a);
    return result;
}

pub fn loadProgram(doc: *d.Document, descriptor: s.Value) !tt.Font {
    if (s.get(descriptor, "FontFile") != null or s.get(descriptor, "FontFile3") != null) return error.UnsupportedEmbeddedFont;
    const reference = s.get(descriptor, "FontFile2") orelse return error.UnsupportedEmbeddedFont;
    if (reference != .ref) return error.InvalidFont;
    const object = try doc.object(reference.ref);
    const data = try doc.streamData(object);
    if (data.len > 64 * 1024 * 1024) return error.FontLimit;
    const length = try field(doc, object.value, "Length1");
    if (length != .null and (s.uint(length) catch return error.InvalidFont) != data.len) return error.InvalidFont;
    return tt.Font.init(data);
}
