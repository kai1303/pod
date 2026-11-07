//! Resolve current objects across classic, stream and hybrid cross-reference revisions.
const std = @import("std");
const d = @import("document.zig");
const s = @import("syntax.zig");
const A = std.mem.Allocator;
const Record = struct { id: usize, entry: d.Xref };
const Section = struct { records: []Record, trailer: s.Value, end: usize, stream: bool = false };
const maximum_objects = 1_000_000;

pub fn load(doc: *d.Document, first: usize, marker: usize) !void {
    var offsets: std.AutoHashMapUnmanaged(usize, void) = .empty;
    defer offsets.deinit(doc.arena.child_allocator);
    var trailer: std.ArrayList(s.Entry) = .empty;
    var offset = first;
    var work: usize = 0;
    var found_tail = false;
    while (true) {
        if (offsets.count() >= 128) return error.RevisionLimit;
        if ((try offsets.getOrPut(doc.arena.child_allocator, offset)).found_existing) return error.XrefCycle;
        var scratch = std.heap.ArenaAllocator.init(doc.arena.child_allocator);
        defer scratch.deinit();
        const a = scratch.allocator();
        const section = try readSection(doc, a, offset);
        const size = try s.uint(s.get(section.trailer, "Size") orelse return error.InvalidTrailer);
        if (size == 0 or size > maximum_objects) return error.InvalidXref;
        var end = s.Parser{ .bytes = doc.bytes, .pos = section.end, .allocator = doc.allocator() };
        end.skip();
        if (end.pos == marker) found_tail = true;
        if (offset == first) {
            doc.entries = try doc.allocator().alloc(d.Xref, size);
            @memset(doc.entries, .{});
        } else if (size > doc.entries.len) return error.InvalidXref;
        try mergeTrailer(doc, &trailer, section);
        if (!section.stream) {
            if (s.get(section.trailer, "XRefStm")) |hybrid| {
                const at = try s.uint(hybrid);
                if ((try offsets.getOrPut(doc.arena.child_allocator, at)).found_existing) return error.XrefCycle;
                const supplement = try readSection(doc, a, at);
                if (!supplement.stream or try s.uint(s.get(supplement.trailer, "Size") orelse return error.InvalidTrailer) != size) return error.InvalidXref;
                // In a hybrid revision the stream supersedes entries in its accompanying table.
                try merge(doc, supplement.records, &work);
                if (s.get(supplement.trailer, "Encrypt")) |encryption| if (encryption != .null) return error.UnsupportedEncryption;
            }
        }
        try merge(doc, section.records, &work);
        const previous = s.get(section.trailer, "Prev") orelse break;
        offset = try s.uint(previous);
        if (offset == 0 or offset >= doc.bytes.len) return error.InvalidXref;
    }
    if (!found_tail) return error.InvalidTrailer;
    if (!doc.entries[0].seen or doc.entries[0].live or doc.entries[0].generation != 65535) return error.InvalidXref;
    doc.trailer = .{ .dict = try trailer.toOwnedSlice(doc.allocator()) };
    if (s.get(doc.trailer, "Root") == null) return error.InvalidTrailer;
}
fn merge(doc: *d.Document, records: []const Record, work: *usize) !void {
    work.* += records.len;
    if (work.* > 4_000_000) return error.XrefLimit;
    for (records) |record| {
        if (record.id >= doc.entries.len) continue;
        if (!doc.entries[record.id].seen) doc.entries[record.id] = record.entry;
    }
}
fn mergeTrailer(doc: *d.Document, result: *std.ArrayList(s.Entry), section: Section) !void {
    if (s.get(section.trailer, "Encrypt")) |encryption| if (encryption != .null) return error.UnsupportedEncryption;
    for (section.trailer.dict) |entry| {
        if (eq(entry.key, "Prev") or eq(entry.key, "XRefStm")) continue;
        if (section.stream and streamKey(entry.key)) continue;
        var present = false;
        for (result.items) |existing| if (eq(existing.key, entry.key)) {
            present = true;
            break;
        };
        if (!present) try result.append(doc.allocator(), entry);
    }
}
fn streamKey(key: []const u8) bool {
    for ([_][]const u8{ "Type", "W", "Index", "Length", "Filter", "DecodeParms", "DL", "F", "FFilter", "FDecodeParms" }) |excluded|
        if (eq(key, excluded)) return true;
    return false;
}
fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
fn integer(p: *s.Parser) !usize {
    return std.fmt.parseInt(usize, try p.token(), 10) catch error.InvalidXref;
}
fn readSection(doc: *d.Document, a: A, offset: usize) !Section {
    if (offset >= doc.bytes.len) return error.InvalidXrefOffset;
    var p = s.Parser{ .bytes = doc.bytes, .pos = offset, .allocator = doc.allocator() };
    if (!p.keyword("xref")) return readStream(doc, a, offset);
    var records: std.ArrayList(Record) = .empty;
    var seen: std.AutoHashMapUnmanaged(usize, void) = .empty;
    while (!p.keyword("trailer")) {
        const first = try integer(&p);
        const count = try integer(&p);
        const limit = std.math.add(usize, first, count) catch return error.ObjectLimit;
        if (limit > maximum_objects or count == 0 or records.items.len + count > maximum_objects) return error.ObjectLimit;
        for (first..limit) |id| {
            if ((try seen.getOrPut(a, id)).found_existing) return error.DuplicateXref;
            const at = try integer(&p);
            const raw_generation = try integer(&p);
            const flag = try p.token();
            if (!eq(flag, "n") and !eq(flag, "f")) return error.InvalidXref;
            const live = flag[0] == 'n';
            // Pillow 11 emits 65536 for the unused free object-zero sentinel.
            const gen: u16 = if (id == 0 and !live and at == 0 and raw_generation == 65536) 65535 else std.math.cast(u16, raw_generation) orelse return error.InvalidXref;
            if (live and (at == 0 or at >= doc.bytes.len or id == 0)) return error.InvalidXref;
            try records.append(a, .{ .id = id, .entry = .{ .offset = at, .generation = gen, .live = live, .seen = true } });
        }
    }
    const trailer = try p.value();
    if (trailer != .dict) return error.InvalidTrailer;
    return .{ .records = records.items, .trailer = trailer, .end = p.pos };
}
fn direct(value: s.Value) bool {
    return switch (value) {
        .ref => false,
        .array => |items| blk: {
            for (items) |item| if (!direct(item)) break :blk false;
            break :blk true;
        },
        .dict => |items| blk: {
            for (items) |item| if (!direct(item.value)) break :blk false;
            break :blk true;
        },
        else => true,
    };
}
fn readStream(doc: *d.Document, a: A, offset: usize) !Section {
    const indirect = try doc.readIndirect(offset, null);
    const obj = indirect.object;
    const typ = s.get(obj.value, "Type") orelse return error.InvalidXrefOffset;
    if (typ != .name or !eq(typ.name, "XRef") or obj.stream == null) return error.InvalidXrefOffset;
    for ([_][]const u8{ "Size", "W", "Index", "Prev", "Length", "Filter", "DecodeParms" }) |key|
        if (s.get(obj.value, key)) |value| if (!direct(value)) return error.InvalidXref;
    const size = try s.uint(s.get(obj.value, "Size") orelse return error.InvalidXref);
    if (size == 0 or size > maximum_objects or indirect.ref.id >= size) return error.InvalidXref;
    const w = s.get(obj.value, "W") orelse return error.InvalidXref;
    if (w != .array or w.array.len != 3) return error.InvalidXref;
    var widths: [3]usize = undefined;
    var stride: usize = 0;
    for (w.array, &widths) |value, *width| {
        width.* = try s.uint(value);
        if (width.* > 8) return error.InvalidXref;
        stride += width.*;
    }
    if (stride == 0) return error.InvalidXref;
    var default_index = [_]s.Value{ .{ .integer = 0 }, .{ .integer = @intCast(size) } };
    const index = s.get(obj.value, "Index") orelse s.Value{ .array = &default_index };
    if (index != .array or index.array.len == 0 or index.array.len % 2 != 0) return error.InvalidXref;
    var last: usize = 0;
    var count: usize = 0;
    var i: usize = 0;
    while (i < index.array.len) : (i += 2) {
        const start = try s.uint(index.array[i]);
        const length = try s.uint(index.array[i + 1]);
        const end = std.math.add(usize, start, length) catch return error.ObjectLimit;
        if (start < last or length == 0 or end > maximum_objects) return error.InvalidXref;
        last = end;
        count += length;
    }
    const bytes = try @import("filters.zig").decode(doc, obj, a, 24 * maximum_objects);
    if (bytes.len != count * stride) return error.InvalidXref;
    const records = try a.alloc(Record, count);
    var cursor: usize = 0;
    i = 0;
    while (i < index.array.len) : (i += 2) {
        const start = try s.uint(index.array[i]);
        const length = try s.uint(index.array[i + 1]);
        for (start..start + length) |id| {
            var fields: [3]u64 = .{ 1, 0, 0 };
            var position = cursor * stride;
            for (widths, &fields) |width, *field| {
                if (width == 0) continue;
                field.* = 0;
                for (bytes[position..][0..width]) |byte| field.* = (field.* << 8) | byte;
                position += width;
            }
            var entry = d.Xref{ .seen = true };
            switch (fields[0]) {
                0 => {
                    entry.generation = std.math.cast(u16, fields[2]) orelse return error.InvalidXref;
                    // Compact writers omit the unused object-zero generation:
                    // qpdf uses zero; MuPDF truncates 65535 to a one-byte 255.
                    if (id == 0 and (entry.generation == 0 or (widths[2] == 1 and fields[1] == 0 and entry.generation == 255))) entry.generation = 65535;
                },
                1 => {
                    if (id == 0 or fields[1] == 0 or fields[1] >= doc.bytes.len) return error.InvalidXref;
                    entry.offset = @intCast(fields[1]);
                    entry.generation = std.math.cast(u16, fields[2]) orelse return error.InvalidXref;
                    entry.live = true;
                },
                2 => {
                    if (id == 0 or fields[1] == 0 or fields[1] >= size or fields[2] >= maximum_objects) return error.InvalidXref;
                    entry.object_stream = @intCast(fields[1]);
                    entry.object_index = @intCast(fields[2]);
                    entry.live = true;
                },
                // Future entry types are interpreted as missing objects by ISO 32000.
                else => {},
            }
            records[cursor] = .{ .id = id, .entry = entry };
            cursor += 1;
        }
    }
    return .{ .records = records, .trailer = obj.value, .end = indirect.end, .stream = true };
}

fn revision(a: A, source: []const u8, free: bool, generation: u16) ![]u8 {
    const start = std.mem.lastIndexOf(u8, source, "startxref\n").? + 10;
    const end = std.mem.indexOfScalarPos(u8, source, start, '\n').?;
    const previous = try std.fmt.parseInt(usize, source[start..end], 10);
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(a);
    try out.appendSlice(a, source);
    const obj = out.items.len;
    const content = "BT /F1 12 Tf (Newest) Tj ET";
    try out.print(a, "5 {d} obj\n<< /Length {d} >>\nstream\n{s}\nendstream\nendobj\n", .{ generation, content.len, content });
    const xref = out.items.len;
    try out.appendSlice(a, "xref\n5 1\n");
    if (free) try out.appendSlice(a, "0000000000 00001 f \n") else try out.print(a, "{d:0>10} {d:0>5} n \n", .{ obj, generation });
    try out.print(a, "trailer\n<< /Size 6 /Prev {d} >>\nstartxref\n{d}\n%%EOF\n", .{ previous, xref });
    return out.toOwnedSlice(a);
}
test "latest revisions override objects, free entries mask older bodies, and generations remain exact" {
    const a = std.testing.allocator;
    const original = try @import("pod.zig").create(a, "Original");
    defer a.free(original);
    const updated = try revision(a, original, false, 0);
    defer a.free(updated);
    var doc = try d.Document.open(a, updated);
    defer doc.deinit();
    try std.testing.expectEqualStrings("Newest", (try doc.inspect())[0].runs[0].text);
    const saved = try doc.save(a);
    defer a.free(saved);
    try std.testing.expect(std.mem.indexOf(u8, saved, "Original") == null);
    try std.testing.expect(std.mem.indexOf(u8, saved, "/Prev") == null);
    var reopen = try d.Document.open(a, saved);
    defer reopen.deinit();
    try std.testing.expectEqualStrings("Newest", (try reopen.inspect())[0].runs[0].text);
    const freed = try revision(a, updated, true, 1);
    defer a.free(freed);
    var deleted = try d.Document.open(a, freed);
    defer deleted.deinit();
    try std.testing.expectError(error.MissingReference, deleted.inspect());
    const reused = try revision(a, freed, false, 1);
    defer a.free(reused);
    var changed = try d.Document.open(a, reused);
    defer changed.deinit();
    try std.testing.expectError(error.MissingReference, changed.object(.{ .id = 5, .generation = 0 }));
    _ = try changed.object(.{ .id = 5, .generation = 1 });
}

test "revision cycles and excessive chains are bounded" {
    const a = std.testing.allocator;
    const original = try @import("pod.zig").create(a, "Original");
    defer a.free(original);
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(a);
    try out.appendSlice(a, original);
    const at = out.items.len;
    try out.print(a, "xref\n5 1\n0000000009 00000 n \ntrailer\n<< /Size 6 /Prev {d} >>\nstartxref\n{d}\n%%EOF\n", .{ at, at });
    try std.testing.expectError(error.XrefCycle, d.Document.open(a, out.items));
    var bytes = try a.dupe(u8, original);
    defer a.free(bytes);
    for (0..128) |_| {
        const next = try revision(a, bytes, false, 0);
        a.free(bytes);
        bytes = next;
    }
    try std.testing.expectError(error.RevisionLimit, d.Document.open(a, bytes));
}

test "Pillow free object zero generation is normalized without accepting live overflow" {
    const a = std.testing.allocator;
    const original = try @import("pod.zig").create(a, "Palette");
    defer a.free(original);
    const at = std.mem.indexOf(u8, original, "65535 f").?;
    original[at + 4] = '6';
    var doc = try d.Document.open(a, original);
    defer doc.deinit();
    try std.testing.expectEqualStrings("Palette", (try doc.inspect())[0].runs[0].text);
    const saved = try doc.save(a);
    defer a.free(saved);
    try std.testing.expect(std.mem.indexOf(u8, saved, "65536") == null);
    try std.testing.expect(std.mem.indexOf(u8, saved, "65535 f") != null);
    original[at + 6] = 'n';
    try std.testing.expectError(error.InvalidXref, d.Document.open(a, original));
    original[at + 6] = 'f';
    original[at + 4] = '7';
    try std.testing.expectError(error.InvalidXref, d.Document.open(a, original));
    original[at + 4] = '5';
    const live_generation = std.mem.indexOfPos(u8, original, at, "00000 n").?;
    @memcpy(original[live_generation..][0..5], "65536");
    try std.testing.expectError(error.InvalidXref, d.Document.open(a, original));
}

fn compactXref(a: A, original: []const u8) ![]u8 {
    var doc = try d.Document.open(a, original);
    defer doc.deinit();
    const marker = std.mem.lastIndexOf(u8, original, "startxref\n").? + 10;
    const end = std.mem.indexOfScalarPos(u8, original, marker, '\n').?;
    const offset = try std.fmt.parseInt(usize, original[marker..end], 10);
    var records: [42]u8 = @splat(0);
    records[5] = 255;
    for (1..7) |id| {
        records[id * 6] = 1;
        std.mem.writeInt(u32, records[id * 6 + 1 ..][0..4], @intCast(if (id == 6) offset else doc.entries[id].offset), .big);
    }
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(a);
    try out.appendSlice(a, original[0..offset]);
    try out.print(a, "6 0 obj\n<< /Type /XRef /Root 1 0 R /Size 7 /W [1 4 1] /Length 42 >>\nstream\n{s}\nendstream\nendobj\nstartxref\n{d}\n%%EOF\n", .{ records, offset });
    return out.toOwnedSlice(a);
}

test "MuPDF compact xref object-zero sentinel normalizes only the unused free entry" {
    const a = std.testing.allocator;
    const original = try @import("pod.zig").create(a, "Compact");
    defer a.free(original);
    const bytes = try compactXref(a, original);
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    try std.testing.expectEqualStrings("Compact", (try doc.inspect())[0].runs[0].text);
    const saved = try doc.save(a);
    defer a.free(saved);
    var reopened = try d.Document.open(a, saved);
    defer reopened.deinit();
    try std.testing.expectEqualStrings("Compact", (try reopened.inspect())[0].runs[0].text);
    try std.testing.expectEqual(@as(u16, 65535), reopened.entries[0].generation);
    const at = std.mem.indexOfPos(u8, bytes, original.len / 2, "/Type /XRef").?;
    const data = std.mem.indexOfPos(u8, bytes, at, "stream\n").? + 7;
    bytes[data] = 1;
    try std.testing.expectError(error.InvalidXref, d.Document.open(a, bytes));
    bytes[data] = 0;
    bytes[data + 4] = 1;
    try std.testing.expectError(error.InvalidXref, d.Document.open(a, bytes));
    bytes[data + 4] = 0;
    bytes[data + 5] = 254;
    try std.testing.expectError(error.InvalidXref, d.Document.open(a, bytes));
    bytes[data + 5] = 255;
    bytes[data + 4 * 6 + 5] = 255;
    var live = try d.Document.open(a, bytes);
    defer live.deinit();
    try std.testing.expectEqual(@as(u16, 255), live.entries[4].generation);
}
