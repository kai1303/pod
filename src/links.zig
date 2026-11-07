const std = @import("std");
const d = @import("document.zig");
const s = @import("syntax.zig");
const annotations = @import("annotations.zig");

// Links stay separate from drawing annotations: their hot area does not create
// selectable ink, and their original action/metadata dictionary survives saves.
pub const Link = struct {
    id: u32,
    rect: [4]f64,
    uri: []const u8 = "",
    destination: ?@import("destinations.zig").Destination = null,
    base: []const u8 = "",
    quads: []const annotations.Point = &.{},
    color: [3]f64 = .{ 0, 0, 0 },
    width: f64 = 1,
    underline: bool = false,
    hidden: bool = false,
};
fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
fn get(doc: *d.Document, value: s.Value, key: []const u8, default: s.Value) !s.Value {
    if (value != .dict) return error.InvalidLink;
    return doc.resolve(s.get(value, key) orelse default);
}
fn numeric(doc: *d.Document, value: s.Value) !f64 {
    const n = try s.number(try doc.resolve(value));
    if (!std.math.isFinite(n) or @abs(n) > 1e6) return error.InvalidLink;
    return n;
}
fn rectangle(doc: *d.Document, value: s.Value) ![4]f64 {
    if (value != .array or value.array.len != 4) return error.InvalidLink;
    var coords: [4]f64 = undefined;
    for (&coords, value.array) |*coord, item| coord.* = try numeric(doc, item);
    return .{ @min(coords[0], coords[2]), @min(coords[1], coords[3]), @max(coords[0], coords[2]), @max(coords[1], coords[3]) };
}
fn string(value: s.Value) ![]const u8 {
    if (value != .string or value.string.len > 8192 or !std.unicode.utf8ValidateSlice(value.string)) return error.InvalidLink;
    for (value.string) |ch| if (ch < 32 or ch == 127) return error.InvalidLink;
    return value.string;
}
pub fn read(doc: *d.Document, ref: s.Ref) !Link {
    const v = (try doc.object(ref)).value;
    const sub = try get(doc, v, "Subtype", .null);
    if (sub != .name or !eq(sub.name, "Link")) return error.InvalidLink;
    const typ = try get(doc, v, "Type", .{ .name = "Annot" });
    if (typ != .name or !eq(typ.name, "Annot")) return error.InvalidLink;
    if (s.get(v, "OC") != null or s.get(v, "AP") != null) return error.UnsupportedLinkAppearance;
    const flags = try s.uint(try get(doc, v, "F", .{ .integer = 0 }));
    // NoZoom/NoRotate/ToggleNoView need view-dependent appearance handling.
    if (flags & ~@as(usize, 1 | 2 | 4 | 32 | 64 | 128 | 512) != 0) return error.UnsupportedLinkAppearance;
    const action = try get(doc, v, "A", .null);
    const target = try get(doc, v, "Dest", .null);
    if (s.get(v, "AA") != null) return error.UnsupportedLinkAction;
    if (action != .null and target != .null) return error.InvalidLink;
    var link = Link{ .id = ref.id, .rect = try rectangle(doc, try get(doc, v, "Rect", .null)), .hidden = flags & (2 | 32) != 0 };
    if (target != .null) {
        link.destination = try @import("destinations.zig").read(doc, target);
    } else {
        const kind = try get(doc, action, "S", .null);
        if (kind != .name or s.get(action, "Next") != null or s.get(action, "SD") != null) return error.UnsupportedLinkAction;
        if (eq(kind.name, "URI")) {
            const is_map = try get(doc, action, "IsMap", .{ .boolean = false });
            if (is_map != .boolean or is_map.boolean) return error.UnsupportedLinkAction;
            link.uri = try string(try get(doc, action, "URI", .null));
        } else if (eq(kind.name, "GoTo")) {
            link.destination = try @import("destinations.zig").read(doc, try get(doc, action, "D", .null));
        } else return error.UnsupportedLinkAction;
    }
    if (s.get(doc.trailer, "Root")) |root| {
        const catalog = try doc.resolve(root);
        const uri = try get(doc, catalog, "URI", .null);
        if (uri != .null) link.base = try string(try get(doc, uri, "Base", .{ .string = "" }));
    }
    const quads = try get(doc, v, "QuadPoints", .null);
    if (quads != .null) {
        if (quads != .array or quads.array.len == 0 or quads.array.len % 8 != 0 or quads.array.len > 8192) return error.InvalidLink;
        const points = try doc.allocator().alloc(annotations.Point, quads.array.len / 2);
        for (points, 0..) |*p, i| p.* = .{ .x = try numeric(doc, quads.array[2 * i]), .y = try numeric(doc, quads.array[2 * i + 1]) };
        link.quads = points;
    }
    const color = try get(doc, v, "C", .null);
    if (color != .null) {
        if (color != .array) return error.InvalidLink;
        if (color.array.len == 0) link.width = 0 else if (color.array.len == 1) link.color = @splat(try numeric(doc, color.array[0])) else if (color.array.len == 3) {
            for (&link.color, color.array) |*channel, x| channel.* = try numeric(doc, x);
        } else if (color.array.len == 4) {
            const k = try numeric(doc, color.array[3]);
            if (k < 0 or k > 1) return error.InvalidLink;
            for (&link.color, color.array[0..3]) |*channel, x| {
                const c = try numeric(doc, x);
                if (c < 0 or c > 1) return error.InvalidLink;
                channel.* = 1 - @min(1, c + k);
            }
        } else return error.InvalidLink;
        for (link.color) |channel| if (channel < 0 or channel > 1) return error.InvalidLink;
    }
    var width: f64 = 1;
    const bs = try get(doc, v, "BS", .null);
    if (bs != .null) {
        width = try numeric(doc, try get(doc, bs, "W", .{ .integer = 1 }));
        const style = try get(doc, bs, "S", .{ .name = "S" });
        if (style != .name) return error.InvalidLink;
        if (width != 0 and !eq(style.name, "S") and !eq(style.name, "U")) return error.UnsupportedLinkAppearance;
        link.underline = eq(style.name, "U");
    } else {
        const border = try get(doc, v, "Border", .null);
        if (border != .null) {
            if (border != .array or border.array.len < 3 or border.array.len > 4) return error.InvalidLink;
            width = try numeric(doc, border.array[2]);
            if (width != 0) {
                if (try numeric(doc, border.array[0]) != 0 or try numeric(doc, border.array[1]) != 0 or border.array.len == 4) return error.UnsupportedLinkAppearance;
            }
        }
    }
    if (width < 0 or width > 100) return error.InvalidLink;
    if (link.width != 0) link.width = width;
    return link;
}
pub fn list(doc: *d.Document, page: usize) ![]Link {
    var result: std.ArrayList(Link) = .empty;
    for (try annotations.refs(doc, page)) |ref| {
        if (ref != .ref) return error.UnsupportedAnnotation;
        const obj = try doc.object(ref.ref);
        const sub = try get(doc, obj.value, "Subtype", .null);
        if (sub == .name and eq(sub.name, "Link")) try result.append(doc.allocator(), try read(doc, ref.ref));
    }
    return result.items;
}

fn fixture(doc: *d.Document, body: []const u8) !s.Ref {
    var parser = s.Parser{ .allocator = doc.allocator(), .bytes = body };
    return .{ .id = try doc.addObject(try parser.value(), null), .generation = 0 };
}
test "URI link styles flags quads indirect actions and catalog base" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    const action = try fixture(&doc, "<< /S /URI /URI (chapter.html) >>");
    const ref = try fixture(&doc, "<< /Subtype /Link /Rect [10 10 90 50] /F 32 /BS << /W 3 /S /U >> /C [0.5] /QuadPoints [10 40 90 40 10 10 90 10] >>");
    try doc.set(try doc.object(ref), "A", .{ .ref = action });
    const base = try fixture(&doc, "<< /Base (https://example.com/course/) >>");
    try doc.set(try doc.object(.{ .id = 1, .generation = 0 }), "URI", .{ .ref = base });
    const link = try read(&doc, ref);
    try std.testing.expectEqualStrings("chapter.html", link.uri);
    try std.testing.expectEqualStrings("https://example.com/course/", link.base);
    try std.testing.expect(link.hidden and link.underline);
    try std.testing.expectEqual(@as(f64, 3), link.width);
    try std.testing.expectEqual(@as(usize, 4), link.quads.len);
    try std.testing.expectEqual([3]f64{ 0.5, 0.5, 0.5 }, link.color);
    // Non-web schemes remain data; the native host chooses what may activate.
    const other = try fixture(&doc, "<< /Subtype /Link /Rect [10 10 90 50] /Border [0 0 0] /A << /S /URI /URI (file:///tmp/private) >> >>");
    try std.testing.expectEqualStrings("file:///tmp/private", (try read(&doc, other)).uri);
    try std.testing.expectEqual(@as(f64, 0), (try read(&doc, other)).width);
}
test "links reject malformed geometry and unsupported appearances or action chains" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    const cases = [_]struct { field: []const u8, err: anyerror }{
        .{ .field = "/QuadPoints [0 0]", .err = error.InvalidLink },
        .{ .field = "/BS << /W -2 >>", .err = error.InvalidLink },
        .{ .field = "/C [2 0 0]", .err = error.InvalidLink },
        .{ .field = "/Border [1 1 2]", .err = error.UnsupportedLinkAppearance },
        .{ .field = "/BS << /S /D >>", .err = error.UnsupportedLinkAppearance },
        .{ .field = "/AP << /N 5 0 R >>", .err = error.UnsupportedLinkAppearance },
        .{ .field = "/F 8", .err = error.UnsupportedLinkAppearance },
        .{ .field = "/Dest [3 0 R /Fit]", .err = error.InvalidLink },
        .{ .field = "/AA << >>", .err = error.UnsupportedLinkAction },
    };
    for (cases) |case| {
        const body = try std.fmt.allocPrint(a, "<< /Subtype /Link /Rect [10 10 90 50] /A << /S /URI /URI (https://example.com/) >> {s} >>", .{case.field});
        defer a.free(body);
        const ref = try fixture(&doc, body);
        try std.testing.expectError(case.err, read(&doc, ref));
    }
    const chained = try fixture(&doc, "<< /Subtype /Link /Rect [0 0 10 10] /A << /S /URI /URI (https://example.com/) /Next << /S /Launch >> >> >>");
    try std.testing.expectError(error.UnsupportedLinkAction, read(&doc, chained));
    const mapped = try fixture(&doc, "<< /Subtype /Link /Rect [0 0 10 10] /A << /S /URI /URI (https://example.com/) /IsMap true >> >>");
    try std.testing.expectError(error.UnsupportedLinkAction, read(&doc, mapped));
}

test "page extraction remaps annotation owner references" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    const ref = try fixture(&doc, "<< /Subtype /Link /P 3 0 R /Rect [10 10 90 50] /Border [0 0 0] /A << /S /URI /URI (https://example.com/) >> >>");
    try doc.set(try doc.object(.{ .id = 3, .generation = 0 }), "Annots", .{ .array = try doc.allocator().dupe(s.Value, &.{.{ .ref = ref }}) });
    const saved = try @import("page_tools.zig").assemble(a, &.{.{ .doc = &doc, .pages = &.{0} }});
    defer a.free(saved);
    var copy = try d.Document.open(a, saved);
    defer copy.deinit();
    const imported = try list(&copy, 0);
    try std.testing.expectEqual(@as(usize, 1), imported.len);
    const obj = try copy.object(.{ .id = imported[0].id, .generation = 0 });
    const owner = s.get(obj.value, "P").?.ref.id;
    try std.testing.expectEqual((try copy.inspect())[0].object_id, owner);
}

test "link rectangles accept reversed coordinates and empty hot areas" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    const reversed = try fixture(&doc, "<< /Subtype /Link /Rect [90 50 10 10] /A << /S /URI /URI (https://example.com/) >> >>");
    try std.testing.expectEqual([4]f64{ 10, 10, 90, 50 }, (try read(&doc, reversed)).rect);
    const empty = try fixture(&doc, "<< /Subtype /Link /Rect [0 0 0 0] /A << /S /URI /URI (https://example.com/) >> >>");
    try std.testing.expectEqual([4]f64{ 0, 0, 0, 0 }, (try read(&doc, empty)).rect);
}

test "internal link destinations render and retain their original target" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    const ref = try fixture(&doc, "<< /Subtype /Link /Rect [10 10 90 50] /Border [0 0 0] /Dest [3 0 R /XYZ 10 720 null] >>");
    try doc.set(try doc.object(.{ .id = 3, .generation = 0 }), "Annots", .{ .array = try doc.allocator().dupe(s.Value, &.{.{ .ref = ref }}) });
    try @import("render.zig").validate(&doc);
    const saved = try doc.save(a);
    defer a.free(saved);
    var copy = try d.Document.open(a, saved);
    defer copy.deinit();
    try std.testing.expectEqual(@as(usize, 1), (try list(&copy, 0)).len);
    const target = s.get((try copy.object(ref)).value, "Dest").?.array;
    try std.testing.expectEqual(@as(u32, 3), target[0].ref.id);
    try std.testing.expectEqualStrings("XYZ", target[1].name);
}
