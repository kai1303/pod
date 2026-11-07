//! Lazy resolution of generation-zero objects in PDF object streams.
const std = @import("std");
const d = @import("document.zig");
const s = @import("syntax.zig");
const Member = struct { id: u32, offset: usize };
pub const Index = struct { data: []const u8, first: usize, members: []Member };

pub fn read(doc: *d.Document, ref: s.Ref, entry: d.Xref) !*d.Object {
    if (entry.object_stream >= doc.entries.len or ref.generation != 0) return error.InvalidObjectStream;
    const container_entry = doc.entries[entry.object_stream];
    if (!container_entry.live or container_entry.object_stream != 0) return error.InvalidObjectStream;
    const container = try doc.object(.{ .id = entry.object_stream, .generation = container_entry.generation });
    const typ = s.get(container.value, "Type") orelse return error.InvalidObjectStream;
    if (typ != .name or !std.mem.eql(u8, typ.name, "ObjStm")) return error.InvalidObjectStream;
    const data = try doc.streamData(container);
    if (container.members == null or container.members.?.data.ptr != data.ptr or container.members.?.data.len != data.len)
        container.members = try index(doc, container.value, data);
    const table = container.members.?;
    if (entry.object_index >= table.members.len or table.members[entry.object_index].id != ref.id) return error.InvalidObjectStream;
    const start = table.first + table.members[entry.object_index].offset;
    const end = if (entry.object_index + 1 < table.members.len) table.first + table.members[entry.object_index + 1].offset else data.len;
    var parser = s.Parser{ .bytes = data[start..end], .allocator = doc.allocator() };
    const value = try parser.value();
    parser.skip();
    if (parser.pos != parser.bytes.len) return error.InvalidObjectStream;
    const obj = try doc.allocator().create(d.Object);
    obj.* = .{ .value = value, .body = data[start..end] };
    return obj;
}
fn index(doc: *d.Document, value: s.Value, data: []const u8) !Index {
    const count = try s.uint(try doc.resolve(s.get(value, "N") orelse return error.InvalidObjectStream));
    const first = try s.uint(try doc.resolve(s.get(value, "First") orelse return error.InvalidObjectStream));
    if (count == 0 or count > 1_000_000 or first > data.len) return error.InvalidObjectStream;
    const members = try doc.allocator().alloc(Member, count);
    var seen: std.AutoHashMapUnmanaged(u32, void) = .empty;
    defer seen.deinit(doc.arena.child_allocator);
    var parser = s.Parser{ .bytes = data[0..first], .allocator = doc.allocator() };
    for (members, 0..) |*member, i| {
        const id = std.fmt.parseInt(u32, try parser.token(), 10) catch return error.InvalidObjectStream;
        const at = std.fmt.parseInt(usize, try parser.token(), 10) catch return error.InvalidObjectStream;
        if (id == 0 or id >= 1_000_000 or at >= data.len - first or (i > 0 and at <= members[i - 1].offset)) return error.InvalidObjectStream;
        if ((try seen.getOrPut(doc.arena.child_allocator, id)).found_existing) return error.InvalidObjectStream;
        member.* = .{ .id = id, .offset = at };
    }
    parser.skip();
    if (parser.pos != first) return error.InvalidObjectStream;
    return .{ .data = data, .first = first, .members = members };
}

test "compressed members validate their header identity, bounds and nested stream prohibition" {
    const a = std.testing.allocator;
    const original = try @import("pod.zig").create(a, "members");
    defer a.free(original);
    var doc = try d.Document.open(a, original);
    defer doc.deinit();
    var parser = s.Parser{ .bytes = "<< /Type /ObjStm /N 2 /First 9 >>", .allocator = doc.allocator() };
    const container_id = try doc.addObject(try parser.value(), "7 0 8 13 << /A 42 >>  [1 2 3]");
    const member_id = try doc.addObject(.null, null);
    const second_id = try doc.addObject(.null, null);
    doc.entries[member_id] = .{ .live = true, .seen = true, .object_stream = container_id, .object_index = 0 };
    doc.entries[second_id] = .{ .live = true, .seen = true, .object_stream = container_id, .object_index = 1 };
    try std.testing.expectEqual(@as(i64, 42), s.get((try doc.object(.{ .id = member_id, .generation = 0 })).value, "A").?.integer);
    try std.testing.expectEqual(@as(usize, 3), (try doc.object(.{ .id = second_id, .generation = 0 })).value.array.len);
    doc.entries[second_id].object = null;
    // A caller cannot use an entry pointing at another object's member index.
    doc.entries[second_id].object_index = 0;
    try std.testing.expectError(error.InvalidObjectStream, doc.object(.{ .id = second_id, .generation = 0 }));
    doc.entries[second_id].object_index = 99;
    try std.testing.expectError(error.InvalidObjectStream, doc.object(.{ .id = second_id, .generation = 0 }));
    doc.entries[container_id].object_stream = container_id;
    try std.testing.expectError(error.InvalidObjectStream, doc.object(.{ .id = second_id, .generation = 0 }));
}
