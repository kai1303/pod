const std = @import("std");
const s = @import("syntax.zig");
const d = @import("document.zig");
const A = std.mem.Allocator;
const max_entries = 65536;
pub const Code = struct {
    value: u32,
    length: u8,
    pub fn key(self: Code) u64 {
        return (@as(u64, self.length) << 32) | self.value;
    }
};
pub const Range = struct {
    first: Code,
    last: Code,
    pub fn contains(self: Range, code: Code) bool {
        if (code.length != self.first.length) return false;
        var a = self.first.value;
        var b = self.last.value;
        var c = code.value;
        for (0..code.length) |_| {
            if ((c & 255) < (a & 255) or (c & 255) > (b & 255)) return false;
            a >>= 8;
            b >>= 8;
            c >>= 8;
        }
        return true;
    }
};
pub const Map = struct {
    ranges: std.ArrayList(Range) = .empty,
    entries: std.AutoHashMapUnmanaged(u64, []const u8) = .empty,
    name: ?[]const u8 = null,
    allocated_text: usize = 0,
    pub fn get(self: *const Map, value: u32, length: u8) ?[]const u8 {
        return self.entries.get((Code{ .value = value, .length = length }).key());
    }
    fn put(self: *Map, a: A, code: Code, utf16: []const u8) !void {
        if (self.entries.count() >= max_entries and !self.entries.contains(code.key())) return error.CMapLimit;
        const text = try decodeUTF16(a, utf16);
        self.allocated_text += text.len;
        if (self.allocated_text > 4 * 1024 * 1024) return error.CMapLimit;
        try self.entries.put(a, code.key(), text);
    }
};
fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
pub fn source(value: s.Value) !Code {
    if (value != .string or value.string.len == 0 or value.string.len > 4) return error.InvalidCMap;
    var code: u32 = 0;
    for (value.string) |byte| code = (code << 8) | byte;
    return .{ .value = code, .length = @intCast(value.string.len) };
}
pub fn range(p: *s.Parser) !Range {
    const first = try source(try p.value());
    const last = try source(try p.value());
    if (first.length != last.length or first.value > last.value) return error.InvalidCMap;
    return .{ .first = first, .last = last };
}
fn decodeUTF16(a: A, bytes: []const u8) ![]const u8 {
    if (bytes.len == 0 or bytes.len > 512 or bytes.len % 2 != 0) return error.InvalidCMapUnicode;
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < bytes.len) {
        const unit = std.mem.readInt(u16, bytes[i..][0..2], .big);
        i += 2;
        var cp: u21 = unit;
        if (unit >= 0xd800 and unit <= 0xdbff) {
            if (i == bytes.len) return error.InvalidCMapUnicode;
            const low = std.mem.readInt(u16, bytes[i..][0..2], .big);
            if (low < 0xdc00 or low > 0xdfff) return error.InvalidCMapUnicode;
            cp = 0x10000 + (@as(u21, unit) - 0xd800) * 1024 + (@as(u21, low) - 0xdc00);
            i += 2;
        } else if (unit >= 0xdc00 and unit <= 0xdfff) return error.InvalidCMapUnicode;
        var encoded: [4]u8 = undefined;
        const n = try std.unicode.utf8Encode(cp, &encoded);
        try out.appendSlice(a, encoded[0..n]);
    }
    return out.toOwnedSlice(a);
}
// Read declarative CMap syntax only; never execute PostScript from a document.
pub fn parse(a: A, bytes: []const u8, base: ?*const Map) !Map {
    if (bytes.len > 4 * 1024 * 1024) return error.CMapLimit;
    var map = Map{};
    if (base) |parent| {
        try map.ranges.appendSlice(a, parent.ranges.items);
        var it = parent.entries.iterator();
        while (it.next()) |entry| try map.entries.put(a, entry.key_ptr.*, entry.value_ptr.*);
        map.allocated_text = parent.allocated_text;
    }
    var p = s.Parser{ .allocator = a, .bytes = bytes };
    var operands: std.ArrayList(s.Value) = .empty;
    var started = false;
    var ended = false;
    var tokens: usize = 0;
    var mappings: usize = 0;
    while (true) {
        p.skip();
        if (p.pos == bytes.len) break;
        tokens += 1;
        if (tokens > 200000) return error.CMapLimit;
        const c = bytes[p.pos];
        if (c == '/' or c == '(' or c == '<' or c == '[' or c == '+' or c == '-' or c == '.' or std.ascii.isDigit(c)) {
            if (operands.items.len >= 32) return error.CMapLimit;
            try operands.append(a, try p.value());
            continue;
        }
        const op = try p.token();
        const args = operands.items;
        if (eq(op, "begincmap")) {
            if (started or args.len != 0) return error.InvalidCMap;
            started = true;
        } else if (eq(op, "endcmap")) {
            if (!started or ended or args.len != 0) return error.InvalidCMap;
            ended = true;
        } else if (eq(op, "begincodespacerange") or eq(op, "beginbfchar") or eq(op, "beginbfrange")) {
            if (!started or ended or args.len != 1) return error.InvalidCMap;
            const count = s.uint(args[0]) catch return error.InvalidCMap;
            if (count > max_entries) return error.CMapLimit;
            const spaces = eq(op, "begincodespacerange");
            const chars = eq(op, "beginbfchar");
            for (0..count) |_| {
                if (spaces) {
                    if (map.ranges.items.len >= 256) return error.CMapLimit;
                    const r = try range(&p);
                    // Every byte defines an inclusive lower/upper bound.
                    if (!r.contains(r.first) or !r.contains(r.last)) return error.InvalidCMap;
                    try map.ranges.append(a, r);
                } else if (chars) {
                    const code = try source(try p.value());
                    const target = try p.value();
                    if (target != .string) return error.InvalidCMap;
                    mappings += 1;
                    if (mappings > max_entries) return error.CMapLimit;
                    try map.put(a, code, target.string);
                } else {
                    const r = try range(&p);
                    const n: u64 = @as(u64, r.last.value) - r.first.value + 1;
                    if (n > max_entries - mappings) return error.CMapLimit;
                    mappings += @intCast(n);
                    const target = try p.value();
                    if (target == .array) {
                        if (target.array.len != n) return error.InvalidCMap;
                        for (target.array, 0..) |item, i| {
                            if (item != .string) return error.InvalidCMap;
                            try map.put(a, .{ .length = r.first.length, .value = r.first.value + @as(u32, @intCast(i)) }, item.string);
                        }
                    } else if (target == .string) {
                        const value = target.string;
                        if (value.len == 0 or value.len > 512 or value.len % 2 != 0) return error.InvalidCMapUnicode;
                        if (@as(u64, value[value.len - 1]) + n - 1 > 255) return error.InvalidCMapUnicode;
                        var buffer: [512]u8 = undefined;
                        @memcpy(buffer[0..value.len], value);
                        for (0..@as(usize, @intCast(n))) |i| {
                            buffer[value.len - 1] = value[value.len - 1] + @as(u8, @intCast(i));
                            try map.put(a, .{ .length = r.first.length, .value = r.first.value + @as(u32, @intCast(i)) }, buffer[0..value.len]);
                        }
                    } else return error.InvalidCMap;
                }
            }
            const end = if (spaces) "endcodespacerange" else if (chars) "endbfchar" else "endbfrange";
            if (!p.keyword(end)) return error.InvalidCMap;
        } else if (eq(op, "usecmap")) {
            if (!started or ended or args.len != 1 or args[0] != .name) return error.InvalidCMap;
            const parent = base orelse return error.UnsupportedPredefinedCMap;
            if (parent.name) |name| if (!eq(name, args[0].name)) return error.InvalidCMap;
        } else if (eq(op, "def")) {
            if (args.len == 2 and args[0] == .name) {
                if (eq(args[0].name, "CMapType") and (args[1] != .integer or args[1].integer != 2)) return error.InvalidCMap;
                if (eq(args[0].name, "CMapName")) {
                    if (args[1] != .name) return error.InvalidCMap;
                    map.name = args[1].name;
                }
            }
        } else {
            const boilerplate = [_][]const u8{ "findresource", "begin", "end", "dict", "dup", "CMapName", "currentdict", "defineresource", "pop" };
            var allowed = false;
            for (boilerplate) |word| if (eq(op, word)) {
                allowed = true;
                break;
            };
            if (!allowed) return error.UnsupportedCMapOperator;
        }
        operands.clearRetainingCapacity();
    }
    if (!started or !ended or operands.items.len != 0 or map.ranges.items.len == 0) return error.InvalidCMap;
    var it = map.entries.keyIterator();
    while (it.next()) |key| {
        const code = Code{ .length = @intCast(key.* >> 32), .value = @truncate(key.*) };
        var valid = false;
        for (map.ranges.items) |r| if (r.contains(code)) {
            valid = true;
            break;
        };
        if (!valid) return error.InvalidCMap;
    }
    return map;
}
pub fn load(doc: *d.Document, value: s.Value) !Map {
    var visited: [8]u32 = undefined;
    return loadInner(doc, value, &visited, 0);
}
fn loadInner(doc: *d.Document, value: s.Value, visited: *[8]u32, depth: usize) anyerror!Map {
    if (value == .name) return error.UnsupportedPredefinedCMap;
    if (value != .ref) return error.InvalidCMap;
    if (depth >= visited.len) return error.CMapLimit;
    for (visited[0..depth]) |id| if (id == value.ref.id) return error.CMapCycle;
    visited[depth] = value.ref.id;
    const obj = try doc.object(value.ref);
    if (obj.value != .dict or (obj.stream == null and obj.changed == null)) return error.InvalidCMap;
    var base: ?Map = null;
    if (s.get(obj.value, "UseCMap")) |parent| base = try loadInner(doc, parent, visited, depth + 1);
    return parse(doc.allocator(), try doc.streamData(obj), if (base) |*b| b else null);
}

test "bfchar bfrange arrays surrogate pairs and inherited overrides" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base = try parse(a,
        \\/CIDInit /ProcSet findresource begin 12 dict begin
        \\begincmap /CMapName /Base def /CMapType 2 def
        \\2 begincodespacerange <00> <ff> <0100> <01ff> endcodespacerange
        \\2 beginbfchar <41> <00660069> <0101> <d83dde00> endbfchar
        \\2 beginbfrange <50> <52> <0061> <60> <62> [<00660066> <00660069> <00660066006c>] endbfrange
        \\endcmap CMapName currentdict /CMap defineresource pop end end
    , null);
    try std.testing.expectEqualStrings("fi", base.get(0x41, 1).?);
    try std.testing.expectEqualStrings("😀", base.get(0x101, 2).?);
    try std.testing.expectEqualStrings("c", base.get(0x52, 1).?);
    try std.testing.expectEqualStrings("ffl", base.get(0x62, 1).?);
    try std.testing.expect(base.get(0x41, 2) == null);
    const child = try parse(a, "begincmap /Base usecmap 1 beginbfchar <41> <0058> endbfchar endcmap", &base);
    try std.testing.expectEqualStrings("X", child.get(0x41, 1).?);
    try std.testing.expectEqualStrings("c", child.get(0x52, 1).?);
    try std.testing.expectEqualStrings("fi", base.get(0x41, 1).?);
}

test "malformed Unicode maps and expansion limits fail explicitly" {
    const cases = .{
        .{ "begincmap endcmap", error.InvalidCMap },
        .{ "begincmap 1 begincodespacerange <00> <ff> endcodespacerange", error.InvalidCMap },
        .{ "begincmap 1 begincodespacerange <00> <ff> endcodespacerange 1 beginbfchar <41> <d800> endbfchar endcmap", error.InvalidCMapUnicode },
        .{ "begincmap 1 begincodespacerange <00> <ff> endcodespacerange 1 beginbfchar <41> <dc00> endbfchar endcmap", error.InvalidCMapUnicode },
        .{ "begincmap 1 begincodespacerange <00> <ff> endcodespacerange 1 beginbfchar <41> <d8000041> endbfchar endcmap", error.InvalidCMapUnicode },
        .{ "begincmap 1 begincodespacerange <00> <ff> endcodespacerange 1 beginbfchar <41> <00> endbfchar endcmap", error.InvalidCMapUnicode },
        .{ "begincmap 1 begincodespacerange <00> <ff> endcodespacerange 1 beginbfchar <41> <> endbfchar endcmap", error.InvalidCMapUnicode },
        .{ "begincmap 1 begincodespacerange <00> <ff> endcodespacerange 1 beginbfrange <41> <42> <00ff> endbfrange endcmap", error.InvalidCMapUnicode },
        .{ "begincmap 1 begincodespacerange <00> <ff> endcodespacerange 1 beginbfrange <41> <42> [<0041>] endbfrange endcmap", error.InvalidCMap },
        .{ "begincmap 1 begincodespacerange <00> <ff> endcodespacerange 1 beginbfchar <0141> <0041> endbfchar endcmap", error.InvalidCMap },
        .{ "begincmap 1 begincodespacerange <8140> <9ffc> endcodespacerange 1 beginbfchar <8200> <0041> endbfchar endcmap", error.InvalidCMap },
        .{ "begincmap 1 begincodespacerange <00000000> <ffffffff> endcodespacerange 1 beginbfrange <00000000> <ffffffff> <0000> endbfrange endcmap", error.CMapLimit },
        .{ "begincmap /Missing usecmap endcmap", error.UnsupportedPredefinedCMap },
        .{ "begincmap (file) run endcmap", error.UnsupportedCMapOperator },
        .{ "begincmap 1 begincodespacerange <00> <ff> endcodespacerange /CMapType 1 def endcmap", error.InvalidCMap },
    };
    inline for (cases) |case| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        try std.testing.expectError(case[1], parse(arena.allocator(), case[0], null));
    }
}
