const std = @import("std");
test "font rejects truncated table directories" {
    try std.testing.expectError(error.InvalidFont, Font.init(&.{}));
    try std.testing.expectError(error.InvalidFont, Font.init(&.{ 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0 }));
}

// Microsoft OpenType: spec/{glyf,cmap,loca}. TrueType hints are intentionally
// skipped: rasterization uses unhinted outlines and subpixel coverage.
pub const Point = struct { x: f64, y: f64, on: bool };
pub const Outline = struct { points: std.ArrayList(Point) = .empty, ends: std.ArrayList(usize) = .empty };
fn slice(b: []const u8, at: usize, n: usize) ![]const u8 {
    if (at > b.len or n > b.len - at) return error.InvalidFont;
    return b[at..][0..n];
}
fn u16be(b: []const u8, at: usize) !u16 {
    return std.mem.readInt(u16, (try slice(b, at, 2))[0..2], .big);
}
fn i16be(b: []const u8, at: usize) !i16 {
    return @bitCast(try u16be(b, at));
}
fn u32be(b: []const u8, at: usize) !u32 {
    return std.mem.readInt(u32, (try slice(b, at, 4))[0..4], .big);
}
fn optionalTable(bytes: []const u8, tag: []const u8) !?[]const u8 {
    const count = try u16be(bytes, 4);
    if (count > 128) return error.InvalidFont;
    for (0..count) |i| {
        const at = 12 + i * 16;
        const entry = try slice(bytes, at, 16);
        if (std.mem.eql(u8, entry[0..4], tag)) return try slice(bytes, try u32be(entry, 8), try u32be(entry, 12));
    }
    return null;
}
fn table(bytes: []const u8, tag: []const u8) ![]const u8 {
    return try optionalTable(bytes, tag) orelse error.InvalidFont;
}
pub const Font = struct {
    glyf: []const u8,
    loca: []const u8,
    cmap: []const u8,
    cmap_table: []const u8 = &.{},
    units: f64,
    glyphs: u16,
    long_loca: bool,
    pub fn init(bytes: []const u8) !Font {
        const scaler = try u32be(bytes, 0);
        // Apple 'true' fonts contain the same glyf/loca TrueType outlines.
        if (scaler != 0x00010000 and scaler != 0x74727565) return error.InvalidFont;
        const head = try table(bytes, "head");
        if (try u32be(head, 0) != 0x00010000 or try u32be(head, 12) != 0x5f0f3cf5) return error.InvalidFont;
        const units = try u16be(head, 18);
        const loc = try i16be(head, 50);
        if (units < 16 or units > 16384 or (loc != 0 and loc != 1)) return error.InvalidFont;
        const cm = try optionalTable(bytes, "cmap") orelse &.{};
        if (cm.len != 0 and try u16be(cm, 0) != 0) return error.InvalidFont;
        const count = if (cm.len == 0) 0 else try u16be(cm, 2);
        if (count > 128) return error.InvalidFont;
        if (cm.len != 0) _ = try slice(cm, 4, @as(usize, count) * 8);
        const maxp = try table(bytes, "maxp");
        if (try u32be(maxp, 0) != 0x00010000 or maxp.len < 32) return error.InvalidFont;
        var result = Font{ .glyf = try table(bytes, "glyf"), .loca = try table(bytes, "loca"), .cmap = &.{}, .cmap_table = cm, .units = @floatFromInt(units), .glyphs = try u16be(maxp, 4), .long_loca = loc == 1 };
        if (result.glyphs == 0) return error.InvalidFont;
        const horizontal = try table(bytes, "hhea");
        if (try u32be(horizontal, 0) != 0x00010000) return error.InvalidFont;
        const count_metrics = try u16be(horizontal, 34);
        if (count_metrics == 0 or count_metrics > result.glyphs) return error.InvalidFont;
        const metrics = try table(bytes, "hmtx");
        _ = try slice(metrics, 0, @as(usize, count_metrics) * 4 + @as(usize, result.glyphs - count_metrics) * 2);
        var previous: usize = 0;
        for (0..@as(usize, result.glyphs) + 1) |i| {
            const at = try result.offset(i);
            if (at < previous or at > result.glyf.len) return error.InvalidFont;
            previous = at;
        }
        // Unicode platform records are used for host fonts; PDF symbolic fonts
        // explicitly select their Windows Symbol or Macintosh subtable below.
        for (0..count) |i| {
            const at = 4 + i * 8;
            if (try u16be(cm, at) == 0) {
                const offset_ = try u32be(cm, at + 4);
                const format = try u16be(cm, offset_);
                if (format != 0 and format != 4 and format != 6 and format != 12) continue;
                const sub = try result.subtableAt(offset_);
                result.cmap = sub;
                break;
            }
        }
        if (try result.subtable(3, 1)) |sub| result.cmap = sub;
        if (try result.subtable(3, 10)) |sub| result.cmap = sub;
        return result;
    }
    fn subtableAt(self: Font, offset_: usize) ![]const u8 {
        const cm = self.cmap_table;
        const format = try u16be(cm, offset_);
        const length: usize = switch (format) {
            0, 4, 6 => try u16be(cm, offset_ + 2),
            12 => try u32be(cm, offset_ + 4),
            else => return error.UnsupportedFontCmap,
        };
        const sub = try slice(cm, offset_, length);
        switch (format) {
            0 => {
                if (length < 262) return error.InvalidFont;
            },
            6 => {
                _ = try slice(sub, 10, @as(usize, try u16be(sub, 8)) * 2);
            },
            4 => {
                const n = try u16be(sub, 6);
                if (n == 0 or n % 2 != 0 or n / 2 > 8192) return error.InvalidFont;
                const segments = n / 2;
                _ = try slice(sub, 0, 16 + @as(usize, segments) * 8);
                var previous: u16 = 0;
                for (0..segments) |i| {
                    const last = try u16be(sub, 14 + 2 * i);
                    const first = try u16be(sub, 16 + 2 * segments + 2 * i);
                    if (first > last or (i != 0 and first <= previous)) return error.InvalidFont;
                    previous = last;
                }
            },
            12 => {
                const count = try u32be(sub, 12);
                if (count > 65536) return error.FontLimit;
                _ = try slice(sub, 16, @as(usize, count) * 12);
                var previous: u32 = 0;
                for (0..count) |i| {
                    const at = 16 + 12 * i;
                    const first = try u32be(sub, at);
                    const last = try u32be(sub, at + 4);
                    const gid = try u32be(sub, at + 8);
                    if (first > last or (i != 0 and first <= previous) or last > 0x10ffff or @as(u64, gid) + last - first >= self.glyphs) return error.InvalidFont;
                    previous = last;
                }
            },
            else => unreachable,
        }
        return sub;
    }
    pub fn subtable(self: Font, platform: u16, encoding: u16) !?[]const u8 {
        if (self.cmap_table.len == 0) return null;
        const count = try u16be(self.cmap_table, 2);
        for (0..count) |i| {
            const at = 4 + i * 8;
            if (try u16be(self.cmap_table, at) == platform and try u16be(self.cmap_table, at + 2) == encoding)
                return try self.subtableAt(try u32be(self.cmap_table, at + 4));
        }
        return null;
    }
    pub fn mappedGlyph(self: Font, cm: []const u8, c: u32) !u16 {
        const format = try u16be(cm, 0);
        const g: u32 = switch (format) {
            0 => if (c < 256) (try slice(cm, 6 + @as(usize, c), 1))[0] else 0,
            6 => blk: {
                const first = try u16be(cm, 6);
                const count = try u16be(cm, 8);
                break :blk if (c >= first and c - first < count) try u16be(cm, 10 + 2 * (@as(usize, c) - first)) else 0;
            },
            12 => blk: {
                var low: usize = 0;
                var high: usize = try u32be(cm, 12);
                while (low < high) {
                    const mid = low + (high - low) / 2;
                    const at = 16 + 12 * mid;
                    const first = try u32be(cm, at);
                    const last = try u32be(cm, at + 4);
                    if (c < first) high = mid else if (c > last) low = mid + 1 else break :blk try u32be(cm, at + 8) + (c - first);
                }
                break :blk 0;
            },
            4 => blk: {
                if (c > 65535) break :blk 0;
                const segments = (try u16be(cm, 6)) / 2;
                if (segments == 0 or segments > 8192) return error.InvalidFont;
                for (0..segments) |i| {
                    const end = try u16be(cm, 14 + 2 * i);
                    const start = try u16be(cm, 16 + 2 * segments + 2 * i);
                    if (c < start or c > end) continue;
                    const delta = try u16be(cm, 16 + 4 * segments + 2 * i);
                    const range_at = 16 + 6 * segments + 2 * i;
                    const range_offset = try u16be(cm, range_at);
                    if (range_offset == 0) break :blk @as(u16, @intCast(c)) +% delta;
                    const raw = try u16be(cm, range_at + range_offset + 2 * (@as(usize, c) - start));
                    break :blk if (raw == 0) 0 else raw +% delta;
                }
                break :blk 0;
            },
            else => return error.UnsupportedFontCmap,
        };
        if (g >= self.glyphs) return error.InvalidFont;
        if (g == 0) return error.MissingGlyph;
        return @intCast(g);
    }
    pub fn glyph(self: Font, c: u21) !u16 {
        if (self.cmap.len == 0) return error.UnsupportedFontCmap;
        return self.mappedGlyph(self.cmap, c);
    }
    pub fn glyphBounds(self: Font, id: u16) ![4]f64 {
        if (id >= self.glyphs) return error.InvalidFont;
        const begin = try self.offset(id);
        const end = try self.offset(@as(usize, id) + 1);
        const b = try slice(self.glyf, begin, end - begin);
        if (b.len == 0) return .{ 0, 0, 0, 0 };
        var bounds: [4]f64 = undefined;
        for (&bounds, 0..) |*v, i| v.* = @floatFromInt(try i16be(b, 2 + 2 * i));
        if (bounds[0] > bounds[2] or bounds[1] > bounds[3]) return error.InvalidFont;
        return bounds;
    }

    fn offset(self: Font, id: usize) !usize {
        return if (self.long_loca) try u32be(self.loca, id * 4) else @as(usize, try u16be(self.loca, id * 2)) * 2;
    }
    pub fn outline(self: Font, a: std.mem.Allocator, id: u16, out: *Outline) !void {
        var work: usize = 0;
        try self.decode(a, id, out, 0, &work);
    }
    fn decode(self: Font, a: std.mem.Allocator, id: u16, out: *Outline, depth: usize, work: *usize) anyerror!void {
        work.* += 1;
        if (work.* > 16384) return error.FontLimit;
        if (depth >= 8 or id >= self.glyphs or out.points.items.len > 16384) return error.FontLimit;
        const begin = try self.offset(id);
        const end = try self.offset(@as(usize, id) + 1);
        if (end < begin) return error.InvalidFont;
        const b = try slice(self.glyf, begin, end - begin);
        if (b.len == 0) return;
        const contours = try i16be(b, 0);
        var pos: usize = 10;
        if (contours < 0) {
            const root = out.points.items.len;
            var has_instructions = false;
            var parts: usize = 0;
            while (true) {
                parts += 1;
                if (parts > 64) return error.FontLimit;
                const flags = try u16be(b, pos);
                const child = try u16be(b, pos + 2);
                pos += 4;
                if (flags & 0x1800 == 0x1800 or @popCount(flags & (8 | 64 | 128)) > 1) return error.InvalidFont;
                has_instructions = has_instructions or flags & 0x100 != 0;
                const xy = flags & 2 != 0;
                var parent_point: usize = 0;
                var child_point: usize = 0;
                var dx: f64 = 0;
                var dy: f64 = 0;
                if (flags & 1 != 0) {
                    if (xy) {
                        dx = @floatFromInt(try i16be(b, pos));
                        dy = @floatFromInt(try i16be(b, pos + 2));
                    } else {
                        parent_point = try u16be(b, pos);
                        child_point = try u16be(b, pos + 2);
                    }
                    pos += 4;
                } else {
                    const args = try slice(b, pos, 2);
                    if (xy) {
                        dx = @floatFromInt(@as(i8, @bitCast(args[0])));
                        dy = @floatFromInt(@as(i8, @bitCast(args[1])));
                    } else {
                        parent_point = args[0];
                        child_point = args[1];
                    }
                    pos += 2;
                }
                var m: [4]f64 = .{ 1, 0, 0, 1 };
                if (flags & 8 != 0) {
                    m[0] = @as(f64, @floatFromInt(try i16be(b, pos))) / 16384;
                    m[3] = m[0];
                    pos += 2;
                } else if (flags & 64 != 0) {
                    m[0] = @as(f64, @floatFromInt(try i16be(b, pos))) / 16384;
                    m[3] = @as(f64, @floatFromInt(try i16be(b, pos + 2))) / 16384;
                    pos += 4;
                } else if (flags & 128 != 0) {
                    for (&m, 0..) |*v, i| v.* = @as(f64, @floatFromInt(try i16be(b, pos + 2 * i))) / 16384;
                    pos += 8;
                }
                const first = out.points.items.len;
                try self.decode(a, child, out, depth + 1, work);
                for (out.points.items[first..]) |*p| {
                    const x = p.x;
                    const y = p.y;
                    p.x = x * m[0] + y * m[2];
                    p.y = x * m[1] + y * m[3];
                }
                if (!xy) {
                    if (parent_point >= first - root or child_point >= out.points.items.len - first) return error.InvalidFont;
                    dx = out.points.items[root + parent_point].x - out.points.items[first + child_point].x;
                    dy = out.points.items[root + parent_point].y - out.points.items[first + child_point].y;
                } else if (flags & 0x0800 != 0) {
                    const x = dx;
                    dx = x * m[0] + dy * m[2];
                    dy = x * m[1] + dy * m[3];
                }
                for (out.points.items[first..]) |*p| {
                    p.x += dx;
                    p.y += dy;
                }
                if (flags & 32 == 0) break;
            }
            if (has_instructions) {
                const count = try u16be(b, pos);
                _ = try slice(b, pos + 2, count);
            }
            return;
        }
        if (contours > 1024) return error.FontLimit;
        if (contours == 0) return;
        const base = out.points.items.len;
        var count: usize = 0;
        for (0..@intCast(contours)) |_| {
            const last = try u16be(b, pos);
            pos += 2;
            if (@as(usize, last) + 1 <= count) return error.InvalidFont;
            count = @as(usize, last) + 1;
            try out.ends.append(a, base + last);
        }
        if (count > 16384 or base + count > 16384) return error.FontLimit;
        const instructions = try u16be(b, pos);
        pos += 2;
        _ = try slice(b, pos, instructions);
        pos += instructions;
        const flags = try a.alloc(u8, count);
        defer a.free(flags);
        var i: usize = 0;
        while (i < count) {
            const flag = (try slice(b, pos, 1))[0];
            pos += 1;
            var repeat: usize = 1;
            if (flag & 8 != 0) {
                repeat += (try slice(b, pos, 1))[0];
                pos += 1;
            }
            if (repeat > count - i) return error.InvalidFont;
            @memset(flags[i..][0..repeat], flag);
            i += repeat;
        }
        try out.points.resize(a, base + count);
        var x: i32 = 0;
        for (flags, 0..) |flag, j| {
            if (flag & 2 != 0) {
                const delta: i32 = (try slice(b, pos, 1))[0];
                pos += 1;
                x += if (flag & 16 != 0) delta else -delta;
            } else if (flag & 16 == 0) {
                x += try i16be(b, pos);
                pos += 2;
            }
            out.points.items[base + j] = .{ .x = @floatFromInt(x), .y = 0, .on = flag & 1 != 0 };
        }
        var y: i32 = 0;
        for (flags, 0..) |flag, j| {
            if (flag & 4 != 0) {
                const delta: i32 = (try slice(b, pos, 1))[0];
                pos += 1;
                y += if (flag & 32 != 0) delta else -delta;
            } else if (flag & 32 == 0) {
                y += try i16be(b, pos);
                pos += 2;
            }
            out.points.items[base + j].y = @floatFromInt(y);
        }
    }
};

test "malformed simple glyph repeats and compound cycles are bounded" {
    const a = std.testing.allocator;
    var out: Outline = .{};
    defer out.points.deinit(a);
    defer out.ends.deinit(a);
    const repeated = [_]u8{ 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 4, 0, 0 };
    const font = Font{ .glyf = &repeated, .loca = &.{ 0, 0, 0, 9 }, .cmap = &.{}, .units = 1000, .glyphs = 1, .long_loca = false };
    try std.testing.expectError(error.InvalidFont, font.outline(a, 0, &out));
    out.points.clearRetainingCapacity();
    out.ends.clearRetainingCapacity();
    const cycle = [_]u8{ 255, 255, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0 };
    const cyclic = Font{ .glyf = &cycle, .loca = &.{ 0, 0, 0, 8 }, .cmap = &.{}, .units = 1000, .glyphs = 1, .long_loca = false };
    try std.testing.expectError(error.FontLimit, cyclic.outline(a, 0, &out));
}

test "cmap formats zero six and twelve map bounded glyph indices" {
    var zero: [262]u8 = @splat(0);
    zero[2] = 1;
    zero[3] = 6;
    zero[6 + 65] = 2;
    const six = [_]u8{ 0, 6, 0, 14, 0, 0, 0, 65, 0, 2, 0, 2, 0, 3 };
    const twelve = [_]u8{ 0, 12, 0, 0, 0, 0, 0, 28, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0xf6, 0, 0, 1, 0xf6, 1, 0, 0, 0, 2 };
    var font = Font{ .glyf = &.{}, .loca = &.{}, .cmap = &zero, .units = 1000, .glyphs = 4, .long_loca = false };
    try std.testing.expectEqual(@as(u16, 2), try font.glyph('A'));
    try std.testing.expectError(error.MissingGlyph, font.glyph('B'));
    font.cmap = &six;
    try std.testing.expectEqual(@as(u16, 3), try font.glyph('B'));
    try std.testing.expectError(error.MissingGlyph, font.glyph('C'));
    font.cmap = &twelve;
    try std.testing.expectEqual(@as(u16, 2), try font.glyph(0x1f600));
    try std.testing.expectEqual(@as(u16, 3), try font.glyph(0x1f601));
    try std.testing.expectError(error.MissingGlyph, font.glyph(0x1f602));
    font.cmap_table = &twelve;
    _ = try font.subtableAt(0);
    font.glyphs = 3;
    try std.testing.expectError(error.InvalidFont, font.subtableAt(0));
}

test "Apple true scaler fonts use the same validated TrueType tables" {
    var bytes: [256]u8 = @splat(0);
    std.mem.writeInt(u32, bytes[0..4], 0x00010000, .big);
    std.mem.writeInt(u16, bytes[4..6], 6, .big);
    const tags = [_][]const u8{ "head", "maxp", "glyf", "loca", "hhea", "hmtx" };
    const lengths = [_]usize{ 54, 32, 0, 4, 36, 4 };
    var offsets: [6]usize = undefined;
    var offset: usize = 108;
    for (tags, lengths, 0..) |tag, length, i| {
        const at = 12 + i * 16;
        @memcpy(bytes[at..][0..4], tag);
        std.mem.writeInt(u32, bytes[at + 8 ..][0..4], @intCast(offset), .big);
        std.mem.writeInt(u32, bytes[at + 12 ..][0..4], @intCast(length), .big);
        offsets[i] = offset;
        offset = (offset + length + 3) & ~@as(usize, 3);
    }
    std.mem.writeInt(u32, bytes[offsets[0]..][0..4], 0x00010000, .big);
    std.mem.writeInt(u32, bytes[offsets[0] + 12 ..][0..4], 0x5f0f3cf5, .big);
    std.mem.writeInt(u16, bytes[offsets[0] + 18 ..][0..2], 1000, .big);
    std.mem.writeInt(u32, bytes[offsets[1]..][0..4], 0x00010000, .big);
    std.mem.writeInt(u16, bytes[offsets[1] + 4 ..][0..2], 1, .big);
    std.mem.writeInt(u32, bytes[offsets[4]..][0..4], 0x00010000, .big);
    std.mem.writeInt(u16, bytes[offsets[4] + 34 ..][0..2], 1, .big);
    const standard = try Font.init(&bytes);
    @memcpy(bytes[0..4], "true");
    const apple = try Font.init(&bytes);
    try std.testing.expectEqualDeep(standard, apple);
    for ([_][]const u8{ "typ1", "OTTO", "ttcf" }) |unsupported| {
        @memcpy(bytes[0..4], unsupported);
        try std.testing.expectError(error.InvalidFont, Font.init(&bytes));
    }
    @memcpy(bytes[0..4], "true");
    bytes[offsets[0] + 12] = 0;
    try std.testing.expectError(error.InvalidFont, Font.init(&bytes));
}
