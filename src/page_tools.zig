const std = @import("std");
const pod = @import("pod.zig");
const d = @import("document.zig");
const s = @import("syntax.zig");
const renderer = @import("render.zig");
const A = std.mem.Allocator;

pub const Selection = struct { doc: *d.Document, pages: []const usize };
fn reference(id: u32) s.Value {
    return .{ .ref = .{ .id = id, .generation = 0 } };
}
fn numbers(a: A, values: [4]f64) !s.Value {
    const out = try a.alloc(s.Value, 4);
    for (out, values) |*v, n| v.* = .{ .real = n };
    return .{ .array = out };
}

// Import only page-local graphs. Destinations, outlines, forms and other
// document-level relationships need an explicit preservation policy first.
const Importer = struct {
    source: *d.Document,
    target: *d.Document,
    map: []u32,
    fn clone(self: *Importer, value: s.Value, depth: usize) anyerror!s.Value {
        if (depth > 64) return error.ReferenceLimit;
        const a = self.target.allocator();
        return switch (value) {
            .name => |v| .{ .name = try a.dupe(u8, v) },
            .string => |v| .{ .string = try a.dupe(u8, v) },
            .array => |v| blk: {
                const out = try a.alloc(s.Value, v.len);
                for (out, v) |*item, input| item.* = try self.clone(input, depth + 1);
                break :blk .{ .array = out };
            },
            .dict => |v| blk: {
                const out = try a.alloc(s.Entry, v.len);
                for (out, v) |*item, input| item.* = .{ .key = try a.dupe(u8, input.key), .value = try self.clone(input.value, depth + 1) };
                break :blk .{ .dict = out };
            },
            .ref => |ref| blk: {
                const obj = try self.source.object(ref);
                if (s.get(obj.value, "Type")) |kind| {
                    if (kind == .name and (std.mem.eql(u8, kind.name, "Page") or std.mem.eql(u8, kind.name, "Pages") or std.mem.eql(u8, kind.name, "Catalog"))) return error.UnsupportedPageOrganization;
                }
                if (self.map[ref.id] != 0) break :blk reference(self.map[ref.id]);
                const id = try self.target.addObject(.null, null);
                self.map[ref.id] = id;
                const target = try self.target.object(reference(id).ref);
                target.value = try self.clone(obj.value, depth + 1);
                if (obj.changed orelse obj.stream) |stream| {
                    target.stream = try a.dupe(u8, stream);
                    target.changed = target.stream;
                }
                break :blk reference(id);
            },
            else => value,
        };
    }
};

pub fn assemble(a: A, selections: []const Selection) ![]u8 {
    var count: usize = 0;
    for (selections) |selection| {
        if (selection.pages.len == 0) return error.EmptyPageSelection;
        count = std.math.add(usize, count, selection.pages.len) catch return error.PageLimit;
        if (count > 100000) return error.PageLimit;
        const pages = try selection.doc.inspect();
        const seen = try a.alloc(bool, pages.len);
        defer a.free(seen);
        @memset(seen, false);
        for (selection.pages) |index| {
            if (index >= pages.len) return error.PageNotFound;
            if (seen[index]) return error.DuplicatePage;
            seen[index] = true;
        }
        const catalog = try selection.doc.resolve(s.get(selection.doc.trailer, "Root").?);
        for (selection.doc.trailer.dict) |entry| {
            if (!std.mem.eql(u8, entry.key, "Root") and !std.mem.eql(u8, entry.key, "Size") and !std.mem.eql(u8, entry.key, "ID")) return error.UnsupportedPageOrganization;
        }
        for (catalog.dict) |entry| {
            if (!std.mem.eql(u8, entry.key, "Type") and !std.mem.eql(u8, entry.key, "Pages")) return error.UnsupportedPageOrganization;
        }
        try renderer.validate(selection.doc);
    }
    if (count == 0) return error.EmptyPageSelection;
    const seed = try pod.create(a, "");
    defer a.free(seed);
    var target = try d.Document.open(a, seed);
    defer target.deinit();
    const ta = target.allocator();
    const kids = try ta.alloc(s.Value, count);
    var cursor: usize = 0;
    for (selections) |selection| {
        const map = try ta.alloc(u32, selection.doc.entries.len);
        @memset(map, 0);
        var importer = Importer{ .source = selection.doc, .target = &target, .map = map };
        const pages = try selection.doc.inspect();
        for (selection.pages) |index| {
            const page = pages[index];
            const object = try selection.doc.object(.{ .id = page.object_id, .generation = selection.doc.entries[page.object_id].generation });
            for (object.value.dict) |entry| {
                var allowed = false;
                for ([_][]const u8{ "Type", "Parent", "Resources", "MediaBox", "CropBox", "Rotate", "Contents", "Annots" }) |key| {
                    if (std.mem.eql(u8, key, entry.key)) allowed = true;
                }
                if (!allowed) return error.UnsupportedPageOrganization;
            }
            const entries = try ta.alloc(s.Entry, 8);
            entries[0] = .{ .key = "Type", .value = .{ .name = "Page" } };
            entries[1] = .{ .key = "Parent", .value = reference(2) };
            entries[2] = .{ .key = "Resources", .value = try importer.clone(page.resources, 0) };
            entries[3] = .{ .key = "MediaBox", .value = try importer.clone(page.media_box, 0) };
            entries[4] = .{ .key = "CropBox", .value = try numbers(ta, try page.visibleBox()) };
            entries[5] = .{ .key = "Rotate", .value = .{ .integer = page.rotation } };
            const contents = try ta.alloc(s.Value, page.contents.len);
            for (contents, page.contents) |*v, id| v.* = try importer.clone(.{ .ref = .{ .id = id, .generation = selection.doc.entries[id].generation } }, 0);
            entries[6] = .{ .key = "Contents", .value = .{ .array = contents } };
            entries[7] = .{ .key = "Annots", .value = try importer.clone(s.get(object.value, "Annots") orelse .{ .array = &.{} }, 0) };
            kids[cursor] = reference(try target.addObject(.{ .dict = entries }, null));
            cursor += 1;
        }
    }
    const tree = try target.object(reference(2).ref);
    const entries = try ta.alloc(s.Entry, 3);
    entries[0] = .{ .key = "Type", .value = .{ .name = "Pages" } };
    entries[1] = .{ .key = "Kids", .value = .{ .array = kids } };
    entries[2] = .{ .key = "Count", .value = .{ .integer = @intCast(count) } };
    tree.value = .{ .dict = entries };
    tree.dirty = true;
    try renderer.validate(&target);
    return target.save(a);
}

fn changedGeometry(a: A, doc: *d.Document, index: usize, key: []const u8, box: ?[4]f64, degrees: i32) ![]u8 {
    const bytes = try doc.save(a);
    defer a.free(bytes);
    var copy = try d.Document.open(a, bytes);
    defer copy.deinit();
    const pages = try copy.inspect();
    if (index >= pages.len) return error.PageNotFound;
    const id = pages[index].object_id;
    const value = if (box) |b| try numbers(copy.allocator(), b) else s.Value{ .integer = @mod(pages[index].rotation + degrees, 360) };
    try copy.set(try copy.object(.{ .id = id, .generation = copy.entries[id].generation }), key, value);
    copy.pages = null;
    try renderer.validate(&copy);
    return copy.save(a);
}
pub fn rotate(a: A, doc: *d.Document, index: usize, degrees: i32) ![]u8 {
    if (@mod(degrees, 90) != 0) return error.InvalidRotation;
    return changedGeometry(a, doc, index, "Rotate", null, @mod(degrees, 360));
}
pub fn crop(a: A, doc: *d.Document, index: usize, box: [4]f64) ![]u8 {
    const pages = try doc.inspect();
    if (index >= pages.len) return error.PageNotFound;
    for (box) |v| if (!std.math.isFinite(v)) return error.InvalidCropBox;
    const media = try d.rectangle(pages[index].media_box);
    if (box[0] < media[0] or box[1] < media[1] or box[2] > media[2] or box[3] > media[3] or box[2] <= box[0] or box[3] <= box[1]) return error.InvalidCropBox;
    return changedGeometry(a, doc, index, "CropBox", box, 0);
}

test "assemble merges distinct resource graphs, reorders, extracts and preserves markup" {
    const a = std.testing.allocator;
    const first = try pod.create(a, "First");
    defer a.free(first);
    const second = try pod.create(a, "Second");
    defer a.free(second);
    var one = try d.Document.open(a, first);
    defer one.deinit();
    var two = try d.Document.open(a, second);
    defer two.deinit();
    _ = try pod.annotations.add(&two, 0, .rectangle, &.{ .{ .x = 50, .y = 50 }, .{ .x = 100, .y = 100 } }, "", .{});
    const merged = try assemble(a, &.{ .{ .doc = &one, .pages = &.{0} }, .{ .doc = &two, .pages = &.{0} } });
    defer a.free(merged);
    var result = try d.Document.open(a, merged);
    defer result.deinit();
    const pages = try result.inspect();
    try std.testing.expectEqual(@as(usize, 2), pages.len);
    try std.testing.expectEqualStrings("First", pages[0].runs[0].text);
    try std.testing.expectEqualStrings("Second", pages[1].runs[0].text);
    try std.testing.expectEqual(@as(usize, 1), (try pod.annotations.list(&result, 1)).len);
    try renderer.validate(&result);
    const reversed = try assemble(a, &.{.{ .doc = &result, .pages = &.{ 1, 0 } }});
    defer a.free(reversed);
    var reverse = try d.Document.open(a, reversed);
    defer reverse.deinit();
    try std.testing.expectEqualStrings("Second", (try reverse.inspect())[0].runs[0].text);
    const extracted = try assemble(a, &.{.{ .doc = &result, .pages = &.{1} }});
    defer a.free(extracted);
    var extract = try d.Document.open(a, extracted);
    defer extract.deinit();
    try std.testing.expectEqual(@as(usize, 1), (try extract.inspect()).len);
    try std.testing.expectEqualStrings("Second", (try extract.inspect())[0].runs[0].text);
    try std.testing.expect(std.mem.indexOf(u8, extracted, "4669727374") == null);
    try std.testing.expectEqualStrings("First", (try one.inspect())[0].runs[0].text);
}

test "page assembly rejects invalid selections and document-level relationships" {
    const a = std.testing.allocator;
    const bytes = try pod.create(a, "test");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    try std.testing.expectError(error.EmptyPageSelection, assemble(a, &.{}));
    try std.testing.expectError(error.EmptyPageSelection, assemble(a, &.{.{ .doc = &doc, .pages = &.{} }}));
    try std.testing.expectError(error.PageNotFound, assemble(a, &.{.{ .doc = &doc, .pages = &.{1} }}));
    try std.testing.expectError(error.DuplicatePage, assemble(a, &.{.{ .doc = &doc, .pages = &.{ 0, 0 } }}));
    var trailer = d.Object{ .value = doc.trailer, .body = "" };
    try doc.set(&trailer, "Info", .null);
    doc.trailer = trailer.value;
    try std.testing.expectError(error.UnsupportedPageOrganization, assemble(a, &.{.{ .doc = &doc, .pages = &.{0} }}));
    doc.trailer.dict = doc.trailer.dict[0 .. doc.trailer.dict.len - 1];
    try doc.set(try doc.object(.{ .id = 1, .generation = 0 }), "Outlines", .null);
    try std.testing.expectError(error.UnsupportedPageOrganization, assemble(a, &.{.{ .doc = &doc, .pages = &.{0} }}));
}

test "crop and rotation round trip, inherit geometry and preserve source" {
    const a = std.testing.allocator;
    const bytes = try pod.create(a, "test");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    const cropped = try crop(a, &doc, 0, .{ 20, 30, 500, 700 });
    defer a.free(cropped);
    var cdoc = try d.Document.open(a, cropped);
    defer cdoc.deinit();
    const rotated = try rotate(a, &cdoc, 0, 90);
    defer a.free(rotated);
    var rdoc = try d.Document.open(a, rotated);
    defer rdoc.deinit();
    const page = (try rdoc.inspect())[0];
    try std.testing.expectEqual(@as(i32, 90), page.rotation);
    try std.testing.expectEqualSlices(f64, &.{ 20, 30, 500, 700 }, &(try page.visibleBox()));
    try renderer.validate(&rdoc);
    const selected = try assemble(a, &.{.{ .doc = &rdoc, .pages = &.{0} }});
    defer a.free(selected);
    var check = try d.Document.open(a, selected);
    defer check.deinit();
    try std.testing.expectEqual(@as(i32, 90), (try check.inspect())[0].rotation);
    try std.testing.expectEqual(@as(i32, 0), (try doc.inspect())[0].rotation);
    try std.testing.expectError(error.InvalidCropBox, crop(a, &doc, 0, .{ 0, 0, 0, 200 }));
    try std.testing.expectError(error.InvalidCropBox, crop(a, &doc, 0, .{ -1, 0, 100, 200 }));
    try std.testing.expectError(error.InvalidCropBox, crop(a, &doc, 0, .{ 0, 0, std.math.nan(f64), 200 }));
    try std.testing.expectError(error.InvalidRotation, rotate(a, &doc, 0, 45));
    try std.testing.expectError(error.PageNotFound, rotate(a, &doc, 1, 90));
}

test "inherited crop and rotation render all quadrants and survive assembly" {
    const a = std.testing.allocator;
    const bytes = try pod.create(a, "test");
    defer a.free(bytes);
    for ([_]i32{ 0, 90, 180, 270 }) |angle| {
        var doc = try d.Document.open(a, bytes);
        defer doc.deinit();
        const tree = try doc.object(.{ .id = 2, .generation = 0 });
        try doc.set(tree, "CropBox", try numbers(doc.allocator(), .{ 20, 30, 120, 230 }));
        try doc.set(tree, "Rotate", .{ .integer = angle });
        (try doc.object(.{ .id = 5, .generation = 0 })).changed = "1 0 0 rg 20 30 100 200 re f 0 0 1 rg 20 30 50 100 re f";
        const width: u32 = if (@mod(angle, 180) == 0) 100 else 200;
        const height: u32 = if (@mod(angle, 180) == 0) 200 else 100;
        const bitmap = try renderer.render(a, &doc, 0, &.{}, width);
        defer a.free(bitmap.pixels);
        try std.testing.expectEqual(height, bitmap.height);
        const x: usize = if (angle == 180 or angle == 270) width - 10 else 10;
        const y: usize = if (angle == 0 or angle == 270) height - 10 else 10;
        try std.testing.expectEqualSlices(u8, &.{ 0, 0, 255, 255 }, bitmap.pixels[(y * width + x) * 4 ..][0..4]);
        const output = try assemble(a, &.{.{ .doc = &doc, .pages = &.{0} }});
        defer a.free(output);
        var reopened = try d.Document.open(a, output);
        defer reopened.deinit();
        const again = try renderer.render(a, &reopened, 0, &.{}, width);
        defer a.free(again.pixels);
        try std.testing.expectEqualSlices(u8, bitmap.pixels, again.pixels);
    }
}
