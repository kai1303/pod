const std = @import("std");
const d = @import("document.zig");
const s = @import("syntax.zig");
const A = std.mem.Allocator;
const ink_ap = @import("ink_appearance.zig");
pub const Kind = enum(u32) { rectangle, ellipse, line, arrow, polyline, polygon, cloud, star, cross, tick, highlight, freehand_highlight, underline, squiggly, strikeout, ink, free_text, comment };
pub const Point = extern struct { x: f64, y: f64 };
pub const Style = struct { stroke: [3]f64 = .{ 0.15, 0.35, 0.9 }, fill: ?[3]f64 = null, opacity: f64 = 1, width: f64 = 2, font_size: f64 = 14 };
pub const Ink = struct {
    starts: []const usize = &.{},
    link: []const u8 = "",
    legacy: bool = false,

    fn validate(self: Ink, kind: Kind, count: usize) !void {
        if (self.starts.len > count or (self.starts.len != 0 and self.starts[0] != 0)) return error.InvalidAnnotationGeometry;
        if (kind != .ink and (self.starts.len != 0 or self.link.len != 0)) return error.InvalidAnnotationGeometry;
        for (self.starts, 0..) |start, i| {
            if (start >= count or (i != 0 and self.starts[i - 1] >= start)) return error.InvalidAnnotationGeometry;
        }
        if (self.link.len != 0) {
            if (self.link.len > 2048 or !std.unicode.utf8ValidateSlice(self.link)) return error.InvalidAnnotationLink;
            for (self.link) |ch| if (ch <= 32 or ch == 127) return error.InvalidAnnotationLink;
            const uri = std.Uri.parse(self.link) catch return error.InvalidAnnotationLink;
            if ((!std.ascii.eqlIgnoreCase(uri.scheme, "http") and !std.ascii.eqlIgnoreCase(uri.scheme, "https")) or uri.host == null or uri.host.?.isEmpty()) return error.InvalidAnnotationLink;
        }
    }
    pub fn subpath(self: Ink, points: []const Point, index: usize) []const Point {
        if (self.starts.len == 0) return points;
        const end = if (index + 1 < self.starts.len) self.starts[index + 1] else points.len;
        return points[self.starts[index]..end];
    }
};
pub const Annotation = struct { imported_ink: bool = false, locked: bool = false, pdfkit_ink: bool = false, ink: Ink = .{}, link_id: u32 = 0, id: u32, kind: Kind, points: []const Point, rect: [4]f64, text: []const u8, style: Style };
const max_annotations = 1000;
fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
fn number(x: f64) s.Value {
    return .{ .real = x };
}
fn name(x: []const u8) s.Value {
    return .{ .name = x };
}
fn reference(id: u32) s.Value {
    return .{ .ref = .{ .id = id, .generation = 0 } };
}
fn dict(a: A, entries: []const s.Entry) !s.Value {
    return .{ .dict = try a.dupe(s.Entry, entries) };
}
fn numbers(a: A, xs: []const f64) !s.Value {
    const out = try a.alloc(s.Value, xs.len);
    for (out, xs) |*v, x| v.* = number(x);
    return .{ .array = out };
}
fn pointValues(a: A, points: []const Point) !s.Value {
    const out = try a.alloc(s.Value, points.len * 2);
    for (points, 0..) |p, i| {
        out[i * 2] = number(p.x);
        out[i * 2 + 1] = number(p.y);
    }
    return .{ .array = out };
}
fn bounds(points: []const Point) [4]f64 {
    var r = [4]f64{ points[0].x, points[0].y, points[0].x, points[0].y };
    for (points) |p| {
        r[0] = @min(r[0], p.x);
        r[1] = @min(r[1], p.y);
        r[2] = @max(r[2], p.x);
        r[3] = @max(r[3], p.y);
    }
    return r;
}
fn pathKind(kind: Kind) bool {
    return kind == .polyline or kind == .polygon or kind == .ink or kind == .freehand_highlight;
}
pub fn effectiveOpacity(ann: Annotation) f64 {
    return ann.style.opacity;
}
fn validateInput(kind: Kind, points: []const Point, text: []const u8, style: Style) !void {
    if (points.len == 0 or (points.len == 1 and kind != .ink) or points.len > 4096 or (!pathKind(kind) and points.len != 2)) return error.InvalidAnnotationGeometry;
    if (kind == .polygon and points.len < 3) return error.InvalidAnnotationGeometry;
    for (points) |p| if (!std.math.isFinite(p.x) or !std.math.isFinite(p.y) or @abs(p.x) > 1e6 or @abs(p.y) > 1e6) return error.InvalidAnnotationGeometry;
    const r = bounds(points);
    if (kind != .ink and r[2] == r[0] and r[3] == r[1]) return error.InvalidAnnotationGeometry;
    if (!pathKind(kind) and kind != .line and kind != .arrow and (r[2] - r[0] < 0.1 or r[3] - r[1] < 0.1)) return error.InvalidAnnotationGeometry;
    if (!std.math.isFinite(style.opacity) or style.opacity < 0 or style.opacity > 1 or !std.math.isFinite(style.width) or style.width < 0.1 or style.width > 100 or !std.math.isFinite(style.font_size) or style.font_size < 1 or style.font_size > 200) return error.InvalidAnnotationStyle;
    for (style.stroke) |v| if (!std.math.isFinite(v) or v < 0 or v > 1) return error.InvalidAnnotationStyle;
    if (style.fill) |fill| for (fill) |v| {
        if (!std.math.isFinite(v) or v < 0 or v > 1) return error.InvalidAnnotationStyle;
    };
    if (text.len > 16384) return error.TextLimit;
    if (kind == .ink) {
        if (!std.unicode.utf8ValidateSlice(text)) return error.UnsupportedEncoding;
    } else for (text) |ch| {
        if ((ch < 32 and ch != '\n') or ch > 126) return error.UnsupportedEncoding;
    }
    if (kind == .free_text) {
        var lines = std.mem.splitScalar(u8, text, '\n');
        var count: usize = 0;
        while (lines.next()) |line| {
            count += 1;
            if (@as(f64, @floatFromInt(line.len)) * style.font_size * 0.6 > r[2] - r[0] - 4) return error.TextOverflow;
        }
        if (@as(f64, @floatFromInt(count)) * style.font_size * 1.2 > r[3] - r[1] - 4) return error.TextOverflow;
    }
}
fn subtype(kind: Kind) []const u8 {
    return switch (kind) {
        .rectangle => "Square",
        .ellipse => "Circle",
        .line, .arrow => "Line",
        .polyline, .cross, .tick => "PolyLine",
        .polygon, .cloud, .star => "Polygon",
        .highlight => "Highlight",
        .underline => "Underline",
        .squiggly => "Squiggly",
        .strikeout => "StrikeOut",
        .ink, .freehand_highlight => "Ink",
        .free_text => "FreeText",
        .comment => "Text",
    };
}
fn pageObject(doc: *d.Document, page: usize) !*d.Object {
    const pages = try doc.inspect();
    if (page >= pages.len) return error.PageNotFound;
    const id = pages[page].object_id;
    return doc.object(.{ .id = id, .generation = doc.entries[id].generation });
}
fn refs(doc: *d.Document, page: usize) ![]s.Value {
    const obj = try pageObject(doc, page);
    const value = try doc.resolve(s.get(obj.value, "Annots") orelse return &.{});
    if (value != .array or value.array.len > max_annotations) return error.UnsupportedAnnotation;
    return value.array;
}
fn required(v: s.Value, key: []const u8) !s.Value {
    return s.get(v, key) orelse error.UnsupportedAnnotation;
}
fn readNumbers(comptime n: usize, v: s.Value) ![n]f64 {
    if (v != .array or v.array.len != n) return error.UnsupportedAnnotation;
    var result: [n]f64 = undefined;
    for (&result, v.array) |*x, entry| x.* = try s.number(entry);
    return result;
}
// PDF writers use both perimeter order and text order (top pair, bottom pair).
// Keep the original points for export and walk the perimeter only for painting.
pub fn quadPerimeter(q: []const Point) [4]Point {
    const first = turn(q[0], q[1], q[2]);
    return if (first * turn(q[1], q[2], q[3]) < 0)
        .{ q[0], q[1], q[3], q[2] }
    else
        .{ q[0], q[1], q[2], q[3] };
}
fn turn(a: Point, b: Point, c: Point) f64 {
    return (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x);
}
fn lerp(p: Point, q: Point, t: f64) Point {
    return .{ .x = p.x + t * (q.x - p.x), .y = p.y + t * (q.y - p.y) };
}
// Bound the number of vertices per wave even for extreme imported coordinates.
pub const MarkupPolygon = [258]Point;
pub fn markupPolygon(ann: Annotation, i: usize, buf: *MarkupPolygon) []const Point {
    const q = quadPerimeter(ann.points[i..][0..4]);
    if (ann.kind == .highlight) {
        buf[0..4].* = q;
        return buf[0..4];
    }
    // ISO perimeter order starts at the baseline; common text order starts at the top.
    const edges: [4]Point = if (turn(q[0], q[1], q[2]) > 0) q else .{ q[3], q[2], q[1], q[0] };
    const height = @max(0.001, std.math.hypot(edges[3].x - edges[0].x, edges[3].y - edges[0].y));
    const width = std.math.hypot(edges[1].x - edges[0].x, edges[1].y - edges[0].y);
    const thickness = @min(1.0, ann.style.width / height);
    const segments: usize = if (ann.kind == .squiggly) @intFromFloat(@min(128, @max(2, @ceil(width / @max(2, height / 4))))) else 1;
    const n = segments + 1;
    for (0..n) |j| {
        const t = @as(f64, @floatFromInt(j)) / @as(f64, @floatFromInt(segments));
        const bottom = lerp(edges[0], edges[1], t);
        const top = lerp(edges[3], edges[2], t);
        const offset: f64 = if (ann.kind == .strikeout) (1 - thickness) / 2 else if (ann.kind == .squiggly and j % 2 != 0) @min(0.18, 1 - thickness) else 0;
        buf[j] = lerp(bottom, top, offset);
        buf[2 * n - 1 - j] = lerp(bottom, top, offset + thickness);
    }
    return buf[0 .. 2 * n];
}
fn validateQuads(points: []const Point, style: Style) !void {
    if (points.len == 0 or points.len % 4 != 0 or points.len > 4096) return error.InvalidAnnotationGeometry;
    // Reuse native coordinate, extent and style limits.
    try validateInput(.polygon, points, "", style);
    var i: usize = 0;
    while (i < points.len) : (i += 4) {
        const q = quadPerimeter(points[i..][0..4]);
        var sign: f64 = 0;
        for (q, 0..) |p, j| {
            const b = q[(j + 1) % 4];
            const c = q[(j + 2) % 4];
            const cross = turn(p, b, c);
            if (cross == 0 or sign * cross < 0) return error.InvalidAnnotationGeometry;
            sign = cross;
        }
    }
}
fn markupText(a: A, raw: []const u8) ![]const u8 {
    if (raw.len > 16384) return error.TextLimit;
    if (std.mem.startsWith(u8, raw, "\xfe\xff")) {
        if (raw.len % 2 != 0) return error.UnsupportedEncoding;
        const units = try a.alloc(u16, (raw.len - 2) / 2);
        for (units, 0..) |*unit, i| unit.* = std.mem.nativeToLittle(u16, std.mem.readInt(u16, raw[2 + i * 2 ..][0..2], .big));
        return std.unicode.utf16LeToUtf8Alloc(a, units);
    }
    if (std.mem.startsWith(u8, raw, "\xef\xbb\xbf")) {
        if (!std.unicode.utf8ValidateSlice(raw[3..])) return error.UnsupportedEncoding;
        return raw[3..];
    }
    // PDFDocEncoding uses Latin-1 with these diacritic and symbol ranges.
    const accents = [_]u16{ 0x2d8, 0x2c7, 0x2c6, 0x2d9, 0x2dd, 0x2db, 0x2da, 0x2dc };
    const symbols = [_]u16{ 0x2022, 0x2020, 0x2021, 0x2026, 0x2014, 0x2013, 0x192, 0x2044, 0x2039, 0x203a, 0x2212, 0x2030, 0x201e, 0x201c, 0x201d, 0x2018, 0x2019, 0x201a, 0x2122, 0xfb01, 0xfb02, 0x141, 0x152, 0x160, 0x178, 0x17d, 0x131, 0x142, 0x153, 0x161, 0x17e };
    const units = try a.alloc(u16, raw.len);
    for (raw, units) |ch, *unit| unit.* = std.mem.nativeToLittle(u16, switch (ch) {
        0x18...0x1f => accents[ch - 0x18],
        0x80...0x9e => symbols[ch - 0x80],
        0xa0 => 0x20ac,
        0x7f, 0x9f, 0xad => 0xfffd,
        else => @as(u16, ch),
    });
    return std.unicode.utf16LeToUtf8Alloc(a, units);
}
fn encodeMarkupText(a: A, text: []const u8) !s.Value {
    if (text.len > 16384) return error.TextLimit;
    const units = try std.unicode.utf8ToUtf16LeAlloc(a, text);
    if (units.len > 8191) return error.TextLimit;
    const raw = try a.alloc(u8, 2 + 2 * units.len);
    raw[0..2].* = .{ 0xfe, 0xff };
    for (units, 0..) |unit, i| std.mem.writeInt(u16, raw[2 + i * 2 ..][0..2], std.mem.littleToNative(u16, unit), .big);
    return .{ .string = raw };
}
fn readTextMarkup(doc: *d.Document, id: u32, v: s.Value, kind: Kind) !Annotation {
    if (s.get(v, "Type")) |typ| if (typ != .name or !eq(typ.name, "Annot")) return error.UnsupportedAnnotation;
    if (s.get(v, "F")) |flags| if ((try s.uint(flags)) & ~@as(usize, 4) != 0) return error.UnsupportedAnnotation;
    if (s.get(v, "OC") != null) return error.UnsupportedAnnotation;
    const raw = try doc.resolve(try required(v, "QuadPoints"));
    if (raw != .array or raw.array.len == 0 or raw.array.len % 8 != 0 or raw.array.len > 8192) return error.InvalidAnnotationGeometry;
    const points = try doc.allocator().alloc(Point, raw.array.len / 2);
    for (points, 0..) |*p, i| p.* = .{ .x = try s.number(raw.array[2 * i]), .y = try s.number(raw.array[2 * i + 1]) };
    var style = Style{ .stroke = if (kind == .highlight) .{ 1, 1, 0 } else .{ 0, 0, 0 } };
    if (kind != .highlight) {
        if (s.get(v, "BS")) |bs| {
            const border = try doc.resolve(bs);
            if (border != .dict) return error.UnsupportedAnnotation;
            if (s.get(border, "W")) |width| style.width = try s.number(try doc.resolve(width));
        }
    }
    if (s.get(v, "C")) |color| {
        const rgb = try doc.resolve(color);
        if (rgb == .array and rgb.array.len == 1) {
            style.stroke = @splat(try s.number(rgb.array[0]));
        } else style.stroke = try readNumbers(3, rgb);
    }
    if (s.get(v, "CA")) |opacity| style.opacity = try s.number(try doc.resolve(opacity));
    try validateQuads(points, style);
    const rect = try d.rectangle(try doc.resolve(try required(v, "Rect")));
    const contents = try doc.resolve(s.get(v, "Contents") orelse .{ .string = "" });
    if (contents != .string) return error.UnsupportedAnnotation;
    return .{ .id = id, .kind = kind, .points = points, .rect = rect, .style = style, .text = try markupText(doc.allocator(), contents.string) };
}
pub fn isImportedMarkup(ann: Annotation) bool {
    return switch (ann.kind) {
        .highlight, .underline, .strikeout, .squiggly => ann.points.len >= 4,
        else => false,
    };
}
fn readCompanion(doc: *d.Document, v: s.Value, mark: *Annotation) !void {
    if (s.get(v, "PodLink")) |link| {
        if (link != .ref) return error.UnsupportedAnnotation;
        mark.link_id = link.ref.id;
        const companion = try doc.resolve(link);
        const action = try required(companion, "A");
        const uri = try required(action, "URI");
        const uri_type = try required(action, "S");
        const link_type = try required(companion, "Type");
        const link_sub = try required(companion, "Subtype");
        if (companion.dict.len != 5 or action.dict.len != 2 or uri != .string or uri.string.len == 0 or
            uri_type != .name or !eq(uri_type.name, "URI") or link_type != .name or !eq(link_type.name, "Annot") or
            link_sub != .name or !eq(link_sub.name, "Link")) return error.UnsupportedAnnotation;
        const border = try readNumbers(3, try required(companion, "Border"));
        const link_rect = try readNumbers(4, try required(companion, "Rect"));
        const ink_rect = try readNumbers(4, try required(v, "Rect"));
        if (!std.mem.eql(f64, &border, &.{ 0, 0, 0 }) or !std.mem.eql(f64, &ink_rect, &link_rect)) return error.UnsupportedAnnotation;
        mark.ink.link = uri.string;
    }
}

fn readStandardInk(doc: *d.Document, id: u32, v: s.Value) !Annotation {
    if (s.get(v, "Type")) |typ| if (typ != .name or !eq(typ.name, "Annot")) return error.UnsupportedAnnotation;
    const flags = try s.uint(try doc.resolve(s.get(v, "F") orelse .{ .integer = 0 }));
    if (flags & ~@as(usize, 4 | 64 | 128 | 512) != 0 or s.get(v, "OC") != null or s.get(v, "BE") != null or s.get(v, "BM") != null) return error.UnsupportedAnnotation;
    const paths = try doc.resolve(try required(v, "InkList"));
    if (paths != .array or paths.array.len == 0 or paths.array.len > 4096) return error.InvalidAnnotationGeometry;
    const a = doc.allocator();
    const starts = try a.alloc(usize, paths.array.len);
    var points: std.ArrayList(Point) = .empty;
    for (paths.array, starts) |raw_path, *start| {
        const values = try doc.resolve(raw_path);
        if (values != .array or values.array.len == 0 or values.array.len % 2 != 0 or values.array.len / 2 > 4096 - points.items.len) return error.InvalidAnnotationGeometry;
        start.* = points.items.len;
        var j: usize = 0;
        while (j < values.array.len) : (j += 2) try points.append(a, .{ .x = try s.number(values.array[j]), .y = try s.number(values.array[j + 1]) });
    }
    var style = Style{ .stroke = .{ 0, 0, 0 }, .width = 1 };
    if (s.get(v, "C")) |color_ref| {
        const color = try doc.resolve(color_ref);
        if (color == .array and color.array.len == 1) style.stroke = @splat(try s.number(color.array[0])) else style.stroke = try readNumbers(3, color);
    }
    if (s.get(v, "BS")) |border_ref| {
        const border = try doc.resolve(border_ref);
        if (border != .dict or s.get(border, "D") != null) return error.UnsupportedStroke;
        if (s.get(border, "S")) |shape| if (shape != .name or !eq(shape.name, "S")) return error.UnsupportedStroke;
        if (s.get(border, "W")) |width| style.width = try s.number(width);
    } else if (s.get(v, "Border")) |border_ref| {
        const border = try readNumbers(3, try doc.resolve(border_ref));
        style.width = border[2];
    }
    if (s.get(v, "CA")) |alpha| style.opacity = try s.number(alpha);
    const contents = try doc.resolve(s.get(v, "Contents") orelse .{ .string = "" });
    if (contents != .string) return error.UnsupportedAnnotation;
    var mark = Annotation{ .imported_ink = true, .locked = flags & (64 | 128 | 512) != 0, .id = id, .kind = .ink, .points = points.items, .ink = .{ .starts = if (starts.len == 1) &.{} else starts }, .text = try markupText(a, contents.string), .style = style, .rect = try d.rectangle(try doc.resolve(try required(v, "Rect"))) };
    try readCompanion(doc, v, &mark);
    try mark.ink.validate(.ink, mark.points.len);
    try validateInput(.ink, mark.points, mark.text, mark.style);
    if (s.get(v, "AP")) |ap_ref| {
        const ap = try doc.resolve(ap_ref);
        const normal = try required(ap, "N");
        if (normal != .ref) return error.UnsupportedAnnotationAppearance;
        const form = try doc.object(normal.ref);
        const subtype_value = try required(form.value, "Subtype");
        if (subtype_value != .name or !eq(subtype_value.name, "Form") or s.get(form.value, "Matrix") != null or s.get(form.value, "Group") != null) return error.UnsupportedAnnotationAppearance;
        const bytes = try ink_ap.stream(a, form, 2 * 1024 * 1024);
        const canonical = try appearance(a, mark, true);
        if (eq(bytes, canonical)) {
            const bbox = try readNumbers(4, try required(form.value, "BBox"));
            if (!std.mem.eql(f64, &bbox, &mark.rect)) return error.UnsupportedAnnotationAppearance;
            try checkResources(a, form, mark);
        } else {
            try ink_ap.pdfKit(doc, form, bytes, &mark);
            mark.pdfkit_ink = true;
        }
    }
    try validateInput(.ink, mark.points, mark.text, mark.style);
    return mark;
}
fn read(doc: *d.Document, value: s.Value) !Annotation {
    if (value != .ref) return error.UnsupportedAnnotation;
    const obj = try doc.object(value.ref);
    const v = obj.value;
    if (v != .dict) return error.UnsupportedAnnotation;
    if (s.get(v, "PodKind") == null) {
        const sub = try required(v, "Subtype");
        if (sub == .name) {
            if (eq(sub.name, "Ink")) return readStandardInk(doc, value.ref.id, v);
            for ([_]Kind{ .highlight, .underline, .strikeout, .squiggly }) |kind|
                if (eq(sub.name, subtype(kind))) return readTextMarkup(doc, value.ref.id, v, kind);
        }
    }
    const typ = try required(v, "Type");
    if (typ != .name or !eq(typ.name, "Annot") or try s.uint(try required(v, "F")) != 4) return error.UnsupportedAnnotation;
    for (v.dict) |entry| {
        var supported = false;
        for ([_][]const u8{ "Type", "Subtype", "Rect", "Contents", "F", "C", "CA", "BS", "AP", "PodKind", "PodSmoothInk", "PodLink", "PodPoints", "PodFill", "PodOpacity", "PodWidth", "PodFontSize", "IC", "L", "LE", "InkList", "QuadPoints", "Vertices", "DA", "Name" }) |key| {
            if (eq(entry.key, key)) supported = true;
        }
        if (!supported) return error.UnsupportedAnnotation;
    }
    const k = try s.uint(try required(v, "PodKind"));
    if (k > @backingInt(Kind.comment)) return error.UnsupportedAnnotation;
    const kind: Kind = @fromBackingInt(@intCast(k));
    const sub = try required(v, "Subtype");
    if (sub != .name or !eq(sub.name, subtype(kind))) return error.UnsupportedAnnotation;
    const pv = try required(v, "PodPoints");
    if (pv != .array or pv.array.len % 2 != 0 or pv.array.len > 8192) return error.UnsupportedAnnotation;
    const points = try doc.allocator().alloc(Point, pv.array.len / 2);
    for (points, 0..) |*p, i| p.* = .{ .x = try s.number(pv.array[i * 2]), .y = try s.number(pv.array[i * 2 + 1]) };
    const text = try required(v, "Contents");
    if (text != .string) return error.UnsupportedAnnotation;
    const fill = try required(v, "PodFill");
    const style = Style{ .stroke = try readNumbers(3, try required(v, "C")), .fill = if (fill == .null) null else try readNumbers(3, fill), .opacity = try s.number(try required(v, "PodOpacity")), .width = try s.number(try required(v, "PodWidth")), .font_size = try s.number(try required(v, "PodFontSize")) };
    var ink: Ink = .{};
    var contents = text.string;
    if (kind == .ink) {
        ink.legacy = s.get(v, "PodSmoothInk") == null;
        if (!ink.legacy) {
            if (try s.uint(try required(v, "PodSmoothInk")) != 1) return error.UnsupportedAnnotation;
        }
        contents = try markupText(doc.allocator(), contents);
        const paths = try required(v, "InkList");
        if (paths != .array or paths.array.len == 0 or paths.array.len > points.len) return error.InvalidAnnotationGeometry;
        const starts = try doc.allocator().alloc(usize, paths.array.len);
        var cursor: usize = 0;
        for (paths.array, starts) |path_values, *start| {
            if (path_values != .array or path_values.array.len == 0 or path_values.array.len % 2 != 0 or path_values.array.len / 2 > points.len - cursor) return error.InvalidAnnotationGeometry;
            start.* = cursor;
            var i: usize = 0;
            while (i < path_values.array.len) : (i += 2) {
                if (points[cursor].x != try s.number(path_values.array[i]) or points[cursor].y != try s.number(path_values.array[i + 1])) return error.InvalidAnnotationGeometry;
                cursor += 1;
            }
        }
        if (cursor != points.len) return error.InvalidAnnotationGeometry;
        if (starts.len > 1) ink.starts = starts;
        try ink.validate(kind, points.len);
    }
    try validateInput(kind, points, contents, style);
    var ann = Annotation{ .ink = ink, .id = value.ref.id, .kind = kind, .points = points, .rect = try readNumbers(4, try required(v, "Rect")), .text = contents, .style = style };
    try readCompanion(doc, v, &ann);
    try ann.ink.validate(kind, points.len);
    // Only our canonical appearance is understood: never silently discard an external AP edit.
    const ap = try appearanceObject(doc, ann);
    const ap_type = try required(ap.value, "Type");
    const ap_subtype = try required(ap.value, "Subtype");
    if (ap_type != .name or !eq(ap_type.name, "XObject") or ap_subtype != .name or !eq(ap_subtype.name, "Form")) return error.UnsupportedAnnotation;
    for (ap.value.dict) |entry| {
        var supported = false;
        for ([_][]const u8{ "Type", "Subtype", "FormType", "BBox", "Resources", "Length" }) |key| {
            if (eq(entry.key, key)) supported = true;
        }
        if (!supported) return error.UnsupportedAnnotation;
    }
    const expected = try appearance(doc.allocator(), ann, true);
    if (!eq(ap.changed orelse ap.stream orelse return error.UnsupportedAnnotation, expected)) return error.UnsupportedAnnotation;
    const expected_box = appearanceBounds(ann);
    if (!std.mem.eql(f64, &ann.rect, &expected_box)) return error.UnsupportedAnnotation;
    const actual_bbox = try readNumbers(4, try required(ap.value, "BBox"));
    if (!std.mem.eql(f64, &actual_bbox, &expected_box)) return error.UnsupportedAnnotation;
    try checkResources(doc.allocator(), ap, ann);
    return ann;
}
fn checkResources(a: A, ap: *d.Object, ann: Annotation) !void {
    const resources = try required(ap.value, "Resources");
    const expected_resources = try appearanceResources(a, ann);
    var actual: std.ArrayList(u8) = .empty;
    var expected_data: std.ArrayList(u8) = .empty;
    try d.serialize(a, &actual, resources);
    try d.serialize(a, &expected_data, expected_resources);
    if (!eq(actual.items, expected_data.items)) return error.UnsupportedAnnotation;
}
pub fn list(doc: *d.Document, page: usize) ![]Annotation {
    const values = try refs(doc, page);
    const result = try doc.allocator().alloc(Annotation, values.len);
    // Paired PDF links remain clickable in other readers but select and edit with their ink in Pod.
    var links: std.AutoHashMapUnmanaged(u32, void) = .empty;
    defer links.deinit(doc.allocator());
    var count: usize = 0;
    var link_count: usize = 0;
    for (values) |value| {
        if (value != .ref) return error.UnsupportedAnnotation;
        const obj = try doc.object(value.ref);
        if (s.get(obj.value, "Subtype")) |sub| {
            if (sub == .name and eq(sub.name, "Link")) {
                link_count += 1;
                continue;
            }
        }
        const ann = try read(doc, value);
        if (ann.link_id != 0) {
            const slot = try links.getOrPut(doc.allocator(), ann.link_id);
            if (slot.found_existing) return error.UnsupportedAnnotation;
        }
        result[count] = ann;
        count += 1;
    }
    if (links.count() != link_count) return error.UnsupportedAnnotation;
    if (link_count != 0) {
        for (values) |value| _ = links.remove(value.ref.id);
        if (links.count() != 0) return error.UnsupportedAnnotation;
    }
    return result[0..count];
}
pub fn appearanceObject(doc: *d.Document, ann: Annotation) !*d.Object {
    const obj = try doc.object(.{ .id = ann.id, .generation = doc.entries[ann.id].generation });
    const ap = try required(obj.value, "AP");
    const normal = try required(ap, "N");
    if (normal != .ref) return error.UnsupportedAnnotation;
    return doc.object(normal.ref);
}
fn appearanceBounds(ann: Annotation) [4]f64 {
    var r = bounds(ann.points);
    const pad = if (ann.kind == .ink and !ann.ink.legacy) ann.style.width / 2 else @max(ann.style.width * 5, 2);
    r[0] -= pad;
    r[1] -= pad;
    r[2] += pad;
    r[3] += pad;
    return r;
}
fn appearanceResources(a: A, ann: Annotation) !s.Value {
    return dict(a, &.{ .{ .key = "Font", .value = try dict(a, &.{.{ .key = "F1", .value = try dict(a, &.{ .{ .key = "Type", .value = name("Font") }, .{ .key = "Subtype", .value = name("Type1") }, .{ .key = "BaseFont", .value = name("Courier") }, .{ .key = "Encoding", .value = name("WinAnsiEncoding") } }) }}) }, .{ .key = "ExtGState", .value = try dict(a, &.{.{ .key = "GS", .value = try dict(a, &.{ .{ .key = "Type", .value = name("ExtGState") }, .{ .key = "CA", .value = number(effectiveOpacity(ann)) }, .{ .key = "ca", .value = number(effectiveOpacity(ann)) } }) }}) } });
}
fn writeCompanion(doc: *d.Document, ann: Annotation, r: [4]f64) !s.Value {
    const a = doc.allocator();
    const action = try dict(a, &.{ .{ .key = "S", .value = name("URI") }, .{ .key = "URI", .value = .{ .string = try a.dupe(u8, ann.ink.link) } } });
    const link = try dict(a, &.{ .{ .key = "Type", .value = name("Annot") }, .{ .key = "Subtype", .value = name("Link") }, .{ .key = "Rect", .value = try numbers(a, &r) }, .{ .key = "Border", .value = try numbers(a, &.{ 0, 0, 0 }) }, .{ .key = "A", .value = action } });
    const link_id = if (ann.link_id == 0) try doc.addObject(link, null) else ann.link_id;
    if (ann.link_id != 0) {
        const companion = try doc.object(reference(link_id).ref);
        companion.value = link;
        companion.dirty = true;
    }
    return reference(link_id);
}
fn build(doc: *d.Document, ann: Annotation, ap_id: ?u32) !s.Value {
    const a = doc.allocator();
    const r = if (ann.imported_ink) ann.rect else appearanceBounds(ann);
    const ap_value = try dict(a, &.{ .{ .key = "Type", .value = name("XObject") }, .{ .key = "Subtype", .value = name("Form") }, .{ .key = "FormType", .value = .{ .integer = 1 } }, .{ .key = "BBox", .value = try numbers(a, &r) }, .{ .key = "Resources", .value = try appearanceResources(a, ann) } });
    const data = try appearance(a, ann, true);
    const normal_id = ap_id orelse try doc.addObject(ap_value, data);
    if (ap_id != null) {
        const obj = try doc.object(.{ .id = normal_id, .generation = doc.entries[normal_id].generation });
        obj.value = ap_value;
        obj.changed = data;
        obj.dirty = true;
    }
    const points = try pointValues(a, ann.points);
    var entries: std.ArrayList(s.Entry) = .empty;
    try entries.appendSlice(a, &.{ .{ .key = "Type", .value = name("Annot") }, .{ .key = "Subtype", .value = name(subtype(ann.kind)) }, .{ .key = "Rect", .value = try numbers(a, &r) }, .{ .key = "Contents", .value = if (ann.kind == .ink and ann.text.len != 0) try encodeMarkupText(a, ann.text) else .{ .string = try a.dupe(u8, ann.text) } }, .{ .key = "F", .value = .{ .integer = 4 } }, .{ .key = "C", .value = try numbers(a, &ann.style.stroke) }, .{ .key = "CA", .value = number(effectiveOpacity(ann)) }, .{ .key = "BS", .value = try dict(a, &.{ .{ .key = "W", .value = number(ann.style.width) }, .{ .key = "S", .value = name("S") } }) }, .{ .key = "AP", .value = try dict(a, &.{.{ .key = "N", .value = reference(normal_id) }}) }, .{ .key = "PodKind", .value = .{ .integer = @backingInt(ann.kind) } }, .{ .key = "PodPoints", .value = points }, .{ .key = "PodFill", .value = if (ann.style.fill) |fill| try numbers(a, &fill) else .null }, .{ .key = "PodOpacity", .value = number(ann.style.opacity) }, .{ .key = "PodWidth", .value = number(ann.style.width) }, .{ .key = "PodFontSize", .value = number(ann.style.font_size) } });
    if (ann.style.fill) |fill| try entries.append(a, .{ .key = "IC", .value = try numbers(a, &fill) });
    const b = bounds(ann.points);
    switch (ann.kind) {
        .line, .arrow => {
            try entries.append(a, .{ .key = "L", .value = points });
            if (ann.kind == .arrow) try entries.append(a, .{ .key = "LE", .value = .{ .array = try a.dupe(s.Value, &.{ name("None"), name("OpenArrow") }) } });
        },
        .ink => {
            const paths = try a.alloc(s.Value, @max(1, ann.ink.starts.len));
            for (paths, 0..) |*item, i| {
                const start = if (ann.ink.starts.len == 0) 0 else ann.ink.starts[i];
                const end = if (i + 1 < paths.len) ann.ink.starts[i + 1] else ann.points.len;
                item.* = .{ .array = points.array[start * 2 .. end * 2] };
            }
            try entries.append(a, .{ .key = "InkList", .value = .{ .array = paths } });
            if (!ann.ink.legacy) try entries.append(a, .{ .key = "PodSmoothInk", .value = .{ .integer = 1 } });
            if (ann.ink.link.len != 0) try entries.append(a, .{ .key = "PodLink", .value = try writeCompanion(doc, ann, r) });
        },
        .freehand_highlight => try entries.append(a, .{ .key = "InkList", .value = .{ .array = try a.dupe(s.Value, &.{points}) } }),
        .highlight, .underline, .strikeout, .squiggly => try entries.append(a, .{ .key = "QuadPoints", .value = try numbers(a, &.{ b[0], b[3], b[2], b[3], b[0], b[1], b[2], b[1] }) }),
        .polygon, .polyline, .cloud, .star, .cross, .tick => try entries.append(a, .{ .key = "Vertices", .value = try pointValues(a, try geometry(a, ann)) }),
        .free_text => {
            var da: std.ArrayList(u8) = .empty;
            try da.print(a, "/F1 {d} Tf {d} {d} {d} rg", .{ ann.style.font_size, ann.style.stroke[0], ann.style.stroke[1], ann.style.stroke[2] });
            try entries.append(a, .{ .key = "DA", .value = .{ .string = da.items } });
        },
        .comment => try entries.append(a, .{ .key = "Name", .value = name("Note") }),
        else => {},
    }
    return .{ .dict = try entries.toOwnedSlice(a) };
}
pub fn add(doc: *d.Document, page: usize, kind: Kind, points: []const Point, text: []const u8, style: Style) !u32 {
    return addWithInk(doc, page, kind, points, text, style, .{});
}
pub fn addWithInk(doc: *d.Document, page: usize, kind: Kind, points: []const Point, text: []const u8, style: Style, ink: Ink) !u32 {
    try ink.validate(kind, points.len);
    try validateInput(kind, points, text, style);
    // Adding preserves unknown existing annotations. Rendering and editing them still
    // require canonical validation in list(); the native open path validates first.
    const old = try refs(doc, page);
    for (old) |value| {
        if (value != .ref or value.ref.id == 0 or value.ref.id >= doc.entries.len) return error.UnsupportedAnnotation;
        const entry = doc.entries[value.ref.id];
        if (!entry.live or entry.generation != value.ref.generation) return error.UnsupportedAnnotation;
    }
    if (old.len + 1 + @as(usize, @intFromBool(ink.link.len != 0)) > max_annotations) return error.AnnotationLimit;
    const ann = Annotation{ .ink = ink, .id = 0, .kind = kind, .points = points, .rect = bounds(points), .text = text, .style = style };
    const value = try build(doc, ann, null);
    const id = try doc.addObject(value, null);
    const link = s.get(value, "PodLink");
    try appendRefs(doc, page, old, if (link) |companion| &.{ reference(id), companion } else &.{reference(id)});
    return id;
}
fn appendRefs(doc: *d.Document, page: usize, old: []s.Value, additions: []const s.Value) !void {
    const storage = &(try doc.inspect())[page].annotation_refs;
    if (storage.items.ptr != old.ptr or storage.items.len != old.len) {
        storage.* = .empty;
        try storage.appendSlice(doc.allocator(), old);
    }
    try storage.appendSlice(doc.allocator(), additions);
    try doc.set(try pageObject(doc, page), "Annots", .{ .array = storage.items });
}
fn updateTextMarkup(doc: *d.Document, obj: *d.Object, old: Annotation, points: []const Point, text: []const u8, style: Style) !void {
    try validateQuads(points, style);
    const moved = !std.mem.eql(u8, std.mem.sliceAsBytes(old.points), std.mem.sliceAsBytes(points));
    const recolored = !std.meta.eql(old.style.stroke, style.stroke);
    const resized_stroke = old.kind != .highlight and old.style.width != style.width;
    const repaint = resized_stroke or moved or recolored or old.style.opacity != style.opacity;
    const new_text = !eq(old.text, text);
    if (!repaint and !new_text) return;
    if (new_text and s.get(obj.value, "RC") != null) return error.UnsupportedAnnotation;
    var edited = old;
    edited.points = points;
    edited.style = style;
    if (moved) edited.rect = bounds(points);
    const a = doc.allocator();
    // Stage dictionary edits privately. An imported appearance may be shared by
    // other annotations, so make a fresh normal appearance for this object.
    var staged = obj.*;
    staged.value = try dict(a, obj.value.dict);
    if (new_text) try doc.set(&staged, "Contents", try encodeMarkupText(a, text));
    if (!repaint) {
        obj.* = staged;
        return;
    }
    if (moved) {
        try doc.set(&staged, "QuadPoints", try pointValues(a, points));
        try doc.set(&staged, "Rect", try numbers(a, &edited.rect));
    }
    if (recolored) try doc.set(&staged, "C", try numbers(a, &style.stroke));
    if (old.style.opacity != style.opacity) try doc.set(&staged, "CA", number(style.opacity));
    if (resized_stroke) {
        var border = d.Object{ .value = try dict(a, if (s.get(obj.value, "BS")) |bs| (try doc.resolve(bs)).dict else &.{}), .body = "" };
        try doc.set(&border, "W", number(style.width));
        try doc.set(&staged, "BS", border.value);
    }
    const gs = try dict(a, &.{ .{ .key = "BM", .value = name(if (old.kind == .highlight) "Multiply" else "Normal") }, .{ .key = "ca", .value = number(style.opacity) } });
    const resources = try dict(a, &.{.{ .key = "ExtGState", .value = try dict(a, &.{.{ .key = "GS", .value = gs }}) }});
    const form = try dict(a, &.{ .{ .key = "Type", .value = name("XObject") }, .{ .key = "Subtype", .value = name("Form") }, .{ .key = "BBox", .value = try numbers(a, &edited.rect) }, .{ .key = "Resources", .value = resources } });
    var ap = d.Object{ .value = try dict(a, &.{}), .body = "" };
    if (s.get(obj.value, "AP")) |existing| {
        const source = try doc.resolve(existing);
        if (source != .dict) return error.UnsupportedAnnotation;
        ap.value = try dict(a, source.dict);
    }
    const normal = try doc.addObject(form, try appearance(a, edited, true));
    try doc.set(&ap, "N", reference(normal));
    try doc.set(&staged, "AP", ap.value);
    obj.* = staged;
}
fn removeKey(a: A, obj: *d.Object, key: []const u8) !void {
    if (s.get(obj.value, key) == null) return;
    var kept: std.ArrayList(s.Entry) = .empty;
    for (obj.value.dict) |entry| if (!eq(entry.key, key)) {
        try kept.append(a, entry);
    };
    obj.value = .{ .dict = kept.items };
    obj.dirty = true;
}
fn updateStandardInk(doc: *d.Document, page: usize, obj: *d.Object, old: Annotation, edited_input: Annotation) !void {
    var edited = edited_input;
    edited.style.fill = null;
    const a = doc.allocator();
    const moved = !std.mem.eql(u8, std.mem.sliceAsBytes(old.points), std.mem.sliceAsBytes(edited.points)) or !std.mem.eql(usize, old.ink.starts, edited.ink.starts);
    const resized = old.style.width != edited.style.width;
    const repaint = moved or resized or !std.meta.eql(old.style.stroke, edited.style.stroke) or old.style.opacity != edited.style.opacity;
    const noted = !eq(old.text, edited.text);
    const linked = !eq(old.ink.link, edited.ink.link);
    if (!repaint and !noted and !linked) return;
    if (old.locked) return error.AnnotationLocked;
    if (noted and s.get(obj.value, "RC") != null) return error.UnsupportedAnnotation;
    // Rollover or pressed appearances would also need a repaint.
    if (repaint) {
        if (s.get(obj.value, "AP")) |ap| if ((try doc.resolve(ap)).dict.len != 1) return error.UnsupportedAnnotationAppearance;
    }
    var staged = obj.*;
    staged.value = try dict(a, obj.value.dict);
    // PDFKit's private archive caches its previous text, color and geometry.
    try removeKey(a, &staged, "AAPL:AKExtras");
    if (noted) try doc.set(&staged, "Contents", try encodeMarkupText(a, edited.text));
    edited.imported_ink = true;
    edited.rect = if (moved or resized) appearanceBounds(edited) else old.rect;
    if (repaint) {
        // Shared APs on imported objects must never be overwritten in place.
        const updated = try build(doc, edited, null);
        for ([_][]const u8{ "AP", "C", "CA", "Rect", "InkList" }) |key| try doc.set(&staged, key, try required(updated, key));
        if (resized) {
            var border = d.Object{ .value = try dict(a, if (s.get(obj.value, "BS")) |bs| (try doc.resolve(bs)).dict else &.{}), .body = "" };
            try doc.set(&border, "W", number(edited.style.width));
            try doc.set(&staged, "BS", border.value);
        }
        if (s.get(updated, "PodLink")) |link| try doc.set(&staged, "PodLink", link);
    } else if (linked and edited.ink.link.len != 0) {
        try doc.set(&staged, "PodLink", try writeCompanion(doc, edited, edited.rect));
    }
    if (linked) {
        if (edited.ink.link.len == 0) {
            try removeKey(a, &staged, "PodLink");
            try dropRefs(doc, page, old.link_id, 0);
        } else if (old.link_id == 0) try appendRefs(doc, page, try refs(doc, page), &.{try required(staged.value, "PodLink")});
    }
    obj.* = staged;
}
pub fn update(doc: *d.Document, page: usize, id: u32, kind: Kind, points: []const Point, text: []const u8, style: Style) !void {
    return updateWithInk(doc, page, id, kind, points, text, style, .{});
}
pub fn updateWithInk(doc: *d.Document, page: usize, id: u32, kind: Kind, points: []const Point, text: []const u8, style: Style, ink: Ink) !void {
    try ink.validate(kind, points.len);
    for (try list(doc, page)) |old| if (old.id == id) {
        const obj = try doc.object(.{ .id = id, .generation = doc.entries[id].generation });
        if (isImportedMarkup(old)) {
            if (kind != old.kind) return error.UnsupportedAnnotation;
            return updateTextMarkup(doc, obj, old, points, text, style);
        }
        try validateInput(kind, points, text, style);
        const old_refs = try refs(doc, page);
        if (ink.link.len != 0 and old.link_id == 0 and old_refs.len >= max_annotations) return error.AnnotationLimit;
        if (old.imported_ink) {
            if (kind != .ink) return error.UnsupportedAnnotation;
            return updateStandardInk(doc, page, obj, old, .{ .id = id, .kind = kind, .ink = ink, .link_id = old.link_id, .points = points, .text = text, .style = style, .rect = old.rect });
        }
        const normal = try required(try required(obj.value, "AP"), "N");
        var edited_ink = ink;
        edited_ink.legacy = kind == .ink and old.ink.legacy;
        obj.value = try build(doc, .{ .ink = edited_ink, .link_id = old.link_id, .id = id, .kind = kind, .points = points, .rect = bounds(points), .text = text, .style = style }, normal.ref.id);
        obj.dirty = true;
        if (ink.link.len != 0 and old.link_id == 0) {
            try appendRefs(doc, page, old_refs, &.{try required(obj.value, "PodLink")});
        } else if (ink.link.len == 0 and old.link_id != 0) {
            try dropRefs(doc, page, old.link_id, 0);
        }
        return;
    };
    return error.AnnotationNotFound;
}
pub fn remove(doc: *d.Document, page: usize, id: u32) !void {
    for (try list(doc, page)) |ann| {
        if (ann.id == id) {
            if (ann.locked) return error.AnnotationLocked;
            return dropRefs(doc, page, id, ann.link_id);
        }
    }
    return error.AnnotationNotFound;
}
fn dropRefs(doc: *d.Document, page: usize, id: u32, companion: u32) !void {
    const old = try refs(doc, page);
    var items: std.ArrayList(s.Value) = .empty;
    try items.ensureTotalCapacity(doc.allocator(), old.len);
    for (old) |v| {
        if (v.ref.id != id and v.ref.id != companion) items.appendAssumeCapacity(v);
    }
    try doc.set(try pageObject(doc, page), "Annots", .{ .array = items.items });
}
fn geometry(a: A, ann: Annotation) ![]const Point {
    const b = bounds(ann.points);
    const x = b[0];
    const y = b[1];
    const w = b[2] - x;
    const h = b[3] - y;
    switch (ann.kind) {
        .star, .ellipse, .cloud => {
            const n: usize = if (ann.kind == .star) 10 else if (ann.kind == .cloud) 192 else 64;
            const pts = try a.alloc(Point, n);
            for (pts, 0..) |*p, i| {
                const angle = std.math.pi / 2.0 + @as(f64, @floatFromInt(i)) * 2 * std.math.pi / @as(f64, @floatFromInt(n));
                const radius: f64 = if (ann.kind == .star) (if (i % 2 == 0) @as(f64, 1) else 0.42) else if (ann.kind == .cloud) 0.9 + 0.1 * @cos(angle * 12) else 1;
                p.* = .{ .x = x + w / 2 + @cos(angle) * w / 2 * radius, .y = y + h / 2 + @sin(angle) * h / 2 * radius };
            }
            return pts;
        },
        .tick => return a.dupe(Point, &.{ .{ .x = x, .y = y + h * 0.5 }, .{ .x = x + w * 0.35, .y = y }, .{ .x = b[2], .y = b[3] } }),
        .cross => return a.dupe(Point, &.{ .{ .x = x, .y = y }, .{ .x = b[2], .y = b[3] }, .{ .x = x, .y = b[3] }, .{ .x = b[2], .y = y } }),
        else => return ann.points,
    }
}
fn path(a: A, out: *std.ArrayList(u8), points: []const Point, closed: bool, fill: bool) !void {
    for (points, 0..) |p, i| try out.print(a, "{d} {d} {s}\n", .{ p.x, p.y, if (i == 0) "m" else "l" });
    if (closed) try out.appendSlice(a, "h\n");
    try out.appendSlice(a, if (fill and closed) "B\n" else "S\n");
}
pub fn appearance(a: A, ann: Annotation, with_alpha: bool) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    const st = ann.style;
    const b = bounds(ann.points);
    const x = b[0];
    const y = b[1];
    const w = b[2] - x;
    const h = b[3] - y;
    try out.appendSlice(a, if (with_alpha) "q /GS gs\n" else "q\n");
    const fill = st.fill orelse st.stroke;
    try out.print(a, "{d} {d} {d} RG {d} {d} {d} rg {d} w 2 j\n", .{ st.stroke[0], st.stroke[1], st.stroke[2], fill[0], fill[1], fill[2], st.width });
    if (isImportedMarkup(ann)) {
        try out.print(a, "{d} {d} {d} rg\n", .{ st.stroke[0], st.stroke[1], st.stroke[2] });
        var i: usize = 0;
        while (i < ann.points.len) : (i += 4) {
            var buf: MarkupPolygon = undefined;
            for (markupPolygon(ann, i, &buf), 0..) |p, j| try out.print(a, "{d} {d} {s}\n", .{ p.x, p.y, if (j == 0) "m" else "l" });
            try out.appendSlice(a, "h f\n");
        }
        try out.appendSlice(a, "Q\n");
        return out.items;
    }
    switch (ann.kind) {
        .rectangle => try out.print(a, "{d} {d} {d} {d} re {s}\n", .{ x, y, w, h, if (st.fill != null) "B" else "S" }),
        .highlight => try out.print(a, "{d} {d} {d} rg {d} {d} {d} {d} re f\n", .{ st.stroke[0], st.stroke[1], st.stroke[2], x, y, w, h }),
        .ellipse, .cloud, .star, .polygon => try path(a, &out, try geometry(a, ann), true, st.fill != null),
        .ink => if (ann.ink.legacy) {
            for (0..@max(1, ann.ink.starts.len)) |i| try path(a, &out, ann.ink.subpath(ann.points, i), false, false);
        } else {
            try out.appendSlice(a, "1 J 1 j\n");
            for (0..@max(1, ann.ink.starts.len)) |i| {
                const pts = ann.ink.subpath(ann.points, i);
                var current = pts[0];
                try out.print(a, "{d} {d} m\n", .{ current.x, current.y });
                if (ann.imported_ink and pts.len > 1) {
                    for (pts[1..]) |p| try out.print(a, "{d} {d} l\n", .{ p.x, p.y });
                } else if (pts.len <= 2) {
                    // An explicit zero-length segment with round caps paints a centered disk.
                    const end = pts[pts.len - 1];
                    try out.print(a, "{d} {d} l\n", .{ end.x, end.y });
                } else for (1..pts.len - 1) |j| {
                    const control = pts[j];
                    const next = pts[j + 1];
                    const end = if (j + 2 == pts.len) next else lerp(control, next, 0.5);
                    const c1 = lerp(current, control, 2.0 / 3.0);
                    const c2 = lerp(end, control, 2.0 / 3.0);
                    try out.print(a, "{d} {d} {d} {d} {d} {d} c\n", .{ c1.x, c1.y, c2.x, c2.y, end.x, end.y });
                    current = end;
                }
            }
            try out.appendSlice(a, "S\n");
        },
        .line, .polyline, .freehand_highlight, .tick => try path(a, &out, try geometry(a, ann), false, false),
        .arrow => {
            try path(a, &out, ann.points, false, false);
            const p = ann.points[0];
            const q = ann.points[1];
            const dx = q.x - p.x;
            const dy = q.y - p.y;
            const dist = @sqrt(dx * dx + dy * dy);
            const size = @min(dist * 0.4, @max(8, st.width * 4));
            try path(a, &out, &.{ .{ .x = q.x - dx / dist * size - dy / dist * size * 0.5, .y = q.y - dy / dist * size + dx / dist * size * 0.5 }, q, .{ .x = q.x - dx / dist * size + dy / dist * size * 0.5, .y = q.y - dy / dist * size - dx / dist * size * 0.5 } }, false, false);
        },
        .cross => {
            const pts = try geometry(a, ann);
            try path(a, &out, pts[0..2], false, false);
            try path(a, &out, pts[2..4], false, false);
        },
        .underline, .strikeout => {
            const yy = if (ann.kind == .underline) y else y + h * 0.5;
            try path(a, &out, &.{ .{ .x = x, .y = yy }, .{ .x = b[2], .y = yy } }, false, false);
        },
        .squiggly => {
            const count: usize = @intFromFloat(@min(2048, @max(2, @ceil(w / 3))));
            const pts = try a.alloc(Point, count + 1);
            for (pts, 0..) |*p, i| p.* = .{ .x = x + w * @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(count)), .y = y + (if (i % 2 == 0) @as(f64, 0) else @min(2, h / 4)) };
            try path(a, &out, pts, false, false);
        },
        .free_text => {
            try out.print(a, "{d} {d} {d} rg BT /F1 {d} Tf {d} TL 1 0 0 1 {d} {d} Tm\n", .{ st.stroke[0], st.stroke[1], st.stroke[2], st.font_size, st.font_size * 1.2, x + 2, b[3] - st.font_size - 2 });
            var lines = std.mem.splitScalar(u8, ann.text, '\n');
            var i: usize = 0;
            while (lines.next()) |line| : (i += 1) {
                if (i > 0) try out.appendSlice(a, "T*\n");
                try d.serialize(a, &out, .{ .string = line });
                try out.appendSlice(a, " Tj\n");
            }
            try out.appendSlice(a, "ET\n");
        },
        .comment => {
            try out.print(a, "{d} {d} {d} rg 0.12 0.12 0.12 RG {d} {d} {d} {d} re B\n", .{ st.stroke[0], st.stroke[1], st.stroke[2], x, y, w, h });
            for (1..4) |i| {
                const yy = y + h * @as(f64, @floatFromInt(i)) / 5;
                try path(a, &out, &.{ .{ .x = x + w * 0.2, .y = yy }, .{ .x = x + w * 0.8, .y = yy } }, false, false);
            }
        },
    }
    try out.appendSlice(a, "Q\n");
    return out.toOwnedSlice(a);
}

test "all markup kinds save reopen with stable ids styles and editable geometry" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "preserved page text");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    const style = Style{ .stroke = .{ 0.2, 0.4, 0.6 }, .fill = .{ 0.9, 0.7, 0.5 }, .opacity = 0.7, .width = 3, .font_size = 12 };
    const box = [_]Point{ .{ .x = 100, .y = 100 }, .{ .x = 250, .y = 180 } };
    const triangle = [_]Point{ box[0], .{ .x = 170, .y = 180 }, box[1] };
    var ids: [18]u32 = undefined;
    for (&ids, 0..) |*id, i| {
        const kind: Kind = @fromBackingInt(@intCast(i));
        id.* = try add(&doc, 0, kind, if (kind == .polygon) &triangle else &box, "Note\nsecond line", style);
    }
    const saved = try doc.save(a);
    defer a.free(saved);
    var reopened = try d.Document.open(a, saved);
    defer reopened.deinit();
    const items = try list(&reopened, 0);
    try std.testing.expectEqual(@as(usize, 18), items.len);
    for (items, ids, 0..) |item, id, i| {
        try std.testing.expectEqual(id, item.id);
        try std.testing.expectEqual(@as(u32, @intCast(i)), @backingInt(item.kind));
        try std.testing.expectEqualDeep(style, item.style);
        try std.testing.expectEqualStrings("Note\nsecond line", item.text);
        try std.testing.expectEqualSlices(Point, if (item.kind == .polygon) &triangle else &box, item.points);
    }
    try std.testing.expectEqualStrings("preserved page text", (try reopened.inspect())[0].runs[0].text);
    const moved = [_]Point{ .{ .x = 120, .y = 120 }, .{ .x = 280, .y = 200 } };
    try update(&reopened, 0, ids[0], .ellipse, &moved, "changed", .{});
    try remove(&reopened, 0, ids[1]);
    const second = try reopened.save(a);
    defer a.free(second);
    var edited = try d.Document.open(a, second);
    defer edited.deinit();
    const remaining = try list(&edited, 0);
    try std.testing.expectEqual(@as(usize, 17), remaining.len);
    try std.testing.expectEqual(ids[0], remaining[0].id);
    try std.testing.expectEqual(Kind.ellipse, remaining[0].kind);
    try std.testing.expectEqualSlices(Point, &moved, remaining[0].points);
    try std.testing.expectEqualStrings("changed", remaining[0].text);
    try std.testing.expectError(error.AnnotationNotFound, remove(&edited, 0, ids[1]));
    try @import("render.zig").validate(&edited);
}

test "annotation input rejection preserves page and unsupported external appearances reject" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "original");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    const box = [_]Point{ .{ .x = 10, .y = 20 }, .{ .x = 110, .y = 120 } };
    try std.testing.expectError(error.PageNotFound, add(&doc, 1, .rectangle, &box, "", .{}));
    try std.testing.expectError(error.InvalidAnnotationGeometry, add(&doc, 0, .rectangle, box[0..1], "", .{}));
    try std.testing.expectError(error.InvalidAnnotationGeometry, add(&doc, 0, .polygon, &box, "", .{}));
    try std.testing.expectError(error.InvalidAnnotationGeometry, add(&doc, 0, .line, &.{ .{ .x = std.math.nan(f64), .y = 0 }, box[1] }, "", .{}));
    try std.testing.expectError(error.InvalidAnnotationStyle, add(&doc, 0, .rectangle, &box, "", .{ .opacity = 1.1 }));
    try std.testing.expectError(error.InvalidAnnotationStyle, add(&doc, 0, .rectangle, &box, "", .{ .stroke = .{ 1, -1, 0 } }));
    try std.testing.expectError(error.UnsupportedEncoding, add(&doc, 0, .free_text, &box, "h\xc3\xa9", .{}));
    try std.testing.expectError(error.TextOverflow, add(&doc, 0, .free_text, &box, "text is too long for this small box", .{}));
    try std.testing.expectEqual(@as(usize, 0), (try list(&doc, 0)).len);
    const id = try add(&doc, 0, .rectangle, &box, "", .{});
    const obj = try doc.object(.{ .id = id, .generation = 0 });
    try doc.set(obj, "Subtype", name("Stamp"));
    try std.testing.expectError(error.UnsupportedAnnotation, @import("render.zig").validate(&doc));
}

test "alpha markup paints over existing page and survives save reopen" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "original");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    (try doc.object(.{ .id = 5, .generation = 0 })).changed = "0 0 1 rg 0 0 612 792 re f";
    const points = [_]Point{ .{ .x = 100, .y = 100 }, .{ .x = 200, .y = 200 } };
    _ = try add(&doc, 0, .highlight, &points, "", .{ .stroke = .{ 1, 1, 0 }, .opacity = 0.4 });
    const saved = try doc.save(a);
    defer a.free(saved);
    var reopened = try d.Document.open(a, saved);
    defer reopened.deinit();
    const bitmap = try @import("render.zig").render(a, &reopened, 0, &.{}, 612);
    defer a.free(bitmap.pixels);
    const at = ((792 - 150) * 612 + 150) * 4;
    try std.testing.expectEqualSlices(u8, &.{ 102, 102, 153, 255 }, bitmap.pixels[at..][0..4]);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 255, 255 }, bitmap.pixels[0..4]);
    const item = (try list(&reopened, 0))[0];
    const ap = try appearanceObject(&reopened, item);
    ap.changed = "q 0 0 0 rg 100 100 100 100 re f Q";
    try std.testing.expectError(error.UnsupportedAnnotation, @import("render.zig").validate(&reopened));
}

test "all eighteen annotation tools paint visible pixels without flattening page content" {
    if (@import("builtin").os.tag != .macos) return error.SkipZigTest;
    const a = std.testing.allocator;
    const font_bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "/System/Library/Fonts/Supplemental/Courier New.ttf", a, .limited(8 * 1024 * 1024));
    defer a.free(font_bytes);
    const bytes = try @import("pod.zig").create(a, "");
    defer a.free(bytes);
    for (0..18) |i| {
        var doc = try d.Document.open(a, bytes);
        defer doc.deinit();
        (try doc.object(.{ .id = 5, .generation = 0 })).changed = "";
        const kind: Kind = @fromBackingInt(@intCast(i));
        const box = [_]Point{ .{ .x = 100, .y = 100 }, .{ .x = 250, .y = 180 } };
        const triangle = [_]Point{ box[0], .{ .x = 170, .y = 180 }, box[1] };
        _ = try add(&doc, 0, kind, if (kind == .polygon) &triangle else &box, "visible", .{ .stroke = .{ 1, 0, 0 } });
        const bitmap = try @import("render.zig").render(a, &doc, 0, font_bytes, 306);
        defer a.free(bitmap.pixels);
        var changed: usize = 0;
        for (0..bitmap.pixels.len / 4) |pixel| if (bitmap.pixels[pixel * 4 + 1] < 250) {
            changed += 1;
        };
        try std.testing.expect(changed > 10);
        try std.testing.expectEqualStrings("", (try doc.object(.{ .id = 5, .generation = 0 })).changed.?);
    }
}

test "repeated annotation edits reuse appearance objects and do not grow saved files" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "original");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    const points = [_]Point{ .{ .x = 100, .y = 100 }, .{ .x = 250, .y = 180 } };
    const id = try add(&doc, 0, .free_text, &points, "Example", .{});
    const original_count = doc.entries.len;
    const original_ap = try appearanceObject(&doc, (try list(&doc, 0))[0]);
    const before = try doc.save(a);
    defer a.free(before);
    for (0..20) |_| try update(&doc, 0, id, .free_text, &points, "Example", .{});
    try std.testing.expectEqual(original_count, doc.entries.len);
    try std.testing.expect(original_ap == try appearanceObject(&doc, (try list(&doc, 0))[0]));
    const after = try doc.save(a);
    defer a.free(after);
    try std.testing.expectEqualSlices(u8, before, after);
}

test "comment selected color paints note background with dark contrasting lines" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    (try doc.object(.{ .id = 5, .generation = 0 })).changed = "";
    _ = try add(&doc, 0, .comment, &.{ .{ .x = 100, .y = 100 }, .{ .x = 200, .y = 200 } }, "Custom green note", .{ .stroke = .{ 0.2, 0.8, 0.4 } });
    const saved = try doc.save(a);
    defer a.free(saved);
    var reopened = try d.Document.open(a, saved);
    defer reopened.deinit();
    const bitmap = try @import("render.zig").render(a, &reopened, 0, &.{}, 612);
    defer a.free(bitmap.pixels);
    const background = ((792 - 150) * 612 + 150) * 4;
    const line = ((792 - 140) * 612 + 150) * 4;
    try std.testing.expectEqualSlices(u8, &.{ 51, 204, 102, 255 }, bitmap.pixels[background..][0..4]);
    try std.testing.expectEqualSlices(u8, &.{ 31, 31, 31, 255 }, bitmap.pixels[line..][0..4]);
}

test "save removes deleted note and appearance secrets while retaining reachable page metadata" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "original page remains");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    const points = [_]Point{ .{ .x = 100, .y = 100 }, .{ .x = 500, .y = 200 } };
    const secret = "deleted-unique-secret";
    const note = try add(&doc, 0, .comment, &points, secret, .{});
    const text = try add(&doc, 0, .free_text, &points, secret, .{});
    const note_ap = (try required(try required((try doc.object(.{ .id = note, .generation = 0 })).value, "AP"), "N")).ref.id;
    const text_ap = (try required(try required((try doc.object(.{ .id = text, .generation = 0 })).value, "AP"), "N")).ref.id;
    const info = try doc.addObject(try dict(doc.allocator(), &.{.{ .key = "Subject", .value = .{ .string = "retain original metadata" } }}), null);
    const trailer = try doc.allocator().alloc(s.Entry, doc.trailer.dict.len + 1);
    @memcpy(trailer[0..doc.trailer.dict.len], doc.trailer.dict);
    trailer[doc.trailer.dict.len] = .{ .key = "Info", .value = reference(info) };
    doc.trailer = .{ .dict = trailer };
    try remove(&doc, 0, note);
    try remove(&doc, 0, text);
    const saved = try doc.save(a);
    defer a.free(saved);
    var encoded: std.ArrayList(u8) = .empty;
    defer encoded.deinit(a);
    try d.serialize(a, &encoded, .{ .string = secret });
    try std.testing.expect(std.mem.indexOf(u8, saved, encoded.items) == null);
    try std.testing.expect(std.mem.indexOf(u8, saved, secret) == null);
    var reopened = try d.Document.open(a, saved);
    defer reopened.deinit();
    try std.testing.expectEqualStrings("original page remains", (try reopened.inspect())[0].runs[0].text);
    try std.testing.expectEqual(@as(usize, 0), (try list(&reopened, 0)).len);
    for ([_]u32{ note, text, note_ap, text_ap }) |id| try std.testing.expect(!reopened.entries[id].live);
    const metadata = try reopened.resolve((try required(reopened.trailer, "Info")));
    try std.testing.expectEqualStrings("retain original metadata", (try required(metadata, "Subject")).string);
}

test "adding preserves unknown existing annotations while rendering still rejects them" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "original");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    const points = [_]Point{ .{ .x = 100, .y = 100 }, .{ .x = 200, .y = 200 } };
    const id = try add(&doc, 0, .comment, &points, "preserved unsupported", .{});
    const obj = try doc.object(.{ .id = id, .generation = 0 });
    try doc.set(obj, "Subtype", name("Stamp"));
    _ = try add(&doc, 0, .rectangle, &points, "", .{});
    try std.testing.expectEqualStrings("Stamp", (try required(obj.value, "Subtype")).name);
    try std.testing.expectError(error.UnsupportedAnnotation, @import("render.zig").validate(&doc));
    const saved = try doc.save(a);
    defer a.free(saved);
    var reopened = try d.Document.open(a, saved);
    defer reopened.deinit();
    const preserved = try reopened.object(.{ .id = id, .generation = 0 });
    try std.testing.expectEqualStrings("preserved unsupported", (try required(preserved.value, "Contents")).string);
    try std.testing.expectError(error.UnsupportedAnnotation, list(&reopened, 0));
}

test "batch annotation appends grow xref and reference storage geometrically" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "original");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    const points = [_]Point{ .{ .x = 100, .y = 100 }, .{ .x = 200, .y = 200 } };
    var xref_moves: usize = 0;
    var refs_moves: usize = 0;
    var last_xref = doc.entries.ptr;
    var last_refs = (try refs(&doc, 0)).ptr;
    for (0..1000) |_| {
        _ = try add(&doc, 0, .rectangle, &points, "", .{});
        if (last_xref != doc.entries.ptr) xref_moves += 1;
        last_xref = doc.entries.ptr;
        const current = try refs(&doc, 0);
        if (last_refs != current.ptr) refs_moves += 1;
        last_refs = current.ptr;
    }
    try std.testing.expect(xref_moves < 20);
    try std.testing.expect(refs_moves < 20);
    try std.testing.expectEqual(@as(usize, 1000), (try refs(&doc, 0)).len);
    try std.testing.expectError(error.AnnotationLimit, add(&doc, 0, .rectangle, &points, "", .{}));
}

test "standard highlight without appearance preserves metadata and quad order across edits" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "page");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    const arena = doc.allocator();
    const value = try dict(arena, &.{
        .{ .key = "Subtype", .value = name("Highlight") },
        .{ .key = "QuadPoints", .value = try numbers(arena, &.{ 10, 20, 40, 25, 41, 31, 11, 26 }) },
        .{ .key = "Rect", .value = try numbers(arena, &.{ 8, 17, 45, 33 }) },
        .{ .key = "NM", .value = .{ .string = "annotation-id" } },
        .{ .key = "Contents", .value = .{ .string = "Review \x80" } },
    });
    const id = try doc.addObject(value, null);
    try doc.set(try pageObject(&doc, 0), "Annots", .{ .array = try arena.dupe(s.Value, &.{reference(id)}) });
    const mark = (try list(&doc, 0))[0];
    try std.testing.expectEqualStrings("Review •", mark.text);
    const obj = try doc.object(reference(id).ref);
    try update(&doc, 0, id, mark.kind, mark.points, "Updated", mark.style);
    try std.testing.expect(s.get(obj.value, "AP") == null);
    var style = mark.style;
    style.opacity = 0.25;
    try update(&doc, 0, id, mark.kind, mark.points, "Updated", style);
    try std.testing.expect(s.get(obj.value, "PodKind") == null);
    try std.testing.expectEqualStrings("annotation-id", (try required(obj.value, "NM")).string);
    const saved = try doc.save(a);
    defer a.free(saved);
    var reopened = try d.Document.open(a, saved);
    defer reopened.deinit();
    const after = (try list(&reopened, 0))[0];
    try std.testing.expectEqualSlices(Point, mark.points, after.points);
    try std.testing.expectEqual(mark.rect, after.rect);
    try std.testing.expectEqualStrings("Updated", after.text);
    try std.testing.expectEqual(0.25, after.style.opacity);
    try doc.set(obj, "QuadPoints", try numbers(arena, &.{ 0, 1, 2, 3, 4, 5, 6, 7 }));
    try std.testing.expectError(error.InvalidAnnotationGeometry, list(&doc, 0));
}

test "rotated markup follows the text baseline in either quad order" {
    // Bottom edge runs upwards, with the top of the text to its left.
    const bl = Point{ .x = 40, .y = 10 };
    const br = Point{ .x = 40, .y = 70 };
    const tl = Point{ .x = 28, .y = 10 };
    const tr = Point{ .x = 28, .y = 70 };
    for ([_][4]Point{ .{ bl, br, tr, tl }, .{ tl, tr, bl, br } }) |quad| {
        var mark = Annotation{ .id = 1, .kind = .underline, .points = &quad, .rect = bounds(&quad), .text = "", .style = .{} };
        var buf: MarkupPolygon = undefined;
        const line = markupPolygon(mark, 0, &buf);
        try std.testing.expectEqual(bl, line[0]);
        try std.testing.expectEqual(br, line[1]);
        mark.kind = .strikeout;
        try std.testing.expectEqual(@as(f64, 35), markupPolygon(mark, 0, &buf)[0].x);
        mark.kind = .squiggly;
        const wave = markupPolygon(mark, 0, &buf);
        try std.testing.expect(wave[1].x < wave[0].x and wave[2].x == wave[0].x and wave[2].y > wave[1].y);
    }
}

test "legacy native ink keeps its original straight-line appearance after reopening and editing" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    const points = [_]Point{ .{ .x = 20, .y = 30 }, .{ .x = 80, .y = 110 }, .{ .x = 140, .y = 30 } };
    const id = try addWithInk(&doc, 0, .ink, &points, "", .{}, .{ .legacy = true });
    const ap = try appearanceObject(&doc, (try list(&doc, 0))[0]);
    try std.testing.expect(std.mem.indexOf(u8, ap.changed.?, "20 30 m\n80 110 l\n140 30 l\nS\n") != null);
    const saved = try doc.save(a);
    defer a.free(saved);
    var reopened = try d.Document.open(a, saved);
    defer reopened.deinit();
    try update(&reopened, 0, id, .ink, &points, "Updated", .{ .width = 8 });
    const mark = (try list(&reopened, 0))[0];
    try std.testing.expect(mark.ink.legacy);
    try std.testing.expectEqualStrings("Updated", mark.text);
    try std.testing.expectEqualSlices(Point, &points, mark.points);
}

test "ink rejects invalid grouped geometry and unsafe hyperlinks before adding objects" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    const points = [_]Point{ .{ .x = 10, .y = 10 }, .{ .x = 20, .y = 20 } };
    for ([_][]const usize{ &.{1}, &.{ 0, 0 }, &.{ 0, 2 }, &.{ 0, 1, 1 } }) |starts|
        try std.testing.expectError(error.InvalidAnnotationGeometry, addWithInk(&doc, 0, .ink, &points, "", .{}, .{ .starts = starts }));
    try std.testing.expectError(error.InvalidAnnotationGeometry, addWithInk(&doc, 0, .line, &points, "", .{}, .{ .starts = &.{ 0, 1 } }));
    for ([_][]const u8{ "file:///tmp/example", "javascript:alert(1)", "https://", "http://example.com/\n" }) |url|
        try std.testing.expectError(error.InvalidAnnotationLink, addWithInk(&doc, 0, .ink, &points, "", .{}, .{ .link = url }));
    try std.testing.expectEqual(0, (try list(&doc, 0)).len);
}

test "standard InkList without AP reads dots and paths, preserves locked objects and refuses custom appearances" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    (try doc.object(reference(5).ref)).changed = "";
    const arena = doc.allocator();
    const contours = try arena.dupe(s.Value, &.{ try numbers(arena, &.{ 20, 30 }), try numbers(arena, &.{ 80, 20, 110, 50 }) });
    const id = try doc.addObject(try dict(arena, &.{ .{ .key = "Subtype", .value = name("Ink") }, .{ .key = "InkList", .value = .{ .array = contours } }, .{ .key = "Rect", .value = try numbers(arena, &.{ 10, 10, 120, 60 }) }, .{ .key = "T", .value = .{ .string = "Owner" } }, .{ .key = "BS", .value = try dict(arena, &.{.{ .key = "W", .value = number(8) }}) } }), null);
    const obj = try doc.object(reference(id).ref);
    try doc.set(try pageObject(&doc, 0), "Annots", .{ .array = try arena.dupe(s.Value, &.{reference(id)}) });
    const first = (try list(&doc, 0))[0];
    try std.testing.expectEqualSlices(usize, &.{ 0, 1 }, first.ink.starts);
    try updateWithInk(&doc, 0, id, .ink, first.points, "", first.style, first.ink);
    try std.testing.expect(s.get(obj.value, "AP") == null);
    const bitmap = try @import("render.zig").render(a, &doc, 0, &.{}, 612);
    defer a.free(bitmap.pixels);
    try std.testing.expectEqual(@as(u8, 0), bitmap.pixels[((791 - 30) * 612 + 20) * 4]);
    try std.testing.expectEqual(@as(u8, 255), bitmap.pixels[((791 - 30) * 612 + 25) * 4]);
    for ([_]i64{ 64, 128, 512 }) |flag| {
        try doc.set(obj, "F", .{ .integer = flag });
        try std.testing.expect((try list(&doc, 0))[0].locked);
        try std.testing.expectError(error.AnnotationLocked, updateWithInk(&doc, 0, id, .ink, first.points, "Modified", first.style, first.ink));
        try std.testing.expectError(error.AnnotationLocked, remove(&doc, 0, id));
    }
    try doc.set(obj, "F", .{ .integer = 4 });
    try updateWithInk(&doc, 0, id, .ink, first.points, "Nouveau", first.style, first.ink);
    try std.testing.expect(s.get(obj.value, "AP") == null);
    var changed = first.style;
    changed.width = 12;
    try updateWithInk(&doc, 0, id, .ink, first.points, "Nouveau", changed, first.ink);
    try std.testing.expectEqualStrings("Owner", (try required(obj.value, "T")).string);
    try std.testing.expect(s.get(obj.value, "PodKind") == null);
    const mark = (try list(&doc, 0))[0];
    const form = try appearanceObject(&doc, mark);
    form.changed = "q 0 0 1 rg 0 0 20 20 re f Q";
    try std.testing.expectError(error.UnsupportedAnnotationAppearance, list(&doc, 0));
}
