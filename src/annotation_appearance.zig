const std = @import("std");
const d = @import("document.zig");
const s = @import("syntax.zig");
const c = @import("content.zig");
pub const Appearance = struct {
    source: union(enum) { form: c.Form, icon: @import("comment_icon.zig").Icon, shape: @import("shape_appearance.zig").Shape, free_text: @import("free_text.zig").Text },
    rect: [4]f64,
    placement: c.Matrix,
    flags: u32,

    // zoom is magnification only; page_view also contains the output pixel density.
    // The PDF-space upper-left corner stays anchored for both display flags.
    pub fn view(self: Appearance, page_view: c.Matrix, zoom: f64) !c.Matrix {
        if (!std.math.isFinite(zoom) or zoom <= 0 or zoom > 1e6) return error.InvalidTransform;
        const x = self.rect[0];
        const y = self.rect[3];
        const anchor = transform(page_view, x, y);
        var result = page_view;
        if (self.flags & 16 != 0) {
            const scale = @sqrt(page_view[0] * page_view[0] + page_view[1] * page_view[1]);
            result = .{ scale, 0, 0, -scale, 0, 0 };
        }
        if (self.flags & 8 != 0) for (result[0..4]) |*v| {
            v.* /= zoom;
        };
        result[4] = anchor[0] - x * result[0] - y * result[2];
        result[5] = anchor[1] - x * result[1] - y * result[3];
        for (result) |v| if (!std.math.isFinite(v) or @abs(v) > 1e12) return error.InvalidTransform;
        return result;
    }
};
fn transform(matrix: c.Matrix, x: f64, y: f64) [2]f64 {
    return .{ x * matrix[0] + y * matrix[2] + matrix[4], x * matrix[1] + y * matrix[3] + matrix[5] };
}
fn isStream(doc: *d.Document, value: s.Value) !bool {
    var current = value;
    for (0..64) |_| {
        if (current != .ref) return false;
        const object = try doc.object(current.ref);
        if (object.stream != null or object.changed != null) return true;
        current = object.value;
    }
    return error.ReferenceLimit;
}
pub fn load(doc: *d.Document, page_index: usize, id: u32) !Appearance {
    const pages = try doc.inspect();
    if (page_index >= pages.len) return error.PageNotFound;
    var member: ?s.Ref = null;
    for (try @import("annotations.zig").refs(doc, page_index)) |ref| {
        if (ref == .ref and ref.ref.id == id) member = ref.ref;
    }
    const annotation = (try doc.object(member orelse return error.AnnotationNotFound)).value;
    const rect = try d.rectangle(try doc.resolve(s.get(annotation, "Rect") orelse return error.InvalidAnnotationGeometry));
    const flags = try s.uint(try doc.resolve(s.get(annotation, "F") orelse .{ .integer = 0 }));
    if (flags > std.math.maxInt(u32)) return error.UnsupportedAnnotation;
    const subtype = try doc.resolve(s.get(annotation, "Subtype") orelse return error.UnsupportedAnnotation);
    if (subtype != .name) return error.UnsupportedAnnotation;
    const is_text = std.mem.eql(u8, subtype.name, "Text");
    const display_flags = @as(u32, @intCast(flags)) | (if (is_text) @as(u32, 24) else 0);
    const ap = try doc.resolve(s.get(annotation, "AP") orelse .null);
    if (ap == .null) {
        if (std.mem.eql(u8, subtype.name, "FreeText")) return .{ .source = .{ .free_text = try @import("free_text.zig").load(doc, annotation) }, .rect = rect, .placement = .{ 1, 0, 0, 1, 0, 0 }, .flags = display_flags };
        if (!is_text) return .{ .source = .{ .shape = try @import("shape_appearance.zig").load(doc, annotation) }, .rect = rect, .placement = .{ 1, 0, 0, 1, 0, 0 }, .flags = display_flags };
        return .{ .source = .{ .icon = try @import("comment_icon.zig").load(doc, annotation) }, .rect = rect, .placement = .{ 1, 0, 0, 1, 0, 0 }, .flags = display_flags };
    }
    if (ap != .dict) return error.InvalidAnnotationAppearance;
    var normal = s.get(ap, "N") orelse return error.MissingAnnotationAppearance;
    const resolved = try doc.resolve(normal);
    // A normal appearance may be a named state dictionary rather than a stream.
    if (resolved == .dict and !try isStream(doc, normal)) {
        const selected = try doc.resolve(s.get(annotation, "AS") orelse return error.MissingAppearanceState);
        if (selected != .name) return error.InvalidAppearanceState;
        normal = s.get(resolved, selected.name) orelse return error.MissingAppearanceState;
    }
    const form = try c.loadForm(doc, normal, pages[page_index].resources);
    var box: [4]f64 = .{ std.math.inf(f64), std.math.inf(f64), -std.math.inf(f64), -std.math.inf(f64) };
    for ([_][2]f64{ .{ form.bbox[0], form.bbox[1] }, .{ form.bbox[2], form.bbox[1] }, .{ form.bbox[2], form.bbox[3] }, .{ form.bbox[0], form.bbox[3] } }) |p| {
        const q = transform(form.matrix, p[0], p[1]);
        box = .{ @min(box[0], q[0]), @min(box[1], q[1]), @max(box[2], q[0]), @max(box[3], q[1]) };
    }
    // A degenerate Form clips to nothing; avoid division by zero while retaining that clip.
    const sx = if (box[2] == box[0]) 1 else (rect[2] - rect[0]) / (box[2] - box[0]);
    const sy = if (box[3] == box[1]) 1 else (rect[3] - rect[1]) / (box[3] - box[1]);
    const placement: c.Matrix = .{ sx, 0, 0, sy, rect[0] - box[0] * sx, rect[1] - box[1] * sy };
    for (placement) |v| if (!std.math.isFinite(v) or @abs(v) > 1e12) return error.InvalidTransform;
    return .{ .source = .{ .form = form }, .rect = rect, .placement = placement, .flags = display_flags };
}
fn parse(doc: *d.Document, bytes: []const u8) !s.Value {
    var parser = s.Parser{ .bytes = bytes, .allocator = doc.allocator() };
    return parser.value();
}
test "FreeText without an appearance renders from metadata without changing the PDF" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    try doc.replaceStream(try doc.object(.{ .id = 5, .generation = 0 }), "");
    const id = try doc.addObject(try parse(&doc, "<< /Type /Annot /Subtype /FreeText /Rect [20 20 180 180] /DA (/Helv 14 Tf 0 g) /Contents () /C [1 0 0] /CA .5 /BS << /W 0 >> >>"), null);
    try doc.set(try doc.object(.{ .id = 3, .generation = 0 }), "Annots", try parse(&doc, "[6 0 R]"));
    const before = try doc.save(a);
    defer a.free(before);
    const marks = try @import("annotations.zig").list(&doc, 0);
    try std.testing.expect(marks[0].imported_free_text);
    const bitmap = try @import("render.zig").renderAnnotationAppearanceWithFonts(a, &doc, 0, id, &.{}, 160);
    defer a.free(bitmap.pixels);
    try std.testing.expectEqualSlices(u8, &.{ 255, 128, 128, 255 }, bitmap.pixels[(80 * 160 + 80) * 4 ..][0..4]);
    const after = try doc.save(a);
    defer a.free(after);
    try std.testing.expectEqualSlices(u8, before, after);
}
test "missing square and circle appearances render from metadata without PDF mutations" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    try doc.replaceStream(try doc.object(.{ .id = 5, .generation = 0 }), "");
    const id = try doc.addObject(try parse(&doc, "<< /Type /Annot /Subtype /Square /Rect [20 20 180 180] /RD [5 10 15 20] /C [0 0 0] /IC [1 0 0] /CA .5 /BS << /W 2 >> >>"), null);
    try doc.set(try doc.object(.{ .id = 3, .generation = 0 }), "Annots", try parse(&doc, "[6 0 R]"));
    const before = try doc.save(a);
    defer a.free(before);
    const marks = try @import("annotations.zig").list(&doc, 0);
    try std.testing.expect(marks[0].imported_shape);
    for ([_][]const u8{ "Square", "Circle" }) |kind| {
        try doc.set(try doc.object(.{ .id = id, .generation = 0 }), "Subtype", .{ .name = kind });
        const bitmap = try @import("render.zig").renderAnnotationAppearanceWithFonts(a, &doc, 0, id, &.{}, 160);
        defer a.free(bitmap.pixels);
        try std.testing.expectEqualSlices(u8, &.{ 255, 128, 128, 255 }, bitmap.pixels[(80 * 160 + 80) * 4 ..][0..4]);
        try std.testing.expectEqualSlices(u8, &.{ 255, 255, 255, 255 }, bitmap.pixels[(5 * 160 + 80) * 4 ..][0..4]);
        if (std.mem.eql(u8, kind, "Square")) {
            // Fill/stroke overlap must receive CA once, not accumulate two layers.
            try std.testing.expectEqualSlices(u8, &.{ 128, 128, 128, 255 }, bitmap.pixels[(80 * 160 + 5) * 4 ..][0..4]);
        }
    }
    try doc.set(try doc.object(.{ .id = id, .generation = 0 }), "Subtype", .{ .name = "Square" });
    const after = try doc.save(a);
    defer a.free(after);
    try std.testing.expectEqualSlices(u8, before, after);
}
test "fallback borders retain PDF defaults precedence transparency and strict geometry" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    const shape = @import("shape_appearance.zig");
    const dashed = try shape.load(&doc, try parse(&doc, "<< /Subtype /Square /Rect [0 0 100 80] /Border [10 10 40] /BS << /W 2 /S /D >> /C [.2] /IC [] >>"));
    try std.testing.expectEqualSlices(f64, &.{ 1, 1, 99, 79 }, &dashed.box);
    try std.testing.expectEqualSlices(f64, &.{ 0.2, 0.2, 0.2 }, &dashed.stroke.?);
    try std.testing.expect(dashed.fill == null);
    try std.testing.expectEqual(@as(usize, 1), dashed.pattern.count);
    try std.testing.expectEqual(@as(f64, 3), dashed.pattern.values[0]);
    const clear = try shape.load(&doc, try parse(&doc, "<< /Subtype /Circle /Rect [0 0 100 80] /BS << /W 0 >> /IC [1 0 0] >>"));
    try std.testing.expect(clear.stroke == null);
    try std.testing.expectEqual(@as(f64, 0), clear.width);
    try std.testing.expectEqualSlices(f64, &.{ 0, 0, 100, 80 }, &clear.box);
    const thick = try shape.load(&doc, try parse(&doc, "<< /Subtype /Square /Rect [0 0 100 80] /RD [0 3 0 3] /BS << /W 8 >> >>"));
    try std.testing.expectEqualSlices(f64, &.{ 4, 4, 96, 76 }, &thick.box);
    try std.testing.expectError(error.InvalidAnnotationGeometry, shape.load(&doc, try parse(&doc, "<< /Subtype /Square /Rect [0 0 100 80] /RD [50 0 50 0] >>")));
    try std.testing.expectError(error.UnsupportedAnnotationAppearance, shape.load(&doc, try parse(&doc, "<< /Subtype /Square /Rect [0 0 100 80] /BE << /S /C >> >>")));
}
test "fallback border overflow clips to the annotation rectangle" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    try doc.replaceStream(try doc.object(.{ .id = 5, .generation = 0 }), "");
    _ = try doc.addObject(try parse(&doc, "<< /Type /Annot /Subtype /Square /Rect [20 20 180 180] /RD [0 3 0 3] /C [0] /BS << /W 8 >> >>"), null);
    try doc.set(try doc.object(.{ .id = 3, .generation = 0 }), "Annots", try parse(&doc, "[6 0 R]"));
    const bitmap = try @import("render.zig").renderWithFonts(a, &doc, 0, &.{}, 612);
    defer a.free(bitmap.pixels);
    try std.testing.expectEqualSlices(u8, &.{ 255, 255, 255, 255 }, bitmap.pixels[(692 * 612 + 17) * 4 ..][0..4]);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 255 }, bitmap.pixels[(692 * 612 + 21) * 4 ..][0..4]);
}
test "appearance Matrix and BBox map to annotation Rect independently of page resources" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "test");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    _ = try doc.addObject(try parse(&doc, "<< /Subtype /Form /BBox [10 20 50 60] /Matrix [0 2 -3 0 200 100] /Resources << >> >>"), "1 0 0 rg 10 20 40 40 re f");
    _ = try doc.addObject(try parse(&doc, "<< /Subtype /Text /Rect [100 200 340 360] /AP << /N 6 0 R >> >>"), null);
    try doc.set(try doc.object(.{ .id = 3, .generation = 0 }), "Annots", try parse(&doc, "[7 0 R]"));
    const appearance = try load(&doc, 0, 7);
    try std.testing.expectEqual(@as(u32, 6), appearance.source.form.id);
    // Transformed BBox is [20,120,140,200], then scaled by two and translated.
    try std.testing.expectEqualSlices(f64, &.{ 2, 0, 0, 2, 60, -40 }, &appearance.placement);
    try doc.set(try doc.object(.{ .id = 3, .generation = 0 }), "Annots", try parse(&doc, "[7 1 R]"));
    try std.testing.expectError(error.MissingReference, load(&doc, 0, 7));
}
test "normal appearance preview renders its transformed clipped stream with fresh state" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "test");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    _ = try doc.addObject(try parse(&doc, "<< /Subtype /Form /BBox [10 20 50 60] /Matrix [0 2 -3 0 200 100] /Resources << >> >>"), "1 0 0 rg 10 20 40 40 re f 0 0 1 rg 10 20 20 40 re f");
    _ = try doc.addObject(try parse(&doc, "<< /Subtype /Text /Rect [100 200 340 360] /CA .1 /AP << /N 6 0 R >> >>"), null);
    try doc.set(try doc.object(.{ .id = 3, .generation = 0 }), "Annots", try parse(&doc, "[7 0 R]"));
    const bitmap = try @import("render.zig").renderAnnotationAppearanceWithFonts(a, &doc, 0, 7, &.{}, 240);
    defer a.free(bitmap.pixels);
    try std.testing.expectEqual(@as(u32, 160), bitmap.height);
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, bitmap.pixels[(20 * 240 + 120) * 4 ..][0..4]);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 255, 255 }, bitmap.pixels[(140 * 240 + 120) * 4 ..][0..4]);
}
test "named normal appearance state may itself be named Subtype" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "test");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    _ = try doc.addObject(try parse(&doc, "<< /Subtype /Form /BBox [0 0 10 10] >>"), "0 0 10 10 re f");
    _ = try doc.addObject(try parse(&doc, "<< /Subtype /Widget /Rect [100 200 110 210] /AS /Subtype /AP << /N << /Subtype 6 0 R >> >> >>"), null);
    try doc.set(try doc.object(.{ .id = 3, .generation = 0 }), "Annots", try parse(&doc, "[7 0 R]"));
    try std.testing.expectEqual(@as(u32, 6), (try load(&doc, 0, 7)).source.form.id);
}
test "sticky-note display transform keeps its PDF upper-left anchor at every rotation and zoom" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "test");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    _ = try doc.addObject(try parse(&doc, "<< /Subtype /Form /BBox [0 0 24 24] >>"), "");
    _ = try doc.addObject(try parse(&doc, "<< /Subtype /Text /Rect [100 200 124 224] /AP << /N 6 0 R >> >>"), null);
    try doc.set(try doc.object(.{ .id = 3, .generation = 0 }), "Annots", try parse(&doc, "[7 0 R]"));
    var item = try load(&doc, 0, 7);
    try std.testing.expectEqual(@as(u32, 24), item.flags);
    for ([_]f64{ 0.5, 1, 2, 4 }) |zoom| {
        for ([_]f64{ 1, 2 }) |density| {
            const scale = zoom * density;
            for ([_]c.Matrix{
                .{ scale, 0, 0, -scale, 0, 792 * scale },
                .{ 0, scale, scale, 0, 0, 0 },
                .{ -scale, 0, 0, scale, 612 * scale, 0 },
                .{ 0, -scale, -scale, 0, 792 * scale, 612 * scale },
            }) |page_view| {
                const view = try item.view(page_view, zoom);
                const before = transform(page_view, 100, 224);
                const after = transform(view, 100, 224);
                try std.testing.expectApproxEqAbs(before[0], after[0], 0.000001);
                try std.testing.expectApproxEqAbs(before[1], after[1], 0.000001);
                try std.testing.expectEqualSlices(f64, &.{ density, 0, 0, -density }, view[0..4]);
                item.flags = 8;
                const rotating = try item.view(page_view, zoom);
                for (rotating[0..4], page_view[0..4]) |actual, expected| try std.testing.expectApproxEqAbs(expected / zoom, actual, 0.000001);
                item.flags = 24;
            }
        }
    }
    try std.testing.expectError(error.InvalidTransform, item.view(.{ 1, 0, 0, -1, 0, 792 }, 0));
}
test "appearance state selection and malformed geometry fail explicitly" {
    const a = std.testing.allocator;
    const cases = [_]struct { normal: []const u8, state: []const u8, form: []const u8, err: anyerror }{
        .{ .normal = "null", .state = "", .form = "<< /Subtype /Form /BBox [0 0 10 10] >>", .err = error.InvalidXObject },
        .{ .normal = "<< /On 6 0 R >>", .state = "", .form = "<< /Subtype /Form /BBox [0 0 10 10] >>", .err = error.MissingAppearanceState },
        .{ .normal = "<< /On 6 0 R >>", .state = "/AS /Off", .form = "<< /Subtype /Form /BBox [0 0 10 10] >>", .err = error.MissingAppearanceState },
        .{ .normal = "<< /On 6 0 R >>", .state = "/AS 7", .form = "<< /Subtype /Form /BBox [0 0 10 10] >>", .err = error.InvalidAppearanceState },
        .{ .normal = "6 0 R", .state = "", .form = "<< /Subtype /Form /BBox [0 0 10 10] /Group << /S /Transparency >> >>", .err = error.UnsupportedForm },
    };
    for (cases) |case| {
        const bytes = try @import("pod.zig").create(a, "test");
        defer a.free(bytes);
        var doc = try d.Document.open(a, bytes);
        defer doc.deinit();
        _ = try doc.addObject(try parse(&doc, case.form), "");
        const dictionary = try std.fmt.allocPrint(doc.allocator(), "<< /Subtype /Text /Rect [100 200 124 224] /AP << /N {s} >> {s} >>", .{ case.normal, case.state });
        _ = try doc.addObject(try parse(&doc, dictionary), null);
        try doc.set(try doc.object(.{ .id = 3, .generation = 0 }), "Annots", try parse(&doc, "[7 0 R]"));
        try std.testing.expectError(case.err, load(&doc, 0, 7));
        try std.testing.expectError(error.AnnotationNotFound, load(&doc, 0, 6));
        try std.testing.expectError(error.PageNotFound, load(&doc, 1, 7));
    }
}

test "degenerate appearance boxes render an empty preview" {
    const a = std.testing.allocator;
    for ([_][]const u8{
        "<< /Subtype /Form /BBox [0 0 0 10] >>",
        "<< /Subtype /Form /BBox [0 0 10 10] /Matrix [0 0 0 1 0 0] >>",
    }) |form| {
        const bytes = try @import("pod.zig").create(a, "test");
        defer a.free(bytes);
        var doc = try d.Document.open(a, bytes);
        defer doc.deinit();
        _ = try doc.addObject(try parse(&doc, form), "1 0 0 rg -100 -100 300 300 re f");
        _ = try doc.addObject(try parse(&doc, "<< /Subtype /Text /Rect [100 200 124 224] /AP << /N 6 0 R >> >>"), null);
        try doc.set(try doc.object(.{ .id = 3, .generation = 0 }), "Annots", try parse(&doc, "[7 0 R]"));
        const bitmap = try @import("render.zig").renderAnnotationAppearanceWithFonts(a, &doc, 0, 7, &.{}, 24);
        defer a.free(bitmap.pixels);
        for (bitmap.pixels) |byte| try std.testing.expectEqual(@as(u8, 255), byte);
    }
}

test "page view composites fixed upright comment appearances over page content at zoom and rotation" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    const page = try doc.object(.{ .id = 3, .generation = 0 });
    try doc.set(page, "MediaBox", try parse(&doc, "[0 0 100 100]"));
    (try doc.object(.{ .id = 5, .generation = 0 })).changed = "0 1 1 rg 0 0 100 100 re f 0 0 1 1 re W n";
    _ = try doc.addObject(try parse(&doc, "<< /Subtype /Form /BBox [0 0 20 16] /Resources << /ExtGState << /Half << /ca .5 >> /Full << /ca 1 >> >> >> >>"), "/Half gs 1 0 0 rg 0 0 10 16 re f /Full gs 0 0 1 rg 10 8 10 8 re f");
    _ = try doc.addObject(try parse(&doc, "<< /Subtype /Text /Rect [40 40 60 56] /CA .1 /AP << /N 6 0 R >> >>"), null);
    try doc.set(page, "Annots", try parse(&doc, "[7 0 R]"));
    const renderer = @import("render.zig");
    for ([_]f64{ 0.5, 1, 2 }) |zoom| for ([_]u32{ 1, 2 }) |density| {
        for ([_]i32{ 0, 90, 180, 270 }, [_][2]f64{ .{ 40, 44 }, .{ 56, 40 }, .{ 60, 56 }, .{ 44, 60 } }) |rotation, anchor| {
            const scale = zoom * @as(f64, @floatFromInt(density));
            const width: u32 = @intFromFloat(100 * scale);
            const bitmap = try renderer.renderPageViewWithFonts(a, &doc, 0, &.{}, width, .{ .zoom = zoom, .rotation = rotation });
            defer a.free(bitmap.pixels);
            const left: usize = @intFromFloat(anchor[0] * scale);
            const top: usize = @intFromFloat(anchor[1] * scale);
            for (0..bitmap.height) |y| for (0..bitmap.width) |x| {
                var expected: [4]u8 = .{ 0, 255, 255, 255 };
                if (x >= left and x < left + 10 * density and y >= top and y < top + 16 * density) expected = .{ 128, 128, 128, 255 };
                if (x >= left + 10 * density and x < left + 20 * density and y >= top and y < top + 8 * density) expected = .{ 0, 0, 255, 255 };
                try std.testing.expectEqualSlices(u8, &expected, bitmap.pixels[(y * width + x) * 4 ..][0..4]);
            };
        }
    };
    try std.testing.expectError(error.InvalidTransform, renderer.renderPageViewWithFonts(a, &doc, 0, &.{}, 100, .{ .zoom = 0 }));
    try std.testing.expectError(error.InvalidRotation, renderer.renderPageViewWithFonts(a, &doc, 0, &.{}, 100, .{ .rotation = 45 }));
    // Ordinary raster APIs mean 100% magnification at the requested output resolution.
    const standard = try renderer.renderWithFonts(a, &doc, 0, &.{}, 100);
    defer a.free(standard.pixels);
    const explicit = try renderer.renderPageViewWithFonts(a, &doc, 0, &.{}, 100, .{});
    defer a.free(explicit.pixels);
    try std.testing.expectEqualSlices(u8, standard.pixels, explicit.pixels);
}

test "missing comment appearances use distinct standard icons without changing the PDF" {
    const a = std.testing.allocator;
    var hashes: [7]u64 = undefined;
    for ([_][]const u8{ "Note", "Comment", "Key", "Help", "NewParagraph", "Paragraph", "Insert", "Unknown", "" }, 0..) |name, i| {
        const bytes = try @import("pod.zig").create(a, "");
        defer a.free(bytes);
        var doc = try d.Document.open(a, bytes);
        defer doc.deinit();
        const extra = if (name.len == 0) "" else try std.fmt.allocPrint(doc.allocator(), "/Name /{s}", .{name});
        const value = try std.fmt.allocPrint(doc.allocator(), "<< /Subtype /Text /Rect [100 200 124 224] /C [0.2 0.8 0.4] /CA .5 {s} >>", .{extra});
        _ = try doc.addObject(try parse(&doc, value), null);
        try doc.set(try doc.object(.{ .id = 3, .generation = 0 }), "Annots", try parse(&doc, "[6 0 R]"));
        const before = try doc.save(a);
        defer a.free(before);
        const bitmap = try @import("render.zig").renderAnnotationAppearanceWithFonts(a, &doc, 0, 6, &.{}, 48);
        defer a.free(bitmap.pixels);
        const hash = std.hash.Wyhash.hash(0, bitmap.pixels);
        if (i < 7) {
            for (hashes[0..i]) |other| try std.testing.expect(hash != other);
            hashes[i] = hash;
        } else try std.testing.expectEqual(hashes[0], hash);
        var colored: usize = 0;
        for (bitmap.pixels) |channel| {
            // /CA applies to the icon as a whole, including overlapping dark details.
            try std.testing.expect(channel >= 127);
            if (channel < 250) colored += 1;
        }
        try std.testing.expect(colored > 50);
        const after = try doc.save(a);
        defer a.free(after);
        try std.testing.expectEqualSlices(u8, before, after);
        try std.testing.expect(s.get((try doc.object(.{ .id = 6, .generation = 0 })).value, "AP") == null);
    }
}

test "fallback icons respect grayscale and zero opacity without masking malformed appearances" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    _ = try doc.addObject(try parse(&doc, "<< /Subtype /Text /Rect [0 0 24 24] /AP null /Name /Help /C [.5] /CA 0 >>"), null);
    const annotation = try doc.object(.{ .id = 6, .generation = 0 });
    try doc.set(try doc.object(.{ .id = 3, .generation = 0 }), "Annots", try parse(&doc, "[6 0 R]"));
    try std.testing.expectEqualSlices(f64, &.{ 0.5, 0.5, 0.5 }, &(try load(&doc, 0, 6)).source.icon.color);
    const bitmap = try @import("render.zig").renderAnnotationAppearanceWithFonts(a, &doc, 0, 6, &.{}, 24);
    defer a.free(bitmap.pixels);
    for (bitmap.pixels) |byte| try std.testing.expectEqual(@as(u8, 255), byte);
    try doc.set(annotation, "AP", try parse(&doc, "<< >>"));
    try std.testing.expectError(error.MissingAnnotationAppearance, load(&doc, 0, 6));
    try doc.set(annotation, "AP", .{ .integer = 7 });
    try std.testing.expectError(error.InvalidAnnotationAppearance, load(&doc, 0, 6));
    try doc.set(annotation, "AP", .null);
    try doc.set(annotation, "C", try parse(&doc, "[2 0 0]"));
    try std.testing.expectError(error.InvalidAnnotationStyle, load(&doc, 0, 6));
    try doc.set(annotation, "C", try parse(&doc, "[1 0 0]"));
    try doc.set(annotation, "Subtype", .{ .name = "Widget" });
    try std.testing.expectError(error.MissingAnnotationAppearance, load(&doc, 0, 6));
    try doc.set(annotation, "Subtype", .{ .name = "Text" });
    _ = try doc.addObject(try parse(&doc, "<< /Subtype /Form /BBox [0 0 24 24] /Resources << >> >>"), "1 0 0 rg 0 0 24 24 re f");
    try doc.set(annotation, "AP", try parse(&doc, "<< /N 7 0 R >>"));
    const explicit = try @import("render.zig").renderAnnotationAppearanceWithFonts(a, &doc, 0, 6, &.{}, 24);
    defer a.free(explicit.pixels);
    // Existing AP overrides the Help icon, C, and annotation-level zero opacity.
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, explicit.pixels[(12 * 24 + 12) * 4 ..][0..4]);
}

test "missing path appearances use vertices leaders and border dashes" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    const shape = @import("shape_appearance.zig");
    const line = try shape.load(&doc, try parse(&doc, "<< /Subtype /Line /Rect [0 0 250 250] /L [50 100 200 100] /LL -20 /LLE 6 /LLO 4 /LE [/ClosedArrow /Circle] /C [0] /IC [1 0 0] /BS << /W 2 /S /D /D [7 3] >> >>"));
    const program = try line.program(a);
    defer a.free(program);
    try std.testing.expect(std.mem.indexOf(u8, program, "50 96 m\n50 70 l") != null);
    try std.testing.expect(std.mem.indexOf(u8, program, "50 76 m\n200 76 l") != null);
    try std.testing.expect(std.mem.indexOf(u8, program, "[ 7 3 ] 0 d") != null);
    for ([_][]const u8{
        "<< /Subtype /PolyLine /Rect [0 0 250 250] /Vertices [50 50 80 140 200 100] /LE [/Square /Diamond] /C [0] >>",
        "<< /Subtype /Polygon /Rect [0 0 250 250] /Vertices [50 50 80 140 200 100] /C [0] /IC [1 0 0] >>",
    }) |input| {
        const path = try shape.load(&doc, try parse(&doc, input));
        const output = try path.program(a);
        defer a.free(output);
        try std.testing.expect(std.mem.indexOf(u8, output, "50 50 m\n80 140 l\n200 100 l") != null);
    }
}

test "captioned fallback lines lay out text and split the inline stroke" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    const shape = try @import("shape_appearance.zig").load(&doc, try parse(&doc, "<< /Subtype /Line /Rect [0 0 300 250] /L [40 100 260 100] /Cap true /Contents (Lesson 1) /C [0] >>"));
    const program = try shape.program(a);
    defer a.free(program);
    // The serializer writes hexadecimal PDF strings; check their decoded value.
    const text_start = std.mem.indexOfScalar(u8, program, '<') orelse return error.MissingCaption;
    var parser = s.Parser{ .bytes = program[text_start..], .allocator = doc.allocator() };
    try std.testing.expectEqualStrings("Lesson 1", (try parser.value()).string);
    try std.testing.expect(parser.keyword("Tj"));
    var drawing = try shape.drawing(a);
    defer drawing.deinit(a);
    try std.testing.expectEqual(@as(usize, 4), drawing.layers.items[0].end);
}
