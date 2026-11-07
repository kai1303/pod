//! Sampled image XObjects. Encoded bytes remain owned by the document stream cache.
const std = @import("std");
const d = @import("document.zig");
const s = @import("syntax.zig");
const color = @import("color.zig");
const eq = std.mem.eql;
pub const Image = struct {
    width: usize,
    height: usize,
    stride: usize,
    bits: u5,
    space: color.Space,
    decode: [6]f64,
    data: []const u8,
    stencil: bool,
    interpolate: bool,
    mask: ?[6]u32 = null,
    alpha_only: bool = false,
    alpha_image: ?*const Image = null,
    matte: ?[3]f64 = null,

    pub fn texel(self: Image, x: usize, y: usize, tint: [3]u8) anyerror![4]f64 {
        const maximum = (@as(u32, 1) << self.bits) - 1;
        var values: [3]f64 = undefined;
        var transparent = self.mask != null;
        for (0..self.space.channels) |channel| {
            const bit = (x * self.space.channels + channel) * self.bits;
            const at = y * self.stride + bit / 8;
            const raw: u32 = if (self.bits == 16) std.mem.readInt(u16, self.data[at..][0..2], .big) else (self.data[at] >> @as(u3, @intCast(8 - self.bits - bit % 8))) & maximum;
            if (self.mask) |mask| transparent = transparent and raw >= mask[channel * 2] and raw <= mask[channel * 2 + 1];
            values[channel] = self.decode[channel * 2] + @as(f64, @floatFromInt(raw)) / @as(f64, @floatFromInt(maximum)) * (self.decode[channel * 2 + 1] - self.decode[channel * 2]);
        }
        var alpha = if (self.stencil) 1 - values[0] else if (self.alpha_only) std.math.clamp(values[0], 0, 1) else if (transparent) @as(f64, 0) else 1;
        const paint_space = self.space.baseSpace();
        if (self.space.indexed != null) values = try self.space.indexedComponents(values[0]);
        if (self.matte) |matte| {
            // Undo Matte in source color space; alpha weights avoid transparent-edge fringes.
            alpha = (try self.alpha_image.?.texel(x, y, tint))[3];
            for (0..paint_space.channels) |i| values[i] = if (alpha > 0) matte[i] + (values[i] - matte[i]) / alpha else 0;
        }
        const rgb = if (self.stencil or self.alpha_only) tint else try paint_space.convert(values[0..paint_space.channels]);
        return .{ @floatFromInt(rgb[0]), @floatFromInt(rgb[1]), @floatFromInt(rgb[2]), alpha };
    }
    pub fn visibleBox(self: Image) !?[4]f64 {
        var box = (try self.ownVisibleBox()) orelse return null;
        if (self.alpha_image) |alpha| {
            const mask_box = (try alpha.ownVisibleBox()) orelse return null;
            box = .{ @max(box[0], mask_box[0]), @max(box[1], mask_box[1]), @min(box[2], mask_box[2]), @min(box[3], mask_box[3]) };
            if (box[0] >= box[2] or box[1] >= box[3]) return null;
        }
        return box;
    }
    fn ownVisibleBox(self: Image) !?[4]f64 {
        if (!self.stencil and !self.alpha_only and self.mask == null) return .{ 0, 0, 1, 1 };
        var left = self.width;
        var top = self.height;
        var right: usize = 0;
        var bottom: usize = 0;
        for (0..self.height) |y| for (0..self.width) |x| {
            if ((try self.texel(x, y, .{ 0, 0, 0 }))[3] == 0) continue;
            left = @min(left, x);
            top = @min(top, y);
            right = @max(right, x + 1);
            bottom = @max(bottom, y + 1);
        };
        if (right == 0) return null;
        const w: f64 = @floatFromInt(self.width);
        const h: f64 = @floatFromInt(self.height);
        const pad: f64 = if (self.interpolate) 0.5 else 0;
        return .{ @max(0, (@as(f64, @floatFromInt(left)) - pad) / w), @max(0, 1 - (@as(f64, @floatFromInt(bottom)) + pad) / h), @min(1, (@as(f64, @floatFromInt(right)) + pad) / w), @min(1, 1 - (@as(f64, @floatFromInt(top)) - pad) / h) };
    }
    // u/v refer to the PDF unit square; the first encoded row is at its top edge.
    pub fn sample(self: Image, u: f64, v: f64, tint: [3]u8) ![4]f64 {
        var value = try self.samplePlane(u, v, tint);
        if (self.alpha_image) |alpha| value[3] = (try alpha.samplePlane(u, v, tint))[3];
        return value;
    }
    fn samplePlane(self: Image, u: f64, v: f64, tint: [3]u8) ![4]f64 {
        const w: f64 = @floatFromInt(self.width);
        const h: f64 = @floatFromInt(self.height);
        const x = std.math.clamp(u * w, 0, w);
        const y = std.math.clamp((1 - v) * h, 0, h);
        if (!self.interpolate) return self.texel(@intFromFloat(@min(@floor(x), w - 1)), @intFromFloat(@min(@floor(y), h - 1)), tint);
        const left = @floor(x - 0.5);
        const top = @floor(y - 0.5);
        const fx = x - 0.5 - left;
        const fy = y - 0.5 - top;
        var result: [4]f64 = @splat(0);
        for (0..2) |row| for (0..2) |col| {
            const value = try self.texel(@intFromFloat(std.math.clamp(left + @as(f64, @floatFromInt(col)), 0, w - 1)), @intFromFloat(std.math.clamp(top + @as(f64, @floatFromInt(row)), 0, h - 1)), tint);
            const weight = (if (col == 0) 1 - fx else fx) * (if (row == 0) 1 - fy else fy) * value[3];
            for (0..3) |i| result[i] += value[i] * weight;
            result[3] += weight;
        };
        if (result[3] > 0) for (0..3) |i| {
            result[i] /= result[3];
        };
        return result;
    }
};
fn optional(doc: *d.Document, value: s.Value, key: []const u8) !s.Value {
    return doc.resolve(s.get(value, key) orelse .null);
}
fn boolean(doc: *d.Document, value: s.Value, key: []const u8) !bool {
    const v = try optional(doc, value, key);
    if (v == .null) return false;
    if (v != .boolean) return error.InvalidImage;
    return v.boolean;
}
pub fn load(doc: *d.Document, object: *d.Object, resources: s.Value) !Image {
    var result = try loadPlane(doc, object, resources, false);
    const soft = try optional(doc, object.value, "SMask");
    const mask = if (soft == .null) try optional(doc, object.value, "Mask") else s.Value.null;
    if (soft != .null or (mask != .null and mask != .array)) {
        if (result.stencil) return error.InvalidImage;
        const mask_object = try maskObject(doc, s.get(object.value, if (soft != .null) "SMask" else "Mask").?);
        if (try optional(doc, mask_object.value, "SMask") != .null or try optional(doc, mask_object.value, "Mask") != .null) return error.InvalidImage;
        const child = try loadPlane(doc, mask_object, resources, soft != .null);
        if (child.stencil != (soft == .null)) return error.InvalidImage;
        const alpha = try doc.allocator().create(Image);
        alpha.* = child;
        result.alpha_image = alpha;
        if (soft != .null) {
            const matte = try optional(doc, mask_object.value, "Matte");
            if (matte != .null) {
                if (matte != .array or matte.array.len != result.space.channels or child.width != result.width or child.height != result.height) return error.InvalidImage;
                var values: [3]f64 = @splat(0);
                for (matte.array, 0..) |entry, i| {
                    values[i] = try s.number(try doc.resolve(entry));
                    const lower = if (result.space.indexed != null) 0 else result.space.range[i * 2];
                    const upper: f64 = if (result.space.indexed) |palette| @floatFromInt(palette.lookup.len / palette.channels - 1) else result.space.range[i * 2 + 1];
                    if (!std.math.isFinite(values[i]) or values[i] < lower or values[i] > upper) return error.InvalidImage;
                }
                // Matte is a color in the image's space (one index for Indexed),
                // but preblending applies to palette components, not the indices.
                result.matte = if (result.space.indexed != null) try result.space.indexedComponents(values[0]) else values;
            }
        }
    }
    return result;
}
fn maskObject(doc: *d.Document, raw: s.Value) !*d.Object {
    var value = raw;
    for (0..64) |_| {
        if (value != .ref) return error.InvalidImage;
        const object = try doc.object(value.ref);
        if (object.value != .ref) {
            if (object.value != .dict or (object.stream == null and object.changed == null)) return error.InvalidImage;
            const subtype = try optional(doc, object.value, "Subtype");
            if (subtype != .name or !eq(u8, subtype.name, "Image")) return error.InvalidImage;
            return object;
        }
        value = object.value;
    }
    return error.ReferenceLimit;
}
fn loadPlane(doc: *d.Document, object: *d.Object, resources: s.Value, soft: bool) !Image {
    var result = try describe(doc, object.value, resources, soft);
    result.data = try doc.streamData(object);
    if (result.data.len != result.stride * result.height) return error.InvalidImageData;
    return result;
}
// Validate dimensions and sample layout before reading or decompressing image bytes.
pub fn describe(doc: *d.Document, dict: s.Value, resources: s.Value, soft: bool) !Image {
    const width = try optional(doc, dict, "Width");
    const height = try optional(doc, dict, "Height");
    if (width != .integer or height != .integer or width.integer <= 0 or height.integer <= 0) return error.InvalidImage;
    if (width.integer > 65536 or height.integer > 65536 or width.integer * height.integer > 16 * 1024 * 1024) return error.ImageLimit;
    const kind = try optional(doc, dict, "Type");
    if (kind != .null and (kind != .name or !eq(u8, kind.name, "XObject"))) return error.InvalidImage;
    const embedded_mask = try optional(doc, dict, "SMaskInData");
    if (embedded_mask != .null and !(embedded_mask == .integer and embedded_mask.integer == 0)) return error.UnsupportedImageMask;
    for ([_][]const u8{ "OC", "F" }) |key| if (try optional(doc, dict, key) != .null) return error.UnsupportedImage;
    if (!soft) for ([_][]const u8{ "Alternates", "OPI" }) |key| {
        if (try optional(doc, dict, key) != .null) return error.UnsupportedImage;
    };
    const intent = try optional(doc, dict, "Intent");
    if (!soft and intent != .null and (intent != .name or !eq(u8, intent.name, "RelativeColorimetric"))) return error.UnsupportedRenderingIntent;
    const stencil = try boolean(doc, dict, "ImageMask");
    const depth = try optional(doc, dict, "BitsPerComponent");
    const bits: i64 = if (depth == .null and stencil) 1 else if (depth == .integer) depth.integer else return error.InvalidImage;
    if (bits != 1 and bits != 2 and bits != 4 and bits != 8 and bits != 16) return error.UnsupportedImageDepth;
    const space_value = try optional(doc, dict, "ColorSpace");
    if (stencil and (bits != 1 or space_value != .null)) return error.InvalidImage;
    if (!stencil and space_value == .null) return error.InvalidImage;
    if (soft and (stencil or space_value != .name or !eq(u8, space_value.name, "DeviceGray"))) return error.InvalidImage;
    const space = if (stencil or soft) color.Space{} else try color.loadValue(doc, resources, space_value);
    if (space.indexed != null and bits > 8) return error.UnsupportedImageDepth;
    var result = Image{ .width = @intCast(width.integer), .height = @intCast(height.integer), .stride = 0, .bits = @intCast(bits), .space = space, .decode = .{ 0, 1, 0, 1, 0, 1 }, .data = undefined, .stencil = stencil, .interpolate = try boolean(doc, dict, "Interpolate") };
    if (space.indexed != null) result.decode[1] = @floatFromInt((@as(u32, 1) << result.bits) - 1);
    if (space.indexed == null) if (space.calibrated) |calibrated| {
        if (calibrated.kind == .lab) result.decode = space.range;
    };
    result.alpha_only = soft;
    const decode = try optional(doc, dict, "Decode");
    if (decode != .null) {
        if (decode != .array or decode.array.len != 2 * space.channels) return error.InvalidImage;
        for (decode.array, 0..) |entry, i| {
            result.decode[i] = try s.number(try doc.resolve(entry));
            if (!std.math.isFinite(result.decode[i]) or @abs(result.decode[i]) > 1e6) return error.InvalidImage;
        }
    }
    if (stencil and !((result.decode[0] == 0 and result.decode[1] == 1) or (result.decode[0] == 1 and result.decode[1] == 0))) return error.InvalidImage;
    const mask = if (try optional(doc, dict, "SMask") == .null) try optional(doc, dict, "Mask") else s.Value.null;
    if (mask != .null) {
        if (stencil) return error.InvalidImage;
    }
    if (mask == .array) {
        if (mask.array.len != 2 * space.channels) return error.InvalidImage;
        var bounds: [6]u32 = @splat(0);
        const maximum = (@as(u32, 1) << result.bits) - 1;
        for (mask.array, 0..) |entry, i| {
            const n = try doc.resolve(entry);
            if (n != .integer or n.integer < 0 or n.integer > maximum) return error.InvalidImage;
            bounds[i] = @intCast(n.integer);
        }
        for (0..space.channels) |i| if (bounds[i * 2] > bounds[i * 2 + 1]) return error.InvalidImage;
        result.mask = bounds;
    }
    result.stride = (result.width * space.channels * result.bits + 7) / 8;
    if (result.stride * result.height > 64 * 1024 * 1024) return error.ImageLimit;
    return result;
}
