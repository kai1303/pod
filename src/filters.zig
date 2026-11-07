//! PDF stream filters (ISO 32000-1, section 7.4).
const std = @import("std");
const d = @import("document.zig");
const s = @import("syntax.zig");
const A = std.mem.Allocator;

pub fn decode(doc: *d.Document, obj: *d.Object, allocator: A, limit: usize) ![]const u8 {
    return decodePrefix(doc, obj, allocator, limit, null);
}
// A non-null consumed pointer frames an inline image by the first filter's EOD.
// Never search binary data for EI or decode successive candidate prefixes.
pub fn decodePrefix(doc: *d.Document, obj: *d.Object, allocator: A, limit: usize, consumed: ?*usize) ![]const u8 {
    var bytes = obj.changed orelse obj.stream orelse return error.InvalidStream;
    if (s.get(obj.value, "F") != null) return error.UnsupportedExternalStream;
    const filter = try doc.resolve(s.get(obj.value, "Filter") orelse .null);
    if (filter == .null) {
        if (consumed) |n| n.* = bytes.len;
        if (bytes.len > limit) return error.DecodedStreamLimit;
        return bytes;
    }
    const filters: []const s.Value = if (filter == .array) filter.array else &.{filter};
    if (filters.len > 16) return error.FilterLimit;
    if (filters.len == 0) if (consumed) |n| {
        n.* = bytes.len;
    };
    const params = try doc.resolve(s.get(obj.value, "DecodeParms") orelse .null);
    if (params != .null and ((filter == .array and (params != .array or params.array.len != filters.len)) or
        (filter != .array and params != .dict))) return error.InvalidDecodeParameters;
    // Release each stage before advancing, so chains cannot retain every expanded buffer.
    const a = doc.arena.child_allocator;
    var owned: ?[]const u8 = null;
    defer if (owned) |buffer| a.free(buffer);
    for (filters, 0..) |raw, index| {
        const name = try doc.resolve(raw);
        if (name != .name) return error.InvalidFilter;
        const param = try doc.resolve(if (params == .array) params.array[index] else params);
        if (param != .null and param != .dict) return error.InvalidDecodeParameters;
        const end = if (index == 0) consumed else null;
        const next = if (std.mem.eql(u8, name.name, "FlateDecode") or std.mem.eql(u8, name.name, "LZWDecode")) blk: {
            const inflated = if (std.mem.eql(u8, name.name, "FlateDecode"))
                try flate(a, bytes, limit, end)
            else
                try lzw(a, bytes, try parameter(doc, param, "EarlyChange", 1), limit, end);
            const predicted = predictor(doc, a, inflated, param, limit) catch |err| {
                a.free(inflated);
                return err;
            };
            if (predicted.ptr != inflated.ptr) a.free(inflated);
            break :blk predicted;
        } else if (std.mem.eql(u8, name.name, "ASCIIHexDecode")) blk: {
            const subtype = try doc.resolve(s.get(obj.value, "Subtype") orelse .null);
            // Pillow omits > on length-delimited images; image loading checks sample count.
            break :blk try asciiHex(a, bytes, limit, consumed == null and subtype == .name and std.mem.eql(u8, subtype.name, "Image"), end);
        } else if (std.mem.eql(u8, name.name, "ASCII85Decode"))
            try ascii85(a, bytes, limit, end)
        else if (std.mem.eql(u8, name.name, "RunLengthDecode"))
            try runLength(a, bytes, limit, end)
        else if (std.mem.eql(u8, name.name, "CCITTFaxDecode"))
            try fax(doc, obj, param, a, bytes, limit, end)
        else if (std.mem.eql(u8, name.name, "DCTDecode"))
            try dct(doc, obj, param, a, bytes, limit, end)
        else
            return error.UnsupportedFilter;
        if (owned) |buffer| a.free(buffer);
        owned = next;
        bytes = next;
    }
    if (bytes.len > limit) return error.DecodedStreamLimit;
    return allocator.dupe(u8, bytes);
}

fn fax(doc: *d.Document, object: *d.Object, params: s.Value, a: A, bytes: []const u8, limit: usize, consumed: ?*usize) ![]const u8 {
    const k = try doc.resolve(s.get(params, "K") orelse .{ .integer = 0 });
    if (k != .integer and k != .null) return error.InvalidDecodeParameters;
    const end_of_block = try booleanParameter(doc, params, "EndOfBlock", true);
    const rows = try parameter(doc, params, "Rows", 0);
    const image = try @import("fax.zig").decode(a, bytes, .{
        .k = if (k == .null) 0 else k.integer,
        .columns = try parameter(doc, params, "Columns", 1728),
        // An unbounded inline stream has no byte length. Its image height gives
        // the row boundary when the fax parameters omit Rows and an end marker.
        .rows = if (consumed != null and rows == 0 and !end_of_block) try parameter(doc, object.value, "Height", 0) else rows,
        .end_of_line = try booleanParameter(doc, params, "EndOfLine", false),
        .byte_align = try booleanParameter(doc, params, "EncodedByteAlign", false),
        .end_of_block = end_of_block,
        .black_is_one = try booleanParameter(doc, params, "BlackIs1", false),
        .damaged_rows = try parameter(doc, params, "DamagedRowsBeforeError", 0),
    }, limit);
    errdefer a.free(image.data);
    const subtype = try doc.resolve(s.get(object.value, "Subtype") orelse .null);
    if (subtype == .name and std.mem.eql(u8, subtype.name, "Image")) {
        if (try parameter(doc, object.value, "Width", 0) != image.width or
            try parameter(doc, object.value, "Height", 0) != image.height or
            try parameter(doc, object.value, "BitsPerComponent", 1) != 1) return error.InvalidImageData;
    }
    if (consumed) |n| n.* = image.consumed;
    return image.data;
}
fn booleanParameter(doc: *d.Document, params: s.Value, key: []const u8, default: bool) !bool {
    const value = try doc.resolve(s.get(params, key) orelse return default);
    if (value == .null) return default;
    if (value != .boolean) return error.InvalidDecodeParameters;
    return value.boolean;
}

fn dct(doc: *d.Document, object: *d.Object, params: s.Value, a: A, bytes: []const u8, limit: usize, consumed: ?*usize) ![]const u8 {
    var transform: ?bool = null;
    const setting = try doc.resolve(s.get(params, "ColorTransform") orelse .null);
    if (setting != .null) {
        if (setting != .integer or (setting.integer != 0 and setting.integer != 1)) return error.InvalidDecodeParameters;
        transform = setting.integer == 1;
    }
    const image = try @import("jpeg.zig").decode(a, bytes, transform, limit);
    errdefer a.free(image.pixels);
    const subtype = try doc.resolve(s.get(object.value, "Subtype") orelse .null);
    if (subtype == .name and std.mem.eql(u8, subtype.name, "Image")) {
        const width = try parameter(doc, object.value, "Width", 0);
        const height = try parameter(doc, object.value, "Height", 0);
        const bits = try parameter(doc, object.value, "BitsPerComponent", 0);
        if (width != image.width or height != image.height or bits != 8) return error.InvalidImageData;
    }
    if (consumed) |n| n.* = image.consumed;
    return image.pixels;
}

fn flate(a: A, bytes: []const u8, limit: usize, consumed: ?*usize) ![]const u8 {
    var input: std.Io.Reader = .fixed(bytes);
    var decompressor = std.compress.flate.Decompress.init(&input, .zlib, &.{});
    const result = decompressor.reader.allocRemaining(a, .limited(limit)) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.StreamTooLong => error.DecodedStreamLimit,
        else => error.InvalidCompressedStream,
    };
    errdefer a.free(result);
    if (std.hash.Adler32.hash(result) != decompressor.container_metadata.zlib.adler) return error.InvalidStreamChecksum;
    if (consumed) |n| n.* = input.seek;
    return result;
}

fn append(out: *std.ArrayList(u8), a: A, bytes: []const u8, limit: usize) !void {
    if (bytes.len > limit - out.items.len) return error.DecodedStreamLimit;
    try out.appendSlice(a, bytes);
}
fn asciiHex(a: A, bytes: []const u8, limit: usize, image_eof: bool, consumed: ?*usize) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(a);
    var high: ?u8 = null;
    for (bytes, 0..) |ch, index| {
        if (s.ws(ch)) continue;
        if (ch == '>') {
            if (consumed) |n| n.* = index + 1;
            if (high) |n| try append(&out, a, &.{n << 4}, limit);
            return out.toOwnedSlice(a);
        }
        const digit = std.fmt.charToDigit(ch, 16) catch return error.InvalidASCIIHex;
        if (high) |n| {
            try append(&out, a, &.{n << 4 | digit}, limit);
            high = null;
        } else high = digit;
    }
    if (!image_eof) return error.InvalidASCIIHex;
    if (high) |n| try append(&out, a, &.{n << 4}, limit);
    return out.toOwnedSlice(a);
}
fn ascii85(a: A, bytes: []const u8, limit: usize, consumed: ?*usize) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(a);
    var value: u64 = 0;
    var count: usize = 0;
    var index: usize = 0;
    while (index < bytes.len) : (index += 1) {
        const ch = bytes[index];
        if (s.ws(ch)) continue;
        if (ch == '~') {
            if (index + 1 >= bytes.len or bytes[index + 1] != '>' or count == 1) return error.InvalidASCII85;
            if (consumed) |n| n.* = index + 2;
            if (count > 0) {
                for (count..5) |_| value = value * 85 + 84;
                if (value > std.math.maxInt(u32)) return error.InvalidASCII85;
                var group: [4]u8 = undefined;
                std.mem.writeInt(u32, &group, @intCast(value), .big);
                try append(&out, a, group[0 .. count - 1], limit);
            }
            return out.toOwnedSlice(a);
        }
        if (ch == 'z') {
            if (count != 0) return error.InvalidASCII85;
            try append(&out, a, &.{ 0, 0, 0, 0 }, limit);
            continue;
        }
        if (ch < '!' or ch > 'u') return error.InvalidASCII85;
        value = value * 85 + ch - '!';
        count += 1;
        if (count == 5) {
            if (value > std.math.maxInt(u32)) return error.InvalidASCII85;
            var group: [4]u8 = undefined;
            std.mem.writeInt(u32, &group, @intCast(value), .big);
            try append(&out, a, &group, limit);
            value = 0;
            count = 0;
        }
    }
    return error.InvalidASCII85;
}
fn runLength(a: A, bytes: []const u8, limit: usize, consumed: ?*usize) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(a);
    var index: usize = 0;
    while (index < bytes.len) {
        const length = bytes[index];
        index += 1;
        if (length == 128) {
            if (consumed) |n| n.* = index;
            return out.toOwnedSlice(a);
        }
        if (length < 128) {
            const count = @as(usize, length) + 1;
            if (count > bytes.len - index) return error.InvalidRunLength;
            try append(&out, a, bytes[index..][0..count], limit);
            index += count;
        } else {
            if (index == bytes.len) return error.InvalidRunLength;
            const count = 257 - @as(usize, length);
            if (count > limit - out.items.len) return error.DecodedStreamLimit;
            try out.appendNTimes(a, bytes[index], count);
            index += 1;
        }
    }
    return error.InvalidRunLength;
}

fn lzw(a: A, bytes: []const u8, early_change: usize, limit: usize, consumed: ?*usize) ![]const u8 {
    if (early_change > 1) return error.InvalidDecodeParameters;
    const Entry = struct { start: usize, length: usize };
    var dictionary: [4096]Entry = undefined;
    var next: usize = 258;
    var width: usize = 9;
    var bit: usize = 0;
    var previous: ?Entry = null;
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(a);
    while (bytes.len * 8 - bit >= width) {
        var code: usize = 0;
        for (0..width) |_| {
            code = code * 2 + ((bytes[bit / 8] >> @as(u3, @intCast(7 - bit % 8))) & 1);
            bit += 1;
        }
        if (code == 256) {
            next = 258;
            width = 9;
            previous = null;
            continue;
        }
        if (code == 257) {
            if (consumed) |n| n.* = (bit + 7) / 8;
            return out.toOwnedSlice(a);
        }
        const start = out.items.len;
        if (code < 256) {
            try append(&out, a, &.{@intCast(code)}, limit);
        } else {
            const special = code == next;
            const entry = if (special) previous orelse return error.InvalidLZW else blk: {
                if (code >= next) return error.InvalidLZW;
                break :blk dictionary[code];
            };
            const count = entry.length + @intFromBool(special);
            if (count > limit - out.items.len) return error.DecodedStreamLimit;
            // Dictionary entries refer to earlier output. Reserve before borrowing its slice.
            try out.ensureUnusedCapacity(a, count);
            out.appendSliceAssumeCapacity(out.items[entry.start..][0..entry.length]);
            if (special) out.appendAssumeCapacity(out.items[entry.start]);
        }
        if (previous) |entry| {
            if (next < dictionary.len) {
                // The previous sequence and this sequence's first byte are adjacent in output.
                dictionary[next] = .{ .start = entry.start, .length = entry.length + 1 };
                next += 1;
                if (width < 12 and next + early_change == @as(usize, 1) << @intCast(width)) width += 1;
            }
        }
        previous = .{ .start = start, .length = out.items.len - start };
    }
    return error.InvalidLZW;
}

fn parameter(doc: *d.Document, params: s.Value, key: []const u8, default: usize) !usize {
    const value = try doc.resolve(s.get(params, key) orelse return default);
    return if (value == .null) default else s.uint(value);
}
fn predictor(doc: *d.Document, a: A, bytes: []const u8, params: s.Value, limit: usize) ![]const u8 {
    const kind = try parameter(doc, params, "Predictor", 1);
    if (kind == 1) return bytes;
    if (kind != 2 and (kind < 10 or kind > 15)) return error.InvalidDecodeParameters;
    const colors = try parameter(doc, params, "Colors", 1);
    const columns = try parameter(doc, params, "Columns", 1);
    const bits = try parameter(doc, params, "BitsPerComponent", 8);
    if (colors == 0 or colors > 32 or columns == 0 or columns > 1_000_000 or
        (bits != 1 and bits != 2 and bits != 4 and bits != 8 and bits != 16)) return error.InvalidDecodeParameters;
    const samples = colors * columns;
    const row_bytes = (samples * bits + 7) / 8;
    const stride = row_bytes + @intFromBool(kind != 2);
    if (bytes.len % stride != 0) return error.InvalidPredictorData;
    const size = bytes.len / stride * row_bytes;
    if (size > limit) return error.DecodedStreamLimit;
    const out = try a.alloc(u8, size);
    errdefer a.free(out);
    const pixel_bytes = (colors * bits + 7) / 8;
    var row: usize = 0;
    while (row < size) : (row += row_bytes) {
        const source = bytes[row / row_bytes * stride ..][0..stride];
        const current = out[row..][0..row_bytes];
        if (kind == 2) {
            @memcpy(current, source);
            const mask: u32 = (@as(u32, 1) << @intCast(bits)) - 1;
            for (colors..samples) |sample| {
                const value = (readSample(current, sample, bits) + readSample(current, sample - colors, bits)) & mask;
                writeSample(current, sample, bits, value);
            }
            continue;
        }
        if (source[0] > 4) return error.InvalidPredictorData;
        for (current, 0..) |*dest, column| {
            const left: u8 = if (column >= pixel_bytes) current[column - pixel_bytes] else 0;
            const up: u8 = if (row > 0) out[row - row_bytes + column] else 0;
            const upper_left: u8 = if (row > 0 and column >= pixel_bytes) out[row - row_bytes + column - pixel_bytes] else 0;
            const prediction: u8 = switch (source[0]) {
                0 => 0,
                1 => left,
                2 => up,
                3 => @intCast((@as(u16, left) + up) / 2),
                4 => paeth(left, up, upper_left),
                else => unreachable,
            };
            dest.* = source[column + 1] +% prediction;
        }
    }
    return out;
}
fn readSample(bytes: []const u8, index: usize, bits: usize) u32 {
    const offset = index * bits;
    if (bits == 16) return std.mem.readInt(u16, bytes[offset / 8 ..][0..2], .big);
    const shift: u3 = @intCast(8 - bits - offset % 8);
    return (bytes[offset / 8] >> shift) & ((@as(u32, 1) << @intCast(bits)) - 1);
}
fn writeSample(bytes: []u8, index: usize, bits: usize, value: u32) void {
    const offset = index * bits;
    if (bits == 16) return std.mem.writeInt(u16, bytes[offset / 8 ..][0..2], @intCast(value), .big);
    const shift: u3 = @intCast(8 - bits - offset % 8);
    const mask: u8 = @intCast(((@as(u32, 1) << @intCast(bits)) - 1) << shift);
    bytes[offset / 8] = (bytes[offset / 8] & ~mask) | (@as(u8, @intCast(value)) << shift);
}
fn paeth(left: u8, up: u8, upper_left: u8) u8 {
    const p = @as(i32, left) + up - upper_left;
    const dl = @abs(p - left);
    const du = @abs(p - up);
    const dc = @abs(p - upper_left);
    if (dl <= du and dl <= dc) return left;
    return if (du <= dc) up else upper_left;
}

test "ASCII filters handle whitespace, short groups, zero runs, corruption and limits" {
    const a = std.testing.allocator;
    const hex = try asciiHex(a, " 61\n62 6>ignored", 3, false, null);
    defer a.free(hex);
    try std.testing.expectEqualSlices(u8, &.{ 'a', 'b', 0x60 }, hex);
    try std.testing.expectError(error.InvalidASCIIHex, asciiHex(a, "6x>", 9, false, null));
    try std.testing.expectError(error.InvalidASCIIHex, asciiHex(a, "61", 9, false, null));
    try std.testing.expectError(error.DecodedStreamLimit, asciiHex(a, "6162>", 1, false, null));
    const base85 = try ascii85(a, "87cURD_*#TDfTZ)+T~>", 14, null);
    defer a.free(base85);
    try std.testing.expectEqualStrings("Hello, world!", base85);
    const zero = try ascii85(a, "z!!~>", 5, null);
    defer a.free(zero);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 0, 0 }, zero);
    for ([_][]const u8{ "!~>", "!z~>", "uuuuu~>", "!!~", "!!" }) |bad|
        try std.testing.expectError(error.InvalidASCII85, ascii85(a, bad, 32, null));
    try std.testing.expectError(error.DecodedStreamLimit, ascii85(a, "z~>", 3, null));
    const runs = try runLength(a, &.{ 1, 'a', 'b', 254, 'c', 128 }, 5, null);
    defer a.free(runs);
    try std.testing.expectEqualStrings("abccc", runs);
    try std.testing.expectError(error.InvalidRunLength, runLength(a, &.{ 2, 'a', 128 }, 5, null));
    try std.testing.expectError(error.InvalidRunLength, runLength(a, &.{255}, 5, null));
    try std.testing.expectError(error.InvalidRunLength, runLength(a, &.{ 0, 'a' }, 5, null));
    try std.testing.expectError(error.DecodedStreamLimit, runLength(a, &.{ 129, 'a', 128 }, 127, null));
}

test "Flate validates checksum, truncation and expansion limit" {
    const a = std.testing.allocator;
    // Python zlib.compress(b'Hello, world!')
    const compressed = "\x78\x9c\xf3\x48\xcd\xc9\xc9\xd7\x51\x28\xcf\x2f\xca\x49\x51\x04\x00\x20\x5e\x04\x8a";
    const plain = try flate(a, compressed, 13, null);
    defer a.free(plain);
    try std.testing.expectEqualStrings("Hello, world!", plain);
    try std.testing.expectError(error.DecodedStreamLimit, flate(a, compressed, 12, null));
    for (0..compressed.len) |length|
        try std.testing.expectError(error.InvalidCompressedStream, flate(a, compressed[0..length], 64, null));
    var broken = compressed.*;
    broken[broken.len - 1] ^= 1;
    try std.testing.expectError(error.InvalidStreamChecksum, flate(a, &broken, 64, null));
}

test "PNG and TIFF predictors decode multiple rows and packed samples" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "predictors");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    var entries = [_]s.Entry{
        .{ .key = "Predictor", .value = .{ .integer = 15 } },
        .{ .key = "Columns", .value = .{ .integer = 3 } },
        .{ .key = "BitsPerComponent", .value = .{ .integer = 8 } },
    };
    const params: s.Value = .{ .dict = &entries };
    const decoded = try predictor(&doc, a, &.{ 0, 10, 20, 30, 1, 10, 10, 10, 2, 0, 0, 0, 3, 5, 5, 5, 4, 0, 0, 0 }, params, 15);
    defer a.free(decoded);
    try std.testing.expectEqualSlices(u8, &.{ 10, 20, 30, 10, 20, 30, 10, 20, 30, 10, 20, 30, 10, 20, 30 }, decoded);
    try std.testing.expectError(error.InvalidPredictorData, predictor(&doc, a, &.{ 5, 1, 2, 3 }, params, 16));
    try std.testing.expectError(error.InvalidPredictorData, predictor(&doc, a, &.{ 0, 1 }, params, 16));
    entries[0].value = .{ .integer = 2 };
    entries[2].value = .{ .integer = 4 };
    const packed_samples = try predictor(&doc, a, &.{ 0x12, 0x3a, 0xf2, 0x3b }, params, 4);
    defer a.free(packed_samples);
    try std.testing.expectEqualSlices(u8, &.{ 0x13, 0x6a, 0xf1, 0x4b }, packed_samples);
    entries[2].value = .{ .integer = 1 };
    entries[1].value = .{ .integer = 8 };
    const one_bit = try predictor(&doc, a, &.{0xd8}, params, 1);
    defer a.free(one_bit);
    try std.testing.expectEqualSlices(u8, &.{0x90}, one_bit);
    entries[2].value = .{ .integer = 2 };
    entries[1].value = .{ .integer = 4 };
    const two_bit = try predictor(&doc, a, &.{0x55}, params, 1);
    defer a.free(two_bit);
    try std.testing.expectEqualSlices(u8, &.{0x6c}, two_bit);
    entries[2].value = .{ .integer = 8 };
    entries[1].value = .{ .integer = 3 };
    const eight_bit = try predictor(&doc, a, &.{ 250, 10, 5 }, params, 3);
    defer a.free(eight_bit);
    try std.testing.expectEqualSlices(u8, &.{ 250, 4, 9 }, eight_bit);
    entries[2].value = .{ .integer = 16 };
    const wide = try predictor(&doc, a, &.{ 0xff, 0xfe, 0, 3, 0, 5 }, params, 6);
    defer a.free(wide);
    try std.testing.expectEqualSlices(u8, &.{ 0xff, 0xfe, 0, 1, 0, 6 }, wide);
}

test "filtered streams survive untouched saves, metadata changes, page extraction and text edits" {
    const a = std.testing.allocator;
    const seed = try @import("pod.zig").create(a, "placeholder");
    defer a.free(seed);
    var doc = try d.Document.open(a, seed);
    defer doc.deinit();
    const obj = try doc.object(.{ .id = 5, .generation = 0 });
    // ASCIIHex encoding supplied independently of the engine's serializer.
    obj.changed = "4254202f463120313220546620373220373230205464202848656c6c6f2920546a2028576f726c642920546a204554>";
    try doc.set(obj, "Filter", .{ .name = "ASCIIHexDecode" });
    const original = try doc.save(a);
    defer a.free(original);
    var reopened = try d.Document.open(a, original);
    defer reopened.deinit();
    const pages = try reopened.inspect();
    try std.testing.expectEqualStrings("Hello", pages[0].runs[0].text);
    const following_x = pages[0].runs[1].x;
    const stream_obj = try reopened.object(.{ .id = 5, .generation = 0 });
    const cached_bytes = reopened.decoded_bytes;
    _ = try reopened.streamData(stream_obj);
    try std.testing.expectEqual(cached_bytes, reopened.decoded_bytes);
    // A dirty stream dictionary must still serialize the original encoded bytes.
    try reopened.set(stream_obj, "CustomMetadata", .{ .string = "preserve" });
    const metadata_save = try reopened.save(a);
    defer a.free(metadata_save);
    var metadata_doc = try d.Document.open(a, metadata_save);
    defer metadata_doc.deinit();
    try std.testing.expectEqualStrings("Hello", (try metadata_doc.inspect())[0].runs[0].text);
    const extracted = try @import("page_tools.zig").assemble(a, &.{.{ .doc = &reopened, .pages = &.{0} }});
    defer a.free(extracted);
    var extracted_doc = try d.Document.open(a, extracted);
    defer extracted_doc.deinit();
    try std.testing.expectEqualStrings("Hello", (try extracted_doc.inspect())[0].runs[0].text);
    try @import("render.zig").validate(&extracted_doc);
    try reopened.replace(1, 0, "Hi");
    try std.testing.expect(s.get(stream_obj.value, "Filter") == null);
    const saved = try reopened.save(a);
    defer a.free(saved);
    var edited = try d.Document.open(a, saved);
    defer edited.deinit();
    const runs = (try edited.inspect())[0].runs;
    try std.testing.expectEqualStrings("Hi", runs[0].text);
    try std.testing.expectEqual(following_x, runs[1].x);
    try @import("render.zig").validate(&edited);
}

test "filter dictionaries resolve references and reject invalid chains and parameters" {
    const a = std.testing.allocator;
    const seed = try @import("pod.zig").create(a, "filters");
    defer a.free(seed);
    var doc = try d.Document.open(a, seed);
    defer doc.deinit();
    const obj = try doc.object(.{ .id = 5, .generation = 0 });
    obj.changed = "61>";
    const filter_id = try doc.addObject(.{ .name = "ASCIIHexDecode" }, null);
    try doc.set(obj, "Filter", .{ .ref = .{ .id = filter_id, .generation = 0 } });
    try std.testing.expectEqualStrings("a", try doc.streamData(obj));
    try doc.set(obj, "DecodeParms", .{ .array = &.{} });
    try std.testing.expectError(error.InvalidDecodeParameters, doc.streamData(obj));
    try doc.set(obj, "DecodeParms", .null);
    try doc.set(obj, "Filter", .{ .name = "Unknown" });
    try std.testing.expectError(error.UnsupportedFilter, doc.streamData(obj));
    var invalid_filters = [_]s.Value{.{ .integer = 1 }};
    try doc.set(obj, "Filter", .{ .array = &invalid_filters });
    try std.testing.expectError(error.InvalidFilter, doc.streamData(obj));
    try doc.set(obj, "Filter", .{ .name = "ASCIIHexDecode" });
    try doc.set(obj, "F", .{ .string = "external" });
    try std.testing.expectError(error.UnsupportedExternalStream, doc.streamData(obj));
}

test "LZW handles dictionary growth, the next-code case and malformed input" {
    const a = std.testing.allocator;
    // ISO 32000-1 table 10: clear, '-', 258, 258, 'A', 259, 'B', EOD.
    const sample = "\x80\x0b\x60\x50\x22\x0c\x0c\x85\x01";
    const plain = try lzw(a, sample, 1, 10, null);
    defer a.free(plain);
    try std.testing.expectEqualStrings("-----A---B", plain);
    try std.testing.expectError(error.DecodedStreamLimit, lzw(a, sample, 1, 9, null));
    try std.testing.expectError(error.InvalidDecodeParameters, lzw(a, sample, 2, 100, null));
    try std.testing.expectError(error.InvalidLZW, lzw(a, sample[0..8], 1, 100, null));
    try std.testing.expectError(error.InvalidLZW, lzw(a, "\x80\x4b\x20\x20", 1, 100, null));
}

test "page views own decoded caches even when the source index has resolved the stream" {
    const a = std.testing.allocator;
    const seed = try @import("pod.zig").create(a, "cache");
    defer a.free(seed);
    var owner = try d.Document.open(a, seed);
    defer owner.deinit();
    const ref: s.Ref = .{ .id = 5, .generation = 0 };
    const shared = try owner.object(ref);
    shared.changed = "61>";
    try owner.set(shared, "Filter", .{ .name = "ASCIIHexDecode" });
    for (0..2) |_| {
        var page = d.Document{
            .arena = std.heap.ArenaAllocator.init(a),
            .bytes = owner.bytes,
            .entries = owner.entries,
            .page_objects = .empty,
        };
        defer page.deinit();
        const local = try page.object(ref);
        try std.testing.expect(local != shared);
        try std.testing.expectEqualStrings("a", try page.streamData(local));
        try std.testing.expect(shared.decoded == null);
    }
    try std.testing.expectEqualStrings("a", try owner.streamData(shared));
}

test "decoded stream budgets apply before interpretation and cached reads reuse their allocation" {
    const a = std.testing.allocator;
    const seed = try @import("pod.zig").create(a, "limits");
    defer a.free(seed);
    var doc = try d.Document.open(a, seed);
    defer doc.deinit();
    const obj = try doc.object(.{ .id = 5, .generation = 0 });
    obj.changed = "6162>";
    try doc.set(obj, "Filter", .{ .name = "ASCIIHexDecode" });
    doc.decoded_bytes = 256 * 1024 * 1024 - 1;
    try std.testing.expectError(error.DecodedStreamLimit, doc.streamData(obj));
    try std.testing.expect(obj.decoded == null);
    doc.decoded_bytes -= 1;
    try std.testing.expectEqualStrings("ab", try doc.streamData(obj));
    try std.testing.expectEqualStrings("ab", try doc.streamData(obj));
    try std.testing.expectEqual(@as(usize, 256 * 1024 * 1024), doc.decoded_bytes);
    obj.changed = "6364>";
    try std.testing.expectError(error.DecodedStreamLimit, doc.streamData(obj));
}

test "inline filter prefixes report the first EOD without consuming following operators" {
    const a = std.testing.allocator;
    const seed = try @import("pod.zig").create(a, "");
    defer a.free(seed);
    var doc = try d.Document.open(a, seed);
    defer doc.deinit();
    var empty_entries = [_]s.Entry{.{ .key = "Filter", .value = .{ .array = &.{} } }};
    var empty = d.Object{ .value = .{ .dict = &empty_entries }, .body = "", .stream = "raw" };
    var raw_length: usize = 0;
    const raw = try decodePrefix(&doc, &empty, a, 3, &raw_length);
    defer a.free(raw);
    try std.testing.expectEqualStrings("raw", raw);
    try std.testing.expectEqual(@as(usize, 3), raw_length);
    const cases = [_]struct { name: []const u8, encoded: []const u8, plain: []const u8 }{
        .{ .name = "ASCIIHexDecode", .encoded = "20454920>", .plain = " EI " },
        .{ .name = "ASCII85Decode", .encoded = "z~>", .plain = "\x00\x00\x00\x00" },
        .{ .name = "RunLengthDecode", .encoded = "\x03 EI \x80", .plain = " EI " },
        .{ .name = "LZWDecode", .encoded = "\x80\x0b\x60\x50\x22\x0c\x0c\x85\x01", .plain = "-----A---B" },
        .{ .name = "FlateDecode", .encoded = "\x78\x9c\xf3\x48\xcd\xc9\xc9\xd7\x51\x28\xcf\x2f\xca\x49\x51\x04\x00\x20\x5e\x04\x8a", .plain = "Hello, world!" },
    };
    for (cases) |case| {
        const bytes = try std.mem.concat(a, u8, &.{ case.encoded, " EI Q 1 0 0 rg" });
        defer a.free(bytes);
        var entries = [_]s.Entry{.{ .key = "Filter", .value = .{ .name = case.name } }};
        var obj = d.Object{ .value = .{ .dict = &entries }, .body = "", .stream = bytes };
        var consumed: usize = 0;
        const decoded = try decodePrefix(&doc, &obj, a, 64, &consumed);
        defer a.free(decoded);
        try std.testing.expectEqualStrings(case.plain, decoded);
        try std.testing.expectEqual(case.encoded.len, consumed);
    }
}
