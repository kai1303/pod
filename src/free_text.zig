//! Plain FreeText layout when a PDF has no saved normal appearance.
const std = @import("std");
const d = @import("document.zig");
const s = @import("syntax.zig");
const fonts = @import("pdf_font.zig");
const shapes = @import("shape_appearance.zig");
const c = @import("content.zig");
const A = std.mem.Allocator;
const eq = std.mem.eql;
pub const Line = struct { text: []const u8, width: f64, left: f64 = 0 };
pub const Spacing = struct {
    character: f64 = 0,
    word: f64 = 0,

    pub fn extra(self: Spacing, font: *const fonts.Font, code: fonts.Code) f64 {
        return self.character + (if (font.wordSpacing(code)) self.word else @as(f64, 0));
    }
    pub fn write(self: Spacing, a: A, out: *std.ArrayList(u8)) !void {
        if (self.character != 0) try out.print(a, " {d} Tc\n", .{self.character});
        if (self.word != 0) try out.print(a, " {d} Tw\n", .{self.word});
    }
};
pub const Text = struct {
    style: @import("annotations.zig").Style,
    rect: [4]f64,
    box: [4]f64,
    font: *const fonts.Font,
    font_resource: s.Value,
    resource_name: []const u8,
    size: f64,
    horizontal_scale: f64,
    spacing: Spacing,
    color: [3]u8,
    background: ?[3]u8,
    border: shapes.Shape,
    callout: ?shapes.Shape,
    matrix: c.Matrix,
    width: f64,
    height: f64,
    alignment: usize,
    lines: []const Line,

    pub fn local(self: Text) Text {
        var result = self;
        for (&result.box, 0..) |*v, i| v.* -= self.rect[i % 2];
        result.matrix[4] -= self.rect[0];
        result.matrix[5] -= self.rect[1];
        result.border = self.border.local(self.rect);
        if (self.callout) |callout| result.callout = callout.local(self.rect);
        result.rect = .{ 0, 0, self.rect[2] - self.rect[0], self.rect[3] - self.rect[1] };
        return result;
    }
    pub fn resources(self: Text, a: A) !s.Value {
        const states = try shapes.resources(a, self.style.opacity, false);
        const font = try dictionary(a, &.{.{ .key = "Text", .value = self.font_resource }});
        return dictionary(a, &.{ .{ .key = "ExtGState", .value = s.get(states, "ExtGState").? }, .{ .key = "Font", .value = font } });
    }
    pub fn program(self: Text, a: A) ![]const u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(a);
        try out.appendSlice(a, "q /GS gs\n");
        if (self.callout) |callout| {
            const drawing = try callout.program(a);
            defer a.free(drawing);
            try out.appendSlice(a, drawing);
        }
        if (self.style.fill) |fill| {
            try out.print(a, "{d} {d} {d} rg\n", .{ fill[0], fill[1], fill[2] });
            try writeRect(a, &out, self.box);
            try out.appendSlice(a, "f\n");
        }
        const border = try self.border.program(a);
        defer a.free(border);
        try out.appendSlice(a, border);
        const w = self.border.width;
        const clip = [4]f64{ self.box[0] + w, self.box[1] + w, self.box[2] - w, self.box[3] - w };
        if (clip[2] > clip[0] and clip[3] > clip[1]) {
            try writeRect(a, &out, clip);
            try out.appendSlice(a, "W n\n");
            const ink = self.style.stroke;
            try out.print(a, "{d} {d} {d} rg\nBT /Text {d} Tf\n", .{ ink[0], ink[1], ink[2], self.size });
            if (self.horizontal_scale != 100) try out.print(a, "{d} Tz\n", .{self.horizontal_scale});
            try self.spacing.write(a, &out);
            for (self.lines, 0..) |line, i| {
                const m = self.lineMatrix(i);
                try out.print(a, "{d} {d} {d} {d} {d} {d} Tm\n", .{ m[0], m[1], m[2], m[3], m[4], m[5] });
                try d.serialize(a, &out, .{ .string = line.text });
                try out.appendSlice(a, " Tj\n");
            }
            try out.appendSlice(a, "ET\n");
        }
        try out.appendSlice(a, "Q\n");
        return out.toOwnedSlice(a);
    }
    pub fn lineMatrix(self: Text, i: usize) c.Matrix {
        const inset = self.border.width * 2;
        const spare = self.width - inset * 2 - self.lines[i].width;
        const x = inset + (if (self.alignment == 1) spare / 2 else if (self.alignment == 2) spare else 0) - self.lines[i].left;
        const y = self.height - inset - self.size * (0.8 + 1.2 * @as(f64, @floatFromInt(i)));
        return c.multiply(.{ 1, 0, 0, 1, x, y }, self.matrix);
    }
};
fn writeRect(a: A, out: *std.ArrayList(u8), box: [4]f64) !void {
    try out.print(a, "{d} {d} {d} {d} re\n", .{ box[0], box[1], box[2] - box[0], box[3] - box[1] });
}
pub fn canonical(doc: *d.Document, value: s.Value) !bool {
    const marker = try optional(doc, value, "PodFreeTextAppearance");
    if (marker != .integer or marker.integer != 1) return false;
    const text = (try load(doc, value)).local();
    return shapes.matchesAppearance(doc, value, "PodFreeTextAppearance", try text.resources(doc.allocator()), try text.program(doc.allocator()));
}
fn optional(doc: *d.Document, v: s.Value, key: []const u8) !s.Value {
    return doc.resolve(s.get(v, key) orelse .null);
}
fn number(v: s.Value) !f64 {
    const n = try s.number(v);
    if (!std.math.isFinite(n) or @abs(n) > 1e6) return error.InvalidAnnotationStyle;
    return n;
}
fn dictionary(a: A, entries: []const s.Entry) !s.Value {
    return .{ .dict = try a.dupe(s.Entry, entries) };
}
fn numbers(a: A, input: []const f64) !s.Value {
    const values = try a.alloc(s.Value, input.len);
    for (values, input) |*v, n| v.* = .{ .real = n };
    return .{ .array = values };
}
const Default = struct { font: []const u8, size: f64, color: [3]f64, horizontal_scale: f64 = 100, spacing: Spacing = .{} };
fn defaultAppearance(a: A, bytes: []const u8) !Default {
    if (bytes.len > 65536) return error.TextLimit;
    var parser = s.Parser{ .allocator = a, .bytes = bytes };
    var args: [3]s.Value = undefined;
    var count: usize = 0;
    var result = Default{ .font = "", .size = 0, .color = .{ 0, 0, 0 } };
    while (true) {
        parser.skip();
        if (parser.pos == bytes.len) break;
        const ch = bytes[parser.pos];
        if (ch == '/' or ch == '+' or ch == '-' or ch == '.' or (ch >= '0' and ch <= '9')) {
            if (count == args.len) return error.InvalidAnnotationStyle;
            args[count] = try parser.value();
            count += 1;
            continue;
        }
        const op = try parser.token();
        if (eq(u8, op, "Tf")) {
            if (count != 2 or args[0] != .name) return error.InvalidAnnotationStyle;
            result.font = args[0].name;
            result.size = try number(args[1]);
            if (result.size < 0) return error.UnsupportedAnnotationAppearance;
        } else if (eq(u8, op, "g") or eq(u8, op, "rg")) {
            if (count != (if (eq(u8, op, "g")) @as(usize, 1) else 3)) return error.InvalidAnnotationStyle;
            for (&result.color, 0..) |*channel, i| channel.* = std.math.clamp(try number(args[if (count == 1) 0 else i]), 0, 1);
        } else if (eq(u8, op, "Tc") or eq(u8, op, "Tw")) {
            if (count != 1) return error.InvalidAnnotationStyle;
            const n = try number(args[0]);
            if (eq(u8, op, "Tc")) result.spacing.character = n else result.spacing.word = n;
        } else if (eq(u8, op, "Tz")) {
            if (count != 1) return error.InvalidAnnotationStyle;
            result.horizontal_scale = try number(args[0]);
            if (result.horizontal_scale <= 0) return error.UnsupportedAnnotationAppearance;
        } else if (eq(u8, op, "Tr")) {
            if (count != 1 or try number(args[0]) != 0) return error.UnsupportedAnnotationAppearance;
        } else return error.UnsupportedAnnotationAppearance;
        count = 0;
    }
    if (count != 0 or result.font.len == 0) return error.InvalidAnnotationStyle;
    return result;
}
fn fontResource(a: A, name: []const u8) !s.Value {
    const aliases = [_][]const u8{ "Cour", "CoBo", "CoOb", "CoBO", "Helv", "HeBo", "HeOb", "HeBO", "TiRo", "TiBo", "TiIt", "TiBI", "Symb", "ZaDb" };
    for (fonts.metrics.names, aliases, 0..) |base, alias, i| {
        if (!eq(u8, name, base) and !eq(u8, name, alias)) continue;
        const entries = [_]s.Entry{ .{ .key = "Type", .value = .{ .name = "Font" } }, .{ .key = "Subtype", .value = .{ .name = "Type1" } }, .{ .key = "BaseFont", .value = .{ .name = base } }, .{ .key = "Encoding", .value = .{ .name = "WinAnsiEncoding" } } };
        return dictionary(a, entries[0..if (i < 12) @as(usize, 4) else 3]);
    }
    return error.UnsupportedFont;
}
fn resolveFont(doc: *d.Document, name: []const u8) !s.Value {
    const root = try doc.resolve(s.get(doc.trailer, "Root").?);
    const form = try optional(doc, root, "AcroForm");
    if (form != .null) {
        if (form != .dict) return error.UnsupportedFont;
        const dr = try optional(doc, form, "DR");
        if (dr != .null) {
            if (dr != .dict) return error.UnsupportedFont;
            const resources = try optional(doc, dr, "Font");
            if (resources != .null) {
                if (resources != .dict) return error.UnsupportedFont;
                if (s.get(resources, name)) |resource| return resource;
            }
        }
    }
    return fontResource(doc.allocator(), name);
}
fn rgb(values: [3]f64) [3]u8 {
    var result: [3]u8 = undefined;
    for (&result, values) |*v, n| v.* = @intFromFloat(@round(n * 255));
    return result;
}
const Glyph = struct { end: usize, width: f64, space: bool, spacing: f64 = 0 };
const Paragraph = struct { text: []const u8, glyphs: []const Glyph, spaced: bool };
// Positions are affine in font size because PDF spacing is in unscaled text units.
const Position = struct {
    slope: f64 = 0,
    constant: f64 = 0,

    fn at(self: Position, size: f64) f64 {
        return self.slope * size + self.constant;
    }
    fn less(self: Position, other: Position, size: f64) bool {
        if (self.slope == other.slope) return self.constant < other.constant;
        // Use the same crossing as the interval search, including at rounding boundaries.
        const crossing = (other.constant - self.constant) / (self.slope - other.slope);
        return if (self.slope > other.slope) size < crossing else size > crossing;
    }
};
const Extent = struct {
    minimum: Position = .{},
    maximum: Position = .{},

    fn width(self: Extent) Position {
        return .{ .slope = self.maximum.slope - self.minimum.slope, .constant = self.maximum.constant - self.minimum.constant };
    }
    fn include(self: *Extent, position: Position, size: f64, probe: ?*FitProbe) !void {
        if (probe) |p| {
            try p.boundary(position, self.minimum);
            try p.boundary(position, self.maximum);
        }
        if (position.less(self.minimum, size)) self.minimum = position;
        if (self.maximum.less(position, size)) self.maximum = position;
    }
};
const FitProbe = struct {
    size: f64,
    change: f64 = 0,
    lower: f64 = 0,
    upper: f64,
    possible: bool = true,
    work: *usize,

    fn boundary(self: *FitProbe, a: Position, b: Position) !void {
        self.work.* += 1;
        if (self.work.* > 1_000_000) return error.TextLimit;
        if (a.slope == b.slope) return;
        const crossing = (b.constant - a.constant) / (a.slope - b.slope);
        if (crossing > 0 and crossing <= self.size) self.change = @max(self.change, crossing);
    }
    fn constrain(self: *FitProbe, position: Position, limit: f64) void {
        if (position.slope > 0) {
            self.upper = @min(self.upper, (limit - position.constant) / position.slope);
        } else if (position.slope < 0) {
            self.lower = @max(self.lower, (limit - position.constant) / position.slope);
        } else if (position.constant > limit) self.possible = false;
    }
};
fn measure(glyphs: []const Glyph, size: f64, probe: ?*FitProbe) !Extent {
    var extent: Extent = .{};
    var pen: Position = .{};
    for (glyphs) |glyph| {
        if (!glyph.space) try extent.include(pen, size, probe);
        pen.slope += glyph.width;
        if (!glyph.space) try extent.include(pen, size, probe);
        pen.constant += glyph.spacing;
    }
    return extent;
}
fn spacedLineEnd(glyphs: []const Glyph, start: usize, size: f64, width: f64, probe: ?*FitProbe) !usize {
    var extent: Extent = .{};
    var pen: Position = .{};
    var end = start;
    var last_space = start;
    while (end < glyphs.len) {
        const glyph = glyphs[end];
        if (!glyph.space) try extent.include(pen, size, probe);
        pen.slope += glyph.width;
        if (!glyph.space) try extent.include(pen, size, probe);
        pen.constant += glyph.spacing;
        if (probe) |p| try p.boundary(extent.width(), .{ .constant = width });
        if (!glyph.space and (Position{ .constant = width }).less(extent.width(), size) and end > start) break;
        end += 1;
        if (glyph.space) last_space = end;
    }
    if (end < glyphs.len) {
        if (last_space > start) return last_space;
        while (end < glyphs.len and !glyphs[end].space) : (end += 1) {}
        if (end < glyphs.len) end += 1;
    }
    return end;
}
fn spacedFits(paragraphs: []const Paragraph, size: f64, width: f64, height: f64) !bool {
    var count: usize = 0;
    for (paragraphs) |paragraph| {
        var start: usize = 0;
        while (true) {
            const end = try spacedLineEnd(paragraph.glyphs, start, size, width, null);
            count += 1;
            if (count > 4096 or @as(f64, @floatFromInt(count)) * 1.2 * size > height) return false;
            if ((Position{ .constant = width }).less((try measure(paragraph.glyphs[start..end], size, null)).width(), size)) return false;
            if (end == paragraph.glyphs.len) break;
            start = end;
        }
    }
    return true;
}
fn spacedAutoSize(paragraphs: []const Paragraph, width: f64, height: f64) !f64 {
    var size = @min(200, height / 1.2 / @as(f64, @floatFromInt(paragraphs.len)));
    var has_text = false;
    for (paragraphs) |paragraph| for (paragraph.glyphs) |glyph| {
        if (!glyph.space) has_text = true;
    };
    if (!has_text) size = @min(size, 12);
    var work: usize = 0;
    // Between recorded crossings, glyph extrema and wrapping decisions are fixed.
    // Search those intervals from largest to smallest; signed spacing is not monotone.
    while (size > 0) {
        var probe = FitProbe{ .size = size, .upper = size, .work = &work };
        var count: usize = 0;
        outer: for (paragraphs) |paragraph| {
            var start: usize = 0;
            while (true) {
                const end = try spacedLineEnd(paragraph.glyphs, start, size, width, &probe);
                const extent = try measure(paragraph.glyphs[start..end], size, &probe);
                probe.constrain(extent.width(), width);
                count += 1;
                if (count > 4096) {
                    probe.possible = false;
                    break :outer;
                }
                if (end == paragraph.glyphs.len) break;
                start = end;
            }
        }
        probe.upper = @min(probe.upper, height / (1.2 * @as(f64, @floatFromInt(count))));
        var candidate = probe.upper;
        for (0..4) |_| {
            if (!probe.possible or candidate <= 0 or candidate < probe.lower or candidate < probe.change) break;
            if (try spacedFits(paragraphs, candidate, width, height)) return candidate;
            candidate = std.math.nextAfter(f64, candidate, 0);
        }
        if (probe.change == 0) break;
        size = if (probe.change < size) probe.change else std.math.nextAfter(f64, size, 0);
    }
    return error.TextOverflow;
}
fn advance(glyphs: []const Glyph) f64 {
    var end = glyphs.len;
    while (end > 0 and glyphs[end - 1].space) end -= 1;
    var width: f64 = 0;
    for (glyphs[0..end]) |glyph| width += glyph.width;
    return width;
}
fn encodedParagraphs(a: A, font: *const fonts.Font, text: []const u8, spacing: Spacing) ![]const Paragraph {
    var normalized: std.ArrayList(u8) = .empty;
    defer normalized.deinit(a);
    for (text, 0..) |ch, i| {
        if (ch == '\n' and i > 0 and text[i - 1] == '\r') continue;
        try normalized.append(a, if (ch == '\r') '\n' else if (ch == '\t') ' ' else ch);
    }
    var result: std.ArrayList(Paragraph) = .empty;
    var decoded: std.ArrayList(u8) = .empty;
    defer decoded.deinit(a);
    var paragraphs = std.mem.splitScalar(u8, normalized.items, '\n');
    while (paragraphs.next()) |paragraph| {
        if (result.items.len >= 4096) return error.TextLimit;
        const encoded = try font.encode(a, paragraph);
        var glyphs: std.ArrayList(Glyph) = .empty;
        var at: usize = 0;
        var start: usize = 0;
        while (try font.nextCode(encoded, &at)) |code| {
            decoded.clearRetainingCapacity();
            try font.decode(a, encoded[start..at], &decoded);
            try glyphs.append(a, .{ .end = at, .width = font.width(code) / 1000, .space = eq(u8, decoded.items, " "), .spacing = spacing.extra(font, code) });
            start = at;
        }
        try result.append(a, .{ .text = encoded, .glyphs = try glyphs.toOwnedSlice(a), .spaced = spacing.character != 0 or spacing.word != 0 });
    }
    return result.toOwnedSlice(a);
}
fn lineEnd(glyphs: []const Glyph, start: usize, size: f64, width: f64) usize {
    var end = start;
    var last_space = start;
    var distance: f64 = 0;
    while (end < glyphs.len) {
        const next = distance + glyphs[end].width * size;
        if (next > width and end > start) {
            // A trailing separator must not eject the word that already fits.
            if (glyphs[end].space) {
                while (end < glyphs.len and glyphs[end].space) : (end += 1) {}
                last_space = end;
            }
            break;
        }
        distance = next;
        end += 1;
        if (glyphs[end - 1].space) last_space = end;
    }
    if (end < glyphs.len) {
        if (last_space > start) {
            end = last_space;
        } else {
            // Keep an unbreakable word intact; the text rectangle clips overflow.
            while (end < glyphs.len and !glyphs[end].space) : (end += 1) {}
            if (end < glyphs.len) end += 1;
        }
    }
    return end;
}
fn wrapEncoded(a: A, paragraphs: []const Paragraph, size: f64, width: f64) ![]Line {
    var lines: std.ArrayList(Line) = .empty;
    for (paragraphs) |paragraph| {
        var start: usize = 0;
        while (true) {
            if (lines.items.len >= 4096) return error.TextLimit;
            const end = if (paragraph.spaced) try spacedLineEnd(paragraph.glyphs, start, size, width, null) else lineEnd(paragraph.glyphs, start, size, width);
            const first_byte = if (start == 0) 0 else paragraph.glyphs[start - 1].end;
            const last_byte = if (end == 0) 0 else paragraph.glyphs[end - 1].end;
            const extent = if (paragraph.spaced) try measure(paragraph.glyphs[start..end], size, null) else Extent{ .maximum = .{ .slope = advance(paragraph.glyphs[start..end]) } };
            try lines.append(a, .{ .text = paragraph.text[first_byte..last_byte], .width = extent.width().at(size), .left = extent.minimum.at(size) });
            if (end == paragraph.glyphs.len) break;
            start = end;
        }
    }
    return lines.toOwnedSlice(a);
}
fn wrap(a: A, font: *const fonts.Font, text: []const u8, size: f64, width: f64) ![]const Line {
    return wrapEncoded(a, try encodedParagraphs(a, font, text, .{}), size, width);
}
fn fits(paragraphs: []const Paragraph, size: f64, width: f64, height: f64) bool {
    var count: usize = 0;
    for (paragraphs) |paragraph| {
        var start: usize = 0;
        while (true) {
            const end = lineEnd(paragraph.glyphs, start, size, width);
            count += 1;
            if (count > 4096 or @as(f64, @floatFromInt(count)) * 1.2 * size > height) return false;
            if (advance(paragraph.glyphs[start..end]) * size > width) return false;
            if (end == paragraph.glyphs.len) break;
            start = end;
        }
    }
    return true;
}
fn autoSize(paragraphs: []const Paragraph, width: f64, height: f64) !f64 {
    if (width <= 0 or height <= 0) return error.TextOverflow;
    if (paragraphs[0].spaced) return spacedAutoSize(paragraphs, width, height);
    var longest: f64 = 0;
    for (paragraphs) |paragraph| {
        var word: f64 = 0;
        for (paragraph.glyphs) |glyph| {
            if (glyph.space) {
                word = 0;
            } else {
                word += glyph.width;
                longest = @max(longest, word);
            }
        }
    }
    var upper = @min(200, height / 1.2 / @as(f64, @floatFromInt(paragraphs.len)));
    upper = @min(upper, if (longest > 0) width / longest else 12);
    var lower: f64 = 0;
    // Trial layout scans encoded text without allocating; only the final layout is retained.
    for (0..32) |_| {
        const middle = (lower + upper) / 2;
        if (fits(paragraphs, middle, width, height)) lower = middle else upper = middle;
    }
    if (lower <= 0) return error.TextOverflow;
    return lower;
}
pub fn load(doc: *d.Document, value: s.Value) !Text {
    const a = doc.allocator();
    for ([_][]const u8{ "RC", "DS" }) |key| if (try optional(doc, value, key) != .null) return error.UnsupportedAnnotationAppearance;
    const da = try optional(doc, value, "DA");
    if (da != .string) return error.InvalidAnnotationStyle;
    const style = try defaultAppearance(a, da.string);
    const font_resource = try resolveFont(doc, style.font);
    const font = try fonts.loadValue(doc, font_resource);
    if (font.vertical()) return error.UnsupportedAnnotationAppearance;
    const rect = try d.rectangle(try optional(doc, value, "Rect"));
    var box = rect;
    const rd = try optional(doc, value, "RD");
    if (rd != .null) {
        if (rd != .array or rd.array.len != 4) return error.InvalidAnnotationGeometry;
        // Follow interoperable Rect order; PDF Association issue 592 tracks the spec wording.
        for (&box, rd.array, 0..) |*coordinate, raw, i| {
            const inset = try number(try doc.resolve(raw));
            if (inset < 0) return error.InvalidAnnotationGeometry;
            coordinate.* += if (i < 2) inset else -inset;
        }
        if (box[2] <= box[0] or box[3] <= box[1]) return error.InvalidAnnotationGeometry;
    }
    const q = try optional(doc, value, "Q");
    const alignment = if (q == .null) 0 else try s.uint(q);
    if (alignment > 2) return error.InvalidAnnotationStyle;
    const rotate = try optional(doc, value, "Rotate");
    const angle = if (rotate == .null) 0 else try s.uint(rotate);
    if (angle != 0 and angle != 90 and angle != 180 and angle != 270) return error.InvalidAnnotationStyle;
    var entries: std.ArrayList(s.Entry) = .empty;
    try entries.appendSlice(a, &.{ .{ .key = "Subtype", .value = .{ .name = "Square" } }, .{ .key = "Rect", .value = try numbers(a, &box) }, .{ .key = "C", .value = try numbers(a, &style.color) } });
    for ([_][]const u8{ "BS", "Border", "BE", "CA" }) |key| if (s.get(value, key)) |v| try entries.append(a, .{ .key = key, .value = v });
    const border = try shapes.load(doc, .{ .dict = entries.items });
    var background: ?[3]u8 = null;
    var fill: ?[3]f64 = null;
    const color = try optional(doc, value, "C");
    if (color != .null) {
        if (color != .array or (color.array.len != 0 and color.array.len != 1 and color.array.len != 3)) return error.UnsupportedColorSpace;
        if (color.array.len != 0) {
            var components: [3]f64 = undefined;
            for (&components, 0..) |*v, i| {
                v.* = try number(try doc.resolve(color.array[if (color.array.len == 1) 0 else i]));
                if (v.* < 0 or v.* > 1) return error.InvalidAnnotationStyle;
            }
            background = rgb(components);
            fill = components;
        }
    }
    var callout: ?shapes.Shape = null;
    const intent = try optional(doc, value, "IT");
    if (intent != .null) {
        if (intent != .name) return error.InvalidAnnotationStyle;
        if (eq(u8, intent.name, "FreeTextCallout")) {
            const cl = try optional(doc, value, "CL");
            if (cl != .array or (cl.array.len != 4 and cl.array.len != 6)) return error.InvalidAnnotationGeometry;
            entries.items[0].value = .{ .name = "PolyLine" };
            try entries.append(a, .{ .key = "Vertices", .value = cl });
            if (color != .null) try entries.append(a, .{ .key = "IC", .value = color });
            const ending = try optional(doc, value, "LE");
            if (ending != .null) {
                const ends = try a.dupe(s.Value, &.{ ending, .{ .name = "None" } });
                try entries.append(a, .{ .key = "LE", .value = .{ .array = ends } });
            }
            callout = try shapes.load(doc, .{ .dict = entries.items });
        } else if (!eq(u8, intent.name, "FreeText") and !eq(u8, intent.name, "FreeTextTypeWriter")) return error.UnsupportedAnnotationAppearance;
    }
    const w = box[2] - box[0];
    const h = box[3] - box[1];
    const width = if (angle == 90 or angle == 270) h else w;
    const height = if (angle == 90 or angle == 270) w else h;
    const matrix: c.Matrix = switch (angle) {
        0 => .{ 1, 0, 0, 1, box[0], box[1] },
        90 => .{ 0, 1, -1, 0, box[2], box[1] },
        180 => .{ -1, 0, 0, -1, box[2], box[3] },
        270 => .{ 0, -1, 1, 0, box[0], box[3] },
        else => unreachable,
    };
    const contents = try optional(doc, value, "Contents");
    if (contents != .null and contents != .string) return error.UnsupportedAnnotation;
    const text = if (contents == .null) "" else try @import("annotations.zig").markupText(a, contents.string);
    if (text.len > 65536) return error.TextLimit;
    const paragraphs = try encodedParagraphs(a, font, text, style.spacing);
    const usable_width = @max(0, width - border.width * 4);
    const scale = style.horizontal_scale / 100;
    const size = if (style.size == 0) try autoSize(paragraphs, usable_width / scale, height - border.width * 4) else style.size;
    const lines = try wrapEncoded(a, paragraphs, size, usable_width / scale);
    for (lines) |*line| {
        line.width *= scale;
        line.left *= scale;
    }
    return .{ .style = .{ .stroke = style.color, .fill = fill, .opacity = border.opacity, .width = border.width, .font_size = style.size }, .rect = rect, .box = box, .font = font, .font_resource = font_resource, .resource_name = style.font, .size = size, .horizontal_scale = style.horizontal_scale, .spacing = style.spacing, .color = rgb(style.color), .background = background, .border = border, .callout = callout, .matrix = matrix, .width = width, .height = height, .alignment = alignment, .lines = lines };
}

fn parseTest(doc: *d.Document, bytes: []const u8) !s.Value {
    var parser = s.Parser{ .allocator = doc.allocator(), .bytes = bytes };
    return parser.value();
}
test "FreeText horizontal scaling controls wrapping alignment and automatic fitting" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    const narrow = try load(&doc, try parseTest(&doc, "<< /Rect [0 0 30 60] /DA (/Cour 10 Tf 50 Tz) /Contents (AB CD EF) /BS << /W 0 >> /Q 2 >>"));
    try std.testing.expectEqual(@as(usize, 1), narrow.lines.len);
    try std.testing.expectEqual(@as(f64, 24), narrow.lines[0].width);
    try std.testing.expectEqual(@as(f64, 6), narrow.lineMatrix(0)[4]);
    const wide = try load(&doc, try parseTest(&doc, "<< /Rect [0 0 30 60] /DA (50 Tz /Cour 10 Tf 200 Tz) /Contents (AB CD EF) /BS << /W 0 >> /Q 1 >>"));
    try std.testing.expectEqual(@as(usize, 3), wide.lines.len);
    try std.testing.expectEqualStrings("AB ", wide.lines[0].text);
    try std.testing.expectEqual(@as(f64, 24), wide.lines[0].width);
    try std.testing.expectEqual(@as(f64, 3), wide.lineMatrix(0)[4]);
    const fitted = try load(&doc, try parseTest(&doc, "<< /Rect [0 0 120 60] /DA (/Cour 0 Tf 200 Tz) /Contents (MMMM) /BS << /W 0 >> >>"));
    try std.testing.expectApproxEqAbs(@as(f64, 25), fitted.size, 0.000001);
    try std.testing.expect(fitted.lines[0].width <= 120);
    const rotated = try load(&doc, try parseTest(&doc, "<< /Rect [0 0 120 60] /DA (/Cour 0 Tf 200 Tz) /Contents (MMMM) /BS << /W 0 >> /Rotate 90 >>"));
    try std.testing.expectApproxEqAbs(@as(f64, 12.5), rotated.size, 0.000001);
    for ([_][]const u8{ "/Cour 10 Tf Tz", "/Cour 10 Tf 50 60 Tz", "/Cour 10 Tf /Bad Tz", "/Cour 10 Tf 1000001 Tz" }) |input| {
        _ = defaultAppearance(doc.allocator(), input) catch continue;
        return error.AcceptedInvalidScale;
    }
    for ([_][]const u8{ "/Cour 10 Tf 0 Tz", "/Cour 10 Tf -100 Tz" }) |input| {
        try std.testing.expectError(error.UnsupportedAnnotationAppearance, defaultAppearance(doc.allocator(), input));
    }
}
test "FreeText spacing measures glyph extents including backward advances" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    const spaced = try load(&doc, try parseTest(&doc, "<< /Rect [0 0 100 60] /DA (/Cour 10 Tf 1 Tc 2 Tw 50 Tz) /Contents (AB CD   ) /BS << /W 0 >> /Q 2 >>"));
    try std.testing.expectEqual(@as(f64, 18), spaced.lines[0].width);
    try std.testing.expectEqual(@as(f64, 82), spaced.lineMatrix(0)[4]);
    const backwards = try load(&doc, try parseTest(&doc, "<< /Rect [0 0 100 60] /DA (/Cour 10 Tf -10 Tc) /Contents (ABC) /BS << /W 0 >> >>"));
    try std.testing.expectEqual(@as(f64, 14), backwards.lines[0].width);
    try std.testing.expectEqual(@as(f64, 8), backwards.lineMatrix(0)[4]);
    const words = try load(&doc, try parseTest(&doc, "<< /Rect [0 0 100 60] /DA (/Cour 10 Tf -30 Tw) /Contents (A A A) /BS << /W 0 >> >>"));
    try std.testing.expectEqual(@as(f64, 42), words.lines[0].width);
    try std.testing.expectEqual(@as(f64, 36), words.lineMatrix(0)[4]);
    const wrapped = try load(&doc, try parseTest(&doc, "<< /Rect [0 0 27 60] /DA (/Cour 10 Tf 1 Tc 2 Tw) /Contents (AB CD) /BS << /W 0 >> >>"));
    try std.testing.expectEqual(@as(usize, 2), wrapped.lines.len);
    try std.testing.expectEqualStrings("AB ", wrapped.lines[0].text);
    try std.testing.expectEqual(@as(f64, 13), wrapped.lines[0].width);
}
test "FreeText auto fitting finds the largest size with signed spacing" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    for ([_]struct { da: []const u8, text: []const u8, width: f64, height: f64, expected: f64 }{
        .{ .da = "2 Tc", .text = "ABC", .width = 40, .height = 60, .expected = 20 },
        .{ .da = "-20 Tc", .text = "ABC", .width = 25, .height = 60, .expected = 65.0 / 1.8 },
        .{ .da = "-20 Tc", .text = "ABC", .width = 25, .height = 30, .expected = 25 },
        .{ .da = "-30 Tw", .text = "A A A", .width = 20, .height = 60, .expected = 80.0 / 3.0 },
    }) |case| {
        const input = try std.fmt.allocPrint(doc.allocator(), "<< /Rect [0 0 {d} {d}] /DA (/Cour 0 Tf {s}) /Contents ({s}) /BS << /W 0 >> >>", .{ case.width, case.height, case.da, case.text });
        const fitted = try load(&doc, try parseTest(&doc, input));
        try std.testing.expectApproxEqAbs(case.expected, fitted.size, 0.000001);
        for (fitted.lines) |line| try std.testing.expect(line.width <= case.width + 0.000001);
    }
    try std.testing.expectError(error.TextOverflow, load(&doc, try parseTest(&doc, "<< /Rect [0 0 30 60] /DA (/Cour 0 Tf 20 Tc) /Contents (ABC) /BS << /W 0 >> >>")));
    try std.testing.expectError(error.TextOverflow, load(&doc, try parseTest(&doc, "<< /Rect [0 0 10 60] /DA (/Cour 0 Tf -20 Tc) /Contents (ABC) /BS << /W 0 >> >>")));
}
test "FreeText lays out standard-font Unicode text with wrapping quadding and rotation" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    const text = try load(&doc, try parseTest(&doc, "<< /Rect [20 30 120 230] /DA (.2 g /Cour 10 Tf 0 Tr) /Contents <FEFF00430061006600E9000D000A00410020004200200043000D> /BS << /W 0 >> /Rotate 90 /Q 2 >>"));
    try std.testing.expectEqual(@as(usize, 3), text.lines.len);
    try std.testing.expectEqualStrings("Caf\xe9", text.lines[0].text);
    try std.testing.expectEqualStrings("A B C", text.lines[1].text);
    try std.testing.expectEqualStrings("", text.lines[2].text);
    try std.testing.expectEqualDeep([3]u8{ 51, 51, 51 }, text.color);
    try std.testing.expectEqualDeep(c.Matrix{ 0, 1, -1, 0, 120, 30 }, text.matrix);
    try std.testing.expectEqualDeep(c.Matrix{ 0, 1, -1, 0, 28, 206 }, text.lineMatrix(0));
    const wrapped = try wrap(doc.allocator(), text.font, "One two three\nabcdefgh", 10, 30);
    try std.testing.expectEqual(@as(usize, 4), wrapped.len);
    try std.testing.expectEqualStrings("One ", wrapped[0].text);
    try std.testing.expectEqual(@as(f64, 18), wrapped[0].width);
    try std.testing.expectEqualStrings("two ", wrapped[1].text);
    try std.testing.expectEqualStrings("three", wrapped[2].text);
    try std.testing.expectEqualStrings("abcdefgh", wrapped[3].text);
    const helvetica = try fonts.loadValue(&doc, try fontResource(doc.allocator(), "Helv"));
    const boundary = try wrap(doc.allocator(), helvetica, "Students read, highlight, and explain their thinking.", 16, 106);
    try std.testing.expectEqualStrings("Students read, ", boundary[0].text);
    try std.testing.expectEqual(@as(usize, 4), boundary.len);
    const separators = try wrap(doc.allocator(), text.font, "One two   three", 10, 42);
    try std.testing.expectEqualStrings("One two   ", separators[0].text);
    try std.testing.expectEqual(@as(f64, 42), separators[0].width);
    try std.testing.expectEqualStrings("three", separators[1].text);
}
test "FreeText separates background border callout and text insets" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    const text = try load(&doc, try parseTest(&doc, "<< /Rect [20 30 220 230] /RD [40 50 0 0] /DA (/Helvetica 12 Tf 1 0 0 rg) /C [.5] /CA .4 /BS << /W 2 /S /D /D [3 2] >> /IT /FreeTextCallout /CL [25 35 40 55 60 100] /LE /OpenArrow >>"));
    try std.testing.expectEqualDeep([4]f64{ 60, 80, 220, 230 }, text.box);
    try std.testing.expectEqualDeep([4]f64{ 61, 81, 219, 229 }, text.border.box);
    try std.testing.expectEqualDeep([3]u8{ 128, 128, 128 }, text.background.?);
    try std.testing.expectEqual(@as(f64, 0.4), text.border.opacity);
    try std.testing.expectEqual(@as(usize, 2), text.border.pattern.count);
    try std.testing.expectEqual(@as(usize, 3), text.callout.?.vertices.len);
    try std.testing.expectEqualDeep([3]f64{ 0.5, 0.5, 0.5 }, text.callout.?.fill.?);
    try std.testing.expect(text.callout.?.endings[0] == .OpenArrow);
}
test "FreeText invalid typography and unsupported rich layouts remain explicit" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    for ([_][]const u8{ "", "12 Tf", "/Helv Tf", "/Helv 12 Tf 1 2 rg", "/Helv 12 Tf 1" }) |input| {
        try std.testing.expectError(error.InvalidAnnotationStyle, defaultAppearance(doc.allocator(), input));
    }
    for ([_][]const u8{ "/Helv -1 Tf", "/Helv 12 Tf 1 TL", "/Helv 12 Tf 1 Tr", "/Helv 12 Tf q" }) |input| {
        try std.testing.expectError(error.UnsupportedAnnotationAppearance, defaultAppearance(doc.allocator(), input));
    }
    const prefix = "<< /Rect [0 0 100 100] /DA (/Helv 12 Tf) ";
    for ([_][]const u8{ "/Q 3 >>", "/Rotate 45 >>" }) |suffix| {
        const input = try std.mem.concat(doc.allocator(), u8, &.{ prefix, suffix });
        try std.testing.expectError(error.InvalidAnnotationStyle, load(&doc, try parseTest(&doc, input)));
    }
    for ([_][]const u8{ "/RD [60 0 60 0] >>", "/IT /FreeTextCallout /CL [1 2 3] >>" }) |suffix| {
        const input = try std.mem.concat(doc.allocator(), u8, &.{ prefix, suffix });
        try std.testing.expectError(error.InvalidAnnotationGeometry, load(&doc, try parseTest(&doc, input)));
    }
    try std.testing.expectError(error.UnsupportedAnnotationAppearance, load(&doc, try parseTest(&doc, prefix ++ "/RC (<p>text</p>) >>")));
    try std.testing.expectError(error.UnsupportedFont, load(&doc, try parseTest(&doc, "<< /Rect [0 0 100 100] /DA (/Unknown 12 Tf) >>")));
    try std.testing.expectError(error.UnsupportedEncoding, load(&doc, try parseTest(&doc, prefix ++ "/Contents <FEFF4E2D> >>")));
    const font = try fonts.loadValue(&doc, try fontResource(doc.allocator(), "Helv"));
    const huge = try doc.allocator().alloc(u8, 4097);
    @memset(huge, '\n');
    try std.testing.expectError(error.TextLimit, wrap(doc.allocator(), font, huge, 12, 1));
}
fn allocationCheck(a: A, bytes: []const u8) !void {
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    _ = try load(&doc, try parseTest(&doc, "<< /Rect [0 0 200 200] /DA (/Helv 14 Tf .1 .2 .3 rg) /Contents (A wrapped line of text\nNext line) /C [.9] /RD [20 10 0 0] /IT /FreeTextCallout /CL [0 0 10 10 20 20] >>"));
    _ = try load(&doc, try parseTest(&doc, "<< /Rect [0 0 200 200] /DA (/Helv 0 Tf .1 .2 .3 rg) /Contents (A wrapped line of text\nNext line) /C [.9] /RD [20 10 0 0] /IT /FreeTextCallout /CL [0 0 10 10 20 20] >>"));
}
test "FreeText layout releases all allocations on failure" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "");
    defer a.free(bytes);
    try std.testing.checkAllAllocationFailures(a, allocationCheck, .{bytes});
}
test "FreeText standard names retain all fourteen distinct font faces" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    for (fonts.metrics.names, 0..) |name, i| {
        const font = try fonts.loadValue(&doc, try fontResource(doc.allocator(), name));
        try std.testing.expectEqual(i, @as(usize, @backingInt(font.face)));
    }
    const style = try defaultAppearance(doc.allocator(), "% font selection\n/Helvetica#2DBold 14.0 Tf .5 g\n");
    const font = try fonts.loadValue(&doc, try fontResource(doc.allocator(), style.font));
    try std.testing.expect(font.face == .helvetica_bold);
}

test "automatic font sizing fits words lines insets and rotated boxes" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    const cases = [_]struct { extra: []const u8, content: []const u8, expected: f64 }{
        .{ .extra = "/BS << /W 0 >>", .content = "MMMM", .expected = 50 },
        .{ .extra = "/BS << /W 0 >>", .content = "AB\nCD", .expected = 25 },
        .{ .extra = "/BS << /W 0 >>", .content = "ABCDEFGHIJKLMNOPQRST", .expected = 10 },
        .{ .extra = "/BS << /W 2 >> /RD [10 10 10 10]", .content = "MMMM", .expected = 32.0 / 1.2 },
        .{ .extra = "/BS << /W 0 >> /Rotate 90", .content = "MMMM", .expected = 25 },
    };
    for (cases) |case| {
        const input = try std.fmt.allocPrint(doc.allocator(), "<< /Rect [0 0 120 60] /DA (/Cour 0 Tf) /Contents ({s}) {s} >>", .{ case.content, case.extra });
        const layout = try load(&doc, try parseTest(&doc, input));
        try std.testing.expectEqual(@as(f64, 0), layout.style.font_size);
        try std.testing.expectApproxEqAbs(case.expected, layout.size, 0.000001);
        for (layout.lines) |line| try std.testing.expect(line.width <= layout.width - 4 * layout.border.width);
        try std.testing.expect(@as(f64, @floatFromInt(layout.lines.len)) * 1.2 * layout.size <= layout.height - 4 * layout.border.width);
    }
    try std.testing.expectError(error.TextOverflow, load(&doc, try parseTest(&doc, "<< /Rect [0 0 10 10] /BS << /W 4 >> /DA (/Cour 0 Tf) /Contents (Cannot fit) >>")));
}

test "FreeText resolves document font resources and wraps decoded spaces" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    const font = try parseTest(&doc, "<< /Type /Font /Subtype /Type1 /BaseFont /Courier /Encoding << /BaseEncoding /WinAnsiEncoding /Differences [32 /A 65 /space] >> >>");
    const id = try doc.addObject(font, null);
    const resource = s.Value{ .ref = .{ .id = id, .generation = 0 } };
    const catalog = try doc.object(s.get(doc.trailer, "Root").?.ref);
    const dictionary_font = try dictionary(doc.allocator(), &.{ .{ .key = "Lesson Font", .value = resource }, .{ .key = "Helv", .value = resource } });
    const dr = try dictionary(doc.allocator(), &.{.{ .key = "Font", .value = dictionary_font }});
    try doc.set(catalog, "AcroForm", try dictionary(doc.allocator(), &.{.{ .key = "DR", .value = dr }}));
    const layout = try load(&doc, try parseTest(&doc, "<< /Rect [0 0 18 60] /DA (/Lesson#20Font 10 Tf) /BS << /W 0 >> /Contents (A A A) >>"));
    try std.testing.expectEqual(@as(usize, 2), layout.lines.len);
    try std.testing.expectEqualStrings(" A A", layout.lines[0].text);
    try std.testing.expectEqualStrings(" ", layout.lines[1].text);
    try std.testing.expectEqual(@as(f64, 18), layout.lines[0].width);
    try std.testing.expectEqual(@as(f64, 6), layout.lines[1].width);
    const spaced = try load(&doc, try parseTest(&doc, "<< /Rect [0 0 100 60] /DA (/Lesson#20Font 10 Tf 9 Tw) /BS << /W 0 >> /Contents (A A) >>"));
    // Code 32 maps to A; the decoded space maps to code 65 and does not get Tw.
    try std.testing.expectEqual(@as(f64, 27), spaced.lines[0].width);
    const resources = try layout.resources(doc.allocator());
    try std.testing.expectEqualDeep(resource, s.get(s.get(resources, "Font").?, "Text").?);
    const overridden = try load(&doc, try parseTest(&doc, "<< /Rect [0 0 100 60] /DA (/Helv 10 Tf) /Contents (A) >>"));
    try std.testing.expect(overridden.font.face == .courier);
    try std.testing.expectEqualStrings(" ", overridden.lines[0].text);
    _ = try doc.indexPages();
    try std.testing.expect(!doc.unsupported_appearance);
}

test "signed spacing auto fit agrees with a dense independent size sweep" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    const font = try fonts.loadValue(&doc, try fontResource(doc.allocator(), "Helv"));
    for ([_]Spacing{ .{ .character = 1, .word = 2 }, .{ .character = -1, .word = 2 }, .{ .character = -20 }, .{ .word = -30 }, .{ .character = -10, .word = 8 }, .{ .character = 10, .word = -25 } }) |spacing| {
        for ([_][]const u8{ "Wii WI M", " AB CD  EF ", "AB\nCD EF", "LongWord" }) |input| {
            const paragraphs = try encodedParagraphs(doc.allocator(), font, input, spacing);
            for ([_]f64{ 12, 25, 60 }) |width| for ([_]f64{ 12, 30, 100 }) |height| {
                const fitted = spacedAutoSize(paragraphs, width, height) catch |err| switch (err) {
                    error.TextOverflow => 0,
                    else => return err,
                };
                if (fitted > 0) try std.testing.expect(try spacedFits(paragraphs, fitted, width, height));
                for (1..801) |step| {
                    const size = @as(f64, @floatFromInt(step)) / 4;
                    if (try spacedFits(paragraphs, size, width, height)) {
                        if (fitted + 0.000001 < size) std.debug.print("spacing={any} text={s} box={d}x{d} fitted={d} missed={d}\n", .{ spacing, input, width, height, fitted, size });
                        try std.testing.expect(fitted + 0.000001 >= size);
                    }
                }
            };
        }
    }
}
