const std = @import("std");
const Allocator = std.mem.Allocator;
pub const Ref = struct { id: u32, generation: u16 };
pub const Entry = struct { key: []const u8, value: Value };
pub const Value = union(enum) { null, boolean: bool, integer: i64, real: f64, name: []const u8, string: []const u8, array: []Value, dict: []Entry, ref: Ref };
pub fn ws(c: u8) bool {
    return c == 0 or c == 9 or c == 10 or c == 12 or c == 13 or c == 32;
}
pub fn delim(c: u8) bool {
    return ws(c) or std.mem.indexOfScalar(u8, "()<>[]{}/%", c) != null;
}
pub fn get(v: Value, key: []const u8) ?Value {
    if (v != .dict) return null;
    for (v.dict) |e| if (std.mem.eql(u8, e.key, key)) return e.value;
    return null;
}
pub fn number(v: Value) !f64 {
    return switch (v) {
        .integer => @floatFromInt(v.integer),
        .real => v.real,
        else => error.ExpectedNumber,
    };
}
pub fn uint(v: Value) !usize {
    if (v != .integer or v.integer < 0) return error.ExpectedUnsignedInteger;
    return std.math.cast(usize, v.integer) orelse error.IntegerOverflow;
}
pub const Parser = struct {
    bytes: []const u8,
    pos: usize = 0,
    allocator: Allocator,
    depth: usize = 0,
    nodes: usize = 0,
    pub fn skip(self: *Parser) void {
        while (self.pos < self.bytes.len) {
            if (ws(self.bytes[self.pos])) {
                self.pos += 1;
                continue;
            }
            if (self.bytes[self.pos] == '%') {
                while (self.pos < self.bytes.len and self.bytes[self.pos] != 10 and self.bytes[self.pos] != 13) self.pos += 1;
                continue;
            }
            break;
        }
    }
    pub fn token(self: *Parser) ![]const u8 {
        self.skip();
        const start = self.pos;
        while (self.pos < self.bytes.len and !delim(self.bytes[self.pos])) self.pos += 1;
        if (self.pos == start) return error.ExpectedToken;
        if (self.pos - start > 1048576) return error.TokenLimit;
        return self.bytes[start..self.pos];
    }
    pub fn keyword(self: *Parser, word: []const u8) bool {
        self.skip();
        const end = std.math.add(usize, self.pos, word.len) catch return false;
        if (end > self.bytes.len or !std.mem.eql(u8, self.bytes[self.pos..end], word) or (end < self.bytes.len and !delim(self.bytes[end]))) return false;
        self.pos = end;
        return true;
    }
    fn hex(c: u8) !u8 {
        return std.fmt.charToDigit(c, 16) catch error.InvalidHex;
    }
    pub fn value(self: *Parser) anyerror!Value {
        if (self.depth >= 64 or self.nodes >= 1000000) return error.SyntaxLimit;
        self.depth += 1;
        defer self.depth -= 1;
        self.nodes += 1;
        self.skip();
        if (self.pos == self.bytes.len) return error.UnexpectedEnd;
        const c = self.bytes[self.pos];
        self.pos += 1;
        if (c == '(') {
            var out: std.ArrayList(u8) = .empty;
            var nesting: usize = 1;
            while (self.pos < self.bytes.len) {
                var x = self.bytes[self.pos];
                self.pos += 1;
                if (x == '\\') {
                    if (self.pos == self.bytes.len) return error.UnexpectedEnd;
                    x = self.bytes[self.pos];
                    self.pos += 1;
                    switch (x) {
                        'n' => x = 10,
                        'r' => x = 13,
                        't' => x = 9,
                        'b' => x = 8,
                        'f' => x = 12,
                        10 => continue,
                        13 => {
                            if (self.pos < self.bytes.len and self.bytes[self.pos] == 10) self.pos += 1;
                            continue;
                        },
                        '0'...'7' => {
                            var n: u16 = x - '0';
                            var i: usize = 1;
                            while (i < 3 and self.pos < self.bytes.len and self.bytes[self.pos] >= '0' and self.bytes[self.pos] <= '7') : (i += 1) {
                                n = n * 8 + self.bytes[self.pos] - '0';
                                self.pos += 1;
                            }
                            x = @truncate(n);
                        },
                        else => {},
                    }
                } else if (x == '(') {
                    nesting += 1;
                    if (nesting > 64) return error.SyntaxLimit;
                } else if (x == ')') {
                    nesting -= 1;
                    if (nesting == 0) return .{ .string = try out.toOwnedSlice(self.allocator) };
                } else if (x == 13) {
                    x = 10;
                    if (self.pos < self.bytes.len and self.bytes[self.pos] == 10) self.pos += 1;
                }
                if (out.items.len >= 1048576) return error.TokenLimit;
                try out.append(self.allocator, x);
            }
            return error.UnexpectedEnd;
        }
        if (c == '/') {
            var out: std.ArrayList(u8) = .empty;
            while (self.pos < self.bytes.len and !delim(self.bytes[self.pos])) {
                var x = self.bytes[self.pos];
                self.pos += 1;
                if (x == '#') {
                    if (self.bytes.len - self.pos < 2) return error.InvalidName;
                    x = (try hex(self.bytes[self.pos])) * 16 + (try hex(self.bytes[self.pos + 1]));
                    self.pos += 2;
                }
                if (x == 0) return error.InvalidName;
                if (out.items.len >= 1048576) return error.TokenLimit;
                try out.append(self.allocator, x);
            }
            return .{ .name = try out.toOwnedSlice(self.allocator) };
        }
        if (c == '[') {
            var out: std.ArrayList(Value) = .empty;
            while (true) {
                self.skip();
                if (self.pos == self.bytes.len) return error.UnexpectedEnd;
                if (self.bytes[self.pos] == ']') {
                    self.pos += 1;
                    break;
                }
                try out.append(self.allocator, try self.value());
            }
            return .{ .array = try out.toOwnedSlice(self.allocator) };
        }
        if (c == '<') {
            if (self.pos < self.bytes.len and self.bytes[self.pos] == '<') {
                self.pos += 1;
                var out: std.ArrayList(Entry) = .empty;
                while (true) {
                    self.skip();
                    if (self.bytes.len - self.pos >= 2 and std.mem.eql(u8, self.bytes[self.pos..][0..2], ">>")) {
                        self.pos += 2;
                        break;
                    }
                    const key = try self.value();
                    if (key != .name) return error.ExpectedName;
                    for (out.items) |e| if (std.mem.eql(u8, e.key, key.name)) return error.DuplicateKey;
                    try out.append(self.allocator, .{ .key = key.name, .value = try self.value() });
                }
                return .{ .dict = try out.toOwnedSlice(self.allocator) };
            }
            var out: std.ArrayList(u8) = .empty;
            var high: ?u8 = null;
            while (self.pos < self.bytes.len) {
                const x = self.bytes[self.pos];
                self.pos += 1;
                if (x == '>') {
                    if (high) |h| try out.append(self.allocator, h * 16);
                    return .{ .string = try out.toOwnedSlice(self.allocator) };
                }
                if (ws(x)) continue;
                const n = try hex(x);
                if (high) |h| {
                    try out.append(self.allocator, h * 16 + n);
                    high = null;
                } else high = n;
                if (out.items.len > 1048576) return error.TokenLimit;
            }
            return error.UnexpectedEnd;
        }
        self.pos -= 1;
        const tok = try self.token();
        if (std.mem.eql(u8, tok, "true")) return .{ .boolean = true };
        if (std.mem.eql(u8, tok, "false")) return .{ .boolean = false };
        if (std.mem.eql(u8, tok, "null")) return .null;
        var dots: usize = 0;
        for (tok, 0..) |x, i| {
            if (x == '.') dots += 1 else if ((x == '+' or x == '-') and i == 0) {} else if (x < '0' or x > '9') return error.InvalidNumber;
        }
        if (dots > 1) return error.InvalidNumber;
        if (dots == 1) {
            const n = std.fmt.parseFloat(f64, tok) catch return error.InvalidNumber;
            if (!std.math.isFinite(n)) return error.InvalidNumber;
            return .{ .real = n };
        }
        const n = std.fmt.parseInt(i64, tok, 10) catch return error.InvalidNumber;
        const saved = self.pos;
        if (n >= 0 and n <= std.math.maxInt(u32)) {
            const gen = self.token() catch {
                self.pos = saved;
                return .{ .integer = n };
            };
            const g = std.fmt.parseInt(u16, gen, 10) catch {
                self.pos = saved;
                return .{ .integer = n };
            };
            if (self.keyword("R")) return .{ .ref = .{ .id = @intCast(n), .generation = g } };
        }
        self.pos = saved;
        return .{ .integer = n };
    }
};
test "bounded syntax values, escaped strings, references and numeric errors" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var p = Parser{ .bytes = "% comment\n[true false null -42 .5 /A#20B (one\\(two\\) (nested)\\n) <4142F> 12 0 R << /K 9 >>]", .allocator = arena.allocator() };
    const a = (try p.value()).array;
    try std.testing.expectEqual(@as(usize, 10), a.len);
    try std.testing.expect(a[0].boolean);
    try std.testing.expectEqual(@as(i64, -42), a[3].integer);
    try std.testing.expectEqual(@as(f64, 0.5), a[4].real);
    try std.testing.expectEqualStrings("A B", a[5].name);
    try std.testing.expectEqualStrings("one(two) (nested)\n", a[6].string);
    try std.testing.expectEqualSlices(u8, &.{ 65, 66, 240 }, a[7].string);
    try std.testing.expectEqual(@as(u32, 12), a[8].ref.id);
    for ([_][]const u8{ "9223372036854775808", "(unfinished", "<AZ>", "[", "<< /x >>", "1e20" }) |bad| {
        var q = Parser{ .bytes = bad, .allocator = arena.allocator() };
        if (q.value()) |_| return error.ExpectedRejection else |_| {}
    }
}
