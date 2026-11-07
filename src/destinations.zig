const std = @import("std");
const d = @import("document.zig");
const s = @import("syntax.zig");
pub const Mode = enum(u32) { xyz, fit, fit_h, fit_v, fit_r, fit_b, fit_bh, fit_bv };
pub const Destination = struct {
    page_ref: s.Ref,
    page: usize,
    mode: Mode,
    parameters: [4]?f64 = @splat(null),
};
fn get(doc: *d.Document, v: s.Value, key: []const u8) !s.Value {
    if (v != .dict) return error.InvalidDestination;
    return doc.resolve(s.get(v, key) orelse .null);
}
const NameTree = struct {
    doc: *d.Document,
    names: std.StringHashMapUnmanaged(s.Value) = .empty,
    visited: std.AutoHashMapUnmanaged(u32, void) = .empty,
    count: usize = 0,
    fn walk(self: *NameTree, raw: s.Value, depth: usize) anyerror!void {
        if (depth >= 64 or self.count >= 100000) return error.DestinationLimit;
        self.count += 1;
        if (raw == .ref) {
            const slot = try self.visited.getOrPut(self.doc.allocator(), raw.ref.id);
            if (slot.found_existing) return error.InvalidDestinationTree;
        }
        const v = try self.doc.resolve(raw);
        if (v != .dict) return error.InvalidDestinationTree;
        if (s.get(v, "Limits")) |limits| {
            const pair = try self.doc.resolve(limits);
            if (pair != .array or pair.array.len != 2 or pair.array[0] != .string or pair.array[1] != .string or std.mem.order(u8, pair.array[0].string, pair.array[1].string) == .gt) return error.InvalidDestinationTree;
        }
        const names = try get(self.doc, v, "Names");
        const kids = try get(self.doc, v, "Kids");
        if (names != .null and kids != .null) return error.InvalidDestinationTree;
        if (names != .null) {
            if (names != .array or names.array.len % 2 != 0 or names.array.len / 2 > 100000 - self.count) return error.InvalidDestinationTree;
            self.count += names.array.len / 2;
            var previous: ?[]const u8 = null;
            var i: usize = 0;
            while (i < names.array.len) : (i += 2) {
                const key = try self.doc.resolve(names.array[i]);
                if (key != .string or key.string.len > 8192) return error.InvalidDestinationTree;
                if (previous) |last| if (std.mem.order(u8, last, key.string) != .lt) return error.InvalidDestinationTree;
                previous = key.string;
                const slot = try self.names.getOrPut(self.doc.allocator(), key.string);
                if (slot.found_existing) return error.InvalidDestinationTree;
                slot.value_ptr.* = names.array[i + 1];
            }
        } else if (kids != .null) {
            if (kids != .array or kids.array.len > 100000 - self.count) return error.InvalidDestinationTree;
            for (kids.array) |child| try self.walk(child, depth + 1);
        }
    }
};
fn named(doc: *d.Document, raw: s.Value) !s.Value {
    const key = if (raw == .name) raw.name else raw.string;
    if (key.len > 8192) return error.DestinationLimit;
    const catalog = try doc.resolve(s.get(doc.trailer, "Root") orelse return error.InvalidCatalog);
    if (raw == .name) {
        const legacy = try get(doc, catalog, "Dests");
        if (legacy != .dict) return error.DestinationNotFound;
        return s.get(legacy, key) orelse error.DestinationNotFound;
    }
    if (doc.destination_names == null) {
        var tree = NameTree{ .doc = doc };
        defer tree.visited.deinit(doc.allocator());
        const names = try get(doc, catalog, "Names");
        if (names != .null) {
            if (names != .dict) return error.InvalidDestinationTree;
            if (s.get(names, "Dests")) |root| try tree.walk(root, 0);
        }
        doc.destination_names = tree.names;
    }
    return doc.destination_names.?.get(key) orelse error.DestinationNotFound;
}
pub fn read(doc: *d.Document, raw: s.Value) !Destination {
    var v = try doc.resolve(raw);
    if (v == .name or v == .string) v = try doc.resolve(try named(doc, v));
    if (v == .dict) {
        if (s.get(v, "SD") != null) return error.UnsupportedStructureDestination;
        v = try get(doc, v, "D");
    }
    if (v != .array or v.array.len < 2 or v.array[0] != .ref) return error.InvalidDestination;
    const ref = v.array[0].ref;
    if (ref.id >= doc.entries.len or !doc.entries[ref.id].live or doc.entries[ref.id].generation != ref.generation) return error.InvalidDestination;
    if (doc.page_numbers.count() == 0) _ = try doc.indexPages();
    const page = doc.page_numbers.get(ref.id) orelse return error.InvalidDestination;
    const mode_name = try doc.resolve(v.array[1]);
    if (mode_name != .name) return error.InvalidDestination;
    const names = [_][]const u8{ "XYZ", "Fit", "FitH", "FitV", "FitR", "FitB", "FitBH", "FitBV" };
    const arity = [_]usize{ 3, 0, 1, 1, 4, 0, 1, 1 };
    for (names, 0..) |name, i| {
        if (!std.mem.eql(u8, mode_name.name, name)) continue;
        if (v.array.len != arity[i] + 2) return error.InvalidDestination;
        var dest = Destination{ .page_ref = ref, .page = page, .mode = @fromBackingInt(@intCast(i)) };
        for (v.array[2..], 0..) |parameter, j| {
            const value = try doc.resolve(parameter);
            if (value == .null and dest.mode != .fit_r) continue;
            const n = s.number(value) catch return error.InvalidDestination;
            if (!std.math.isFinite(n) or @abs(n) > 1e6) return error.InvalidDestination;
            dest.parameters[j] = n;
        }
        if (dest.mode == .xyz) {
            if (dest.parameters[2]) |zoom| {
                if (zoom < 0) return error.InvalidDestination;
                if (zoom == 0) dest.parameters[2] = null;
            }
        }
        if (dest.mode == .fit_r and (dest.parameters[2].? <= dest.parameters[0].? or dest.parameters[3].? <= dest.parameters[1].?)) return error.InvalidDestination;
        return dest;
    }
    return error.UnsupportedDestinationMode;
}

fn parseValue(doc: *d.Document, text: []const u8) !s.Value {
    var parser = s.Parser{ .allocator = doc.allocator(), .bytes = text };
    return parser.value();
}
test "all explicit destination modes preserve null coordinates and zero zoom" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    const cases = [_][]const u8{ "[3 0 R /XYZ null 720 0]", "[3 0 R /Fit]", "[3 0 R /FitH null]", "[3 0 R /FitV 10]", "[3 0 R /FitR 10 20 100 200]", "[3 0 R /FitB]", "[3 0 R /FitBH 700]", "[3 0 R /FitBV null]" };
    for (cases, 0..) |text, i| {
        const dest = try read(&doc, try parseValue(&doc, text));
        try std.testing.expectEqual(@as(usize, 0), dest.page);
        try std.testing.expectEqual(i, @backingInt(dest.mode));
        if (i == 0) {
            try std.testing.expectEqual(@as(?f64, null), dest.parameters[0]);
            try std.testing.expectEqual(@as(?f64, 720), dest.parameters[1]);
            try std.testing.expectEqual(@as(?f64, null), dest.parameters[2]);
        }
    }
    for ([_][]const u8{ "[4 0 R /Fit]", "[3 1 R /Fit]", "[0 /Fit]", "[3 0 R /XYZ 0 0 -1]", "[3 0 R /Fit 1]", "[3 0 R /FitR 10 10 5 5]", "[3 0 R /FitR null 10 20 30]" }) |text|
        try std.testing.expectError(error.InvalidDestination, read(&doc, try parseValue(&doc, text)));
}
test "legacy dictionary and name tree destinations resolve and invalidate on edits" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    const root = try doc.object(.{ .id = 1, .generation = 0 });
    try doc.set(root, "Dests", try parseValue(&doc, "<< /chapter << /D [3 0 R /FitH 720] >> >>"));
    try std.testing.expectEqual(Mode.fit_h, (try read(&doc, .{ .name = "chapter" })).mode);
    try doc.set(root, "Names", try parseValue(&doc, "<< /Dests << /Kids [<< /Limits [(a) (chapter)] /Names [(a) [3 0 R /Fit] (chapter) << /D [3 0 R /XYZ null 400 2] >>] >>] >> >>"));
    try std.testing.expectEqual(@as(?f64, 400), (try read(&doc, .{ .string = "chapter" })).parameters[1]);
    try doc.set(root, "Names", try parseValue(&doc, "<< /Dests << /Names [(chapter) [3 0 R /FitV 15]] >> >>"));
    try std.testing.expectEqual(Mode.fit_v, (try read(&doc, .{ .string = "chapter" })).mode);
    try std.testing.expectError(error.DestinationNotFound, read(&doc, .{ .string = "absent" }));
}
test "destination name trees reject cycles duplicate keys and excessive depth" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    const root = try doc.object(.{ .id = 1, .generation = 0 });
    const cycle = try doc.addObject(try parseValue(&doc, "<< /Kids [6 0 R] >>"), null);
    try std.testing.expectEqual(@as(u32, 6), cycle);
    try doc.set(root, "Names", try parseValue(&doc, "<< /Dests 6 0 R >>"));
    try std.testing.expectError(error.InvalidDestinationTree, read(&doc, .{ .string = "chapter" }));
    try doc.set(root, "Names", try parseValue(&doc, "<< /Dests << /Names [(chapter) [3 0 R /Fit] (chapter) [3 0 R /Fit]] >> >>"));
    try std.testing.expectError(error.InvalidDestinationTree, read(&doc, .{ .string = "chapter" }));
    var child = try parseValue(&doc, "<< /Names [(chapter) [3 0 R /Fit]] >>");
    for (0..65) |_| {
        child = .{ .dict = try doc.allocator().dupe(s.Entry, &.{.{ .key = "Kids", .value = .{ .array = try doc.allocator().dupe(s.Value, &.{child}) } }}) };
    }
    try doc.set(root, "Names", .{ .dict = try doc.allocator().dupe(s.Entry, &.{.{ .key = "Dests", .value = child }}) });
    try std.testing.expectError(error.DestinationLimit, read(&doc, .{ .string = "chapter" }));
}
