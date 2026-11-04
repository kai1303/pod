const std = @import("std");
const d = @import("document.zig");
const s = @import("syntax.zig");
const A = std.mem.Allocator;
pub const Kind = enum(u32) { rectangle, ellipse, line, arrow, polyline, polygon, cloud, star, cross, tick, highlight, freehand_highlight, underline, squiggly, strikeout, ink, free_text, comment };
pub const Point = extern struct { x: f64, y: f64 };
pub const Style = struct { stroke: [3]f64 = .{ 0.15, 0.35, 0.9 }, fill: ?[3]f64 = null, opacity: f64 = 1, width: f64 = 2, font_size: f64 = 14 };
pub const Annotation = struct { id: u32, kind: Kind, points: []const Point, rect: [4]f64, text: []const u8, style: Style };
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
    if (points.len < 2 or points.len > 4096 or (!pathKind(kind) and points.len != 2)) return error.InvalidAnnotationGeometry;
    if (kind == .polygon and points.len < 3) return error.InvalidAnnotationGeometry;
    for (points) |p| if (!std.math.isFinite(p.x) or !std.math.isFinite(p.y) or @abs(p.x) > 1e6 or @abs(p.y) > 1e6) return error.InvalidAnnotationGeometry;
    const r = bounds(points);
    if (r[2] == r[0] and r[3] == r[1]) return error.InvalidAnnotationGeometry;
    if (!pathKind(kind) and kind != .line and kind != .arrow and (r[2] - r[0] < 0.1 or r[3] - r[1] < 0.1)) return error.InvalidAnnotationGeometry;
    if (!std.math.isFinite(style.opacity) or style.opacity < 0 or style.opacity > 1 or !std.math.isFinite(style.width) or style.width < 0.1 or style.width > 100 or !std.math.isFinite(style.font_size) or style.font_size < 1 or style.font_size > 200) return error.InvalidAnnotationStyle;
    for (style.stroke) |v| if (!std.math.isFinite(v) or v < 0 or v > 1) return error.InvalidAnnotationStyle;
    if (style.fill) |fill| for (fill) |v| {
        if (!std.math.isFinite(v) or v < 0 or v > 1) return error.InvalidAnnotationStyle;
    };
    if (text.len > 16384) return error.TextLimit;
    for (text) |ch| if ((ch < 32 and ch != '\n') or ch > 126) return error.UnsupportedEncoding;
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
fn read(doc: *d.Document, value: s.Value) !Annotation {
    if (value != .ref) return error.UnsupportedAnnotation;
    const obj = try doc.object(value.ref);
    const v = obj.value;
    if (v != .dict) return error.UnsupportedAnnotation;
    const typ = try required(v, "Type");
    if (typ != .name or !eq(typ.name, "Annot") or try s.uint(try required(v, "F")) != 4) return error.UnsupportedAnnotation;
    for (v.dict) |entry| {
        var supported = false;
        for ([_][]const u8{ "Type", "Subtype", "Rect", "Contents", "F", "C", "CA", "BS", "AP", "PodKind", "PodPoints", "PodFill", "PodOpacity", "PodWidth", "PodFontSize", "IC", "L", "LE", "InkList", "QuadPoints", "Vertices", "DA", "Name" }) |key| {
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
    try validateInput(kind, points, text.string, style);
    const ann = Annotation{ .id = value.ref.id, .kind = kind, .points = points, .rect = try readNumbers(4, try required(v, "Rect")), .text = text.string, .style = style };
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
    const resources = try required(ap.value, "Resources");
    const expected_resources = try appearanceResources(doc.allocator(), ann);
    var actual: std.ArrayList(u8) = .empty;
    var expected_data: std.ArrayList(u8) = .empty;
    try d.serialize(doc.allocator(), &actual, resources);
    try d.serialize(doc.allocator(), &expected_data, expected_resources);
    if (!eq(actual.items, expected_data.items) or s.get(ap.value, "Matrix") != null or s.get(ap.value, "Filter") != null) return error.UnsupportedAnnotation;
    return ann;
}
pub fn list(doc: *d.Document, page: usize) ![]Annotation {
    const values = try refs(doc, page);
    const result = try doc.allocator().alloc(Annotation, values.len);
    for (result, values) |*item, value| item.* = try read(doc, value);
    return result;
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
    const pad = @max(ann.style.width * 5, 2);
    r[0] -= pad;
    r[1] -= pad;
    r[2] += pad;
    r[3] += pad;
    return r;
}
fn appearanceResources(a: A, ann: Annotation) !s.Value {
    return dict(a, &.{ .{ .key = "Font", .value = try dict(a, &.{.{ .key = "F1", .value = try dict(a, &.{ .{ .key = "Type", .value = name("Font") }, .{ .key = "Subtype", .value = name("Type1") }, .{ .key = "BaseFont", .value = name("Courier") }, .{ .key = "Encoding", .value = name("WinAnsiEncoding") } }) }}) }, .{ .key = "ExtGState", .value = try dict(a, &.{.{ .key = "GS", .value = try dict(a, &.{ .{ .key = "Type", .value = name("ExtGState") }, .{ .key = "CA", .value = number(effectiveOpacity(ann)) }, .{ .key = "ca", .value = number(effectiveOpacity(ann)) } }) }}) } });
}
fn build(doc: *d.Document, ann: Annotation, ap_id: ?u32) !s.Value {
    const a = doc.allocator();
    const r = appearanceBounds(ann);
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
    try entries.appendSlice(a, &.{ .{ .key = "Type", .value = name("Annot") }, .{ .key = "Subtype", .value = name(subtype(ann.kind)) }, .{ .key = "Rect", .value = try numbers(a, &r) }, .{ .key = "Contents", .value = .{ .string = try a.dupe(u8, ann.text) } }, .{ .key = "F", .value = .{ .integer = 4 } }, .{ .key = "C", .value = try numbers(a, &ann.style.stroke) }, .{ .key = "CA", .value = number(effectiveOpacity(ann)) }, .{ .key = "BS", .value = try dict(a, &.{ .{ .key = "W", .value = number(ann.style.width) }, .{ .key = "S", .value = name("S") } }) }, .{ .key = "AP", .value = try dict(a, &.{.{ .key = "N", .value = reference(normal_id) }}) }, .{ .key = "PodKind", .value = .{ .integer = @backingInt(ann.kind) } }, .{ .key = "PodPoints", .value = points }, .{ .key = "PodFill", .value = if (ann.style.fill) |fill| try numbers(a, &fill) else .null }, .{ .key = "PodOpacity", .value = number(ann.style.opacity) }, .{ .key = "PodWidth", .value = number(ann.style.width) }, .{ .key = "PodFontSize", .value = number(ann.style.font_size) } });
    if (ann.style.fill) |fill| try entries.append(a, .{ .key = "IC", .value = try numbers(a, &fill) });
    const b = bounds(ann.points);
    switch (ann.kind) {
        .line, .arrow => {
            try entries.append(a, .{ .key = "L", .value = points });
            if (ann.kind == .arrow) try entries.append(a, .{ .key = "LE", .value = .{ .array = try a.dupe(s.Value, &.{ name("None"), name("OpenArrow") }) } });
        },
        .ink, .freehand_highlight => try entries.append(a, .{ .key = "InkList", .value = .{ .array = try a.dupe(s.Value, &.{points}) } }),
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
    try validateInput(kind, points, text, style);
    // Adding preserves unknown existing annotations. Rendering and editing them still
    // require canonical validation in list(); the native open path validates first.
    const old = try refs(doc, page);
    for (old) |value| {
        if (value != .ref or value.ref.id == 0 or value.ref.id >= doc.entries.len) return error.UnsupportedAnnotation;
        const entry = doc.entries[value.ref.id];
        if (!entry.live or entry.generation != value.ref.generation) return error.UnsupportedAnnotation;
    }
    if (old.len >= max_annotations) return error.AnnotationLimit;
    const ann = Annotation{ .id = 0, .kind = kind, .points = points, .rect = bounds(points), .text = text, .style = style };
    const value = try build(doc, ann, null);
    const id = try doc.addObject(value, null);
    const storage = &(try doc.inspect())[page].annotation_refs;
    if (storage.items.ptr != old.ptr or storage.items.len != old.len) {
        storage.* = .empty;
        try storage.appendSlice(doc.allocator(), old);
    }
    try storage.append(doc.allocator(), reference(id));
    try doc.set(try pageObject(doc, page), "Annots", .{ .array = storage.items });
    return id;
}
pub fn update(doc: *d.Document, page: usize, id: u32, kind: Kind, points: []const Point, text: []const u8, style: Style) !void {
    try validateInput(kind, points, text, style);
    for (try list(doc, page)) |old| if (old.id == id) {
        const obj = try doc.object(.{ .id = id, .generation = doc.entries[id].generation });
        const normal = try required(try required(obj.value, "AP"), "N");
        obj.value = try build(doc, .{ .id = id, .kind = kind, .points = points, .rect = bounds(points), .text = text, .style = style }, normal.ref.id);
        obj.dirty = true;
        return;
    };
    return error.AnnotationNotFound;
}
pub fn remove(doc: *d.Document, page: usize, id: u32) !void {
    _ = try list(doc, page);
    const old = try refs(doc, page);
    for (old, 0..) |v, i| if (v.ref.id == id) {
        const items = try doc.allocator().alloc(s.Value, old.len - 1);
        @memcpy(items[0..i], old[0..i]);
        @memcpy(items[i..], old[i + 1 ..]);
        try doc.set(try pageObject(doc, page), "Annots", .{ .array = items });
        return;
    };
    return error.AnnotationNotFound;
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
    switch (ann.kind) {
        .rectangle => try out.print(a, "{d} {d} {d} {d} re {s}\n", .{ x, y, w, h, if (st.fill != null) "B" else "S" }),
        .highlight => try out.print(a, "{d} {d} {d} rg {d} {d} {d} {d} re f\n", .{ st.stroke[0], st.stroke[1], st.stroke[2], x, y, w, h }),
        .ellipse, .cloud, .star, .polygon => try path(a, &out, try geometry(a, ann), true, st.fill != null),
        .line, .polyline, .ink, .freehand_highlight, .tick => try path(a, &out, try geometry(a, ann), false, false),
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
