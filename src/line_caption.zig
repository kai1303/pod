//! Plain-text line captions. Placement uses the font's measured em bounds;
//! source strings remain unchanged and saved appearances carry their font resource.
const std = @import("std");
const d = @import("document.zig");
const s = @import("syntax.zig");
const fonts = @import("pdf_font.zig");
const c = @import("content.zig");
const A = std.mem.Allocator;
pub const size: f64 = 12;
pub const leading: f64 = size * 1.2;
const padding: f64 = 3;
pub const Line = struct { text: []const u8, width: f64 };
pub const Layout = struct { matrix: c.Matrix, bounds: [4]f64, gap: ?[2]f64 };
pub const Caption = struct {
    font: *const fonts.Font,
    lines: []const Line,
    width: f64,
    bounds: [4]f64,
    top: bool,
    offset: [2]f64,
    visible: bool,

    pub fn layout(self: Caption, first: [2]f64, last: [2]f64, stroke_width: f64) ?Layout {
        if (!self.visible) return null;
        const dx = last[0] - first[0];
        const dy = last[1] - first[1];
        const length = @sqrt(dx * dx + dy * dy);
        const t: [2]f64 = if (length == 0) .{ 1, 0 } else .{ dx / length, dy / length };
        const top = self.top or self.width + 2 * padding > length;
        const x = (length - self.width) / 2 + self.offset[0];
        const y = (if (top) stroke_width / 2 + padding - self.bounds[1] else -(self.bounds[1] + self.bounds[3]) / 2) + self.offset[1];
        const matrix: c.Matrix = .{ t[0], t[1], -t[1], t[0], first[0] + t[0] * x - t[1] * y, first[1] + t[1] * x + t[0] * y };
        var bounds: [4]f64 = .{ std.math.inf(f64), std.math.inf(f64), -std.math.inf(f64), -std.math.inf(f64) };
        for ([_][2]f64{ .{ self.bounds[0], self.bounds[1] }, .{ self.bounds[2], self.bounds[1] }, .{ self.bounds[2], self.bounds[3] }, .{ self.bounds[0], self.bounds[3] } }) |p| {
            const q = transform(matrix, p);
            bounds = .{ @min(bounds[0], q[0]), @min(bounds[1], q[1]), @max(bounds[2], q[0]), @max(bounds[3], q[1]) };
        }
        var gap: ?[2]f64 = null;
        if (!top and y + self.bounds[1] <= stroke_width / 2 + padding and y + self.bounds[3] >= -stroke_width / 2 - padding) {
            const start = @max(0, x + self.bounds[0] - padding);
            const end = @min(length, x + self.bounds[2] + padding);
            if (end > start) gap = .{ start, end };
        }
        return .{ .matrix = matrix, .bounds = bounds, .gap = gap };
    }
    pub fn lineMatrix(self: Caption, placement: Layout, index: usize) c.Matrix {
        const x = (self.width - self.lines[index].width) / 2;
        const y = -leading * @as(f64, @floatFromInt(index));
        return c.multiply(.{ 1, 0, 0, 1, x, y }, placement.matrix);
    }
    pub fn write(self: Caption, a: A, out: *std.ArrayList(u8), placement: Layout) !void {
        try out.appendSlice(a, "0 g BT /Caption 12 Tf\n");
        for (self.lines, 0..) |line, i| {
            const matrix = self.lineMatrix(placement, i);
            try out.print(a, "{d} {d} {d} {d} {d} {d} Tm\n", .{ matrix[0], matrix[1], matrix[2], matrix[3], matrix[4], matrix[5] });
            try d.serialize(a, out, .{ .string = line.text });
            try out.appendSlice(a, " Tj\n");
        }
        try out.appendSlice(a, "ET\n");
    }
};
fn transform(matrix: c.Matrix, p: [2]f64) [2]f64 {
    return .{ p[0] * matrix[0] + p[1] * matrix[2] + matrix[4], p[0] * matrix[1] + p[1] * matrix[3] + matrix[5] };
}
fn dictionary(a: A, entries: []const s.Entry) !s.Value {
    return .{ .dict = try a.dupe(s.Entry, entries) };
}
pub fn fontResource(a: A) !s.Value {
    return dictionary(a, &.{ .{ .key = "Type", .value = .{ .name = "Font" } }, .{ .key = "Subtype", .value = .{ .name = "Type1" } }, .{ .key = "BaseFont", .value = .{ .name = "Helvetica" } }, .{ .key = "Encoding", .value = .{ .name = "WinAnsiEncoding" } } });
}
fn optional(doc: *d.Document, value: s.Value, key: []const u8) !s.Value {
    return doc.resolve(s.get(value, key) orelse .null);
}
pub fn enabled(doc: *d.Document, value: s.Value) !bool {
    const cap = try optional(doc, value, "Cap");
    if (cap == .null) return false;
    if (cap != .boolean) return error.InvalidAnnotationStyle;
    return cap.boolean;
}
pub fn load(doc: *d.Document, value: s.Value) !Caption {
    if (try optional(doc, value, "RC") != .null) return error.UnsupportedAnnotationAppearance;
    var top = false;
    const position = try optional(doc, value, "CP");
    if (position != .null) {
        if (position != .name) return error.InvalidAnnotationStyle;
        if (std.mem.eql(u8, position.name, "Top")) top = true else if (!std.mem.eql(u8, position.name, "Inline")) return error.InvalidAnnotationStyle;
    }
    var offset: [2]f64 = .{ 0, 0 };
    const raw_offset = try optional(doc, value, "CO");
    if (raw_offset != .null) {
        if (raw_offset != .array or raw_offset.array.len != 2) return error.InvalidAnnotationStyle;
        for (&offset, raw_offset.array) |*out, raw| {
            out.* = try s.number(try doc.resolve(raw));
            if (!std.math.isFinite(out.*) or @abs(out.*) > 1e6) return error.InvalidAnnotationStyle;
        }
    }
    const a = doc.allocator();
    const contents = try optional(doc, value, "Contents");
    if (contents != .null and contents != .string) return error.UnsupportedAnnotation;
    const text = if (contents == .null) "" else try @import("annotations.zig").markupText(a, contents.string);
    var normalized: std.ArrayList(u8) = .empty;
    defer normalized.deinit(a);
    for (text, 0..) |ch, i| {
        if (ch == '\n' and i > 0 and text[i - 1] == '\r') continue;
        try normalized.append(a, if (ch == '\r') '\n' else if (ch == '\t') ' ' else ch);
    }
    const font = try fonts.loadValue(doc, try fontResource(a));
    var lines: std.ArrayList(Line) = .empty;
    var split = std.mem.splitScalar(u8, normalized.items, '\n');
    var width: f64 = 0;
    var visible = false;
    while (split.next()) |line| {
        if (lines.items.len >= 64) return error.TextLimit;
        const encoded = try font.encode(a, line);
        var advance: f64 = 0;
        for (encoded) |byte| advance += font.width(.{ .value = byte, .length = 1 }) * size / 1000;
        width = @max(width, advance);
        visible = visible or encoded.len != 0;
        try lines.append(a, .{ .text = encoded, .width = advance });
    }
    var bounds: [4]f64 = .{ 0, 0, width, 0 };
    for (lines.items, 0..) |line, i| {
        var x = (width - line.width) / 2;
        const y = -leading * @as(f64, @floatFromInt(i));
        for (line.text) |byte| {
            const code = fonts.Code{ .value = byte, .length = 1 };
            const box = try font.bounds(code);
            bounds = .{ @min(bounds[0], x + box[0] * size), @min(bounds[1], y + box[1] * size), @max(bounds[2], x + box[2] * size), @max(bounds[3], y + box[3] * size) };
            x += font.width(code) * size / 1000;
        }
    }
    return .{ .font = font, .lines = try lines.toOwnedSlice(a), .width = width, .bounds = bounds, .top = top, .offset = offset, .visible = visible };
}

test "caption placement respects inline gaps top offsets rotation and long labels" {
    var caption = Caption{ .font = undefined, .lines = &.{.{ .text = "Label", .width = 40 }}, .width = 40, .bounds = .{ 0, -2, 40, 8 }, .top = false, .offset = .{ 0, 0 }, .visible = true };
    var placement = caption.layout(.{ 10, 50 }, .{ 110, 50 }, 2).?;
    try std.testing.expectEqualDeep([6]f64{ 1, 0, 0, 1, 40, 47 }, placement.matrix);
    try std.testing.expectEqualDeep([4]f64{ 40, 45, 80, 55 }, placement.bounds);
    try std.testing.expectEqualDeep([2]f64{ 27, 73 }, placement.gap.?);
    caption.offset = .{ 8, 20 };
    placement = caption.layout(.{ 10, 50 }, .{ 110, 50 }, 2).?;
    try std.testing.expectEqualDeep([4]f64{ 48, 65, 88, 75 }, placement.bounds);
    try std.testing.expect(placement.gap == null);
    caption.offset = .{ 8, 0 };
    try std.testing.expectEqualDeep([2]f64{ 35, 81 }, caption.layout(.{ 10, 50 }, .{ 110, 50 }, 2).?.gap.?);
    caption.offset = .{ 0, 0 };
    caption.top = true;
    placement = caption.layout(.{ 10, 50 }, .{ 110, 50 }, 2).?;
    try std.testing.expectEqualDeep([4]f64{ 40, 54, 80, 64 }, placement.bounds);
    try std.testing.expect(placement.gap == null);
    caption.top = false;
    placement = caption.layout(.{ 110, 50 }, .{ 10, 50 }, 2).?;
    try std.testing.expectEqualDeep([6]f64{ -1, 0, 0, -1, 80, 53 }, placement.matrix);
    placement = caption.layout(.{ 50, 10 }, .{ 50, 110 }, 2).?;
    try std.testing.expectEqualDeep([6]f64{ 0, 1, -1, 0, 53, 40 }, placement.matrix);
    placement = caption.layout(.{ 10, 50 }, .{ 40, 50 }, 2).?;
    try std.testing.expectEqualDeep([4]f64{ 5, 54, 45, 64 }, placement.bounds);
    try std.testing.expect(placement.gap == null);
    try std.testing.expect(caption.layout(.{ 10, 50 }, .{ 10, 50 }, 2).?.gap == null);
    caption.visible = false;
    try std.testing.expect(caption.layout(.{ 10, 50 }, .{ 110, 50 }, 2) == null);
}

fn parseTest(doc: *d.Document, bytes: []const u8) !s.Value {
    var parser = s.Parser{ .allocator = doc.allocator(), .bytes = bytes };
    return parser.value();
}
test "caption decoding normalizes line breaks and keeps WinAnsi text in its own font" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    const caption = try load(&doc, try parseTest(&doc, "<< /Contents <FEFF00480069000D000A00430061006600E90009002020AC000D0058000A> /CP /Top /CO [3 -4] >>"));
    try std.testing.expectEqual(@as(usize, 4), caption.lines.len);
    try std.testing.expectEqualStrings("Hi", caption.lines[0].text);
    try std.testing.expectEqualStrings("Caf\xe9  \x80", caption.lines[1].text);
    try std.testing.expectEqualStrings("X", caption.lines[2].text);
    try std.testing.expectEqualStrings("", caption.lines[3].text);
    try std.testing.expectApproxEqAbs(@as(f64, 11.328), caption.lines[0].width, 1e-9);
    try std.testing.expect(caption.top and caption.visible);
    try std.testing.expectEqualDeep([2]f64{ 3, -4 }, caption.offset);
    const placement = caption.layout(.{ 0, 0 }, .{ 200, 0 }, 2).?;
    const second = caption.lineMatrix(placement, 1);
    try std.testing.expectApproxEqAbs(placement.matrix[5] - leading, second[5], 1e-9);
    try std.testing.expectApproxEqAbs(placement.matrix[4], second[4], 1e-9);
    try std.testing.expect(!(try load(&doc, try parseTest(&doc, "<< >>"))).visible);
    try std.testing.expect(!try enabled(&doc, try parseTest(&doc, "<< /Cap false >>")));
    try std.testing.expect(try enabled(&doc, try parseTest(&doc, "<< /Cap true >>")));
}

test "invalid caption metadata and unrepresentable text fail explicitly" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    for ([_][]const u8{ "<< /CP /Elsewhere >>", "<< /CP 1 >>", "<< /CO [1] >>", "<< /CO [0 1000001] >>" }) |input| {
        try std.testing.expectError(error.InvalidAnnotationStyle, load(&doc, try parseTest(&doc, input)));
    }
    try std.testing.expectError(error.InvalidAnnotationStyle, enabled(&doc, try parseTest(&doc, "<< /Cap 1 >>")));
    try std.testing.expectError(error.UnsupportedAnnotationAppearance, load(&doc, try parseTest(&doc, "<< /RC (<p>Rich</p>) >>")));
    try std.testing.expectError(error.UnsupportedEncoding, load(&doc, try parseTest(&doc, "<< /Contents <FEFF4E2D6587> >>")));
    try std.testing.expectError(error.UnsupportedAnnotation, load(&doc, try parseTest(&doc, "<< /Contents 1 >>")));
    var many_lines: [64]u8 = undefined;
    @memset(&many_lines, '\n');
    const value = try dictionary(doc.allocator(), &.{.{ .key = "Contents", .value = .{ .string = &many_lines } }});
    try std.testing.expectError(error.TextLimit, load(&doc, value));
}
