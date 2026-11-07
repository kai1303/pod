const std = @import("std");
const pod = @import("pod.zig");
const s = @import("syntax.zig");
const render = @import("render.zig");
const a = std.testing.allocator;
fn parse(doc: *pod.Document, bytes: []const u8) !s.Value {
    var p = s.Parser{ .bytes = bytes, .allocator = doc.allocator() };
    return p.value();
}
const Fixture = struct {
    bytes: []u8,
    doc: pod.Document,
    fn init(entries: []const u8, samples: []const u8, content: []const u8) !Fixture {
        const bytes = try pod.create(a, "test");
        errdefer a.free(bytes);
        var doc = try pod.Document.open(a, bytes);
        errdefer doc.deinit();
        const dict = try std.fmt.allocPrint(doc.allocator(), "<< /Type /XObject /Subtype /Image {s} >>", .{entries});
        _ = try doc.addObject(try parse(&doc, dict), samples);
        try doc.set(try doc.object(.{ .id = 3, .generation = 0 }), "Resources", try parse(&doc, "<< /XObject << /Im 6 0 R >> >>"));
        try doc.replaceStream(try doc.object(.{ .id = 5, .generation = 0 }), content);
        return .{ .bytes = bytes, .doc = doc };
    }
    fn deinit(self: *Fixture) void {
        self.doc.deinit();
        a.free(self.bytes);
    }
};
fn pixel(b: render.Bitmap, x: usize, y: usize) []const u8 {
    return b.pixels[((b.height - 1 - y) * b.width + x) * 4 ..][0..4];
}
test "sampled RGB image orientation clipping state and save round trip" {
    var f = try Fixture.init("/Width 2 /Height 2 /BitsPerComponent 8 /ColorSpace /DeviceRGB", &.{ 255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 0 }, "q 50 100 150 200 re W n 200 0 0 200 50 100 cm /Im Do Q 0 0 0 rg 300 100 10 10 re f");
    defer f.deinit();
    const bitmap = try render.render(a, &f.doc, 0, &.{}, 612);
    defer a.free(bitmap.pixels);
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, pixel(bitmap, 75, 250));
    try std.testing.expectEqualSlices(u8, &.{ 0, 255, 0, 255 }, pixel(bitmap, 175, 250));
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 255, 255 }, pixel(bitmap, 75, 150));
    try std.testing.expectEqualSlices(u8, &.{ 255, 255, 0, 255 }, pixel(bitmap, 175, 150));
    try std.testing.expectEqualSlices(u8, &.{ 255, 255, 255, 255 }, pixel(bitmap, 225, 150));
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 255 }, pixel(bitmap, 305, 105));
    const saved = try f.doc.save(a);
    defer a.free(saved);
    var copy = try pod.Document.open(a, saved);
    defer copy.deinit();
    const second = try render.render(a, &copy, 0, &.{}, 612);
    defer a.free(second.pixels);
    try std.testing.expectEqualSlices(u8, bitmap.pixels, second.pixels);
}
test "packed grayscale rows decode reversal and stencil tint" {
    var f = try Fixture.init("/Width 3 /Height 2 /BitsPerComponent 2 /ColorSpace /DeviceGray /Decode [1 0]", &.{ 0x1b, 0xe4 }, "q 120 0 0 80 0 0 cm /Im Do Q");
    defer f.deinit();
    const bitmap = try render.render(a, &f.doc, 0, &.{}, 612);
    defer a.free(bitmap.pixels);
    try std.testing.expectEqualSlices(u8, &.{ 255, 255, 255, 255 }, pixel(bitmap, 10, 60));
    try std.testing.expectEqualSlices(u8, &.{ 170, 170, 170, 255 }, pixel(bitmap, 50, 60));
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 255 }, pixel(bitmap, 10, 20));
    var mask = try Fixture.init("/Width 2 /Height 1 /ImageMask true", &.{0x40}, "0 0 1 rg 0 0 120 80 re f 1 0 0 rg q 120 0 0 80 0 0 cm /Im Do Q");
    defer mask.deinit();
    const masked = try render.render(a, &mask.doc, 0, &.{}, 612);
    defer a.free(masked.pixels);
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, pixel(masked, 20, 40));
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 255, 255 }, pixel(masked, 100, 40));
}
test "images reject malformed samples sizes and unsupported masks" {
    const cases = [_]struct { entries: []const u8, data: []const u8, err: anyerror }{
        .{ .entries = "/Width 0 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceGray", .data = "", .err = error.InvalidImage },
        .{ .entries = "/Width 1000000 /Height 1000000 /BitsPerComponent 8 /ColorSpace /DeviceGray", .data = "", .err = error.ImageLimit },
        .{ .entries = "/Width 2 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceRGB", .data = "abc", .err = error.InvalidImageData },
        .{ .entries = "/Width 1 /Height 1 /BitsPerComponent 3 /ColorSpace /DeviceGray", .data = "a", .err = error.UnsupportedImageDepth },
        .{ .entries = "/Width 1 /Height 1 /ImageMask true /ColorSpace /DeviceGray", .data = "a", .err = error.InvalidImage },
        .{ .entries = "/Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceGray /SMask 6 0 R", .data = "a", .err = error.InvalidImage },
    };
    for (cases) |case| {
        var f = try Fixture.init(case.entries, case.data, "/Im Do");
        defer f.deinit();
        try std.testing.expectError(case.err, f.doc.inspect());
    }
}

test "transparent stencil does not contribute content bounds" {
    var f = try Fixture.init("/Width 3 /Height 1 /ImageMask true", &.{0xe0}, "q 120 0 0 80 40 60 cm /Im Do Q");
    defer f.deinit();
    try std.testing.expectEqual(@as(?[4]f64, null), try render.contentBoundsWithFonts(a, &f.doc, 0, &.{}));
}

fn minimalJPEG(progressive: bool) ![]u8 {
    var jpeg: std.ArrayList(u8) = .empty;
    defer jpeg.deinit(a);
    try jpeg.appendSlice(a, "\xff\xd8\xff\xdb\x00\x43\x00");
    try jpeg.appendNTimes(a, 1, 64);
    try jpeg.appendSlice(a, "\xff\xc0\x00\x0b\x08\x00\x01\x00\x01\x01\x01\x11\x00\xff\xc4\x00\x26");
    for ([_]u8{ 0, 0x10 }) |table| {
        try jpeg.append(a, table);
        try jpeg.append(a, 1);
        try jpeg.appendNTimes(a, 0, 15);
        try jpeg.append(a, 0);
    }
    if (progressive) {
        jpeg.items[72] = 0xc2;
        try jpeg.appendSlice(a, "\xff\xda\x00\x08\x01\x01\x00\x00\x00\x01\x7f");
        try jpeg.appendSlice(a, "\xff\xda\x00\x08\x01\x01\x00\x00\x00\x10\x7f");
        try jpeg.appendSlice(a, "\xff\xda\x00\x08\x01\x01\x00\x01\x3f\x01\x7f");
        try jpeg.appendSlice(a, "\xff\xda\x00\x08\x01\x01\x00\x01\x3f\x10\x7f\xff\xd9");
    } else try jpeg.appendSlice(a, "\xff\xda\x00\x08\x01\x01\x00\x00\x3f\x00\x3f\xff\xd9");
    return jpeg.toOwnedSlice(a);
}

test "DCTDecode renders a baseline grayscale JPEG and validates PDF dimensions" {
    const jpeg = try minimalJPEG(false);
    defer a.free(jpeg);
    var f = try Fixture.init("/Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceGray /Filter /DCTDecode", jpeg, "q 120 0 0 80 0 0 cm /Im Do Q");
    defer f.deinit();
    const bitmap = try render.render(a, &f.doc, 0, &.{}, 612);
    defer a.free(bitmap.pixels);
    try std.testing.expectEqualSlices(u8, &.{ 128, 128, 128, 255 }, pixel(bitmap, 20, 20));
    var wrong = try Fixture.init("/Width 2 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceGray /Filter /DCTDecode", jpeg, "/Im Do");
    defer wrong.deinit();
    try std.testing.expectError(error.InvalidImageData, wrong.doc.inspect());
}

test "JPEG truncations and single byte mutations stay bounded and release allocations" {
    for ([_]bool{ false, true }) |progressive| try mutateJPEG(progressive);
}

fn mutateJPEG(progressive: bool) !void {
    const bytes = try minimalJPEG(progressive);
    defer a.free(bytes);
    const codec = @import("jpeg.zig");
    for (0..bytes.len) |end| {
        if (codec.decode(a, bytes[0..end], null, 4096)) |result| {
            a.free(result.pixels);
            return error.AcceptedTruncatedJPEG;
        } else |_| {}
    }
    for (0..bytes.len) |index| {
        const original = bytes[index];
        for ([_]u8{ 0, 0x80, 0xff }) |value| {
            bytes[index] = value;
            if (codec.decode(a, bytes, null, 4096)) |result| {
                defer a.free(result.pixels);
                try std.testing.expect(result.pixels.len <= 4096);
                try std.testing.expectEqual(result.width * result.height * result.channels, result.pixels.len);
            } else |_| {}
        }
        bytes[index] = original;
    }
    try std.testing.expectError(error.DecodedStreamLimit, codec.decode(a, bytes, null, 0));
}

fn decodeJPEGWithAllocator(allocator: std.mem.Allocator, bytes: []const u8) !void {
    const image = try @import("jpeg.zig").decode(allocator, bytes, null, 4096);
    defer allocator.free(image.pixels);
    try std.testing.expectEqualSlices(u8, &.{128}, image.pixels);
}

test "JPEG allocation failures release component planes and output" {
    for ([_]bool{ false, true }) |progressive| {
        const bytes = try minimalJPEG(progressive);
        defer a.free(bytes);
        try std.testing.checkAllAllocationFailures(a, decodeJPEGWithAllocator, .{bytes});
    }
}

test "progressive JPEG decodes initial and refinement scans through DCTDecode" {
    const bytes = try minimalJPEG(true);
    defer a.free(bytes);
    var f = try Fixture.init("/Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceGray /Filter /DCTDecode", bytes, "q 120 0 0 80 0 0 cm /Im Do Q");
    defer f.deinit();
    const bitmap = try render.render(a, &f.doc, 0, &.{}, 612);
    defer a.free(bitmap.pixels);
    try std.testing.expectEqualSlices(u8, &.{ 128, 128, 128, 255 }, pixel(bitmap, 20, 20));
}

test "progressive DC refinement appends a bit to a negative coefficient" {
    const source = try minimalJPEG(true);
    defer a.free(source);
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);
    const scan = std.mem.indexOf(u8, source, "\xff\xda").?;
    try bytes.appendSlice(a, source[0..scan]);
    const dc_symbol = std.mem.indexOf(u8, source, "\xff\xc4").? + 4 + 17;
    bytes.items[dc_symbol] = 1;
    // DC -1 at Al=4 gives -16; the next bit yields -8, or sample 127.
    try bytes.appendSlice(a, "\xff\xda\x00\x08\x01\x01\x00\x00\x00\x04\x3f");
    try bytes.appendSlice(a, "\xff\xda\x00\x08\x01\x01\x00\x00\x00\x43\xff\x00\xff\xd9");
    const decoded = try @import("jpeg.zig").decode(a, bytes.items, null, 4096);
    defer a.free(decoded.pixels);
    try std.testing.expectEqualSlices(u8, &.{127}, decoded.pixels);
}

test "progressive EOB runs cannot extend beyond the scan" {
    const bytes = try minimalJPEG(true);
    defer a.free(bytes);
    const ac_symbol = std.mem.indexOf(u8, bytes, "\xff\xc4").? + 4 + 18 + 17;
    bytes[ac_symbol] = 0x10;
    try std.testing.expectError(error.InvalidJPEGRun, @import("jpeg.zig").decode(a, bytes, null, 4096));
}

test "CCITTFaxDecode renders two white Group 4 scanlines" {
    var f = try Fixture.init("/Width 8 /Height 2 /BitsPerComponent 1 /ColorSpace /DeviceGray /Filter /CCITTFaxDecode /DecodeParms << /K -1 /Columns 8 /Rows 2 >>", &.{ 0xc0, 0x04, 0x00, 0x40 }, "q 120 0 0 80 0 0 cm /Im Do Q");
    defer f.deinit();
    const bitmap = try render.render(a, &f.doc, 0, &.{}, 612);
    defer a.free(bitmap.pixels);
    try std.testing.expectEqualSlices(u8, &.{ 255, 255, 255, 255 }, pixel(bitmap, 20, 20));
}

test "CCITT null optional decode parameters use defaults" {
    var f = try Fixture.init("/Width 8 /Height 2 /BitsPerComponent 1 /ColorSpace /DeviceGray /Filter /CCITTFaxDecode /DecodeParms << /K null /Columns 8 /Rows null /EndOfLine null /EncodedByteAlign null /EndOfBlock false /BlackIs1 null /DamagedRowsBeforeError null >>", &.{ 0x9c, 0xc0 }, "q 120 0 0 80 0 0 cm /Im Do Q");
    defer f.deinit();
    const bitmap = try render.render(a, &f.doc, 0, &.{}, 612);
    defer a.free(bitmap.pixels);
    try std.testing.expectEqualSlices(u8, &.{ 255, 255, 255, 255 }, pixel(bitmap, 20, 20));
}

fn addMask(f: *Fixture, entries: []const u8, data: []const u8) !void {
    const dict = try std.fmt.allocPrint(f.doc.allocator(), "<< /Type /XObject /Subtype /Image {s} >>", .{entries});
    _ = try f.doc.addObject(try parse(&f.doc, dict), data);
}

test "explicit image masks retain their own resolution and decode polarity" {
    var f = try Fixture.init("/Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceRGB /Mask 7 0 R", &.{ 255, 0, 0 }, "0 0 1 rg 0 0 120 80 re f q 120 0 0 80 0 0 cm /Im Do Q");
    defer f.deinit();
    try addMask(&f, "/Width 4 /Height 1 /ImageMask true /Decode [1 0]", &.{0x50});
    const bitmap = try render.render(a, &f.doc, 0, &.{}, 612);
    defer a.free(bitmap.pixels);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 255, 255 }, pixel(bitmap, 15, 40));
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, pixel(bitmap, 45, 40));
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 255, 255 }, pixel(bitmap, 75, 40));
}

test "soft image masks override Mask and decode alpha independently of default gray" {
    var f = try Fixture.init("/Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceRGB /SMask 7 0 R /Mask false", &.{ 255, 0, 0 }, "0 0 1 rg 0 0 120 80 re f q 120 0 0 80 0 0 cm /Im Do Q");
    defer f.deinit();
    try addMask(&f, "/Width 3 /Height 1 /ColorSpace /DeviceGray /BitsPerComponent 8 /Decode [1 0] /Intent /Perceptual /OPI << >> /Alternates []", &.{ 255, 128, 0 });
    const resources = try parse(&f.doc, "<< /ColorSpace << /DefaultGray /Unsupported >> >>");
    const image = try @import("images.zig").load(&f.doc, try f.doc.object(.{ .id = 6, .generation = 0 }), resources);
    try std.testing.expectApproxEqAbs(@as(f64, 127.0 / 255.0), (try image.sample(0.5, 0.5, .{ 0, 0, 0 }))[3], 1e-9);
    const bitmap = try render.render(a, &f.doc, 0, &.{}, 612);
    defer a.free(bitmap.pixels);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 255, 255 }, pixel(bitmap, 20, 40));
    try std.testing.expectEqualSlices(u8, &.{ 127, 0, 128, 255 }, pixel(bitmap, 60, 40));
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, pixel(bitmap, 100, 40));
}

test "soft mask interpolation and transparent content bounds" {
    var f = try Fixture.init("/Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceRGB /SMask 7 0 R", &.{ 255, 0, 0 }, "q 120 0 0 80 0 0 cm /Im Do Q");
    defer f.deinit();
    try addMask(&f, "/Width 2 /Height 1 /ColorSpace /DeviceGray /BitsPerComponent 8 /Interpolate true", &.{ 0, 255 });
    const image = try @import("images.zig").load(&f.doc, try f.doc.object(.{ .id = 6, .generation = 0 }), .null);
    const sample = try image.sample(0.5, 0.5, .{ 0, 0, 0 });
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), sample[3], 1e-9);
    try f.doc.replaceStream(try f.doc.object(.{ .id = 7, .generation = 0 }), &.{ 0, 0 });
    try std.testing.expectEqual(@as(?[4]f64, null), try render.contentBoundsWithFonts(a, &f.doc, 0, &.{}));
}

test "soft mask Matte removes preblending before painting and interpolation" {
    var f = try Fixture.init("/Width 2 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceRGB /SMask 7 0 R /Interpolate true", &.{ 255, 127, 127, 255, 255, 255 }, "0 0 1 rg 0 0 120 80 re f q 120 0 0 80 0 0 cm /Im Do Q");
    defer f.deinit();
    try addMask(&f, "/Width 2 /Height 1 /ColorSpace /DeviceGray /BitsPerComponent 8 /Matte [1 1 1] /Interpolate true", &.{ 128, 0 });
    const bitmap = try render.render(a, &f.doc, 0, &.{}, 612);
    defer a.free(bitmap.pixels);
    try std.testing.expectEqualSlices(u8, &.{ 128, 0, 127, 255 }, pixel(bitmap, 15, 40));
    const image = try @import("images.zig").load(&f.doc, try f.doc.object(.{ .id = 6, .generation = 0 }), .null);
    const sample = try image.sample(0.5, 0.5, .{ 0, 0, 0 });
    try std.testing.expectEqual(@as(f64, 255), sample[0]);
    try std.testing.expectEqual(@as(f64, 0), sample[1]);
    try std.testing.expectApproxEqAbs(@as(f64, 64.0 / 255.0), sample[3], 1e-9);
}

test "image masks reject cycles invalid children and invalid matte data" {
    for ([_][]const u8{
        "/Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceGray /SMask 6 0 R",
        "/Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceGray /Mask [0 0]",
        "/Width 1 /Height 1 /ImageMask true",
        "/Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceGray /Matte [1]",
        "/Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceGray /Matte [1 -1 1]",
    }) |entries| {
        var f = try Fixture.init("/Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceRGB /SMask 7 0 R", &.{ 255, 0, 0 }, "/Im Do");
        defer f.deinit();
        try addMask(&f, entries, &.{0});
        try std.testing.expectError(error.InvalidImage, f.doc.inspect());
    }
}

test "soft mask alpha multiplies constant opacity before Multiply compositing" {
    var f = try Fixture.init("/Width 3 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceRGB /SMask 7 0 R", &.{ 255, 0, 0, 0, 255, 0, 0, 0, 255 }, ".2 .4 .8 rg 0 0 120 80 re f /A gs q 120 0 0 80 0 0 cm /Im Do Q");
    defer f.deinit();
    try addMask(&f, "/Width 3 /Height 1 /ColorSpace /DeviceGray /BitsPerComponent 8", &.{ 0, 128, 255 });
    try f.doc.set(try f.doc.object(.{ .id = 3, .generation = 0 }), "Resources", try parse(&f.doc, "<< /XObject << /Im 6 0 R >> /ExtGState << /A << /ca .5 /BM /Multiply >> >> >>"));
    const bitmap = try render.render(a, &f.doc, 0, &.{}, 612);
    defer a.free(bitmap.pixels);
    try std.testing.expectEqualSlices(u8, &.{ 51, 102, 204, 255 }, pixel(bitmap, 20, 40));
    try std.testing.expectEqualSlices(u8, &.{ 38, 102, 153, 255 }, pixel(bitmap, 60, 40));
    try std.testing.expectEqualSlices(u8, &.{ 26, 51, 204, 255 }, pixel(bitmap, 100, 40));
}

fn renderMaskWithAllocator(allocator: std.mem.Allocator, bytes: []const u8) !void {
    var doc = try pod.Document.open(allocator, bytes);
    defer doc.deinit();
    const bitmap = try render.render(allocator, &doc, 0, &.{}, 8);
    defer allocator.free(bitmap.pixels);
    const Callbacks = struct {
        fn paint(_: *anyopaque, _: [*]const render.Edge, _: usize, _: u32, _: f64, _: bool, _: u32, _: u32) callconv(.c) bool {
            return true;
        }
        fn image(_: *anyopaque, _: [*]const render.Edge, _: usize, value: *const render.ImagePaint, _: f64, _: u32, _: u32) callconv(.c) bool {
            std.debug.assert(value.mask_width == 2 and value.mask_height == 1 and value.mask_interpolate);
            std.debug.assert(value.mask_alpha.?[0] == 0 and value.mask_alpha.?[1] == 1);
            return true;
        }
    };
    var context: u8 = 0;
    var hairlines = false;
    _ = try render.collect(allocator, &doc, 0, &.{}, 8, .{ .context = &context, .paint = Callbacks.paint, .image = Callbacks.image, .hairlines = &hairlines });
}

test "masked image decoding rendering and scene collection release failed allocations" {
    var f = try Fixture.init("/Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceRGB /SMask 7 0 R", &.{ 255, 0, 0 }, "q 120 0 0 80 0 0 cm /Im Do Q");
    defer f.deinit();
    try addMask(&f, "/Width 2 /Height 1 /ColorSpace /DeviceGray /BitsPerComponent 8 /Interpolate true", &.{ 0, 255 });
    const bytes = try f.doc.save(a);
    defer a.free(bytes);
    try std.testing.checkAllAllocationFailures(a, renderMaskWithAllocator, .{bytes});
}

test "indexed image default Decode retains packed indices and clamps to hival" {
    var f = try Fixture.init("/Width 4 /Height 1 /BitsPerComponent 2 /ColorSpace [/Indexed /DeviceRGB 2 <ff000000ff000000ff>]", &.{0x1b}, "q 120 0 0 80 0 0 cm /Im Do Q");
    defer f.deinit();
    const bitmap = try render.render(a, &f.doc, 0, &.{}, 612);
    defer a.free(bitmap.pixels);
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, pixel(bitmap, 15, 40));
    try std.testing.expectEqualSlices(u8, &.{ 0, 255, 0, 255 }, pixel(bitmap, 45, 40));
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 255, 255 }, pixel(bitmap, 75, 40));
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 255, 255 }, pixel(bitmap, 105, 40));
}

test "indexed image Decode rounds before lookup and color key masking uses raw indices" {
    var f = try Fixture.init("/Width 4 /Height 1 /BitsPerComponent 2 /Decode [2 0] /Mask [1 1] /ColorSpace [/Indexed /DeviceRGB 2 7 0 R]", &.{0x1b}, "q 120 0 0 80 0 0 cm /Im Do Q");
    defer f.deinit();
    _ = try f.doc.addObject(try parse(&f.doc, "<< /Filter /ASCIIHexDecode >>"), "ff000000ff000000ff>");
    const bitmap = try render.render(a, &f.doc, 0, &.{}, 612);
    defer a.free(bitmap.pixels);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 255, 255 }, pixel(bitmap, 15, 40));
    try std.testing.expectEqualSlices(u8, &.{ 255, 255, 255, 255 }, pixel(bitmap, 45, 40));
    try std.testing.expectEqualSlices(u8, &.{ 0, 255, 0, 255 }, pixel(bitmap, 75, 40));
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, pixel(bitmap, 105, 40));
}

test "indexed colors initialize to index zero and restore through graphics state" {
    var f = try Fixture.init("/Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceGray", &.{0}, "/Palette cs 0 0 30 80 re f q .6 scn 30 0 30 80 re f 100 sc 60 0 30 80 re f Q 90 0 30 80 re f");
    defer f.deinit();
    try f.doc.set(try f.doc.object(.{ .id = 3, .generation = 0 }), "Resources", try parse(&f.doc, "<< /ColorSpace << /Palette [/Indexed /DeviceRGB 2 <ff000000ff000000ff>] >> >>"));
    const bitmap = try render.render(a, &f.doc, 0, &.{}, 612);
    defer a.free(bitmap.pixels);
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, pixel(bitmap, 15, 40));
    try std.testing.expectEqualSlices(u8, &.{ 0, 255, 0, 255 }, pixel(bitmap, 45, 40));
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 255, 255 }, pixel(bitmap, 75, 40));
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, pixel(bitmap, 105, 40));
}

test "indexed image Matte selects a palette color and unblends base components" {
    var f = try Fixture.init("/Width 2 /Height 1 /BitsPerComponent 1 /ColorSpace [/Indexed /DeviceRGB 2 <ff7f7f7fff7fffffff>] /SMask 7 0 R", &.{0x40}, "0 0 1 rg 0 0 120 80 re f q 120 0 0 80 0 0 cm /Im Do Q");
    defer f.deinit();
    try addMask(&f, "/Width 2 /Height 1 /ColorSpace /DeviceGray /BitsPerComponent 8 /Matte [2]", &.{ 128, 128 });
    const bitmap = try render.render(a, &f.doc, 0, &.{}, 612);
    defer a.free(bitmap.pixels);
    try std.testing.expectEqualSlices(u8, &.{ 128, 0, 127, 255 }, pixel(bitmap, 20, 40));
    try std.testing.expectEqualSlices(u8, &.{ 0, 128, 127, 255 }, pixel(bitmap, 100, 40));
}

test "indexed palettes validate table lengths bounds nesting and lookup cycles" {
    for ([_][]const u8{
        "[/Indexed /DeviceRGB -1 <>]",
        "[/Indexed /DeviceRGB 256 <>]",
        "[/Indexed /DeviceRGB 1.5 <000000ffffff>]",
        "[/Indexed /DeviceRGB 1 <000000>]",
        "[/Indexed /DeviceGray 0 <0000>]",
        "[/Indexed /DeviceGray 0 false]",
        "[/Indexed [/Indexed /DeviceGray 0 <00>] 0 <00>]",
    }) |space| {
        var f = try Fixture.init("/Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceGray", &.{0}, "/Im Do");
        defer f.deinit();
        try std.testing.expectError(error.InvalidColorSpace, @import("color.zig").loadValue(&f.doc, .null, try parse(&f.doc, space)));
    }
    var f = try Fixture.init("/Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace [/Indexed /DeviceGray 0 7 0 R]", &.{0}, "/Im Do");
    defer f.deinit();
    _ = try f.doc.addObject(.{ .ref = .{ .id = 7, .generation = 0 } }, null);
    try std.testing.expectError(error.ReferenceLimit, f.doc.inspect());
    const resources = try parse(&f.doc, "<< /ColorSpace << /DefaultGray [/Indexed /DeviceGray 0 <00>] >> >>");
    try std.testing.expectError(error.InvalidColorSpace, @import("color.zig").load(&f.doc, resources, "DeviceGray"));
}

test "indexed palette bytes map to base component ranges" {
    const space = @import("color.zig").Space{ .channels = 1, .range = .{ 0.25, 0.75, 0, 1, 0, 1 }, .indexed = .{ .channels = 1, .lookup = &.{ 0, 128, 255 } } };
    try std.testing.expectEqualSlices(u8, &.{ 64, 64, 64 }, &(try space.convert(&.{-1})));
    try std.testing.expectEqualSlices(u8, &.{ 191, 191, 191 }, &(try space.convert(&.{100})));
    try std.testing.expectApproxEqAbs(@as(f64, 0.25 + 128.0 / 255.0 * 0.5), (try space.indexedComponents(0.6))[0], 1e-9);
    try std.testing.expectError(error.InvalidNumber, space.convert(&.{std.math.nan(f64)}));
    try std.testing.expectError(error.InvalidOperands, space.convert(&.{ 0, 1 }));
}

test "indexed rendering and masked scene collection release failed allocations" {
    var f = try Fixture.init("/Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace [/Indexed /DeviceRGB 0 8 0 R] /SMask 7 0 R", &.{0}, "q 120 0 0 80 0 0 cm /Im Do Q");
    defer f.deinit();
    try addMask(&f, "/Width 2 /Height 1 /ColorSpace /DeviceGray /BitsPerComponent 8 /Interpolate true", &.{ 0, 255 });
    _ = try f.doc.addObject(try parse(&f.doc, "<< /Filter /ASCIIHexDecode >>"), "ff0000>");
    const bytes = try f.doc.save(a);
    defer a.free(bytes);
    try std.testing.checkAllAllocationFailures(a, renderMaskWithAllocator, .{bytes});
}

test "bounded Pillow ASCIIHex image streams may end after complete samples" {
    var f = try Fixture.init("/Width 2 /Height 1 /BitsPerComponent 8 /ColorSpace [/Indexed /DeviceGray 1 <00ff>] /Filter /ASCIIHexDecode", "00\n01\n", "q 120 0 0 80 0 0 cm /Im Do Q");
    defer f.deinit();
    const bitmap = try render.render(a, &f.doc, 0, &.{}, 612);
    defer a.free(bitmap.pixels);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 255 }, pixel(bitmap, 20, 40));
    try std.testing.expectEqualSlices(u8, &.{ 255, 255, 255, 255 }, pixel(bitmap, 100, 40));
    var short = try Fixture.init("/Width 2 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceGray /Filter /ASCIIHexDecode", "00", "/Im Do");
    defer short.deinit();
    try std.testing.expectError(error.InvalidImageData, short.doc.inspect());
}

test "indexed palettes address the last of all 256 entries" {
    var f = try Fixture.init("/Width 3 /Height 1 /BitsPerComponent 8 /ColorSpace [/Indexed /DeviceGray 255 7 0 R]", &.{ 0, 128, 255 }, "q 120 0 0 80 0 0 cm /Im Do Q");
    defer f.deinit();
    var lookup: [256]u8 = undefined;
    for (&lookup, 0..) |*v, i| v.* = @intCast(i);
    _ = try f.doc.addObject(try parse(&f.doc, "<< >>"), &lookup);
    const bitmap = try render.render(a, &f.doc, 0, &.{}, 612);
    defer a.free(bitmap.pixels);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 255 }, pixel(bitmap, 20, 40));
    try std.testing.expectEqualSlices(u8, &.{ 128, 128, 128, 255 }, pixel(bitmap, 60, 40));
    try std.testing.expectEqualSlices(u8, &.{ 255, 255, 255, 255 }, pixel(bitmap, 100, 40));
}

test "calibrated gray RGB and Lab colors resolve their native component domains" {
    var f = try Fixture.init("/Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceGray", &.{0}, "/Im Do");
    defer f.deinit();
    const color = @import("color.zig");
    const gray = try color.loadValue(&f.doc, .null, try parse(&f.doc, "[/CalGray << /WhitePoint [.95047 1 1.08883] /Gamma 2 >>]"));
    try std.testing.expectEqualSlices(u8, &.{ 137, 137, 137 }, &(try gray.convert(&.{0.5})));
    const rgb = try color.loadValue(&f.doc, .null, try parse(&f.doc, "[/CalRGB << /WhitePoint [.95047 1 1.08883] /Gamma [2 2 2] /Matrix [.4124564 .2126729 .0193339 .3575761 .7151522 .1191920 .1804375 .0721750 .9503041] >>]"));
    try std.testing.expectEqualSlices(u8, &.{ 137, 0, 255 }, &(try rgb.convert(&.{ 0.5, 0, 1 })));
    const lab = try color.loadValue(&f.doc, .null, try parse(&f.doc, "[/Lab << /WhitePoint [.9642 1 .8249] >>]"));
    try std.testing.expectEqualSlices(u8, &.{ 119, 119, 119 }, &(try lab.convert(&.{ 50, 0, 0 })));
    try std.testing.expectEqualSlices(u8, &.{ 255, 255, 255 }, &(try lab.convert(&.{ 100, 0, 0 })));
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0 }, &(try lab.convert(&.{ 0, 0, 0 })));
}

test "Lab image default Decode and Indexed lookup honor declared component ranges" {
    var f = try Fixture.init("/Width 2 /Height 1 /BitsPerComponent 8 /ColorSpace [/Lab << /WhitePoint [.95047 1 1.08883] /Range [0 0 0 0] >>]", &.{ 0, 0, 0, 255, 255, 255 }, "q 120 0 0 80 0 0 cm /Im Do Q");
    defer f.deinit();
    const bitmap = try render.render(a, &f.doc, 0, &.{}, 612);
    defer a.free(bitmap.pixels);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 255 }, pixel(bitmap, 20, 40));
    try std.testing.expectEqualSlices(u8, &.{ 255, 255, 255, 255 }, pixel(bitmap, 100, 40));
    const palette = try @import("color.zig").loadValue(&f.doc, .null, try parse(&f.doc, "[/Indexed [/Lab << /WhitePoint [.95047 1 1.08883] /Range [0 0 0 0] >>] 1 <000000ffffff>]"));
    try std.testing.expectEqualSlices(u8, &.{ 255, 255, 255 }, &(try palette.convert(&.{1})));
}

test "calibrated dictionaries validate required parameters and numeric domains" {
    var f = try Fixture.init("/Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceGray", &.{0}, "/Im Do");
    defer f.deinit();
    for ([_][]const u8{
        "[/CalGray << >>]",                                      "[/CalRGB << /WhitePoint [1 0 1] >>]",
        "[/Lab << /WhitePoint [-1 1 1] >>]",                     "[/CalGray << /WhitePoint [1 1] >>]",
        "[/CalGray << /WhitePoint [1 1 1] /Gamma 0 >>]",         "[/CalGray << /WhitePoint [1 1 1] /Gamma [2] >>]",
        "[/CalRGB << /WhitePoint [1 1 1] /Gamma [1 -1 1] >>]",   "[/CalRGB << /WhitePoint [1 1 1] /Matrix [1 2 3] >>]",
        "[/Lab << /WhitePoint [1 1 1] /Range [2 1 0 1] >>]",     "[/Lab << /WhitePoint [1 1 1] /BlackPoint [0 -1 0] >>]",
        "[/Lab << /WhitePoint [1 1 1] /BlackPoint /Invalid >>]", "[/CalRGB << /WhitePoint [1 1 1] /Gamma [1 1000000000001 1] >>]",
    }) |space| try std.testing.expectError(error.InvalidColorSpace, @import("color.zig").loadValue(&f.doc, .null, try parse(&f.doc, space)));
    const id = try f.doc.addObject(try parse(&f.doc, "<< /WhitePoint [1 1 1] /Gamma null /BlackPoint null >>"), null);
    const spec = try std.fmt.allocPrint(f.doc.allocator(), "[/CalGray {d} 0 R]", .{id});
    const gray = try @import("color.zig").loadValue(&f.doc, .null, try parse(&f.doc, spec));
    try std.testing.expectEqualSlices(u8, &.{ 188, 188, 188 }, &(try gray.convert(&.{0.5})));
    try std.testing.expectError(error.InvalidNumber, gray.convert(&.{std.math.inf(f64)}));
    const singular = try std.fmt.allocPrint(f.doc.allocator(), "[/CalGray << /WhitePoint [{d:.17} 1 1] >>]", .{1.7502 / 0.7502});
    try std.testing.expectError(error.UnsupportedColorSpace, @import("color.zig").loadValue(&f.doc, .null, try parse(&f.doc, singular)));
}

test "calibrated colors restore graphics state and release failed allocations" {
    var f = try Fixture.init("/Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceGray", &.{0}, "/Gray cs .5 sc 0 0 30 80 re f q /Lab cs 100 0 0 scn 30 0 30 80 re f Q 60 0 30 80 re f /Gray CS .5 SC 5 w 110 0 m 110 80 l S");
    defer f.deinit();
    try f.doc.set(try f.doc.object(.{ .id = 3, .generation = 0 }), "Resources", try parse(&f.doc, "<< /ColorSpace << /Gray [/CalGray << /WhitePoint [1 1 1] /Gamma 2 >>] /Lab [/Lab << /WhitePoint [1 1 1] >>] >> >>"));
    const bitmap = try render.render(a, &f.doc, 0, &.{}, 612);
    defer a.free(bitmap.pixels);
    try std.testing.expectEqualSlices(u8, &.{ 137, 137, 137, 255 }, pixel(bitmap, 15, 40));
    try std.testing.expectEqualSlices(u8, &.{ 255, 255, 255, 255 }, pixel(bitmap, 45, 40));
    try std.testing.expectEqualSlices(u8, &.{ 137, 137, 137, 255 }, pixel(bitmap, 75, 40));
    try std.testing.expectEqualSlices(u8, &.{ 137, 137, 137, 255 }, pixel(bitmap, 110, 40));
    const bytes = try f.doc.save(a);
    defer a.free(bytes);
    try std.testing.checkAllAllocationFailures(a, renderMaskWithAllocator, .{bytes});
}

test "Lab Matte unblending happens in Lab before conversion to display RGB" {
    var f = try Fixture.init("/Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace [/Lab << /WhitePoint [.9642 1 .8249] /Range [0 0 0 0] >>] /SMask 7 0 R", &.{ 191, 0, 0 }, "0 0 1 rg 0 0 120 80 re f q 120 0 0 80 0 0 cm /Im Do Q");
    defer f.deinit();
    try addMask(&f, "/Width 1 /Height 1 /ColorSpace /DeviceGray /BitsPerComponent 8 /Matte [100 0 0]", &.{128});
    const bitmap = try render.render(a, &f.doc, 0, &.{}, 612);
    defer a.free(bitmap.pixels);
    try std.testing.expectEqualSlices(u8, &.{ 60, 60, 187, 255 }, pixel(bitmap, 60, 40));
}

test "inline images keep binary EI samples and following operators across save" {
    const stream = "q 160 0 0 80 20 20 cm BI /W 4 /H 1 /BPC 8 /CS /G ID  EI  EI Q 1 0 0 rg 200 20 10 10 re f";
    var f = try Fixture.init("", "", stream);
    defer f.deinit();
    const bitmap = try render.render(a, &f.doc, 0, &.{}, 612);
    defer a.free(bitmap.pixels);
    for ([_]u8{ 32, 69, 73, 32 }, 0..) |gray, i| try std.testing.expectEqualSlices(u8, &.{ gray, gray, gray, 255 }, pixel(bitmap, 40 + i * 40, 40));
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, pixel(bitmap, 205, 25));
    const saved = try f.doc.save(a);
    defer a.free(saved);
    var copy = try pod.Document.open(a, saved);
    defer copy.deinit();
    const second = try render.render(a, &copy, 0, &.{}, 612);
    defer a.free(second.pixels);
    try std.testing.expectEqualSlices(u8, bitmap.pixels, second.pixels);
    try std.testing.expectEqualStrings(stream, try copy.streamData(try copy.object(.{ .id = 5, .generation = 0 })));
}

test "inline image filter terminators preserve binary data and parser position" {
    const cases = [_][]const u8{
        "BI /W 4 /H 1 /BPC 8 /CS /G /F /AHx ID 20454920> EI",
        "BI /W 4 /H 1 /BPC 8 /CS /G /F /RL ID \x03 EI \x80 EI",
        "BI /W 4 /H 1 /BPC 8 /CS /G /F [/AHx /RL] /DP [null null] ID 032045492080> EI",
    };
    for (cases) |inline_image| {
        const stream = try std.fmt.allocPrint(a, "q 160 0 0 80 20 20 cm {s} Q 1 0 0 rg 200 20 10 10 re f", .{inline_image});
        defer a.free(stream);
        var f = try Fixture.init("", "", stream);
        defer f.deinit();
        const bitmap = try render.render(a, &f.doc, 0, &.{}, 612);
        defer a.free(bitmap.pixels);
        for ([_]u8{ 32, 69, 73, 32 }, 0..) |gray, i| try std.testing.expectEqualSlices(u8, &.{ gray, gray, gray, 255 }, pixel(bitmap, 40 + i * 40, 40));
        try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, pixel(bitmap, 205, 25));
        try std.testing.expectEqual(@as(usize, 0), f.doc.decoded_bytes);
    }
}

test "inline dictionaries and exact framing reject malformed inputs" {
    const cases = [_]struct { bytes: []const u8, err: anyerror }{
        .{ .bytes = "BI /W 1 /H 1 /CS /G /BPC 8 ID x EIx", .err = error.InvalidInlineImage },
        .{ .bytes = "BI /W 1 /H 1 /CS /G /BPC 8 ID xy EI", .err = error.InvalidInlineImage },
        .{ .bytes = "BI /W 1 /Width 1 /H 1 /CS /G /BPC 8 ID x EI", .err = error.InvalidInlineImage },
        .{ .bytes = "BI /W 1 0 R /H 1 /CS /G /BPC 8 ID x EI", .err = error.InvalidInlineImage },
        .{ .bytes = "BI /W 1 /H 1 /CS /G /BPC 8 /Custom [5 0 R] ID x EI", .err = error.InvalidInlineImage },
        .{ .bytes = "BI /W 1 /H 1 /CS /G /BPC 8 /F /AHx ID 00 EI", .err = error.InvalidASCIIHex },
        .{ .bytes = "BI /W 1 /H 1 /CS /G /BPC 8 /F /RL ID \x00x EI", .err = error.InvalidRunLength },
        .{ .bytes = "BI /W 1 /H 1 /CS /G /BPC 8 /F /A85 ID z~> EI", .err = error.InvalidImageData },
        .{ .bytes = "BI /W 65536 /H 65536 /CS /G /BPC 8 ID x EI", .err = error.ImageLimit },
        .{ .bytes = "BT BI /W 1 /H 1 /CS /G /BPC 8 ID x EI ET", .err = error.InvalidTextObject },
        .{ .bytes = "1 BI /W 1 /H 1 /CS /G /BPC 8 ID x EI", .err = error.InvalidOperands },
        .{ .bytes = "ID", .err = error.UnsupportedOperator },
        .{ .bytes = "EI", .err = error.UnsupportedOperator },
    };
    for (cases) |case| {
        var f = try Fixture.init("", "", case.bytes);
        defer f.deinit();
        try std.testing.expectError(case.err, f.doc.inspect());
    }
}
fn renderInlineWithAllocator(allocator: std.mem.Allocator, bytes: []const u8) !void {
    var doc = try pod.Document.open(allocator, bytes);
    defer doc.deinit();
    const bitmap = try render.render(allocator, &doc, 0, &.{}, 8);
    defer allocator.free(bitmap.pixels);
    const Callbacks = struct {
        fn paint(_: *anyopaque, _: [*]const render.Edge, _: usize, _: u32, _: f64, _: bool, _: u32, _: u32) callconv(.c) bool {
            return true;
        }
        fn image(ctx: *anyopaque, _: [*]const render.Edge, _: usize, _: *const render.ImagePaint, _: f64, _: u32, _: u32) callconv(.c) bool {
            const count: *usize = @ptrCast(@alignCast(ctx));
            count.* += 1;
            return true;
        }
    };
    var count: usize = 0;
    var hairlines = false;
    _ = try render.collect(allocator, &doc, 0, &.{}, 8, .{ .context = &count, .paint = Callbacks.paint, .image = Callbacks.image, .hairlines = &hairlines });
    try std.testing.expectEqual(@as(usize, 1), count);
}
test "inline filter and palette scratch allocations are released on failure and repeated renders" {
    var f = try Fixture.init("", "", "q 612 0 0 792 0 0 cm BI /W 2 /H 1 /CS [/I /RGB 1 <ff00000000ff>] /BPC 8 /F [/AHx /RL] ID 01000180> EI Q");
    defer f.deinit();
    const bytes = try f.doc.save(a);
    defer a.free(bytes);
    try std.testing.checkAllAllocationFailures(a, renderInlineWithAllocator, .{bytes});
    _ = try f.doc.inspect();
    const capacity = f.doc.arena.queryCapacity();
    for (0..100) |_| {
        const bitmap = try render.render(a, &f.doc, 0, &.{}, 8);
        defer a.free(bitmap.pixels);
    }
    try std.testing.expectEqual(capacity, f.doc.arena.queryCapacity());
    try std.testing.expectEqual(@as(usize, 0), f.doc.decoded_bytes);
}
