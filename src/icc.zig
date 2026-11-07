// ICC matrix/TRC profiles, evaluated by Pod; no host color-management dependency.
const std = @import("std");
const eq = std.mem.eql;
fn part(bytes: []const u8, offset: usize, size: usize) ![]const u8 {
    if (offset > bytes.len or size > bytes.len - offset) return error.InvalidICCProfile;
    return bytes[offset..][0..size];
}
fn uint(comptime T: type, bytes: []const u8, offset: usize) !T {
    return std.mem.readInt(T, (try part(bytes, offset, @sizeOf(T)))[0..@sizeOf(T)], .big);
}
fn fixed(bytes: []const u8, offset: usize) !f64 {
    return @as(f64, @floatFromInt(try uint(i32, bytes, offset))) / 65536;
}
fn reserved(bytes: []const u8) !void {
    for (bytes) |b| if (b != 0) return error.InvalidICCProfile;
}
const Curve = union(enum) {
    identity,
    gamma: f64,
    table: []const u8,
    parametric: struct { kind: u16, p: [7]f64 },
    fn parse(bytes: []const u8) !Curve {
        const signature = try part(bytes, 0, 4);
        try reserved(try part(bytes, 4, 4));
        if (eq(u8, signature, "curv")) {
            const count = try uint(u32, bytes, 8);
            if (count > 65536) return error.ICCProfileLimit;
            const table = try part(bytes, 12, count * 2);
            if (count == 0) return .identity;
            if (count == 1) {
                const gamma = @as(f64, @floatFromInt(try uint(u16, table, 0))) / 256;
                if (gamma <= 0) return error.InvalidICCProfile;
                return .{ .gamma = gamma };
            }
            var previous: u16 = 0;
            for (0..count) |i| {
                const value = try uint(u16, table, 2 * i);
                if (value < previous) return error.InvalidICCProfile;
                previous = value;
            }
            return .{ .table = table };
        }
        if (!eq(u8, signature, "para")) return error.UnsupportedICCProfile;
        const kind = try uint(u16, bytes, 8);
        try reserved(try part(bytes, 10, 2));
        if (kind > 4) return error.UnsupportedICCProfile;
        const counts = [_]usize{ 1, 3, 4, 5, 7 };
        var p: [7]f64 = @splat(0);
        for (p[0..counts[kind]], 0..) |*v, i| v.* = try fixed(bytes, 12 + 4 * i);
        if (p[0] <= 0 or (kind != 0 and p[1] <= 0)) return error.InvalidICCProfile;
        // Reject undefined power branches over the supported device domain.
        if (kind >= 3 and p[4] <= 1 and p[1] * @max(0, p[4]) + p[2] < 0) return error.InvalidICCProfile;
        const curve = Curve{ .parametric = .{ .kind = kind, .p = p } };
        _ = try curve.apply(0);
        _ = try curve.apply(1);
        return curve;
    }
    fn apply(self: Curve, input: f64) !f64 {
        const x = std.math.clamp(input, 0, 1);
        const y = switch (self) {
            .identity => x,
            .gamma => |g| std.math.pow(f64, x, g),
            .table => |table| blk: {
                const last = table.len / 2 - 1;
                const position = x * @as(f64, @floatFromInt(last));
                const i: usize = @intFromFloat(position);
                const lo: f64 = @floatFromInt(try uint(u16, table, 2 * i));
                const hi: f64 = @floatFromInt(try uint(u16, table, 2 * @min(i + 1, last)));
                break :blk (lo + (hi - lo) * (position - @as(f64, @floatFromInt(i)))) / 65535;
            },
            .parametric => |v| blk: {
                const p = v.p;
                if (v.kind == 0) break :blk std.math.pow(f64, x, p[0]);
                const threshold = if (v.kind < 3) -p[2] / p[1] else p[4];
                if (x < threshold) break :blk switch (v.kind) {
                    1 => 0,
                    2 => p[3],
                    3 => p[3] * x,
                    else => p[3] * x + p[6],
                };
                const powered = std.math.pow(f64, @max(0, p[1] * x + p[2]), p[0]);
                break :blk powered + (if (v.kind == 2) p[3] else if (v.kind == 4) p[5] else @as(f64, 0));
            },
        };
        if (!std.math.isFinite(y)) return error.InvalidICCProfile;
        return std.math.clamp(y, 0, 1);
    }
};
const d50 = [3]f64{ 0.9642, 1, 0.8249 };
pub const Profile = struct {
    bytes: []const u8,
    channels: usize,
    curves: [3]Curve = @splat(.identity),
    columns: [3][3]f64 = @splat(.{ 0, 0, 0 }),
    pub fn parse(bytes: []const u8) !Profile {
        if (bytes.len > 4 * 1024 * 1024) return error.ICCProfileLimit;
        if (bytes.len < 132 or try uint(u32, bytes, 0) != bytes.len or !eq(u8, bytes[36..40], "acsp")) return error.InvalidICCProfile;
        if ((bytes[8] != 2 and bytes[8] != 4) or !eq(u8, bytes[20..24], "XYZ ")) return error.UnsupportedICCProfile;
        const class = bytes[12..16];
        if (!eq(u8, class, "mntr") and !eq(u8, class, "scnr") and !eq(u8, class, "prtr") and !eq(u8, class, "spac")) return error.UnsupportedICCProfile;
        const channels: usize = if (eq(u8, bytes[16..20], "RGB ")) 3 else if (eq(u8, bytes[16..20], "GRAY")) 1 else return error.UnsupportedICCProfile;
        for (d50, 0..) |v, i| if (@abs(try fixed(bytes, 68 + i * 4) - v) > 0.0001) return error.UnsupportedICCProfile;
        const count = try uint(u32, bytes, 128);
        if (count > 256) return error.ICCProfileLimit;
        const end = 132 + count * 12;
        _ = try part(bytes, 0, end);
        for (0..count) |i| {
            const at = 132 + 12 * i;
            const signature = bytes[at..][0..4];
            const offset = try uint(u32, bytes, at + 4);
            const size = try uint(u32, bytes, at + 8);
            if (offset < end or offset % 4 != 0 or size < 8) return error.InvalidICCProfile;
            _ = try part(bytes, offset, size);
            for (0..i) |j| {
                const other = 132 + 12 * j;
                if (eq(u8, signature, bytes[other..][0..4])) return error.InvalidICCProfile;
                const other_offset = try uint(u32, bytes, other + 4);
                const other_size = try uint(u32, bytes, other + 8);
                if (offset < other_offset + other_size and other_offset < offset + size and (offset != other_offset or size != other_size)) return error.InvalidICCProfile;
            }
            // LUTs take precedence over matrix/TRC tags; do not silently bypass them.
            if (eq(u8, signature[0..3], "A2B") or eq(u8, signature[0..3], "D2B")) return error.UnsupportedICCProfile;
        }
        var result = Profile{ .bytes = bytes, .channels = channels };
        const white = try xyz(try result.tag("wtpt"));
        if (white[0] <= 0 or @abs(white[1] - 1) > 0.0001 or white[2] <= 0) return error.InvalidICCProfile;
        if (channels == 1) {
            result.curves[0] = try Curve.parse(try result.tag("kTRC"));
            result.columns[0] = d50;
        } else {
            for ([_][]const u8{ "rTRC", "gTRC", "bTRC" }, [_][]const u8{ "rXYZ", "gXYZ", "bXYZ" }, 0..) |trc, column, i| {
                result.curves[i] = try Curve.parse(try result.tag(trc));
                result.columns[i] = try xyz(try result.tag(column));
            }
        }
        return result;
    }
    fn tag(self: Profile, signature: []const u8) ![]const u8 {
        const count = try uint(u32, self.bytes, 128);
        for (0..count) |i| {
            const at = 132 + 12 * i;
            if (eq(u8, self.bytes[at..][0..4], signature)) return part(self.bytes, try uint(u32, self.bytes, at + 4), try uint(u32, self.bytes, at + 8));
        }
        return error.InvalidICCProfile;
    }
    pub fn rgb(self: Profile, values: []const f64) ![3]f64 {
        if (values.len != self.channels) return error.InvalidOperands;
        var pcs: [3]f64 = @splat(0);
        for (values, 0..) |value, i| {
            if (!std.math.isFinite(value)) return error.InvalidNumber;
            const linear = try self.curves[i].apply(value);
            for (&pcs, self.columns[i]) |*v, coefficient| v.* += coefficient * linear;
        }
        // ICC PCS is D50-adapted. Bradford adaptation to D65 followed by the
        // IEC sRGB inverse-primary matrix is combined here into one transform.
        const matrix = [3][3]f64{
            .{ 3.1338561, -1.6168667, -0.4906146 },
            .{ -0.9787684, 1.9161415, 0.0334540 },
            .{ 0.0719453, -0.2289914, 1.4052427 },
        };
        var rgb_values: [3]f64 = undefined;
        for (&rgb_values, matrix) |*out, row| {
            var linear: f64 = 0;
            for (row, pcs) |coefficient, value| linear += coefficient * value;
            linear = std.math.clamp(linear, 0, 1);
            out.* = if (linear <= 0.0031308) 12.92 * linear else 1.055 * std.math.pow(f64, linear, 1.0 / 2.4) - 0.055;
        }
        return rgb_values;
    }
};
fn xyz(bytes: []const u8) ![3]f64 {
    if (bytes.len != 20 or !eq(u8, bytes[0..4], "XYZ ")) return error.InvalidICCProfile;
    try reserved(bytes[4..8]);
    return .{ try fixed(bytes, 8), try fixed(bytes, 12), try fixed(bytes, 16) };
}

fn put(comptime T: type, b: []u8, at: usize, value: T) void {
    std.mem.writeInt(T, b[at..][0..@sizeOf(T)], value, .big);
}
fn putFixed(b: []u8, at: usize, value: f64) void {
    put(i32, b, at, @intFromFloat(@round(value * 65536)));
}
fn testProfile(a: std.mem.Allocator) ![]u8 {
    const signatures = [_][]const u8{ "wtpt", "rXYZ", "gXYZ", "bXYZ", "rTRC", "gTRC", "bTRC" };
    const bytes = try a.alloc(u8, 132 + 7 * 12 + 4 * 20 + 3 * 16);
    @memset(bytes, 0);
    put(u32, bytes, 0, @intCast(bytes.len));
    bytes[8] = 4;
    @memcpy(bytes[12..24], "mntrRGB XYZ ");
    @memcpy(bytes[36..40], "acsp");
    for (d50, 0..) |v, i| putFixed(bytes, 68 + 4 * i, v);
    put(u32, bytes, 128, 7);
    const columns = [4][3]f64{ d50, .{ 0.4360747, 0.2225045, 0.0139322 }, .{ 0.3850649, 0.7168786, 0.0971045 }, .{ 0.1430804, 0.0606169, 0.7141733 } };
    var offset: usize = 216;
    for (signatures, 0..) |signature, i| {
        const at = 132 + 12 * i;
        @memcpy(bytes[at..][0..4], signature);
        put(u32, bytes, at + 4, @intCast(offset));
        put(u32, bytes, at + 8, if (i < 4) 20 else 14);
        @memcpy(bytes[offset..][0..4], if (i < 4) "XYZ " else "curv");
        if (i < 4) {
            for (columns[i], 0..) |v, j| putFixed(bytes, offset + 8 + 4 * j, v);
            offset += 20;
        } else {
            put(u32, bytes, offset + 8, 1);
            put(u16, bytes, offset + 12, 0x233);
            offset += 16;
        }
    }
    return bytes;
}

test "ICC matrix curves decode and invalid tag structures fail" {
    const a = std.testing.allocator;
    const bytes = try testProfile(a);
    defer a.free(bytes);
    const profile = try Profile.parse(bytes);
    const rgb = try profile.rgb(&.{ 0.5, 0.5, 0.5 });
    for (rgb) |v| try std.testing.expectApproxEqAbs(@as(f64, 0.504), v, 0.001);
    for (0..bytes.len) |length| try std.testing.expectError(error.InvalidICCProfile, Profile.parse(bytes[0..length]));
    put(u32, bytes, 148, 217);
    try std.testing.expectError(error.InvalidICCProfile, Profile.parse(bytes));
    put(u32, bytes, 148, 236);
    @memcpy(bytes[144..148], "A2B0");
    try std.testing.expectError(error.UnsupportedICCProfile, Profile.parse(bytes));
}

test "ICC identity sampled and all parametric curve types" {
    var b: [40]u8 = @splat(0);
    @memcpy(b[0..4], "curv");
    try std.testing.expectEqual(@as(f64, 0.3), try (try Curve.parse(&b)).apply(0.3));
    put(u32, &b, 8, 3);
    put(u16, &b, 12, 0);
    put(u16, &b, 14, 32768);
    put(u16, &b, 16, 65535);
    try std.testing.expectApproxEqAbs(@as(f64, 0.25), try (try Curve.parse(&b)).apply(0.25), 0.00001);
    put(u16, &b, 16, 1);
    try std.testing.expectError(error.InvalidICCProfile, Curve.parse(&b));
    const parameters = [5][7]f64{
        .{ 2, 0, 0, 0, 0, 0, 0 },
        .{ 2, 1, -0.25, 0, 0, 0, 0 },
        .{ 2, 1, -0.25, 0.1, 0, 0, 0 },
        .{ 2, 1, 0, 0.25, 0.25, 0, 0 },
        .{ 2, 1, 0, 0.25, 0.25, 0.1, 0.1 },
    };
    for (parameters, 0..) |params, kind| {
        @memset(&b, 0);
        @memcpy(b[0..4], "para");
        put(u16, &b, 8, @intCast(kind));
        for (params, 0..) |v, i| putFixed(&b, 12 + 4 * i, v);
        const curve = try Curve.parse(&b);
        const expected = [_][2]f64{ .{ 0.01, 0.25 }, .{ 0, 0.0625 }, .{ 0.1, 0.1625 }, .{ 0.025, 0.25 }, .{ 0.125, 0.35 } };
        try std.testing.expectApproxEqAbs(expected[kind][0], try curve.apply(0.1), 0.00002);
        try std.testing.expectApproxEqAbs(expected[kind][1], try curve.apply(0.5), 0.00002);
    }
    putFixed(&b, 16, 0);
    try std.testing.expectError(error.InvalidICCProfile, Curve.parse(&b));
}

test "PDF ICC resources enforce channels ranges defaults and invalidate cached profiles" {
    const a = std.testing.allocator;
    const pod = @import("pod.zig");
    const s = @import("syntax.zig");
    const colors = @import("color.zig");
    const bytes = try pod.create(a, "color");
    defer a.free(bytes);
    var doc = try pod.Document.open(a, bytes);
    defer doc.deinit();
    const data = try testProfile(a);
    defer a.free(data);
    const entries = try doc.allocator().dupe(s.Entry, &.{.{ .key = "N", .value = .{ .integer = 3 } }});
    const id = try doc.addObject(.{ .dict = entries }, data);
    const array = try doc.allocator().dupe(s.Value, &.{ .{ .name = "ICCBased" }, .{ .ref = .{ .id = id, .generation = 0 } } });
    const spaces = try doc.allocator().dupe(s.Entry, &.{ .{ .key = "Custom", .value = .{ .array = array } }, .{ .key = "DefaultRGB", .value = .{ .array = array } } });
    const resources = s.Value{ .dict = try doc.allocator().dupe(s.Entry, &.{.{ .key = "ColorSpace", .value = .{ .dict = spaces } }}) };
    const before = try colors.load(&doc, resources, "Custom");
    const initial = try before.convert(&.{ 0.5, 0.5, 0.5 });
    try std.testing.expectEqualSlices(u8, &initial, &(try (try colors.load(&doc, resources, "DeviceRGB")).convert(&.{ 0.5, 0.5, 0.5 })));
    try std.testing.expectEqual(@as(usize, 1), doc.icc_profiles.count());
    const object = try doc.object(.{ .id = id, .generation = 0 });
    const replacement = try doc.allocator().dupe(u8, data);
    for (0..3) |i| put(u16, replacement, 296 + i * 16 + 12, 256);
    try doc.replaceStream(object, replacement);
    const after = try (try colors.load(&doc, resources, "Custom")).convert(&.{ 0.5, 0.5, 0.5 });
    try std.testing.expect(after[0] > initial[0] + 40);
    const range = try doc.allocator().dupe(s.Value, &.{ .{ .real = 0.2 }, .{ .real = 0.8 }, .{ .real = 0.2 }, .{ .real = 0.8 }, .{ .real = 0.2 }, .{ .real = 0.8 } });
    try doc.set(object, "Range", .{ .array = range });
    const ranged = try colors.load(&doc, resources, "Custom");
    try std.testing.expectEqualSlices(u8, &(try ranged.convert(&.{ 0.2, 0.2, 0.2 })), &(try colors.Color.initial(ranged)).rgb);
    try doc.set(object, "N", .{ .integer = 1 });
    try std.testing.expectError(error.InvalidColorSpace, colors.load(&doc, resources, "Custom"));
}
