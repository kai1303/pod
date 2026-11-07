const std = @import("std");
const d = @import("document.zig");
const s = @import("syntax.zig");
const icc = @import("icc.zig");
const eq = std.mem.eql;
pub const Space = struct {
    channels: usize = 1,
    profile: ?*const icc.Profile = null,
    calibrated: ?@import("cie.zig").Space = null,
    range: [6]f64 = .{ 0, 1, 0, 1, 0, 1 },
    // Indexed spaces retain the base profile/ranges; their input is one index.
    indexed: ?struct { channels: usize, lookup: []const u8 } = null,
    pub fn baseSpace(self: Space) Space {
        var base = self;
        if (self.indexed) |palette| {
            base.channels = palette.channels;
            base.indexed = null;
        }
        return base;
    }
    pub fn indexedComponents(self: Space, value: f64) ![3]f64 {
        const palette = self.indexed orelse return error.InvalidColorSpace;
        if (!std.math.isFinite(value) or @abs(value) > 1e12) return error.InvalidNumber;
        const maximum: f64 = @floatFromInt(palette.lookup.len / palette.channels - 1);
        const index: usize = @intFromFloat(@round(std.math.clamp(value, 0, maximum)));
        var result: [3]f64 = @splat(0);
        for (0..palette.channels) |i| {
            const sample: f64 = @floatFromInt(palette.lookup[index * palette.channels + i]);
            result[i] = self.range[2 * i] + sample / 255 * (self.range[2 * i + 1] - self.range[2 * i]);
        }
        return result;
    }
    pub fn convert(self: Space, values: []const f64) ![3]u8 {
        if (values.len != self.channels) return error.InvalidOperands;
        const base = self.baseSpace();
        var input: [3]f64 = @splat(0);
        if (self.indexed != null) {
            input = try self.indexedComponents(values[0]);
        } else {
            for (values, 0..) |v, i| {
                if (!std.math.isFinite(v) or @abs(v) > 1e12) return error.InvalidNumber;
                input[i] = std.math.clamp(v, self.range[2 * i], self.range[2 * i + 1]);
            }
        }
        const rgb = if (base.profile) |profile| try profile.rgb(input[0..base.channels]) else if (base.calibrated) |calibrated| try calibrated.rgb(input[0..base.channels]) else if (base.channels == 1) [3]f64{ input[0], input[0], input[0] } else input;
        var result: [3]u8 = undefined;
        for (&result, rgb) |*out, v| out.* = @intFromFloat(@round(std.math.clamp(v, 0, 1) * 255));
        return result;
    }
};
pub const Color = struct {
    space: Space = .{},
    rgb: [3]u8 = .{ 0, 0, 0 },
    pub fn initial(space: Space) !Color {
        const zero = [3]f64{ 0, 0, 0 };
        return .{ .space = space, .rgb = try space.convert(zero[0..space.channels]) };
    }
    pub fn set(self: *Color, values: []s.Value) !void {
        if (values.len != self.space.channels) return error.InvalidOperands;
        var numbers: [3]f64 = undefined;
        for (values, 0..) |v, i| numbers[i] = try s.number(v);
        self.rgb = try self.space.convert(numbers[0..values.len]);
    }
};
pub fn load(doc: *d.Document, resources: s.Value, name: []const u8) !Space {
    return resolve(doc, resources, .{ .name = name }, true, 0);
}
pub fn loadValue(doc: *d.Document, resources: s.Value, value: s.Value) !Space {
    return resolve(doc, try doc.resolve(resources), value, true, 0);
}
fn resolve(doc: *d.Document, resources: s.Value, raw: s.Value, defaults: bool, depth: usize) anyerror!Space {
    if (depth >= 16) return error.ColorSpaceLimit;
    const value = try doc.resolve(raw);
    if (value == .name) {
        if (eq(u8, value.name, "DeviceGray") or eq(u8, value.name, "DeviceRGB")) {
            const channels: usize = if (eq(u8, value.name, "DeviceGray")) 1 else 3;
            if (defaults) if (s.get(resources, "ColorSpace")) |table| {
                const spaces = try doc.resolve(table);
                if (spaces != .dict) return error.InvalidColorSpace;
                const key = if (channels == 1) "DefaultGray" else "DefaultRGB";
                if (s.get(spaces, key)) |replacement| {
                    if (try doc.resolve(replacement) != .null) {
                        const space = try resolve(doc, resources, replacement, false, depth + 1);
                        if (space.channels != channels or space.indexed != null) return error.InvalidColorSpace;
                        return space;
                    }
                }
            };
            return .{ .channels = channels };
        }
        if (eq(u8, value.name, "DeviceCMYK") or eq(u8, value.name, "Pattern")) return error.UnsupportedColorSpace;
        const spaces = try doc.resolve(s.get(resources, "ColorSpace") orelse return error.MissingColorSpace);
        if (spaces != .dict) return error.InvalidColorSpace;
        return resolve(doc, resources, s.get(spaces, value.name) orelse return error.MissingColorSpace, defaults, depth + 1);
    }
    if (value != .array or value.array.len == 0 or value.array[0] != .name) return error.InvalidColorSpace;
    const name = value.array[0].name;
    if (eq(u8, name, "CalGray") or eq(u8, name, "CalRGB") or eq(u8, name, "Lab")) {
        if (value.array.len != 2) return error.InvalidColorSpace;
        const calibrated = try @import("cie.zig").Space.parse(doc, name, value.array[1]);
        return .{ .channels = if (calibrated.kind == .gray) 1 else 3, .range = calibrated.range, .calibrated = calibrated };
    }
    if (value.array.len == 1 and (eq(u8, name, "DeviceRGB") or eq(u8, name, "DeviceGray"))) return resolve(doc, resources, value.array[0], defaults, depth + 1);
    if (eq(u8, name, "Indexed")) {
        if (value.array.len != 4) return error.InvalidColorSpace;
        const maximum = try doc.resolve(value.array[2]);
        if (maximum != .integer or maximum.integer < 0 or maximum.integer > 255) return error.InvalidColorSpace;
        var base = try resolve(doc, resources, value.array[1], defaults, depth + 1);
        if (base.indexed != null) return error.InvalidColorSpace;
        const lookup = try lookupData(doc, value.array[3]);
        if (lookup.len != (@as(usize, @intCast(maximum.integer)) + 1) * base.channels) return error.InvalidColorSpace;
        base.indexed = .{ .channels = base.channels, .lookup = lookup };
        base.channels = 1;
        return base;
    }
    if (!eq(u8, name, "ICCBased")) return error.UnsupportedColorSpace;
    if (value.array.len != 2 or value.array[1] != .ref) return error.InvalidColorSpace;
    const ref = value.array[1].ref;
    const object = try doc.object(ref);
    const n = try s.uint(try doc.resolve(s.get(object.value, "N") orelse return error.InvalidColorSpace));
    if (n != 1 and n != 3) return error.UnsupportedColorSpace;
    var space = Space{ .channels = n };
    if (s.get(object.value, "Range")) |raw_range| {
        const range = try doc.resolve(raw_range);
        if (range != .array or range.array.len != n * 2) return error.InvalidColorSpace;
        for (range.array, 0..) |v, i| {
            space.range[i] = try s.number(try doc.resolve(v));
            if (!std.math.isFinite(space.range[i]) or @abs(space.range[i]) > 1e12) return error.InvalidColorSpace;
        }
        for (0..n) |i| if (space.range[2 * i] > space.range[2 * i + 1]) return error.InvalidColorSpace;
    }
    if (doc.icc_profiles.get(ref.id)) |cached| {
        space.profile = cached;
    } else {
        if (doc.icc_profiles.count() >= 256) return error.ICCProfileLimit;
        const profile = try doc.allocator().create(icc.Profile);
        profile.* = try icc.Profile.parse(try doc.streamData(object));
        try doc.icc_profiles.put(doc.allocator(), ref.id, profile);
        space.profile = profile;
    }
    if (space.profile.?.channels != n) return error.InvalidColorSpace;
    return space;
}

fn lookupData(doc: *d.Document, raw: s.Value) ![]const u8 {
    var value = raw;
    for (0..64) |_| {
        if (value == .string) return value.string;
        if (value != .ref) return error.InvalidColorSpace;
        const object = try doc.object(value.ref);
        if (object.stream != null or object.changed != null) return doc.streamData(object);
        value = object.value;
    }
    return error.ReferenceLimit;
}
