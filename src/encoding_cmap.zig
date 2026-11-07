const std = @import("std");
const s = @import("syntax.zig");
const d = @import("document.zig");
const unicode = @import("to_unicode.zig");
pub const Code = unicode.Code;
const Range = unicode.Range;
const A = std.mem.Allocator;
const Notdef = struct { range: Range, cid: u16 };
pub const Map = struct {
    spaces: std.ArrayList(Range) = .empty,
    entries: std.AutoHashMapUnmanaged(u64, u16) = .empty,
    notdef: std.ArrayList(Notdef) = .empty,
    identity: bool = false,
    vertical: bool = false,
    declared_mode: ?bool = null,
    name: ?[]const u8 = null,
    pub fn contains(self: *const Map, code: Code) bool {
        for (self.spaces.items) |space| if (space.contains(code)) return true;
        return false;
    }
    pub fn cid(self: *const Map, code: Code) u16 {
        if (self.entries.get(code.key())) |id| return id;
        if (self.identity and code.length == 2) return @intCast(code.value);
        var i = self.notdef.items.len;
        while (i != 0) {
            i -= 1;
            const fallback = self.notdef.items[i];
            if (fallback.range.contains(code)) return fallback.cid;
        }
        return 0;
    }
    pub fn next(self: *const Map, text: []const u8, at: *usize) !?Code {
        if (at.* == text.len) return null;
        var code = Code{ .value = 0, .length = 0 };
        while (at.* < text.len and code.length < 4) {
            code.value = (code.value << 8) | text[at.*];
            code.length += 1;
            at.* += 1;
            if (self.contains(code)) return code;
        }
        return error.InvalidCharacterCode;
    }
};
fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
fn identity(a: A, vertical: bool) !Map {
    var result = Map{ .identity = true, .vertical = vertical, .name = if (vertical) "Identity-V" else "Identity-H" };
    try result.spaces.append(a, .{ .first = .{ .value = 0, .length = 2 }, .last = .{ .value = 65535, .length = 2 } });
    return result;
}
fn byte(code: Code, i: u8) u8 {
    return @truncate(code.value >> @as(u5, @intCast((code.length - 1 - i) * 8)));
}
fn validateSpaces(map: *const Map) !void {
    if (map.spaces.items.len == 0 or map.spaces.items.len > 256) return error.InvalidCMap;
    for (map.spaces.items, 0..) |left, i| {
        if (!left.contains(left.first) or !left.contains(left.last)) return error.InvalidCMap;
        for (map.spaces.items[0..i]) |right| {
            if (left.first.key() == right.first.key() and left.last.key() == right.last.key()) continue;
            var overlap = true;
            var j: u8 = 0;
            while (j < @min(left.first.length, right.first.length)) : (j += 1) {
                if (byte(left.first, j) > byte(right.last, j) or byte(right.first, j) > byte(left.last, j)) {
                    overlap = false;
                    break;
                }
            }
            if (overlap) return error.AmbiguousCMap;
        }
    }
}
fn rangeSize(r: Range) !u64 {
    var size: u64 = 1;
    var i: u8 = 0;
    while (i < r.first.length) : (i += 1) {
        const lo = byte(r.first, i);
        const hi = byte(r.last, i);
        if (lo > hi) return error.InvalidCMap;
        size *= @as(u64, hi) - lo + 1;
    }
    return size;
}
fn rangeCode(r: Range, index: u64) Code {
    var code = Code{ .value = 0, .length = r.first.length };
    var offset = index;
    var i = r.first.length;
    while (i != 0) {
        i -= 1;
        const lo = byte(r.first, i);
        const count = @as(u64, byte(r.last, i)) - lo + 1;
        code.value |= @as(u32, @intCast(lo + offset % count)) << @as(u5, @intCast((r.first.length - 1 - i) * 8));
        offset /= count;
    }
    return code;
}
fn cidValue(value: s.Value) !u16 {
    const n = s.uint(value) catch return error.InvalidCMap;
    if (n > 65535) return error.InvalidCMap;
    return @intCast(n);
}
pub fn parse(a: A, bytes: []const u8, base: ?*const Map) !Map {
    if (bytes.len > 4 * 1024 * 1024) return error.CMapLimit;
    var result = Map{};
    if (base) |parent| {
        result.identity = parent.identity;
        try result.spaces.appendSlice(a, parent.spaces.items);
        try result.notdef.appendSlice(a, parent.notdef.items);
        var it = parent.entries.iterator();
        while (it.next()) |entry| try result.entries.put(a, entry.key_ptr.*, entry.value_ptr.*);
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
        const ch = p.bytes[p.pos];
        if (ch == '/' or ch == '(' or ch == '<' or ch == '[' or ch == '+' or ch == '-' or ch == '.' or std.ascii.isDigit(ch)) {
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
        } else if (eq(op, "begincodespacerange") or eq(op, "begincidchar") or eq(op, "begincidrange") or eq(op, "beginnotdefchar") or eq(op, "beginnotdefrange")) {
            if (!started or ended or args.len != 1) return error.InvalidCMap;
            const count = s.uint(args[0]) catch return error.InvalidCMap;
            if (count > 65536) return error.CMapLimit;
            const spaces = eq(op, "begincodespacerange");
            const single = eq(op, "begincidchar") or eq(op, "beginnotdefchar");
            const fallback = std.mem.startsWith(u8, op, "beginnotdef");
            for (0..count) |_| {
                if (spaces) {
                    if (result.spaces.items.len >= 256) return error.CMapLimit;
                    try result.spaces.append(a, try unicode.range(&p));
                } else {
                    const range = if (single) blk: {
                        const code = try unicode.source(try p.value());
                        break :blk Range{ .first = code, .last = code };
                    } else try unicode.range(&p);
                    const cid = try cidValue(try p.value());
                    const size = try rangeSize(range);
                    if (fallback) {
                        if (result.notdef.items.len >= 256) return error.CMapLimit;
                        try result.notdef.append(a, .{ .range = range, .cid = cid });
                    } else {
                        if (size > 65536 - mappings or @as(u64, cid) + range.last.value - range.first.value >= 65536) return error.CMapLimit;
                        mappings += @intCast(size);
                        for (0..@as(usize, @intCast(size))) |i| {
                            const code = rangeCode(range, i);
                            // CID offsets retain numeric gaps between codespace rows.
                            try result.entries.put(a, code.key(), @intCast(@as(u64, cid) + code.value - range.first.value));
                        }
                        if (result.entries.count() > 65536) return error.CMapLimit;
                    }
                }
            }
            const end = if (spaces) "endcodespacerange" else if (fallback) (if (single) "endnotdefchar" else "endnotdefrange") else if (single) "endcidchar" else "endcidrange";
            if (!p.keyword(end)) return error.InvalidCMap;
        } else if (eq(op, "usecmap")) {
            if (!started or ended or args.len != 1 or args[0] != .name) return error.InvalidCMap;
            if (base) |parent| {
                if (parent.name) |name| if (!eq(name, args[0].name)) return error.InvalidCMap;
            } else if ((eq(args[0].name, "Identity-H") or eq(args[0].name, "Identity-V")) and result.spaces.items.len == 0 and mappings == 0 and result.notdef.items.len == 0) {
                const parent = try identity(a, eq(args[0].name, "Identity-V"));
                result.identity = true;
                try result.spaces.appendSlice(a, parent.spaces.items);
            } else return error.UnsupportedPredefinedCMap;
        } else if (eq(op, "def")) {
            if (args.len == 2 and args[0] == .name) {
                const key = args[0].name;
                if (eq(key, "WMode")) {
                    result.vertical = try writingMode(args[1]);
                    result.declared_mode = result.vertical;
                }
                if (eq(key, "CMapType") and (args[1] != .integer or args[1].integer != 1)) return error.InvalidCMap;
                if (eq(key, "CMapName")) {
                    if (args[1] != .name) return error.InvalidCMap;
                    result.name = args[1].name;
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
    if (!started or !ended or operands.items.len != 0) return error.InvalidCMap;
    try validateSpaces(&result);
    var it = result.entries.keyIterator();
    while (it.next()) |key| if (!result.contains(.{ .value = @truncate(key.*), .length = @intCast(key.* >> 32) })) return error.InvalidCMap;
    for (result.notdef.items) |fallback| {
        // A fallback rectangle must fit a codespace rectangle; it is not expanded.
        var fits = false;
        for (result.spaces.items) |space| if (space.contains(fallback.range.first) and space.contains(fallback.range.last)) {
            fits = true;
            break;
        };
        if (!fits) return error.InvalidCMap;
    }
    return result;
}
fn writingMode(value: s.Value) !bool {
    if (value != .integer or value.integer < 0 or value.integer > 1) return error.InvalidCMap;
    return value.integer == 1;
}
pub fn load(doc: *d.Document, value: s.Value) !Map {
    var visited: [8]u32 = undefined;
    return loadInner(doc, value, &visited, 0);
}
fn loadInner(doc: *d.Document, value: s.Value, visited: *[8]u32, depth: usize) anyerror!Map {
    const resolved = try doc.resolve(value);
    if (resolved == .name) {
        if (eq(resolved.name, "Identity-H") or eq(resolved.name, "Identity-V")) return identity(doc.allocator(), eq(resolved.name, "Identity-V"));
        return error.UnsupportedCMapEncoding;
    }
    if (value != .ref or resolved != .dict) return error.InvalidCMap;
    if (depth >= visited.len) return error.CMapLimit;
    for (visited[0..depth]) |id| if (id == value.ref.id) return error.CMapCycle;
    visited[depth] = value.ref.id;
    const obj = try doc.object(value.ref);
    const typ = s.get(obj.value, "Type") orelse return error.InvalidCMap;
    if (typ != .name or !eq(typ.name, "CMap")) return error.InvalidCMap;
    var base: ?Map = null;
    if (s.get(obj.value, "UseCMap")) |parent| base = try loadInner(doc, parent, visited, depth + 1);
    var result = try parse(doc.allocator(), try doc.streamData(obj), if (base) |*b| b else null);
    if (s.get(obj.value, "WMode")) |raw| {
        const mode = try writingMode(try doc.resolve(raw));
        if (result.declared_mode) |declared| if (declared != mode) return error.InvalidCMap;
        result.vertical = mode;
    }
    if (s.get(obj.value, "CMapName")) |raw| {
        const name = try doc.resolve(raw);
        if (name != .name) return error.InvalidCMap;
        if (result.name) |actual| if (!eq(name.name, actual)) return error.InvalidCMap;
    }
    return result;
}

test "codespaces distinguish equal values with different byte lengths" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const map = try parse(arena.allocator(), "begincmap 2 begincodespacerange <01> <7f> <0000> <00ff> endcodespacerange 2 begincidchar <01> 2 <0001> 3 endcidchar endcmap", null);
    var at: usize = 0;
    const one = (try map.next("\x01\x00\x01", &at)).?;
    const two = (try map.next("\x01\x00\x01", &at)).?;
    try std.testing.expectEqual(@as(u16, 2), map.cid(one));
    try std.testing.expectEqual(@as(u16, 3), map.cid(two));
    try std.testing.expect(one.key() != two.key());
    try std.testing.expect(try map.next("\x01\x00\x01", &at) == null);
    at = 0;
    try std.testing.expectError(error.InvalidCharacterCode, map.next("\x00", &at));
}

test "notdef rectangles stay bounded and ordinary mappings override fallbacks" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const map = try parse(arena.allocator(), "begincmap 1 begincodespacerange <00000000> <ffffffff> endcodespacerange 1 beginnotdefrange <00000000> <ffffffff> 7 endnotdefrange 1 begincidchar <12345678> 9 endcidchar endcmap", null);
    try std.testing.expectEqual(@as(usize, 1), map.notdef.items.len);
    try std.testing.expectEqual(@as(u32, 1), map.entries.count());
    try std.testing.expectEqual(@as(u16, 7), map.cid(.{ .value = 0xffffffff, .length = 4 }));
    try std.testing.expectEqual(@as(u16, 9), map.cid(.{ .value = 0x12345678, .length = 4 }));
}

test "CID CMap malformed ranges and expansion limits fail explicitly" {
    const cases = .{
        .{ "begincmap 2 begincodespacerange <00> <ff> <8100> <81ff> endcodespacerange endcmap", error.AmbiguousCMap },
        .{ "begincmap 1 begincodespacerange <8142> <8240> endcodespacerange endcmap", error.InvalidCMap },
        .{ "begincmap 1 begincodespacerange <00> <7f> endcodespacerange 1 begincidchar <ff> 1 endcidchar endcmap", error.InvalidCMap },
        .{ "begincmap 1 begincodespacerange <00000000> <ffffffff> endcodespacerange 1 begincidrange <00000000> <ffffffff> 0 endcidrange endcmap", error.CMapLimit },
        .{ "begincmap 1 begincodespacerange <00> <ff> endcodespacerange 1 begincidrange <40> <41> 65535 endcidrange endcmap", error.CMapLimit },
    };
    inline for (cases) |case| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        try std.testing.expectError(case[1], parse(arena.allocator(), case[0], null));
    }
}

test "CID ranges retain numeric offsets across codespace byte gaps" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const map = try parse(arena.allocator(), "begincmap 1 begincodespacerange <8140> <8242> endcodespacerange 1 begincidrange <8140> <8242> 1 endcidrange endcmap", null);
    try std.testing.expectEqual(@as(u16, 259), map.cid(.{ .value = 0x8242, .length = 2 }));
    try std.testing.expectEqual(@as(u16, 257), map.cid(.{ .value = 0x8240, .length = 2 }));
    try std.testing.expect(!map.contains(.{ .value = 0x8200, .length = 2 }));
}

test "embedded CMap inherits codespaces and overrides parent mappings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const parent = try parse(a, "begincmap /CMapName /Parent def 2 begincodespacerange <00> <7f> <8100> <81ff> endcodespacerange 2 begincidchar <41> 3 <8142> 4 endcidchar endcmap", null);
    const child = try parse(a, "begincmap /Parent usecmap 1 begincidchar <41> 2 endcidchar endcmap", &parent);
    try std.testing.expectEqual(@as(u16, 3), parent.cid(.{ .value = 0x41, .length = 1 }));
    try std.testing.expectEqual(@as(u16, 2), child.cid(.{ .value = 0x41, .length = 1 }));
    var at: usize = 0;
    const code = (try child.next("\x81\x42", &at)).?;
    try std.testing.expectEqual(@as(u16, 4), child.cid(code));
}

test "CMaps inherit mappings but select their own writing mode" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const parent = try parse(a, "begincmap /CMapName /Parent def /WMode 1 def 1 begincodespacerange <00> <ff> endcodespacerange endcmap", null);
    const inherited = try parse(a, "begincmap /Parent usecmap endcmap", &parent);
    const horizontal = try parse(a, "begincmap /Parent usecmap /WMode 0 def endcmap", &parent);
    const predefined = try parse(a, "begincmap /Identity-V usecmap endcmap", null);
    const vertical = try parse(a, "begincmap /Identity-V usecmap /WMode 1 def endcmap", null);
    try std.testing.expect(parent.vertical and vertical.vertical);
    try std.testing.expect(!inherited.vertical and !horizontal.vertical and !predefined.vertical);
    try std.testing.expectError(error.InvalidCMap, parse(a, "begincmap /Identity-V usecmap /WMode 2 def endcmap", null));
}
