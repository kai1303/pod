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

// Page graphs and explicitly handled document font resources share one object map.
// Other document-level relationships still need a preservation policy.
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
                if (self.map[ref.id] != 0) break :blk reference(self.map[ref.id]);
                if (s.get(obj.value, "Type")) |kind| {
                    if (kind == .name and (std.mem.eql(u8, kind.name, "Page") or std.mem.eql(u8, kind.name, "Pages") or std.mem.eql(u8, kind.name, "Catalog"))) return error.UnsupportedPageOrganization;
                }
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

fn mergeInfo(a: A, doc: *d.Document, info: *std.StringArrayHashMapUnmanaged(s.Value), work: *usize) !void {
    var value = s.get(doc.trailer, "Info") orelse return;
    var depth: usize = 0;
    while (value == .ref) : (depth += 1) {
        if (depth >= 64) return error.ReferenceLimit;
        const object = try doc.object(value.ref);
        if (object.stream != null or object.changed != null) return error.InvalidDocumentInfo;
        value = object.value;
    }
    if (value == .null) return;
    if (value != .dict) return error.InvalidDocumentInfo;
    if (value.dict.len > 1_000_000 -| work.*) return error.DocumentMetadataLimit;
    work.* += value.dict.len;
    for (value.dict) |entry| {
        const scalar = try doc.resolve(entry.value);
        switch (scalar) {
            .null, .string, .name, .boolean, .integer, .real => {},
            else => return error.UnsupportedPageOrganization,
        }
        if (info.get(entry.key)) |existing| {
            // Keep explicit null fields on extraction, but a null value does not
            // conflict with a populated field from another source document.
            if (scalar == .null) continue;
            if (existing == .null) {
                try info.put(a, entry.key, scalar);
                continue;
            }
            const equal = switch (scalar) {
                .string => |v| existing == .string and std.mem.eql(u8, existing.string, v),
                .name => |v| existing == .name and std.mem.eql(u8, existing.name, v),
                .boolean => |v| existing == .boolean and existing.boolean == v,
                .integer => |v| existing == .integer and existing.integer == v,
                .real => |v| existing == .real and existing.real == v,
                else => unreachable,
            };
            if (!equal) return error.UnsupportedPageOrganization;
        } else {
            if (info.count() >= 1024) return error.DocumentMetadataLimit;
            try info.put(a, entry.key, scalar);
        }
    }
}

const view_settings = [_]struct { key: []const u8, values: []const []const u8 }{
    .{ .key = "PageMode", .values = &.{ "UseNone", "UseOutlines", "UseThumbs", "FullScreen", "UseOC", "UseAttachments" } },
    .{ .key = "PageLayout", .values = &.{ "SinglePage", "OneColumn", "TwoColumnLeft", "TwoColumnRight", "TwoPageLeft", "TwoPageRight" } },
};
const FontForm = struct { raw: s.Value, fonts: s.Value };
fn fontForm(doc: *d.Document) !?FontForm {
    const catalog = try doc.resolve(s.get(doc.trailer, "Root").?);
    const raw = s.get(catalog, "AcroForm") orelse return null;
    const form = try doc.resolve(raw);
    if (form != .dict) return error.UnsupportedPageOrganization;
    for (form.dict) |entry| {
        const value = try doc.resolve(entry.value);
        if (std.mem.eql(u8, entry.key, "Fields") and value == .array and value.array.len == 0) continue;
        if (std.mem.eql(u8, entry.key, "DR") and value == .dict) continue;
        return error.UnsupportedPageOrganization;
    }
    const resources = try doc.resolve(s.get(form, "DR") orelse .{ .dict = &.{} });
    for (resources.dict) |entry| if (!std.mem.eql(u8, entry.key, "Font")) return error.UnsupportedPageOrganization;
    const fonts = try doc.resolve(s.get(resources, "Font") orelse .{ .dict = &.{} });
    if (fonts == .null) return .{ .raw = raw, .fonts = .{ .dict = &.{} } };
    if (fonts != .dict) return error.UnsupportedPageOrganization;
    return .{ .raw = raw, .fonts = fonts };
}
const FontToken = struct { start: usize, end: usize, name: []const u8, font: bool = false };
fn appearanceNames(a: A, bytes: []const u8) ![]FontToken {
    if (bytes.len > 65536) return error.TextLimit;
    var parser = s.Parser{ .bytes = bytes, .allocator = a };
    var names: std.ArrayList(FontToken) = .empty;
    var operands: [128]?usize = undefined;
    var count: usize = 0;
    while (true) {
        parser.skip();
        if (parser.pos == bytes.len) break;
        const start = parser.pos;
        const ch = bytes[start];
        if (ch == '/' or ch == '(' or ch == '<' or ch == '[' or ch == '+' or ch == '-' or ch == '.' or std.ascii.isDigit(ch)) {
            if (count == operands.len) return error.OperandLimit;
            const value = try parser.value();
            operands[count] = if (value == .name) names.items.len else null;
            if (value == .name) try names.append(a, .{ .start = start, .end = parser.pos, .name = value.name });
            count += 1;
        } else {
            const op = try parser.token();
            if (std.mem.eql(u8, op, "Tf")) {
                if (count != 2 or operands[0] == null) return error.UnsupportedPageOrganization;
                names.items[operands[0].?].font = true;
            }
            count = 0;
        }
    }
    // Some protected appearances have a legacy DA containing only an escaped name.
    // Retain it verbatim, and reserve that name so a merge cannot newly bind it.
    return names.toOwnedSlice(a);
}
fn pageAnnotations(doc: *d.Document, page: d.Page) ![]s.Value {
    const object = try doc.object(.{ .id = page.object_id, .generation = doc.entries[page.object_id].generation });
    const values = try doc.resolve(s.get(object.value, "Annots") orelse .{ .array = &.{} });
    if (values != .array) return error.UnsupportedPageOrganization;
    return values.array;
}
fn defaultAppearance(doc: *d.Document, annotation: s.Value) !?[]const u8 {
    const value = try doc.resolve(annotation);
    const subtype = try doc.resolve(s.get(value, "Subtype") orelse .null);
    if (subtype != .name or !std.mem.eql(u8, subtype.name, "FreeText")) return null;
    const da = try doc.resolve(s.get(value, "DA") orelse .null);
    if (da == .null) return null;
    if (da != .string) return error.UnsupportedPageOrganization;
    return da.string;
}
fn renameFonts(doc: *d.Document, annotations: s.Value, renamed: std.StringHashMapUnmanaged([]const u8)) !void {
    if (renamed.count() == 0) return;
    const a = doc.allocator();
    const values = try doc.resolve(annotations);
    for (values.array) |annotation| {
        const bytes = try defaultAppearance(doc, annotation) orelse continue;
        var out: std.ArrayList(u8) = .empty;
        var from: usize = 0;
        for (try appearanceNames(a, bytes)) |token| {
            if (!token.font) continue;
            const name = renamed.get(token.name) orelse continue;
            try out.appendSlice(a, bytes[from..token.start]);
            try d.serialize(a, &out, .{ .name = name });
            from = token.end;
        }
        if (from == 0) continue;
        try out.appendSlice(a, bytes[from..]);
        try doc.set(try doc.object(annotation.ref), "DA", .{ .string = try out.toOwnedSlice(a) });
    }
}
pub fn assemble(a: A, selections: []const Selection) ![]u8 {
    var settings: [view_settings.len]?[]const u8 = @splat(null);
    var count: usize = 0;
    var info: std.StringArrayHashMapUnmanaged(s.Value) = .empty;
    defer info.deinit(a);
    var metadata_work: usize = 0;
    var has_form = false;
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
            if (!std.mem.eql(u8, entry.key, "Root") and !std.mem.eql(u8, entry.key, "Size") and !std.mem.eql(u8, entry.key, "ID") and !std.mem.eql(u8, entry.key, "Info")) return error.UnsupportedPageOrganization;
        }
        try mergeInfo(a, selection.doc, &info, &metadata_work);
        catalog_entries: for (catalog.dict) |entry| {
            if (std.mem.eql(u8, entry.key, "Type") or std.mem.eql(u8, entry.key, "Pages")) continue;
            if (std.mem.eql(u8, entry.key, "AcroForm")) {
                const form = (try fontForm(selection.doc)).?;
                if (form.fonts.dict.len > 1_000_000 -| metadata_work) return error.DocumentMetadataLimit;
                metadata_work += form.fonts.dict.len;
                has_form = true;
                continue;
            }
            for (view_settings, 0..) |setting, i| {
                if (!std.mem.eql(u8, entry.key, setting.key)) continue;
                const value = try selection.doc.resolve(entry.value);
                if (value == .null) continue :catalog_entries;
                if (value != .name) return error.UnsupportedPageOrganization;
                var valid = false;
                for (setting.values) |name| if (std.mem.eql(u8, name, value.name)) {
                    valid = true;
                };
                if (!valid) return error.UnsupportedPageOrganization;
                if (settings[i]) |previous| {
                    if (!std.mem.eql(u8, previous, value.name)) return error.UnsupportedPageOrganization;
                }
                settings[i] = value.name;
                continue :catalog_entries;
            }
            return error.UnsupportedPageOrganization;
        }
        try renderer.validate(selection.doc);
    }
    if (count == 0) return error.EmptyPageSelection;
    const seed = try pod.create(a, "");
    defer a.free(seed);
    var target = try d.Document.open(a, seed);
    defer target.deinit();
    const ta = target.allocator();
    const target_catalog = try target.object(s.get(target.trailer, "Root").?.ref);
    var reserved: std.StringHashMapUnmanaged(void) = .empty;
    var merged_fonts: std.ArrayList(s.Entry) = .empty;
    if (has_form and selections.len > 1) for (selections) |selection| {
        if (try fontForm(selection.doc)) |form| for (form.fonts.dict) |entry| try reserved.put(ta, entry.key, {});
        const pages = try selection.doc.inspect();
        for (selection.pages) |index| for (try pageAnnotations(selection.doc, pages[index])) |annotation| {
            const bytes = try defaultAppearance(selection.doc, annotation) orelse continue;
            for (try appearanceNames(ta, bytes)) |token| try reserved.put(ta, token.name, {});
        };
    };
    for (settings, view_settings) |value, setting| if (value) |name| {
        try target.set(target_catalog, setting.key, .{ .name = try ta.dupe(u8, name) });
    };
    const kids = try ta.alloc(s.Value, count);
    var cursor: usize = 0;
    for (selections, 0..) |selection, selection_index| {
        const map = try ta.alloc(u32, selection.doc.entries.len);
        @memset(map, 0);
        var importer = Importer{ .source = selection.doc, .target = &target, .map = map };
        const pages = try selection.doc.inspect();
        // Allocate selected pages first so annotation /P back-references point
        // into the new page tree rather than cloning an old page or its parent.
        for (selection.pages) |index| map[pages[index].object_id] = try target.addObject(.null, null);
        var renamed: std.StringHashMapUnmanaged([]const u8) = .empty;
        if (try fontForm(selection.doc)) |form| {
            if (selections.len == 1) {
                try target.set(target_catalog, "AcroForm", try importer.clone(form.raw, 0));
            } else {
                var ordinal: usize = 0;
                for (form.fonts.dict) |entry| {
                    if (renamed.contains(entry.key)) return error.UnsupportedPageOrganization;
                    const name = while (true) {
                        const candidate = try std.fmt.allocPrint(ta, "PodMerge{d}_{d}", .{ selection_index, ordinal });
                        ordinal += 1;
                        if (!reserved.contains(candidate)) break candidate;
                    };
                    try reserved.put(ta, name, {});
                    try renamed.put(ta, entry.key, name);
                    try merged_fonts.append(ta, .{ .key = name, .value = try importer.clone(entry.value, 0) });
                }
            }
        }
        for (selection.pages) |index| {
            const page = pages[index];
            const object = try selection.doc.object(.{ .id = page.object_id, .generation = selection.doc.entries[page.object_id].generation });
            for (object.value.dict) |entry| {
                var allowed = false;
                for ([_][]const u8{ "Type", "Parent", "Resources", "MediaBox", "CropBox", "Rotate", "Contents", "Annots", "Trans" }) |key| {
                    if (std.mem.eql(u8, key, entry.key)) allowed = true;
                }
                if (!allowed) return error.UnsupportedPageOrganization;
            }
            const transition = s.get(object.value, "Trans");
            if (transition) |raw| {
                const value = try selection.doc.resolve(raw);
                if (value != .dict and value != .null) return error.UnsupportedPageOrganization;
            }
            const entries = try ta.alloc(s.Entry, 8 + @as(usize, @intFromBool(transition != null)));
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
            try renameFonts(&target, entries[7].value, renamed);
            if (transition) |value| entries[8] = .{ .key = "Trans", .value = try importer.clone(value, 0) };
            const id = map[page.object_id];
            const imported_page = try target.object(reference(id).ref);
            imported_page.value = .{ .dict = entries };
            imported_page.dirty = true;
            kids[cursor] = reference(id);
            cursor += 1;
        }
    }
    if (has_form and selections.len > 1) {
        const resources = s.Value{ .dict = try ta.dupe(s.Entry, &.{.{ .key = "Font", .value = .{ .dict = merged_fonts.items } }}) };
        try target.set(target_catalog, "AcroForm", .{ .dict = try ta.dupe(s.Entry, &.{ .{ .key = "Fields", .value = .{ .array = &.{} } }, .{ .key = "DR", .value = resources } }) });
    }
    const tree = try target.object(reference(2).ref);
    const entries = try ta.alloc(s.Entry, 3);
    entries[0] = .{ .key = "Type", .value = .{ .name = "Pages" } };
    entries[1] = .{ .key = "Kids", .value = .{ .array = kids } };
    entries[2] = .{ .key = "Count", .value = .{ .integer = @intCast(count) } };
    tree.value = .{ .dict = entries };
    tree.dirty = true;
    if (info.count() != 0) {
        const metadata = try ta.alloc(s.Entry, info.count());
        for (metadata, info.keys(), info.values()) |*entry, key, value| entry.* = .{
            .key = try ta.dupe(u8, key),
            .value = switch (value) {
                .string => |v| .{ .string = try ta.dupe(u8, v) },
                .name => |v| .{ .name = try ta.dupe(u8, v) },
                else => value,
            },
        };
        const id = try target.addObject(.{ .dict = metadata }, null);
        var trailer = d.Object{ .value = target.trailer, .body = "" };
        try target.set(&trailer, "Info", reference(id));
        target.trailer = trailer.value;
    }
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
    try doc.set(&trailer, "UnsupportedTrailerEntry", .null);
    doc.trailer = trailer.value;
    try std.testing.expectError(error.UnsupportedPageOrganization, assemble(a, &.{.{ .doc = &doc, .pages = &.{0} }}));
    doc.trailer.dict = doc.trailer.dict[0 .. doc.trailer.dict.len - 1];
    try doc.set(try doc.object(.{ .id = 1, .generation = 0 }), "Outlines", .null);
    try std.testing.expectError(error.UnsupportedPageOrganization, assemble(a, &.{.{ .doc = &doc, .pages = &.{0} }}));
}

test "page assembly preserves compatible document information and rejects conflicting metadata" {
    const a = std.testing.allocator;
    const bytes = try pod.create(a, "test");
    defer a.free(bytes);
    var one = try d.Document.open(a, bytes);
    defer one.deinit();
    var two = try d.Document.open(a, bytes);
    defer two.deinit();
    const author = try one.addObject(.{ .string = "Teacher" }, null);
    const info = try one.addObject(.{ .dict = &.{} }, null);
    try one.set(try one.object(reference(info).ref), "Title", .{ .string = "\xfe\xff\x00N\x00o\x00t\x00e\x00s" });
    try one.set(try one.object(reference(info).ref), "Author", reference(author));
    try one.set(try one.object(reference(info).ref), "Course", .null);
    try one.set(try one.object(reference(info).ref), "Empty", .null);
    var trailer = d.Object{ .value = one.trailer, .body = "" };
    try one.set(&trailer, "Info", reference(info));
    one.trailer = trailer.value;
    const other_info = try two.addObject(.{ .dict = &.{} }, null);
    try two.set(try two.object(reference(other_info).ref), "Author", .{ .string = "Teacher" });
    try two.set(try two.object(reference(other_info).ref), "Course", .{ .string = "Biology" });
    try two.set(try two.object(reference(other_info).ref), "Title", .null);
    try two.set(try two.object(reference(other_info).ref), "Empty", .null);
    trailer.value = two.trailer;
    try two.set(&trailer, "Info", reference(other_info));
    two.trailer = trailer.value;
    const merged = try assemble(a, &.{ .{ .doc = &one, .pages = &.{0} }, .{ .doc = &two, .pages = &.{0} } });
    defer a.free(merged);
    var result = try d.Document.open(a, merged);
    defer result.deinit();
    const preserved = try result.resolve(s.get(result.trailer, "Info").?);
    try std.testing.expect(s.get(preserved, "Empty") != null);
    try std.testing.expect(s.get(preserved, "Empty").? == .null);
    try std.testing.expectEqualStrings("Teacher", (try result.resolve(s.get(preserved, "Author").?)).string);
    try std.testing.expectEqualStrings("Biology", (try result.resolve(s.get(preserved, "Course").?)).string);
    try std.testing.expectEqualStrings("\xfe\xff\x00N\x00o\x00t\x00e\x00s", (try result.resolve(s.get(preserved, "Title").?)).string);
    const selected = try assemble(a, &.{.{ .doc = &result, .pages = &.{1} }});
    defer a.free(selected);
    var extracted = try d.Document.open(a, selected);
    defer extracted.deinit();
    const selected_info = try extracted.resolve(s.get(extracted.trailer, "Info").?);
    try std.testing.expectEqualStrings("Biology", (try extracted.resolve(s.get(selected_info, "Course").?)).string);
    try two.set(try two.object(reference(other_info).ref), "Author", .{ .string = "Student" });
    try std.testing.expectError(error.UnsupportedPageOrganization, assemble(a, &.{ .{ .doc = &one, .pages = &.{0} }, .{ .doc = &two, .pages = &.{0} } }));
    try std.testing.expectEqualStrings("Teacher", (try one.resolve(s.get((try one.object(reference(info).ref)).value, "Author").?)).string);
}

fn assembleInfoWithAllocator(allocator: A, bytes: []const u8) !void {
    var doc = try d.Document.open(allocator, bytes);
    defer doc.deinit();
    const output = try assemble(allocator, &.{.{ .doc = &doc, .pages = &.{0} }});
    defer allocator.free(output);
}

test "document information assembly validates structure and cleans up failed allocations" {
    const a = std.testing.allocator;
    const bytes = try pod.create(a, "metadata");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    const id = try doc.addObject(.{ .dict = &.{} }, null);
    const info = try doc.object(reference(id).ref);
    try doc.set(info, "Title", .{ .string = "A title" });
    try doc.set(info, "Trapped", .{ .name = "False" });
    try doc.set(info, "Custom", .{ .integer = 3 });
    try doc.set(info, "Empty", .null);
    var trailer = d.Object{ .value = doc.trailer, .body = "" };
    try doc.set(&trailer, "Info", reference(id));
    doc.trailer = trailer.value;
    const saved = try doc.save(a);
    defer a.free(saved);
    try std.testing.checkAllAllocationFailures(a, assembleInfoWithAllocator, .{saved});
    try doc.set(info, "Nested", .{ .array = &.{} });
    try std.testing.expectError(error.UnsupportedPageOrganization, assemble(a, &.{.{ .doc = &doc, .pages = &.{0} }}));
    info.stream = "data";
    try std.testing.expectError(error.InvalidDocumentInfo, assemble(a, &.{.{ .doc = &doc, .pages = &.{0} }}));
    info.stream = null;
    const many = try doc.allocator().alloc(s.Entry, 1025);
    for (many, 0..) |*entry, i| entry.* = .{ .key = try std.fmt.allocPrint(doc.allocator(), "Field{d}", .{i}), .value = .{ .integer = 1 } };
    info.value = .{ .dict = many };
    try std.testing.expectError(error.DocumentMetadataLimit, assemble(a, &.{.{ .doc = &doc, .pages = &.{0} }}));
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

test "page assembly preserves compatible catalog viewing preferences" {
    const a = std.testing.allocator;
    const bytes = try pod.create(a, "viewing preferences");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    const catalog = try doc.object(s.get(doc.trailer, "Root").?.ref);
    try doc.set(catalog, "PageMode", .{ .name = "UseNone" });
    try doc.set(catalog, "PageLayout", .{ .name = "TwoPageLeft" });
    const page = try doc.object(reference(3).ref);
    try doc.set(page, "Trans", .{ .dict = &.{} });
    const saved = try assemble(a, &.{ .{ .doc = &doc, .pages = &.{0} }, .{ .doc = &doc, .pages = &.{0} } });
    defer a.free(saved);
    var copy = try d.Document.open(a, saved);
    defer copy.deinit();
    const root = try copy.resolve(s.get(copy.trailer, "Root").?);
    try std.testing.expectEqualStrings("UseNone", s.get(root, "PageMode").?.name);
    try std.testing.expectEqualStrings("TwoPageLeft", s.get(root, "PageLayout").?.name);
    const copied_pages = try copy.inspect();
    const copied_page = try copy.object(reference(copied_pages[0].object_id).ref);
    try std.testing.expectEqual(@as(usize, 0), s.get(copied_page.value, "Trans").?.dict.len);
    const allocation_source = try doc.save(a);
    defer a.free(allocation_source);
    try std.testing.checkAllAllocationFailures(a, assembleInfoWithAllocator, .{allocation_source});
    const copy_catalog = try copy.object(s.get(copy.trailer, "Root").?.ref);
    try copy.set(copy_catalog, "PageMode", .{ .name = "FullScreen" });
    try std.testing.expectError(error.UnsupportedPageOrganization, assemble(a, &.{ .{ .doc = &doc, .pages = &.{0} }, .{ .doc = &copy, .pages = &.{0} } }));
    try doc.set(catalog, "PageMode", .{ .integer = 1 });
    try std.testing.expectError(error.UnsupportedPageOrganization, assemble(a, &.{.{ .doc = &doc, .pages = &.{0} }}));
}

fn resourceTextFixture(doc: *d.Document, base: []const u8) !void {
    const a = doc.allocator();
    const id = try pod.annotations.add(doc, 0, .free_text, &.{ .{ .x = 20, .y = 30 }, .{ .x = 200, .y = 100 } }, "Reading notes", .{});
    const annotation = try doc.object(reference(id).ref);
    try doc.set(annotation, "AP", .null);
    try doc.set(annotation, "DA", .{ .string = "% keep this comment\n/Cour 14 Tf .2 g" });
    const font_id = try doc.addObject(.{ .dict = try a.dupe(s.Entry, &.{
        .{ .key = "Type", .value = .{ .name = "Font" } },   .{ .key = "Subtype", .value = .{ .name = "Type1" } },
        .{ .key = "BaseFont", .value = .{ .name = base } }, .{ .key = "Encoding", .value = .{ .name = "WinAnsiEncoding" } },
    }) }, null);
    const fonts = s.Value{ .dict = try a.dupe(s.Entry, &.{.{ .key = "Cour", .value = reference(font_id) }}) };
    const dr = s.Value{ .dict = try a.dupe(s.Entry, &.{.{ .key = "Font", .value = fonts }}) };
    try doc.set(try doc.object(s.get(doc.trailer, "Root").?.ref), "AcroForm", .{ .dict = try a.dupe(s.Entry, &.{.{ .key = "DR", .value = dr }}) });
}
fn assembledFont(doc: *d.Document, page: usize) !@import("pdf_font.zig").Face {
    const mark = (try pod.annotations.list(doc, page))[0];
    const layout = try @import("free_text.zig").load(doc, (try doc.object(reference(mark.id).ref)).value);
    try std.testing.expect(mark.free_text_editable);
    return layout.font.face;
}
fn assembleFontsWithAllocator(a: A, bytes: []const u8) !void {
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    const output = try assemble(a, &.{ .{ .doc = &doc, .pages = &.{0} }, .{ .doc = &doc, .pages = &.{0} } });
    defer a.free(output);
}
test "page assembly preserves document fonts and isolates colliding and fallback names" {
    const a = std.testing.allocator;
    const bytes = try pod.create(a, "");
    defer a.free(bytes);
    var one = try d.Document.open(a, bytes);
    defer one.deinit();
    var two = try d.Document.open(a, bytes);
    defer two.deinit();
    var fallback = try d.Document.open(a, bytes);
    defer fallback.deinit();
    try resourceTextFixture(&one, "Courier");
    try resourceTextFixture(&two, "Helvetica");
    _ = try pod.annotations.add(&fallback, 0, .free_text, &.{ .{ .x = 20, .y = 30 }, .{ .x = 200, .y = 100 } }, "Reading notes", .{});
    const protected_id = try pod.annotations.add(&fallback, 0, .free_text, &.{ .{ .x = 20, .y = 120 }, .{ .x = 200, .y = 200 } }, "Protected", .{});
    try fallback.set(try fallback.object(reference(protected_id).ref), "DA", .{ .string = "/PodMerge0_0 12 Tf" });
    const before = try one.save(a);
    defer a.free(before);
    const merged = try assemble(a, &.{ .{ .doc = &one, .pages = &.{0} }, .{ .doc = &two, .pages = &.{0} }, .{ .doc = &fallback, .pages = &.{0} } });
    defer a.free(merged);
    var result = try d.Document.open(a, merged);
    defer result.deinit();
    try std.testing.expect(try assembledFont(&result, 0) == .courier);
    try std.testing.expect(try assembledFont(&result, 1) == .helvetica);
    try std.testing.expect(try assembledFont(&result, 2) == .courier);
    const form = (try fontForm(&result)).?;
    try std.testing.expect(s.get(form.fonts, "PodMerge0_0") == null);
    const extracted = try assemble(a, &.{.{ .doc = &result, .pages = &.{ 1, 0 } }});
    defer a.free(extracted);
    var copy = try d.Document.open(a, extracted);
    defer copy.deinit();
    try std.testing.expect(try assembledFont(&copy, 0) == .helvetica);
    try std.testing.expect(try assembledFont(&copy, 1) == .courier);
    const after = try one.save(a);
    defer a.free(after);
    try std.testing.expectEqualSlices(u8, before, after);
    try std.testing.checkAllAllocationFailures(a, assembleFontsWithAllocator, .{before});
    const source_form = (try fontForm(&one)).?;
    const duplicate_fonts = s.Value{ .dict = try one.allocator().dupe(s.Entry, &.{ source_form.fonts.dict[0], source_form.fonts.dict[0] }) };
    const duplicate_resources = s.Value{ .dict = try one.allocator().dupe(s.Entry, &.{.{ .key = "Font", .value = duplicate_fonts }}) };
    try one.set(try one.object(s.get(one.trailer, "Root").?.ref), "AcroForm", .{ .dict = try one.allocator().dupe(s.Entry, &.{.{ .key = "DR", .value = duplicate_resources }}) });
    if (assemble(a, &.{ .{ .doc = &one, .pages = &.{0} }, .{ .doc = &two, .pages = &.{0} } })) |unexpected| {
        a.free(unexpected);
        return error.ExpectedDuplicateResourceRejection;
    } else |err| try std.testing.expectEqual(error.UnsupportedPageOrganization, err);
}

test "font renaming changes only Tf operands and preserves escaped names and comments" {
    const a = std.testing.allocator;
    const bytes = try pod.create(a, "");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    const id = try pod.annotations.add(&doc, 0, .free_text, &.{ .{ .x = 20, .y = 30 }, .{ .x = 200, .y = 100 } }, "Text", .{});
    const obj = try doc.object(reference(id).ref);
    const original = "% /Old#20Font 12 Tf\n/Old#20Font 14 Tf /Old#20Font gs (literal /Old#20Font 12 Tf) Tj /Other 10 Tf";
    try doc.set(obj, "DA", .{ .string = original });
    var mapping: std.StringHashMapUnmanaged([]const u8) = .empty;
    defer mapping.deinit(a);
    try mapping.put(a, "Old Font", "New Font");
    var refs = [_]s.Value{reference(id)};
    try renameFonts(&doc, .{ .array = &refs }, mapping);
    const renamed = s.get(obj.value, "DA").?.string;
    try std.testing.expectEqualStrings("% /Old#20Font 12 Tf\n /New#20Font 14 Tf /Old#20Font gs (literal /Old#20Font 12 Tf) Tj /Other 10 Tf", renamed);
    try renameFonts(&doc, .{ .array = &refs }, mapping);
    try std.testing.expectEqualStrings(renamed, s.get(obj.value, "DA").?.string);
}
