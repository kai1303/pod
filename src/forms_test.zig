const std = @import("std");
const pod = @import("pod.zig");
const s = @import("syntax.zig");
const render = @import("render.zig");
const a = std.testing.allocator;
const Fixture = struct {
    bytes: []u8,
    doc: pod.Document,
    fn init(content: []const u8, dictionary: []const u8, body: []const u8) !Fixture {
        const bytes = try pod.create(a, "test");
        errdefer a.free(bytes);
        var doc = try pod.Document.open(a, bytes);
        errdefer doc.deinit();
        _ = try doc.addObject(try parse(&doc, dictionary), body);
        try doc.set(try doc.object(.{ .id = 3, .generation = 0 }), "Resources", try parse(&doc, "<< /Font << /F1 4 0 R >> /XObject << /Fm 6 0 R >> >>"));
        try doc.replaceStream(try doc.object(.{ .id = 5, .generation = 0 }), content);
        return .{ .bytes = bytes, .doc = doc };
    }
    fn deinit(self: *Fixture) void {
        self.doc.deinit();
        a.free(self.bytes);
    }
};
fn parse(doc: *pod.Document, bytes: []const u8) !s.Value {
    var parser = s.Parser{ .bytes = bytes, .allocator = doc.allocator() };
    return parser.value();
}
const basic = "<< /Type /XObject /Subtype /Form /BBox [0 0 100 100] /Matrix [2 0 0 2 50 100] >>";
fn pixel(bitmap: render.Bitmap, x: usize, y: usize) []const u8 {
    const offset = ((bitmap.height - 1 - y) * bitmap.width + x) * 4;
    return bitmap.pixels[offset..][0..4];
}
test "Form BBox clips transformed artwork and restores invoking state" {
    var f = try Fixture.init("0 0 1 rg /Fm Do 300 100 50 50 re f", basic, "1 0 0 rg -100 -100 300 300 re f");
    defer f.deinit();
    const bitmap = try render.render(a, &f.doc, 0, &.{}, 612);
    defer a.free(bitmap.pixels);
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, pixel(bitmap, 100, 200));
    try std.testing.expectEqualSlices(u8, &.{ 255, 255, 255, 255 }, pixel(bitmap, 25, 200));
    try std.testing.expectEqualSlices(u8, &.{ 255, 255, 255, 255 }, pixel(bitmap, 260, 200));
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 255, 255 }, pixel(bitmap, 325, 125));
}
test "nested Forms retain source spans and safe text replacement" {
    var f = try Fixture.init("/Fm Do", "<< /Subtype /Form /BBox [0 0 300 300] /Matrix [2 0 0 2 50 100] /Resources << /XObject << /Child 7 0 R >> >> >>", "q 1 0 0 1 10 20 cm /Child Do Q");
    defer f.deinit();
    _ = try f.doc.addObject(try parse(&f.doc, "<< /Subtype /Form /BBox [0 0 100 100] /Matrix [1 0 0 1 3 4] /Resources << /Font << /Local 4 0 R >> >> >>"), "BT /Local 10 Tf 1 0 0 1 5 6 Tm (Hello) Tj (World) Tj ET");
    const pages = try f.doc.inspect();
    try std.testing.expectEqual(@as(usize, 2), pages[0].runs.len);
    const first = pages[0].runs[0];
    const next = pages[0].runs[1];
    try std.testing.expectEqual(@as(u32, 7), first.object_id);
    try std.testing.expectApproxEqAbs(@as(f64, 86), first.x, 0.000001);
    try std.testing.expectApproxEqAbs(@as(f64, 160), first.y, 0.000001);
    try f.doc.replace(1, 0, "Hi");
    const saved = try f.doc.save(a);
    defer a.free(saved);
    var copy = try pod.Document.open(a, saved);
    defer copy.deinit();
    const edited = (try copy.inspect())[0].runs;
    try std.testing.expectEqualStrings("Hi", edited[0].text);
    try std.testing.expectApproxEqAbs(next.x, edited[1].x, 0.000001);
    try std.testing.expectApproxEqAbs(next.y, edited[1].y, 0.000001);
}
test "reused Form text is protected against editing every instance" {
    var f = try Fixture.init("/Fm Do /Fm Do", basic, "BT /F1 10 Tf (Hello) Tj ET");
    defer f.deinit();
    try std.testing.expectEqual(@as(usize, 2), (try f.doc.inspect())[0].runs.len);
    try std.testing.expectError(error.UnsupportedSharedContent, f.doc.replace(1, 0, "Hi"));
    try std.testing.expectEqualStrings("Hello", (try f.doc.inspect())[0].runs[1].text);
}
test "Form resource scope is local and absent resources inherit" {
    var f = try Fixture.init("/Fm Do BT /F1 10 Tf (AA) Tj ET", "<< /Subtype /Form /BBox [0 0 100 100] /Resources << /Font << /F1 7 0 R >> >> >>", "BT /F1 10 Tf (AA) Tj ET");
    defer f.deinit();
    _ = try f.doc.addObject(try parse(&f.doc, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"), null);
    const runs = (try f.doc.inspect())[0].runs;
    try std.testing.expectApproxEqAbs(@as(f64, 13.34), runs[0].advance, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f64, 12), runs[1].advance, 0.00001);
    try f.doc.set(try f.doc.object(.{ .id = 6, .generation = 0 }), "Resources", try parse(&f.doc, "<< /Font << >> >>"));
    f.doc.pages = null;
    try std.testing.expectError(error.MissingFont, f.doc.inspect());
}
test "Form rejects malformed dictionaries recursive content and unbalanced state" {
    const cases = [_]struct { dict: []const u8, body: []const u8, err: anyerror }{
        .{ .dict = "<< /Subtype /Image >>", .body = "", .err = error.InvalidImage },
        .{ .dict = "<< /Subtype /Form >>", .body = "", .err = error.InvalidForm },
        .{ .dict = "<< /Subtype /Form /BBox [0 0 1] >>", .body = "", .err = error.InvalidForm },
        .{ .dict = "<< /Subtype /Form /BBox [0 0 100 100] /Matrix [1 0] >>", .body = "", .err = error.InvalidForm },
        .{ .dict = "<< /Subtype /Form /BBox [0 0 100 100] /Resources 42 >>", .body = "", .err = error.InvalidForm },
        .{ .dict = "<< /Subtype /Form /BBox [0 0 100 100] /Type /Page >>", .body = "", .err = error.InvalidForm },
        .{ .dict = "<< /Subtype /Form /BBox [0 0 100 100] /FormType 2 >>", .body = "", .err = error.InvalidForm },
        .{ .dict = "<< /Subtype /Form /BBox [0 0 100 100] /Group << /S /Transparency >> >>", .body = "", .err = error.UnsupportedForm },
        .{ .dict = "<< /Subtype /Form /BBox [0 0 100 100] /OC << >> >>", .body = "", .err = error.UnsupportedForm },
        .{ .dict = basic, .body = "/Fm Do", .err = error.CyclicForm },
        .{ .dict = basic, .body = "Q", .err = error.GraphicsStackUnderflow },
        .{ .dict = basic, .body = "q", .err = error.UnclosedGraphicsState },
        .{ .dict = basic, .body = "BT", .err = error.UnclosedTextObject },
        .{ .dict = basic, .body = "BT /Fm Do ET", .err = error.InvalidTextObject },
        .{ .dict = basic, .body = "0 0 m", .err = error.UnpaintedPath },
        .{ .dict = basic, .body = "0 0 1 1 re W", .err = error.UnpaintedPath },
    };
    for (cases) |case| {
        var f = try Fixture.init("q /Fm Do Q", case.dict, case.body);
        defer f.deinit();
        try std.testing.expectError(case.err, render.validate(&f.doc));
    }
}
test "Form nesting and repeated expansion have bounded work" {
    for ([_]bool{ false, true }) |fanout| {
        var f = try Fixture.init("/Fm Do", basic, "/Next Do");
        defer f.deinit();
        try f.doc.set(try f.doc.object(.{ .id = 6, .generation = 0 }), "Matrix", try parse(&f.doc, "[1 0 0 1 0 0]"));
        for (0..65) |i| {
            const id: u32 = @intCast(6 + i);
            if (i > 0) _ = try f.doc.addObject(try parse(&f.doc, "<< /Subtype /Form /BBox [0 0 100 100] >>"), if (i == 64) "" else if (fanout) "/Next Do /Next Do" else "/Next Do");
            const resource = try std.fmt.allocPrint(f.doc.allocator(), "<< /XObject << /Next {d} 0 R >> >>", .{id + 1});
            try f.doc.set(try f.doc.object(.{ .id = id, .generation = 0 }), "Resources", try parse(&f.doc, resource));
        }
        // Shorten the branching case to reach the invocation limit before the depth limit.
        if (fanout) try f.doc.replaceStream(try f.doc.object(.{ .id = 22, .generation = 0 }), "");
        try std.testing.expectError(if (fanout) error.ContentWorkLimit else error.FormDepthLimit, f.doc.inspect());
    }
}
test "cross-page Form reuse and indexed views cannot bypass shared edit protection" {
    var f = try Fixture.init("/Fm Do", basic, "BT /F1 10 Tf (Hello) Tj ET");
    defer f.deinit();
    _ = try f.doc.addObject(try parse(&f.doc, "<< /Type /Page /Parent 2 0 R /Resources << /Font << /F1 4 0 R >> /XObject << /Fm 6 0 R >> >> /Contents 8 0 R >>"), null);
    _ = try f.doc.addObject(try parse(&f.doc, "<< >>"), "/Fm Do");
    const tree = try f.doc.object(.{ .id = 2, .generation = 0 });
    try f.doc.set(tree, "Kids", try parse(&f.doc, "[3 0 R 7 0 R]"));
    try f.doc.set(tree, "Count", .{ .integer = 2 });
    try std.testing.expectError(error.UnsupportedSharedContent, f.doc.replace(1, 0, "Hi"));
    f.doc.page_objects = .empty;
    try std.testing.expectError(error.ReadOnlyPageView, f.doc.replace(1, 0, "Hi"));
    f.doc.page_objects = null;
}
test "Form used as an annotation appearance is not edited through page text" {
    var f = try Fixture.init("/Fm Do", basic, "BT /F1 10 Tf (Hello) Tj ET");
    defer f.deinit();
    _ = try f.doc.addObject(try parse(&f.doc, "<< /Subtype /Stamp /Rect [0 0 100 100] /AP << /N 6 0 R >> >>"), null);
    try f.doc.set(try f.doc.object(.{ .id = 3, .generation = 0 }), "Annots", try parse(&f.doc, "[7 0 R]"));
    try std.testing.expectError(error.UnsupportedSharedContent, f.doc.replace(1, 0, "Hi"));
}
test "nonuniform Form transforms scale stroke outlines in user space" {
    var f = try Fixture.init("/Fm Do", "<< /Subtype /Form /BBox [0 0 250 250] /Matrix [2 0 0 1 50 100] >>", "20 w 1 0 0 RG 20 50 m 100 50 l S 0 0 1 RG 150 20 m 150 100 l S");
    defer f.deinit();
    const bitmap = try render.render(a, &f.doc, 0, &.{}, 612);
    defer a.free(bitmap.pixels);
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, pixel(bitmap, 150, 155));
    try std.testing.expectEqualSlices(u8, &.{ 255, 255, 255, 255 }, pixel(bitmap, 150, 165));
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 255, 255 }, pixel(bitmap, 365, 150));
    try std.testing.expectEqualSlices(u8, &.{ 255, 255, 255, 255 }, pixel(bitmap, 375, 150));
}
test "bevel joins and miter-limit fallback fill the outer corner" {
    for ([_][]const u8{ "2 j", "0 j 1 M" }) |join| {
        const body = try std.fmt.allocPrint(a, "20 w 1 0 0 RG {s} 50 100 m 100 100 l 100 50 l S", .{join});
        defer a.free(body);
        var f = try Fixture.init("/Fm Do", "<< /Subtype /Form /BBox [0 0 200 200] >>", body);
        defer f.deinit();
        const bitmap = try render.render(a, &f.doc, 0, &.{}, 612);
        defer a.free(bitmap.pixels);
        try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, pixel(bitmap, 103, 103));
        try std.testing.expectEqualSlices(u8, &.{ 255, 255, 255, 255 }, pixel(bitmap, 108, 108));
    }
}
test "hairlines remain one device pixel under nonuniform Form scaling" {
    for ([_]u32{ 612, 1224 }) |width| {
        var f = try Fixture.init("/Fm Do", "<< /Subtype /Form /BBox [0 0 250 250] /Matrix [2 0 0 1 50 100] >>", "0 w 20 50 m 100 50 l S");
        defer f.deinit();
        const bitmap = try render.render(a, &f.doc, 0, &.{}, width);
        defer a.free(bitmap.pixels);
        var area: f64 = 0;
        for (0..bitmap.pixels.len / 4) |i| area += @as(f64, @floatFromInt(255 - bitmap.pixels[i * 4])) / 255;
        const length: f64 = 160 * @as(f64, @floatFromInt(width)) / 612;
        try std.testing.expectApproxEqAbs(length, area, length * 0.01);
    }
}
