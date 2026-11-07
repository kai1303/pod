//! PDF calibrated spaces to sRGB, with relative colorimetric Bradford adaptation.
const std = @import("std");
const d = @import("document.zig");
const s = @import("syntax.zig");
const Vec = [3]f64;
const Matrix = [3]Vec;
const identity: Matrix = .{ .{ 1, 0, 0 }, .{ 0, 1, 0 }, .{ 0, 0, 1 } };
const d65: Vec = .{ 0.95047, 1, 1.08883 };
const bradford: Matrix = .{ .{ 0.8951, 0.2664, -0.1614 }, .{ -0.7502, 1.7135, 0.0367 }, .{ 0.0389, -0.0685, 1.0296 } };
const inverse_bradford: Matrix = .{ .{ 0.9869929, -0.1470543, 0.1599627 }, .{ 0.4323053, 0.5183603, 0.0492912 }, .{ -0.0085287, 0.0400428, 0.9684867 } };
const srgb: Matrix = .{ .{ 3.2404542, -1.5371385, -0.4985314 }, .{ -0.9692660, 1.8760108, 0.0415560 }, .{ 0.0556434, -0.2040259, 1.0572252 } };

fn multiply(matrix: Matrix, vector: Vec) Vec {
    var result: Vec = @splat(0);
    for (&result, matrix) |*out, row| for (row, vector) |coefficient, value| {
        out.* += coefficient * value;
    };
    return result;
}
fn number(doc: *d.Document, value: s.Value) !f64 {
    const resolved = try doc.resolve(value);
    if (resolved != .integer and resolved != .real) return error.InvalidColorSpace;
    const result = try s.number(resolved);
    if (!std.math.isFinite(result) or @abs(result) > 1e12) return error.InvalidColorSpace;
    return result;
}
fn array(comptime n: usize, doc: *d.Document, value: s.Value) ![n]f64 {
    const resolved = try doc.resolve(value);
    if (resolved != .array or resolved.array.len != n) return error.InvalidColorSpace;
    var result: [n]f64 = undefined;
    for (&result, resolved.array) |*out, v| out.* = try number(doc, v);
    return result;
}
fn optional(doc: *d.Document, dict: s.Value, key: []const u8) !s.Value {
    return doc.resolve(s.get(dict, key) orelse .null);
}

pub const Space = struct {
    kind: enum { gray, rgb, lab },
    white: Vec,
    gamma: Vec = .{ 1, 1, 1 },
    columns: Matrix = identity,
    to_rgb: Matrix,
    range: [6]f64 = .{ 0, 1, 0, 1, 0, 1 },

    pub fn parse(doc: *d.Document, name: []const u8, raw: s.Value) !Space {
        const dict = try doc.resolve(raw);
        if (dict != .dict) return error.InvalidColorSpace;
        const white = try array(3, doc, s.get(dict, "WhitePoint") orelse return error.InvalidColorSpace);
        if (white[0] <= 0 or white[1] != 1 or white[2] <= 0) return error.InvalidColorSpace;
        const black = try optional(doc, dict, "BlackPoint");
        if (black != .null) for (try array(3, doc, black)) |v| {
            if (v < 0) return error.InvalidColorSpace;
        };
        // As with ICC colors, use relative colorimetry without optional black-point
        // compensation. The original BlackPoint remains in the saved dictionary.
        var result = Space{ .kind = if (std.mem.eql(u8, name, "CalGray")) .gray else if (std.mem.eql(u8, name, "CalRGB")) .rgb else .lab, .white = white, .to_rgb = undefined };
        if (result.kind == .lab) {
            result.range = .{ 0, 100, -100, 100, -100, 100 };
            const ranges = try optional(doc, dict, "Range");
            if (ranges != .null) @memcpy(result.range[2..], &(try array(4, doc, ranges)));
            if (result.range[2] > result.range[3] or result.range[4] > result.range[5]) return error.InvalidColorSpace;
        } else {
            const gamma = try optional(doc, dict, "Gamma");
            if (gamma != .null) result.gamma = if (result.kind == .gray) @splat(try number(doc, gamma)) else try array(3, doc, gamma);
            for (result.gamma) |g| if (g <= 0) return error.InvalidColorSpace;
            const matrix = try optional(doc, dict, "Matrix");
            if (result.kind == .rgb and matrix != .null) {
                const values = try array(9, doc, matrix);
                for (&result.columns, 0..) |*column, i| column.* = values[i * 3 ..][0..3].*;
            }
        }
        const source = multiply(bradford, white);
        const target = multiply(bradford, d65);
        var adaptation: Matrix = @splat(@splat(0));
        for (source) |v| if (@abs(v) < 1e-12) return error.UnsupportedColorSpace;
        for (&adaptation, 0..) |*row, i| for (row, 0..) |*value, j| {
            for (0..3) |k| value.* += inverse_bradford[i][k] * target[k] / source[k] * bradford[k][j];
        };
        result.to_rgb = @splat(@splat(0));
        for (&result.to_rgb, 0..) |*row, i| for (row, 0..) |*value, j| {
            for (0..3) |k| value.* += srgb[i][k] * adaptation[k][j];
        };
        return result;
    }
    pub fn rgb(self: Space, values: []const f64) !Vec {
        if (values.len != (if (self.kind == .gray) @as(usize, 1) else 3)) return error.InvalidOperands;
        var xyz: Vec = @splat(0);
        switch (self.kind) {
            .gray => {
                const value = std.math.pow(f64, values[0], self.gamma[0]);
                for (&xyz, self.white) |*v, w| v.* = value * w;
            },
            .rgb => for (values, self.gamma, self.columns) |value, gamma, column| {
                const powered = std.math.pow(f64, value, gamma);
                for (&xyz, column) |*v, coefficient| v.* += coefficient * powered;
            },
            .lab => {
                const y = (values[0] + 16) / 116;
                const components: Vec = .{ y + values[1] / 500, y, y - values[2] / 200 };
                for (&xyz, components, self.white) |*v, t, w| v.* = w * (if (t >= 6.0 / 29.0) t * t * t else (108.0 / 841.0) * (t - 4.0 / 29.0));
            },
        }
        var result = multiply(self.to_rgb, xyz);
        for (&result) |*value| {
            if (!std.math.isFinite(value.*)) return error.InvalidNumber;
            const linear = std.math.clamp(value.*, 0, 1);
            value.* = if (linear <= 0.0031308) linear * 12.92 else 1.055 * std.math.pow(f64, linear, 1.0 / 2.4) - 0.055;
        }
        return result;
    }
};
