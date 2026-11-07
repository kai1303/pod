//! Inline image framing: dictionary aliases and codec EOD, never an EI byte search.
const std = @import("std");
const d = @import("document.zig");
const s = @import("syntax.zig");
const images = @import("images.zig");
const filters = @import("filters.zig");
const eq = std.mem.eql;
const keys = [_][2][]const u8{
    .{ "BPC", "BitsPerComponent" }, .{ "CS", "ColorSpace" }, .{ "D", "Decode" },
    .{ "DP", "DecodeParms" },       .{ "F", "Filter" },      .{ "H", "Height" },
    .{ "IM", "ImageMask" },         .{ "Intent", "Intent" }, .{ "I", "Interpolate" },
    .{ "W", "Width" },
};
const filter_names = [_][2][]const u8{
    .{ "AHx", "ASCIIHexDecode" }, .{ "A85", "ASCII85Decode" },  .{ "LZW", "LZWDecode" },
    .{ "Fl", "FlateDecode" },     .{ "RL", "RunLengthDecode" }, .{ "CCF", "CCITTFaxDecode" },
    .{ "DCT", "DCTDecode" },
};
fn direct(value: s.Value) anyerror!void {
    switch (value) {
        .ref => return error.InvalidInlineImage,
        .array => |items| for (items) |item| try direct(item),
        .dict => |entries| for (entries) |entry| try direct(entry.value),
        else => {},
    }
}
fn alias(value: *s.Value, names: []const [2][]const u8) void {
    if (value.* != .name) return;
    for (names) |pair| if (eq(u8, value.name, pair[0])) {
        value.* = .{ .name = pair[1] };
        return;
    };
}
fn colorSpace(value: *s.Value) !void {
    const devices = [_][2][]const u8{ .{ "G", "DeviceGray" }, .{ "RGB", "DeviceRGB" }, .{ "CMYK", "DeviceCMYK" } };
    if (value.* == .name) {
        alias(value, &devices);
    } else if (value.* == .array) {
        const items = value.array;
        if (items.len != 4) return error.InvalidInlineImage;
        alias(&items[0], &.{.{ "I", "Indexed" }});
        if (items[0] != .name or !eq(u8, items[0].name, "Indexed") or items[3] != .string) return error.InvalidInlineImage;
        alias(&items[1], &devices);
        if (items[1] != .name) return error.InvalidInlineImage;
        for (devices) |pair| if (eq(u8, items[1].name, pair[1])) return;
        return error.InvalidInlineImage;
    } else if (value.* != .null) return error.InvalidInlineImage;
}
// Returned samples and inline palette live in the caller's scratch arena, through
// the synchronous image callback. Resource profiles retain document ownership.
pub fn read(doc: *d.Document, parser: *s.Parser, resources: s.Value, a: std.mem.Allocator) !images.Image {
    const previous = parser.allocator;
    parser.allocator = a;
    defer parser.allocator = previous;
    var entries: std.ArrayList(s.Entry) = .empty;
    defer entries.deinit(a);
    var count: usize = 0;
    while (!parser.keyword("ID")) {
        count += 1;
        if (count > 128) return error.OperandLimit;
        const key = try parser.value();
        if (key != .name) return error.InvalidInlineImage;
        var value = try parser.value();
        try direct(value);
        for (keys) |pair| {
            if (!eq(u8, key.name, pair[0]) and !eq(u8, key.name, pair[1])) continue;
            for (entries.items) |entry| if (eq(u8, entry.key, pair[1])) return error.InvalidInlineImage;
            if (eq(u8, pair[1], "Filter")) {
                if (value == .array) {
                    for (value.array) |*item| alias(item, &filter_names);
                } else alias(&value, &filter_names);
            } else if (eq(u8, pair[1], "ColorSpace")) try colorSpace(&value);
            try entries.append(a, .{ .key = pair[1], .value = value });
            break;
        }
    }
    // ID consumes one separator (a CRLF is one end-of-line). Further whitespace
    // is sample data; in particular, do not call Parser.skip here.
    if (parser.pos == parser.bytes.len or !s.ws(parser.bytes[parser.pos])) return error.InvalidInlineImage;
    const separator = parser.bytes[parser.pos];
    parser.pos += 1;
    if (separator == '\r' and parser.pos < parser.bytes.len and parser.bytes[parser.pos] == '\n') parser.pos += 1;
    try entries.append(a, .{ .key = "Subtype", .value = .{ .name = "Image" } });
    const dict = s.Value{ .dict = entries.items };
    var image = try images.describe(doc, dict, resources, false);
    const bytes = parser.bytes[parser.pos..];
    const filter = s.get(dict, "Filter") orelse .null;
    var consumed: usize = 0;
    if (filter == .null or (filter == .array and filter.array.len == 0)) {
        consumed = image.stride * image.height;
        if (consumed > bytes.len) return error.InvalidImageData;
        image.data = bytes[0..consumed];
    } else {
        var object = d.Object{ .value = dict, .body = &.{}, .stream = bytes };
        image.data = try filters.decodePrefix(doc, &object, a, 64 * 1024 * 1024, &consumed);
        if (image.data.len != image.stride * image.height) return error.InvalidImageData;
    }
    parser.pos += consumed;
    if (parser.pos == parser.bytes.len or !s.ws(parser.bytes[parser.pos])) return error.InvalidInlineImage;
    if (!parser.keyword("EI")) return error.InvalidInlineImage;
    return image;
}
