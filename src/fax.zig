//! CCITT T.4/T.6 bilevel fax decoding and PDF CCITTFaxDecode framing.
const std = @import("std");
const A = std.mem.Allocator;
pub const Options = struct {
    k: i64 = 0,
    columns: usize = 1728,
    rows: usize = 0,
    end_of_line: bool = false,
    byte_align: bool = false,
    end_of_block: bool = true,
    black_is_one: bool = false,
    damaged_rows: usize = 0,
};
pub const Result = struct { width: usize, height: usize, data: []u8, consumed: usize };
const Code = struct { length: u8 = 0, run: u16 = 0 };
const Reader = struct {
    bytes: []const u8,
    pos: usize = 0,
    work: usize = 0,
    fn remaining(self: Reader) usize {
        return self.bytes.len * 8 - self.pos;
    }
    fn peek(self: Reader, n: u5) u32 {
        var value: u32 = 0;
        for (0..n) |i| {
            value <<= 1;
            if (i < self.remaining()) value |= (self.bytes[(self.pos + i) / 8] >> @as(u3, @intCast(7 - (self.pos + i) % 8))) & 1;
        }
        return value;
    }
    fn consume(self: *Reader, n: usize) !void {
        if (n > self.remaining()) return error.TruncatedFax;
        if (n > 256 * 1024 * 1024 -| self.work) return error.FaxWorkLimit;
        self.pos += n;
        self.work += n;
    }
    fn bit(self: *Reader) !u1 {
        const value: u1 = @intCast(self.peek(1));
        try self.consume(1);
        return value;
    }
    fn byteAlign(self: *Reader) !void {
        while (self.pos % 8 != 0) if (try self.bit() != 0) return error.InvalidFaxPadding;
    }
    // Fill zeros before EOL are permitted by T.4, independently of byte alignment.
    fn eol(self: *Reader) !bool {
        const start = self.pos;
        while (self.remaining() != 0) {
            if (try self.bit() != 0) {
                if (self.pos - start >= 12) return true;
                break;
            }
        }
        self.pos = start;
        return false;
    }
    fn code(self: *Reader, black: bool) !usize {
        const table = if (black) &black_table else &white_table;
        const entry = table[self.peek(13)];
        if (entry.length == 0) return error.InvalidFaxCode;
        try self.consume(entry.length);
        return entry.run;
    }
    fn run(self: *Reader, black: bool, maximum: usize) !usize {
        var total: usize = 0;
        while (true) {
            const value = try self.code(black);
            if (value > maximum - total) return error.InvalidFaxRun;
            total += value;
            if (value < 64) return total;
        }
    }
    fn seekEOL(self: *Reader, start: usize) !void {
        self.pos = start;
        while (self.remaining() >= 12) {
            if (self.peek(12) == 1) return;
            try self.consume(1);
        }
        return error.TruncatedFax;
    }
};
const RowKind = enum { one, two, end };
fn header(reader: *Reader, options: Options) !RowKind {
    // Padding plus a valid run prefix can resemble EOL; align MH rows first.
    if (options.byte_align and !options.end_of_line) try reader.byteAlign();
    var eol = try reader.eol();
    if (!eol and options.byte_align and options.end_of_line) {
        try reader.byteAlign();
        eol = try reader.eol();
    }
    if (eol) {
        if (options.k < 0) return if (try reader.eol()) .end else .two;
        const tag = if (options.k > 0) try reader.bit() else 1;
        if (try reader.eol()) {
            if (tag != 1) return error.InvalidFaxEnd;
            // RTC has six EOLs; mixed Group 3 appends a 1-D tag to each.
            for (1..6) |i| {
                if (options.k > 0 and try reader.bit() != 1) return error.InvalidFaxEnd;
                if (i != 5 and !try reader.eol()) return error.InvalidFaxEnd;
            }
            return .end;
        }
        return if (tag == 1) .one else .two;
    }
    if (options.end_of_line) return error.InvalidFaxEOL;
    return if (options.k < 0) .two else if (options.k == 0 or try reader.bit() == 1) .one else .two;
}
fn isBlack(row: []const u8, x: usize) bool {
    return row[x / 8] & (@as(u8, 0x80) >> @as(u3, @intCast(x % 8))) != 0;
}
fn paint(row: []u8, left: usize, right: usize, black: bool) void {
    if (!black) return;
    for (left..right) |x| row[x / 8] |= @as(u8, 0x80) >> @as(u3, @intCast(x % 8));
}
fn decodeRow(reader: *Reader, row: []u8, changes: []const u32, width: usize, kind: RowKind) !void {
    var x: usize = 0;
    var black = false;
    var first = true;
    var reference: usize = 0;
    var operations: usize = 0;
    while (x < width) {
        operations += 1;
        if (operations > 2 * width + 16) return error.FaxWorkLimit;
        if (kind == .one) {
            const length = try reader.run(black, width - x);
            paint(row, x, x + length, black);
            x += length;
            black = !black;
            continue;
        }
        // Retain the first transition strictly to the right of a0 (including 0
        // for the imaginary white starting pixel). Parity selects opposite color.
        while (reference < changes.len and (changes[reference] < x or (!first and changes[reference] == x))) reference += 1;
        const index = reference + @intFromBool(reference % 2 != @intFromBool(black));
        const b1: usize = if (index < changes.len) changes[index] else width;
        const b2: usize = if (index + 1 < changes.len) changes[index + 1] else width;
        var code: u8 = 0;
        var mode: ?i8 = null;
        for (1..8) |length| {
            code = (code << 1) | try reader.bit();
            mode = switch (length) {
                1 => if (code == 1) 0 else null,
                3 => switch (code) {
                    1 => 10,
                    2 => -1,
                    3 => 1,
                    else => null,
                },
                4 => if (code == 1) 11 else null,
                6 => switch (code) {
                    2 => -2,
                    3 => 2,
                    else => null,
                },
                7 => switch (code) {
                    1 => return error.UnsupportedFaxExtension,
                    2 => -3,
                    3 => 3,
                    else => null,
                },
                else => null,
            };
            if (mode != null) break;
        }
        const value = mode orelse return error.InvalidFaxCode;
        if (value == 10) {
            const a = try reader.run(black, width - x);
            const b = try reader.run(!black, width - x - a);
            if (a + b == 0) return error.InvalidFaxRun;
            paint(row, x, x + a, black);
            paint(row, x + a, x + a + b, !black);
            x += a + b;
        } else if (value == 11) {
            if (b2 <= x) return error.InvalidFaxRun;
            paint(row, x, b2, black);
            x = b2;
        } else {
            const next = @as(i64, @intCast(b1)) + value;
            if (next < x or next > width) return error.InvalidFaxRun;
            const end: usize = @intCast(next);
            paint(row, x, end, black);
            x = end;
            black = !black;
        }
        first = false;
    }
}
pub fn decode(a: A, bytes: []const u8, options: Options, limit: usize) !Result {
    if (options.columns == 0 or options.columns > 65536 or options.rows > 65536 or options.damaged_rows > 65536) return error.InvalidDecodeParameters;
    const stride = (options.columns + 7) / 8;
    var current = try a.alloc(u8, stride);
    defer a.free(current);
    var previous = try a.alloc(u8, stride);
    defer a.free(previous);
    @memset(previous, 0);
    const transitions = try a.alloc(u32, options.columns + 2);
    defer a.free(transitions);
    transitions[0] = @intCast(options.columns);
    transitions[1] = @intCast(options.columns);
    var transition_count: usize = 2;
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(a);
    var reader = Reader{ .bytes = bytes };
    var height: usize = 0;
    var damaged: usize = 0;
    var last_damaged = false;
    while (true) {
        if (!options.end_of_block) {
            if (options.rows != 0 and height == options.rows) break;
            if (reader.remaining() == 0 or (reader.remaining() < 8 and reader.peek(8) == 0)) break;
        }
        const kind = try header(&reader, options);
        if (kind == .end) break;
        if (height == 0 and options.k > 0 and kind != .one) return error.InvalidFaxCode;
        if (height >= 65536 or options.columns * (height + 1) > 16 * 1024 * 1024 or stride > limit -| out.items.len) return error.DecodedStreamLimit;
        const start = reader.pos;
        @memset(current, 0);
        var row_damaged = false;
        decodeRow(&reader, current, transitions[0..transition_count], options.columns, kind) catch |err| {
            switch (err) {
                error.InvalidFaxCode, error.InvalidFaxRun, error.TruncatedFax => {},
                else => return err,
            }
            if (!options.end_of_line or options.k < 0 or damaged >= options.damaged_rows) return err;
            try reader.seekEOL(start);
            if (last_damaged) @memset(current, 0) else @memcpy(current, previous);
            damaged += 1;
            row_damaged = true;
        };
        last_damaged = row_damaged;
        const offset = out.items.len;
        try out.appendSlice(a, current);
        if (!options.black_is_one) for (out.items[offset..]) |*byte| {
            byte.* = ~byte.*;
        };
        transition_count = 0;
        var black = false;
        for (0..options.columns) |x| {
            const value = isBlack(current, x);
            if (value != black) {
                transitions[transition_count] = @intCast(x);
                transition_count += 1;
                black = value;
            }
        }
        transitions[transition_count] = @intCast(options.columns);
        transitions[transition_count + 1] = @intCast(options.columns);
        transition_count += 2;
        std.mem.swap([]u8, &current, &previous);
        height += 1;
    }
    return .{ .width = options.columns, .height = height, .data = try out.toOwnedSlice(a), .consumed = (reader.pos + 7) / 8 };
}
fn makeTable(comptime words: [104][]const u8) [8192]Code {
    @setEvalBranchQuota(200000);
    var table: [8192]Code = @splat(.{});
    for (words, 0..) |word, index| {
        const code = std.fmt.parseInt(usize, word, 2) catch unreachable;
        const padding: u4 = @intCast(13 - word.len);
        const count = @as(usize, 1) << padding;
        for (table[code << padding ..][0..count]) |*entry| {
            if (entry.length != 0) @compileError("Overlapping fax codes");
            entry.* = .{ .length = word.len, .run = if (index < 64) index else (index - 63) * 64 };
        }
    }
    return table;
}
// T.4/T.6 terminating and makeup code assignments, also published in RFC 804.
// https://www.rfc-editor.org/rfc/rfc804.txt (Tables 1a, 1b, 2a, 2b and 3).
const white_table = makeTable(.{
    "00110101",     "000111",       "0111",         "1000",         "1011",         "1100",         "1110",         "1111",
    "10011",        "10100",        "00111",        "01000",        "001000",       "000011",       "110100",       "110101",
    "101010",       "101011",       "0100111",      "0001100",      "0001000",      "0010111",      "0000011",      "0000100",
    "0101000",      "0101011",      "0010011",      "0100100",      "0011000",      "00000010",     "00000011",     "00011010",
    "00011011",     "00010010",     "00010011",     "00010100",     "00010101",     "00010110",     "00010111",     "00101000",
    "00101001",     "00101010",     "00101011",     "00101100",     "00101101",     "00000100",     "00000101",     "00001010",
    "00001011",     "01010010",     "01010011",     "01010100",     "01010101",     "00100100",     "00100101",     "01011000",
    "01011001",     "01011010",     "01011011",     "01001010",     "01001011",     "00110010",     "00110011",     "00110100",
    "11011",        "10010",        "010111",       "0110111",      "00110110",     "00110111",     "01100100",     "01100101",
    "01101000",     "01100111",     "011001100",    "011001101",    "011010010",    "011010011",    "011010100",    "011010101",
    "011010110",    "011010111",    "011011000",    "011011001",    "011011010",    "011011011",    "010011000",    "010011001",
    "010011010",    "011000",       "010011011",    "00000001000",  "00000001100",  "00000001101",  "000000010010", "000000010011",
    "000000010100", "000000010101", "000000010110", "000000010111", "000000011100", "000000011101", "000000011110", "000000011111",
});
const black_table = makeTable(.{
    "0000110111",    "010",           "11",            "10",            "011",           "0011",          "0010",          "00011",
    "000101",        "000100",        "0000100",       "0000101",       "0000111",       "00000100",      "00000111",      "000011000",
    "0000010111",    "0000011000",    "0000001000",    "00001100111",   "00001101000",   "00001101100",   "00000110111",   "00000101000",
    "00000010111",   "00000011000",   "000011001010",  "000011001011",  "000011001100",  "000011001101",  "000001101000",  "000001101001",
    "000001101010",  "000001101011",  "000011010010",  "000011010011",  "000011010100",  "000011010101",  "000011010110",  "000011010111",
    "000001101100",  "000001101101",  "000011011010",  "000011011011",  "000001010100",  "000001010101",  "000001010110",  "000001010111",
    "000001100100",  "000001100101",  "000001010010",  "000001010011",  "000000100100",  "000000110111",  "000000111000",  "000000100111",
    "000000101000",  "000001011000",  "000001011001",  "000000101011",  "000000101100",  "000001011010",  "000001100110",  "000001100111",
    "0000001111",    "000011001000",  "000011001001",  "000001011011",  "000000110011",  "000000110100",  "000000110101",  "0000001101100",
    "0000001101101", "0000001001010", "0000001001011", "0000001001100", "0000001001101", "0000001110010", "0000001110011", "0000001110100",
    "0000001110101", "0000001110110", "0000001110111", "0000001010010", "0000001010011", "0000001010100", "0000001010101", "0000001011010",
    "0000001011011", "0000001100100", "0000001100101", "00000001000",   "00000001100",   "00000001101",   "000000010010",  "000000010011",
    "000000010100",  "000000010101",  "000000010110",  "000000010111",  "000000011100",  "000000011101",  "000000011110",  "000000011111",
});

fn testPacked(comptime text: []const u8) [(text.len + 7) / 8]u8 {
    var data: [(text.len + 7) / 8]u8 = @splat(0);
    for (text, 0..) |bit, i| {
        if (bit == '1') data[i / 8] |= @as(u8, 0x80) >> @as(u3, @intCast(i % 8));
    }
    return data;
}
test "fax repeated makeup codes decode 6000-pixel white and black runs" {
    const data = testPacked("000000011111" ++ "000000011111" ++ "011010010" ++ "00001011" ++
        "00110101" ++ "000000011111" ++ "000000011111" ++ "0000001001101" ++ "000001100100");
    const image = try decode(std.testing.allocator, &data, .{ .columns = 6000, .rows = 2, .end_of_block = false }, 4096);
    defer std.testing.allocator.free(image.data);
    try std.testing.expectEqual(@as(usize, 1500), image.data.len);
    for (image.data[0..750]) |byte| try std.testing.expectEqual(@as(u8, 255), byte);
    for (image.data[750..]) |byte| try std.testing.expectEqual(@as(u8, 0), byte);
}
test "fax output limit and malformed runs are explicit errors" {
    const a = std.testing.allocator;
    const data = [_]u8{ 0xc0, 0x04, 0x00, 0x40 };
    try std.testing.expectError(error.DecodedStreamLimit, decode(a, &data, .{ .k = -1, .columns = 8 }, 1));
    const too_wide = testPacked("10011");
    try std.testing.expectError(error.InvalidFaxRun, decode(a, &too_wide, .{ .columns = 7, .rows = 1, .end_of_block = false }, 4096));
    const extension = testPacked("0000001111");
    try std.testing.expectError(error.UnsupportedFaxExtension, decode(a, &extension, .{ .k = -1, .columns = 8 }, 4096));
}
test "fax truncated streams and byte mutations release bounded allocations" {
    const a = std.testing.allocator;
    var data = [_]u8{ 0xc0, 0x04, 0x00, 0x40 };
    for (0..data.len) |end| {
        if (decode(a, data[0..end], .{ .k = -1, .columns = 8 }, 64)) |image| {
            a.free(image.data);
            return error.AcceptedTruncatedFax;
        } else |_| {}
    }
    for (0..data.len) |i| {
        const original = data[i];
        for (0..256) |value| {
            data[i] = @intCast(value);
            if (decode(a, &data, .{ .k = -1, .columns = 8 }, 64)) |image| {
                defer a.free(image.data);
                try std.testing.expect(image.data.len <= 64);
            } else |_| {}
        }
        data[i] = original;
    }
}
fn allocationCheck(a: A) !void {
    const image = try decode(a, &.{ 0xc0, 0x04, 0x00, 0x40 }, .{ .k = -1, .columns = 8 }, 4096);
    defer a.free(image.data);
    try std.testing.expectEqualSlices(u8, &.{ 255, 255 }, image.data);
}
test "fax allocation failures release row and transition buffers" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCheck, .{});
}

test "byte-aligned MH padding cannot become an optional EOL" {
    const first = testPacked("000111" ++ "000011010111");
    const second = testPacked("00000011" ++ "0000100");
    const data = first ++ second;
    const image = try decode(std.testing.allocator, &data, .{ .columns = 40, .rows = 2, .byte_align = true, .end_of_block = false }, 4096);
    defer std.testing.allocator.free(image.data);
    try std.testing.expectEqualSlices(u8, &.{ 0x80, 0, 0, 0, 0, 255, 255, 255, 0xfc, 0 }, image.data);
}
