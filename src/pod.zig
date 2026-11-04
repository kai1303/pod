pub const syntax = @import("syntax.zig");
pub const Document = @import("document.zig").Document;
test {
    _ = syntax;
    _ = @import("document.zig");
}
const std = @import("std");
pub fn create(a: std.mem.Allocator, text: []const u8) ![]u8 {
    if (text.len > 10000) return error.TextLimit;
    for (text) |c| if (c < 32 or c > 126) return error.UnsupportedEncoding;
    var content: std.ArrayList(u8) = .empty;
    defer content.deinit(a);
    try content.appendSlice(a, "BT /F1 12 Tf 1 0 0 1 72 720 Tm ");
    try @import("document.zig").serialize(a, &content, .{ .string = text });
    try content.appendSlice(a, " Tj ( - Pod) Tj ET\n");
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(a);
    try out.appendSlice(a, "%PDF-1.7\n%\xe2\xe3\xcf\xd3\n");
    var offsets: [6]usize = @splat(0);
    const bodies = [_][]const u8{
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> >>",
        "<< /Type /Page /Parent 2 0 R /Contents 5 0 R >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Courier /Encoding /WinAnsiEncoding >>",
    };
    for (bodies, 1..) |body, i| {
        offsets[i] = out.items.len;
        try out.print(a, "{d} 0 obj\n{s}\nendobj\n", .{ i, body });
    }
    offsets[5] = out.items.len;
    try out.print(a, "5 0 obj\n<< /Length {d} >>\nstream\n{s}\nendstream\nendobj\n", .{ content.items.len, content.items });
    const xref = out.items.len;
    try out.appendSlice(a, "xref\n0 6\n0000000000 65535 f \n");
    for (offsets[1..]) |offset| try out.print(a, "{d:0>10} 00000 n \n", .{offset});
    try out.print(a, "trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n{d}\n%%EOF\n", .{xref});
    return out.toOwnedSlice(a);
}
test "create inspect replace save preserves following text position" {
    const a = std.testing.allocator;
    const bytes = try create(a, "Hello world");
    defer a.free(bytes);
    var doc = try Document.open(a, bytes);
    defer doc.deinit();
    const pages = try doc.inspect();
    try std.testing.expectEqual(@as(usize, 1), pages.len);
    try std.testing.expectEqualStrings("Hello world", pages[0].runs[0].text);
    const next_x = pages[0].runs[1].x;
    try doc.replace(1, 0, "Hi");
    const saved = try doc.save(a);
    defer a.free(saved);
    var reopened = try Document.open(a, saved);
    defer reopened.deinit();
    const edited = try reopened.inspect();
    try std.testing.expectEqualStrings("Hi", edited[0].runs[0].text);
    try std.testing.expectApproxEqAbs(next_x, edited[0].runs[1].x, 0.000001);
    try std.testing.expectError(error.TextOverflow, reopened.replace(1, 0, "This is far too long to fit into the original run"));
}
fn testDocument(content: []const u8) !struct { doc: Document, bytes: []u8 } {
    const a = std.testing.allocator;
    const bytes = try create(a, "test");
    errdefer a.free(bytes);
    var doc = try Document.open(a, bytes);
    errdefer doc.deinit();
    (try doc.object(.{ .id = 5, .generation = 0 })).changed = content;
    return .{ .doc = doc, .bytes = bytes };
}
test "text and graphics transforms, spacing, TJ and line positioning" {
    var fixture = try testDocument("q 2 0 0 3 10 20 cm BT /F1 10 Tf 1 0 0 1 5 6 Tm 1 Tc 2 Tw 50 Tz 4 Ts (A B) Tj [(C) 100 (D)] TJ 12 TL T* (E) Tj 1 -2 TD (F) Tj T* (G) Tj ET Q BT /F1 10 Tf (H) Tj ET");
    defer fixture.doc.deinit();
    defer std.testing.allocator.free(fixture.bytes);
    const runs = (try fixture.doc.inspect())[0].runs;
    try std.testing.expectApproxEqAbs(@as(f64, 20), runs[0].x, 1e-8);
    try std.testing.expectApproxEqAbs(@as(f64, 50), runs[0].y, 1e-8);
    try std.testing.expectApproxEqAbs(@as(f64, 11.5), runs[0].advance, 1e-8);
    try std.testing.expectApproxEqAbs(@as(f64, 43), runs[1].x, 1e-8);
    try std.testing.expectApproxEqAbs(@as(f64, 6.5), runs[1].advance, 1e-8);
    try std.testing.expectApproxEqAbs(@as(f64, 14), runs[2].y, 1e-8);
    try std.testing.expectApproxEqAbs(@as(f64, 22), runs[3].x, 1e-8);
    try std.testing.expectApproxEqAbs(@as(f64, 8), runs[3].y, 1e-8);
    try std.testing.expectApproxEqAbs(@as(f64, 2), runs[4].y, 1e-8);
    try std.testing.expectApproxEqAbs(@as(f64, 0), runs[5].x, 1e-8);
    try std.testing.expectApproxEqAbs(@as(f64, 0), runs[5].y, 1e-8);
}
test "malformed and unsupported content rejects explicitly" {
    const cases = .{
        .{ "BT /F1 12 Tf (x) Tj", error.UnclosedTextObject },
        .{ "BT /F1 Tf ET", error.InvalidOperands },
        .{ "BT /F1 12 Tf [12 /bad] TJ ET", error.InvalidOperands },
        .{ "Q", error.GraphicsStackUnderflow },
        .{ "q", error.UnclosedGraphicsState },
        .{ "BT /F1 12 Tf <FF> Tj ET", error.UnsupportedEncoding },
        .{ "BT /F1 12 Tf 7 Tr (x) Tj ET", error.UnsupportedTextRendering },
        .{ "/X1 Do", error.UnsupportedOperator },
        .{ "BT /F1 12 Tf 0 Tz (x) Tj ET", error.UnsupportedTextState },
        .{ "BT /F1 12 Tf 1e9 Tc ET", error.InvalidNumber },
    };
    inline for (cases) |case| {
        var f = try testDocument(case[0]);
        defer f.doc.deinit();
        defer std.testing.allocator.free(f.bytes);
        try std.testing.expectError(case[1], f.doc.inspect());
    }
}
test "invalid xref offsets, lengths, missing references and cyclic page trees" {
    const a = std.testing.allocator;
    const original = try create(a, "hello");
    defer a.free(original);
    {
        var doc = try Document.open(a, original);
        defer doc.deinit();
        doc.entries[1].offset += 1;
        try std.testing.expectError(error.InvalidXrefOffset, doc.inspect());
    }
    {
        var doc = try Document.open(a, original);
        defer doc.deinit();
        doc.entries[2].live = false;
        try std.testing.expectError(error.MissingReference, doc.inspect());
    }
    {
        var doc = try Document.open(a, original);
        defer doc.deinit();
        const pages = try doc.object(.{ .id = 2, .generation = 0 });
        const kids = syntax.get(pages.value, "Kids").?.array;
        kids[0] = .{ .ref = .{ .id = 2, .generation = 0 } };
        try std.testing.expectError(error.PageTreeCycle, doc.inspect());
    }
    {
        const damaged = try a.dupe(u8, original);
        defer a.free(damaged);
        const at = std.mem.indexOf(u8, damaged, "/Length ").? + 8;
        damaged[at] = '9';
        var doc = try Document.open(a, damaged);
        defer doc.deinit();
        try std.testing.expectError(error.InvalidStreamLength, doc.inspect());
    }
    {
        var doc = try Document.open(a, original);
        defer doc.deinit();
        const pages = try doc.inspect();
        const stream = pages[0].contents[0];
        pages[0].contents = try doc.allocator().dupe(u32, &.{ stream, stream });
        try std.testing.expectError(error.UnsupportedSharedContent, doc.replace(1, 0, "hi"));
    }
}
test "parser nesting and token boundaries are bounded" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var p = syntax.Parser{ .allocator = arena.allocator(), .bytes = "[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[0" };
    try std.testing.expectError(error.SyntaxLimit, p.value());
    var q = syntax.Parser{ .allocator = arena.allocator(), .bytes = "(a\\101\\\r\nb) /A#23B 1 65536 R" };
    try std.testing.expectEqualStrings("aAb", (try q.value()).string);
    try std.testing.expectEqualStrings("A#B", (try q.value()).name);
    try std.testing.expectEqual(@as(i64, 1), (try q.value()).integer);
}
test "indirect stream length nesting is bounded" {
    const a = std.testing.allocator;
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);
    try bytes.appendSlice(a, "%PDF-1.7\n");
    var offsets: [72]usize = @splat(0);
    for (1..71) |i| {
        offsets[i] = bytes.items.len;
        try bytes.print(a, "{d} 0 obj\n<< /Length {d} 0 R >>\nstream\n\nendstream\nendobj\n", .{ i, i + 1 });
    }
    offsets[71] = bytes.items.len;
    try bytes.appendSlice(a, "71 0 obj\n0\nendobj\n");
    const xref = bytes.items.len;
    try bytes.appendSlice(a, "xref\n0 72\n0000000000 65535 f \n");
    for (offsets[1..]) |offset| try bytes.print(a, "{d:0>10} 00000 n \n", .{offset});
    try bytes.print(a, "trailer\n<< /Size 72 /Root 1 0 R >>\nstartxref\n{d}\n%%EOF\n", .{xref});
    var doc = try Document.open(a, bytes.items);
    defer doc.deinit();
    try std.testing.expectError(error.ReferenceLimit, doc.object(.{ .id = 1, .generation = 0 }));
}
test "nonrepresentable edit compensation rejects without mutation" {
    var f = try testDocument("BT /F1 .0000000000001 Tf 100 Tc (AA) Tj ET");
    defer f.doc.deinit();
    defer std.testing.allocator.free(f.bytes);
    try std.testing.expectError(error.UnsupportedTextState, f.doc.replace(1, 0, "A"));
    try std.testing.expectEqualStrings("AA", (try f.doc.inspect())[0].runs[0].text);
}
test "invalid startxref is malformed, not an unsupported xref stream" {
    const a = std.testing.allocator;
    const bytes = try create(a, "hi");
    defer a.free(bytes);
    const at = std.mem.lastIndexOf(u8, bytes, "startxref\n").? + 10;
    const end = std.mem.indexOfScalarPos(u8, bytes, at, '\n').?;
    @memset(bytes[at..end], '0');
    bytes[end - 1] = '1';
    try std.testing.expectError(error.InvalidXrefOffset, Document.open(a, bytes));
}
test "writer links free xref slots" {
    const a = std.testing.allocator;
    const bytes = try create(a, "hi");
    defer a.free(bytes);
    var doc = try Document.open(a, bytes);
    defer doc.deinit();
    const entries = try doc.allocator().alloc(@TypeOf(doc.entries[0]), 8);
    @memcpy(entries[0..6], doc.entries);
    @memset(entries[6..], .{});
    doc.entries = entries;
    for (doc.trailer.dict) |*e| if (std.mem.eql(u8, e.key, "Size")) {
        e.value = .{ .integer = 8 };
    };
    const saved = try doc.save(a);
    defer a.free(saved);
    try std.testing.expect(std.mem.indexOf(u8, saved, "xref\n0 8\n0000000006 65535 f") != null);
    try std.testing.expect(std.mem.indexOf(u8, saved, "0000000007 00000 f \n0000000000 00000 f") != null);
}
test "page-tree nodes cannot be revisited through sibling references" {
    const a = std.testing.allocator;
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);
    try bytes.appendSlice(a, "%PDF-1.7\n");
    const bodies = [_][]const u8{
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R 3 0 R] /Count 0 >>",
        "<< /Type /Pages /Kids [] /Count 0 >>",
    };
    var offsets: [4]usize = @splat(0);
    for (bodies, 1..) |body, i| {
        offsets[i] = bytes.items.len;
        try bytes.print(a, "{d} 0 obj\n{s}\nendobj\n", .{ i, body });
    }
    const xref = bytes.items.len;
    try bytes.appendSlice(a, "xref\n0 4\n0000000000 65535 f \n");
    for (offsets[1..]) |offset| try bytes.print(a, "{d:0>10} 00000 n \n", .{offset});
    try bytes.print(a, "trailer\n<< /Size 4 /Root 1 0 R >>\nstartxref\n{d}\n%%EOF\n", .{xref});
    var doc = try Document.open(a, bytes.items);
    defer doc.deinit();
    try std.testing.expectError(error.InvalidPageTree, doc.inspect());
}
