const std = @import("std");

// Stable values shared with PodBlendMode and the Metal scene interpreter.
pub const Mode = enum(u32) {
    normal,
    multiply,
    screen,
    overlay,
    darken,
    lighten,
    color_dodge,
    color_burn,
    hard_light,
    soft_light,
    difference,
    exclusion,
    hue,
    saturation,
    color,
    luminosity,
};
pub const names = [_][]const u8{ "Normal", "Multiply", "Screen", "Overlay", "Darken", "Lighten", "ColorDodge", "ColorBurn", "HardLight", "SoftLight", "Difference", "Exclusion", "Hue", "Saturation", "Color", "Luminosity" };
pub fn fromName(name: []const u8) ?Mode {
    if (std.mem.eql(u8, name, "Compatible")) return .normal;
    for (names, 0..) |known, i| if (std.mem.eql(u8, name, known)) return @fromBackingInt(@as(u32, @intCast(i)));
    return null;
}
const RGB = [3]f64;
fn lum(rgb: RGB) f64 {
    return 0.3 * rgb[0] + 0.59 * rgb[1] + 0.11 * rgb[2];
}
fn minimum(rgb: RGB) f64 {
    return @min(rgb[0], rgb[1], rgb[2]);
}
fn maximum(rgb: RGB) f64 {
    return @max(rgb[0], rgb[1], rgb[2]);
}
fn saturation(rgb: RGB) f64 {
    return maximum(rgb) - minimum(rgb);
}
fn setLum(rgb: RGB, value: f64) RGB {
    var out: RGB = undefined;
    const delta = value - lum(rgb);
    for (&out, rgb) |*channel, v| channel.* = v + delta;
    const low = minimum(out);
    const high = maximum(out);
    if (low < 0) for (&out) |*v| {
        v.* = value + (v.* - value) * value / (value - low);
    };
    if (high > 1) for (&out) |*v| {
        v.* = value + (v.* - value) * (1 - value) / (high - value);
    };
    return out;
}
fn setSat(rgb: RGB, value: f64) RGB {
    const low = minimum(rgb);
    const range = maximum(rgb) - low;
    if (range == 0) return .{ 0, 0, 0 };
    var out: RGB = undefined;
    for (&out, rgb) |*channel, v| channel.* = (v - low) * value / range;
    return out;
}
fn hardLight(b: f64, s: f64) f64 {
    return if (s <= 0.5) 2 * b * s else 1 - 2 * (1 - b) * (1 - s);
}
fn separable(mode: Mode, b: f64, s: f64) f64 {
    return switch (mode) {
        .normal => s,
        .multiply => b * s,
        .screen => b + s - b * s,
        .overlay => hardLight(s, b),
        .darken => @min(b, s),
        .lighten => @max(b, s),
        // Adobe's 2009 correction keeps these continuous in the source color.
        .color_dodge => if (b == 0) 0 else if (s == 1) 1 else @min(1, b / (1 - s)),
        .color_burn => if (b == 1) 1 else if (s == 0) 0 else 1 - @min(1, (1 - b) / s),
        .hard_light => hardLight(b, s),
        .soft_light => if (s <= 0.5) b - (1 - 2 * s) * b * (1 - b) else b + (2 * s - 1) * ((if (b <= 0.25) ((16 * b - 12) * b + 4) * b else @sqrt(b)) - b),
        .difference => @abs(b - s),
        .exclusion => b + s - 2 * b * s,
        else => unreachable,
    };
}
// Inputs and output use the current RGB blending space, with channels in [0,1].
// Alpha and shape coverage are applied by the compositor after this function.
pub fn apply(mode: Mode, backdrop: RGB, source: RGB) RGB {
    var result = switch (mode) {
        .hue => setLum(setSat(source, saturation(backdrop)), lum(backdrop)),
        .saturation => setLum(setSat(backdrop, saturation(source)), lum(backdrop)),
        .color => setLum(source, lum(backdrop)),
        .luminosity => setLum(backdrop, lum(source)),
        else => RGB{ separable(mode, backdrop[0], source[0]), separable(mode, backdrop[1], source[1]), separable(mode, backdrop[2], source[2]) },
    };
    // Bound floating-point error after ClipColor before byte conversion.
    for (&result) |*v| v.* = std.math.clamp(v.*, 0, 1);
    return result;
}

test "blend modes include corrected dodge burn endpoints and soft light branches" {
    try std.testing.expectEqualSlices(f64, &.{ 0, 1, 1 }, &apply(.color_dodge, .{ 0, 1, 0.5 }, .{ 1, 0, 0.5 }));
    try std.testing.expectEqualSlices(f64, &.{ 1, 0, 0 }, &apply(.color_burn, .{ 1, 0, 0.5 }, .{ 0, 1, 0.5 }));
    const soft = apply(.soft_light, .{ 0.125, 0.25, 0.81 }, .{ 0.25, 0.75, 1 });
    for (soft, [3]f64{ 0.0703125, 0.375, 0.9 }) |v, expected| try std.testing.expectApproxEqAbs(expected, v, 1e-12);
}

test "nonseparable modes preserve selected luminosity and handle gray clipping" {
    const b = RGB{ 0.2, 0.4, 0.8 };
    const s = RGB{ 0.9, 0.4, 0.6 };
    const expected = [_]RGB{ .{ 0.7776, 0.1776, 0.4176 }, .{ 0.2306666666666667, 0.3973333333333333, 0.7306666666666667 }, .{ 0.712, 0.212, 0.412 }, .{ 0.388, 0.588, 0.988 } };
    for ([_]Mode{ .hue, .saturation, .color, .luminosity }, expected) |mode, want| {
        const actual = apply(mode, b, s);
        for (actual, want) |v, w| try std.testing.expectApproxEqAbs(w, v, 1e-12);
    }
    for ([_]f64{ 0, 0.05, 0.4, 0.95, 1 }) |gray| {
        const actual = apply(.color, .{ gray, gray, gray }, .{ 1, 0, 0 });
        try std.testing.expectApproxEqAbs(gray, lum(actual), 1e-12);
        const unsaturated = apply(.saturation, .{ gray, gray, gray }, s);
        for (unsaturated) |v| try std.testing.expectApproxEqAbs(gray, v, 1e-12);
    }
}

test "all RGB blend modes are bounded across a color grid" {
    const colors = [_]RGB{ .{ 0, 0, 0 }, .{ 1, 1, 1 }, .{ 1, 0, 0 }, .{ 0, 1, 0 }, .{ 0, 0, 1 }, .{ 0.5, 0.5, 0.5 }, .{ 0.1, 0.7, 0.9 } };
    for (names, 0..) |name, i| {
        const mode = fromName(name).?;
        try std.testing.expectEqual(@as(u32, @intCast(i)), @backingInt(mode));
        for (colors) |b| for (colors) |s| {
            for (apply(mode, b, s)) |v| try std.testing.expect(std.math.isFinite(v) and v >= 0 and v <= 1);
        };
    }
}
