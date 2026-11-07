// Recognize a PDFKit ink form only when its painting operations agree with
// InkList. A different external AP may describe entirely different artwork.
const std = @import("std");
const s = @import("syntax.zig");
const d = @import("document.zig");
const ann = @import("annotations.zig");
const eq = std.mem.eql;

pub fn stream(doc: *d.Document, obj: *d.Object, limit: usize) ![]const u8 {
    return @import("filters.zig").decode(doc, obj, doc.allocator(), limit);
}

fn sameNumber(parser: *s.Parser, expected: f64) !void {
    const actual = try s.number(try parser.value());
    if (@abs(expected - actual) > 0.0001) return error.UnsupportedAnnotationAppearance;
}
fn word(parser: *s.Parser, expected: []const u8) !void {
    if (!parser.keyword(expected)) return error.UnsupportedAnnotationAppearance;
}
fn resource(doc: *d.Document, resources: s.Value, category: []const u8, key: s.Value) !s.Value {
    if (key != .name) return error.UnsupportedAnnotationAppearance;
    const table = try doc.resolve(s.get(resources, category) orelse return error.UnsupportedAnnotationAppearance);
    return doc.resolve(s.get(table, key.name) orelse return error.UnsupportedAnnotationAppearance);
}
pub fn pdfKit(doc: *d.Document, form: *d.Object, data: []const u8, mark: *ann.Annotation) !void {
    const a = doc.allocator();
    const resources = try doc.resolve(s.get(form.value, "Resources") orelse return error.UnsupportedAnnotationAppearance);
    const box = try d.rectangle(try doc.resolve(s.get(form.value, "BBox") orelse return error.UnsupportedAnnotationAppearance));
    const w = mark.rect[2] - mark.rect[0];
    const h = mark.rect[3] - mark.rect[1];
    if (box[0] != 0 or box[1] != 0 or @abs(box[2] - w) > 0.0001 or @abs(box[3] - h) > 0.0001) return error.UnsupportedAnnotationAppearance;
    var parser = s.Parser{ .bytes = data, .allocator = a };
    try word(&parser, "q");
    try word(&parser, "Q");
    try word(&parser, "q");
    for (box) |n| try sameNumber(&parser, n);
    for ([_][]const u8{ "re", "W", "n" }) |op| try word(&parser, op);
    try sameNumber(&parser, mark.style.width);
    try word(&parser, "w");
    try sameNumber(&parser, 1);
    try word(&parser, "J");
    try sameNumber(&parser, 1);
    try word(&parser, "j");
    const colorspace = try resource(doc, resources, "ColorSpace", try parser.value());
    if (colorspace != .array or colorspace.array.len != 2 or colorspace.array[0] != .name or !eq(u8, colorspace.array[0].name, "ICCBased") or colorspace.array[1] != .ref) return error.UnsupportedAnnotationAppearance;
    const profile = try doc.object(colorspace.array[1].ref);
    const channels = try s.uint(s.get(profile.value, "N") orelse return error.UnsupportedAnnotationAppearance);
    const icc = try stream(doc, profile, 256 * 1024);
    if (icc.len < 56) return error.UnsupportedAnnotationAppearance;
    if (channels == 3) {
        if (!eq(u8, icc[16..20], "RGB ") or !eq(u8, icc[48..56], "IEC sRGB")) return error.UnsupportedAnnotationAppearance;
    } else if (channels == 1) {
        const gray = mark.style.stroke[0];
        if (!eq(u8, icc[16..20], "GRAY") or (gray != 0 and gray != 1) or mark.style.stroke[1] != gray or mark.style.stroke[2] != gray) return error.UnsupportedAnnotationAppearance;
    } else return error.UnsupportedAnnotationAppearance;
    try word(&parser, "CS");
    for (mark.style.stroke[0..channels]) |v| try sameNumber(&parser, v);
    try word(&parser, "SC");
    parser.skip();
    if (parser.pos < data.len and data[parser.pos] == '/') {
        const gs = try resource(doc, resources, "ExtGState", try parser.value());
        if (gs != .dict) return error.UnsupportedAnnotationAppearance;
        for (gs.dict) |entry| {
            if (!eq(u8, entry.key, "Type") and !eq(u8, entry.key, "CA")) return error.UnsupportedAnnotationAppearance;
        }
        mark.style.opacity = try s.number(s.get(gs, "CA") orelse return error.UnsupportedAnnotationAppearance);
        try word(&parser, "gs");
    }
    for (0..@max(1, mark.ink.starts.len)) |i| {
        const path = mark.ink.subpath(mark.points, i);
        for (path, 0..) |p, j| {
            try sameNumber(&parser, p.x - mark.rect[0]);
            try sameNumber(&parser, p.y - mark.rect[1]);
            try word(&parser, if (j == 0) "m" else "l");
        }
        try word(&parser, "S");
    }
    try word(&parser, "Q");
    parser.skip();
    if (parser.pos != data.len) return error.UnsupportedAnnotationAppearance;
}
