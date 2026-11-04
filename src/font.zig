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
fn table(bytes: []const u8, tag: []const u8) ![]const u8 {
    const count = try u16be(bytes, 4);
    if (count > 128) return error.InvalidFont;
    for (0..count) |i| {
        const at = 12 + i * 16;
        const entry = try slice(bytes, at, 16);
        if (std.mem.eql(u8, entry[0..4], tag)) return slice(bytes, try u32be(entry, 8), try u32be(entry, 12));
    }
    return error.InvalidFont;
}
pub const Font = struct {
    glyf: []const u8,
    loca: []const u8,
    cmap: []const u8,
    units: f64,
    glyphs: u16,
    long_loca: bool,
    pub fn init(bytes: []const u8) !Font {
        if (try u32be(bytes, 0) != 0x00010000) return error.InvalidFont;
        const head = try table(bytes, "head");
        const units = try u16be(head, 18);
        const loc = try i16be(head, 50);
        if (units < 16 or units > 16384 or (loc != 0 and loc != 1)) return error.InvalidFont;
        const cm = try table(bytes, "cmap");
        const count = try u16be(cm, 2);
        if (count > 128) return error.InvalidFont;
        var chosen: ?[]const u8 = null;
        for (0..count) |i| {
            const at = 4 + i * 8;
            const platform = try u16be(cm, at);
            const enc = try u16be(cm, at + 2);
            const off = try u32be(cm, at + 4);
            if ((platform == 0 or (platform == 3 and enc == 1)) and try u16be(cm, off) == 4) {
                chosen = try slice(cm, off, try u16be(cm, off + 2));
                break;
            }
        }
        const maxp = try table(bytes, "maxp");
        return .{ .glyf = try table(bytes, "glyf"), .loca = try table(bytes, "loca"), .cmap = chosen orelse return error.UnsupportedFontCmap, .units = @floatFromInt(units), .glyphs = try u16be(maxp, 4), .long_loca = loc == 1 };
    }
    pub fn glyph(self: Font, c: u16) !u16 {
        const segments = (try u16be(self.cmap, 6)) / 2;
        if (segments == 0 or segments > 8192) return error.InvalidFont;
        for (0..segments) |i| {
            const end = try u16be(self.cmap, 14 + 2 * i);
            const start = try u16be(self.cmap, 16 + 2 * segments + 2 * i);
            if (c < start or c > end) continue;
            const delta = try u16be(self.cmap, 16 + 4 * segments + 2 * i);
            const range_at = 16 + 6 * segments + 2 * i;
            const range = try u16be(self.cmap, range_at);
            const g = if (range == 0) @as(u16, c) +% delta else blk: {
                const raw = try u16be(self.cmap, range_at + range + 2 * (@as(usize, c) - start));
                break :blk if (raw == 0) 0 else raw +% delta;
            };
            if (g == 0 or g >= self.glyphs) return error.MissingGlyph;
            return g;
        }
        return error.MissingGlyph;
    }
    fn offset(self: Font, id: usize) !usize {
        return if (self.long_loca) try u32be(self.loca, id * 4) else @as(usize, try u16be(self.loca, id * 2)) * 2;
    }
    pub fn outline(self: Font, a: std.mem.Allocator, id: u16, out: *Outline) !void {
        try self.decode(a, id, out, 0);
    }
    fn decode(self: Font, a: std.mem.Allocator, id: u16, out: *Outline, depth: usize) anyerror!void {
        if (depth >= 8 or id >= self.glyphs or out.points.items.len > 16384) return error.FontLimit;
        const begin = try self.offset(id);
        const end = try self.offset(@as(usize, id) + 1);
        if (end < begin) return error.InvalidFont;
        const b = try slice(self.glyf, begin, end - begin);
        if (b.len == 0) return;
        const contours = try i16be(b, 0);
        var pos: usize = 10;
        if (contours < 0) {
            var parts: usize = 0;
            while (true) {
                parts += 1;
                if (parts > 64) return error.FontLimit;
                const flags = try u16be(b, pos);
                const child = try u16be(b, pos + 2);
                pos += 4;
                if (flags & 2 == 0 or flags & 0x0800 != 0) return error.UnsupportedFontCompound;
                var dx: f64 = 0;
                var dy: f64 = 0;
                if (flags & 1 != 0) {
                    dx = @floatFromInt(try i16be(b, pos));
                    dy = @floatFromInt(try i16be(b, pos + 2));
                    pos += 4;
                } else {
                    const args = try slice(b, pos, 2);
                    dx = @floatFromInt(@as(i8, @bitCast(args[0])));
                    dy = @floatFromInt(@as(i8, @bitCast(args[1])));
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
                try self.decode(a, child, out, depth + 1);
                for (out.points.items[first..]) |*p| {
                    const x = p.x;
                    const y = p.y;
                    p.x = x * m[0] + y * m[2] + dx;
                    p.y = x * m[1] + y * m[3] + dy;
                }
                if (flags & 32 == 0) break;
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
