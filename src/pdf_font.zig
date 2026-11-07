const std = @import("std");
const d = @import("document.zig");
const s = @import("syntax.zig");
const cmap = @import("to_unicode.zig");
const truetype = @import("font.zig");
const cid_font = @import("cid_font.zig");
const reverse_encoding = @import("font_encoding.zig");
pub const metrics = @import("font_metrics.zig");
pub const Face = metrics.Face;
pub const Code = cmap.Code;
pub const max_decoded_text = 16 * 1024 * 1024;
pub const Embedded = struct { program: truetype.Font, ids: [256]u16 = @splat(0), boxes: [256][4]f64 = @splat(.{ 0, 0, 0, 0 }) };
pub const Font = struct {
    face: Face,
    composite: ?*const cid_font.Font = null,
    embedded: ?Embedded = null,
    pdf_name: ?[]const u8 = null,
    glyphs: [256]u16,
    widths: [256]f64,
    extraction: [256]?[]const u8 = @splat(null),
    pub fn name(self: *const Font) []const u8 {
        return self.pdf_name orelse metrics.names[@backingInt(self.face)];
    }
    pub fn nextCode(self: *const Font, text: []const u8, at: *usize) !?Code {
        if (self.composite) |font| return font.cmap.next(text, at);
        if (at.* == text.len) return null;
        const code = text[at.*];
        at.* += 1;
        return .{ .value = code, .length = 1 };
    }
    pub fn width(self: *const Font, code: Code) f64 {
        return if (self.composite) |font| font.width(code) else self.widths[code.value];
    }
    pub fn vertical(self: *const Font) bool {
        return if (self.composite) |font| font.cmap.vertical else false;
    }
    pub fn verticalMetrics(self: *const Font, code: Code) [3]f64 {
        return self.composite.?.verticalMetrics(code);
    }
    pub fn wordSpacing(_: *const Font, code: Code) bool {
        return code.length == 1 and code.value == 32;
    }
    pub fn validateGlyph(self: *const Font, source: Code) !void {
        const code = source.value;
        if (self.composite) |font| {
            _ = try font.glyph(source);
            return;
        }
        if (code > 255 or source.length != 1) return error.InvalidCharacterCode;
        if (self.embedded) |*embedded| {
            if (embedded.ids[code] == 0) return error.MissingGlyph;
        } else _ = try self.glyphUnicode(@intCast(code));
    }
    pub fn glyphUnicode(self: *const Font, code: u16) !u21 {
        const cp = metrics.glyphs[self.glyphs[code]].unicode;
        if (cp == 0) return error.UnsupportedEncoding;
        return cp;
    }
    pub fn bounds(self: *const Font, source: Code) ![4]f64 {
        if (self.composite) |font| return font.bounds(source);
        const code = source.value;
        if (self.embedded) |*embedded| {
            const b = embedded.boxes[code];
            return .{ @min(0, b[0]), b[1], @max(self.widths[code] / 1000, b[2]), b[3] };
        }
        const face = @backingInt(self.face);
        const b = metrics.glyphs[self.glyphs[code]].metrics[face].bounds;
        return .{ @as(f64, @floatFromInt(@min(0, b[0]))) / 1000, @as(f64, @floatFromInt(@min(metrics.descent[face], b[1]))) / 1000, @max(self.widths[code], @as(f64, @floatFromInt(b[2]))) / 1000, @as(f64, @floatFromInt(@max(metrics.ascent[face], b[3]))) / 1000 };
    }
    pub fn decode(self: *const Font, a: std.mem.Allocator, text: []const u8, out: *std.ArrayList(u8)) !void {
        var at: usize = 0;
        while (try self.nextCode(text, &at)) |code| {
            if (self.composite) |font| {
                const mapped = font.mapping.get(code.value, code.length) orelse return error.UnsupportedEncoding;
                if (mapped.len > max_decoded_text -| out.items.len) return error.TextLimit;
                try out.appendSlice(a, mapped);
                continue;
            }
            if (self.extraction[code.value]) |mapped| {
                if (mapped.len > max_decoded_text -| out.items.len) return error.TextLimit;
                try out.appendSlice(a, mapped);
                continue;
            }
            var bytes: [4]u8 = undefined;
            const len = try std.unicode.utf8Encode(try self.glyphUnicode(@intCast(code.value)), &bytes);
            if (len > max_decoded_text -| out.items.len) return error.TextLimit;
            try out.appendSlice(a, bytes[0..len]);
        }
    }
    pub fn encode(self: *const Font, a: std.mem.Allocator, text: []const u8) ![]const u8 {
        if (self.composite) |font| return reverse_encoding.encode(a, text, font.candidates);
        var storage: [256][4]u8 = undefined;
        var candidates: [256]reverse_encoding.Candidate = undefined;
        var count: usize = 0;
        for (0..256) |i| {
            self.validateGlyph(.{ .value = @intCast(i), .length = 1 }) catch continue;
            const decoded = if (self.extraction[i]) |mapped| mapped else blk: {
                const cp = self.glyphUnicode(@intCast(i)) catch continue;
                const n = try std.unicode.utf8Encode(cp, &storage[i]);
                break :blk storage[i][0..n];
            };
            candidates[count] = .{ .code = .{ .value = @intCast(i), .length = 1 }, .text = decoded };
            count += 1;
        }
        return reverse_encoding.encode(a, text, candidates[0..count]);
    }
};
fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
fn resolved(doc: *d.Document, v: s.Value, key: []const u8) !s.Value {
    return doc.resolve(s.get(v, key) orelse .null);
}
fn encoding(name: []const u8) ![256]u16 {
    if (eq(name, "StandardEncoding")) return metrics.standard;
    if (eq(name, "WinAnsiEncoding")) return metrics.win_ansi;
    if (eq(name, "MacRomanEncoding")) return metrics.mac_roman;
    return error.UnsupportedEncoding;
}
fn glyphIndex(name: []const u8) ?u16 {
    var low: usize = 0;
    var high = metrics.glyphs.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        switch (std.mem.order(u8, metrics.glyphs[mid].name, name)) {
            .eq => return @intCast(mid),
            .lt => low = mid + 1,
            .gt => high = mid,
        }
    }
    return null;
}
pub fn load(doc: *d.Document, resources: s.Value, resource_name: []const u8) !*const Font {
    const fonts = try resolved(doc, resources, "Font");
    return loadValue(doc, s.get(fonts, resource_name) orelse return error.MissingFont);
}
pub fn loadValue(doc: *d.Document, font_value: s.Value) !*const Font {
    const value = try doc.resolve(font_value);
    if (value != .dict) return error.UnsupportedFont;
    const key = @intFromPtr(value.dict.ptr);
    if (doc.pdf_fonts.get(key)) |cached| return cached;
    const base = try resolved(doc, value, "BaseFont");
    const sub = try resolved(doc, value, "Subtype");
    if (base != .name or sub != .name) return error.UnsupportedFont;
    if (eq(sub.name, "Type0")) {
        const result = try doc.allocator().create(Font);
        result.* = .{ .face = .courier, .pdf_name = base.name, .composite = try cid_font.load(doc, value), .glyphs = @splat(0), .widths = @splat(0) };
        try doc.pdf_fonts.put(doc.allocator(), key, result);
        return result;
    }
    const is_truetype = eq(sub.name, "TrueType");
    if (!is_truetype and !eq(sub.name, "Type1")) return error.UnsupportedFont;
    var face: ?Face = null;
    for (metrics.names, 0..) |name, i| if (eq(base.name, name)) {
        face = @fromBackingInt(@intCast(i));
        break;
    };
    const kind = face orelse if (is_truetype) Face.courier else return error.UnsupportedFont;
    const descriptor = try resolved(doc, value, "FontDescriptor");
    if (descriptor != .null) {
        if (descriptor != .dict) return error.UnsupportedFont;
        if (!is_truetype) for ([_][]const u8{ "FontFile", "FontFile2", "FontFile3" }) |name| {
            if (s.get(descriptor, name) != null) return error.UnsupportedEmbeddedFont;
        };
    }
    var glyphs = switch (kind) {
        .symbol => metrics.symbol_encoding,
        .zapf_dingbats => metrics.dingbats_encoding,
        else => metrics.standard,
    };
    const enc = try resolved(doc, value, "Encoding");
    if (enc == .name) glyphs = try encoding(enc.name) else if (enc == .dict) {
        const base_enc = try resolved(doc, enc, "BaseEncoding");
        if (base_enc != .null) {
            if (base_enc != .name) return error.UnsupportedEncoding;
            glyphs = try encoding(base_enc.name);
        }
        const diff = try resolved(doc, enc, "Differences");
        if (diff != .null) {
            if (diff != .array or diff.array.len > 512) return error.UnsupportedEncoding;
            var code: ?usize = null;
            for (diff.array) |raw| {
                const item = try doc.resolve(raw);
                if (item == .integer) {
                    code = s.uint(item) catch return error.UnsupportedEncoding;
                    if (code.? > 255) return error.UnsupportedEncoding;
                } else if (item == .name) {
                    const at = code orelse return error.UnsupportedEncoding;
                    if (at > 255) return error.UnsupportedEncoding;
                    glyphs[at] = glyphIndex(item.name) orelse return error.UnsupportedEncoding;
                    code = at + 1;
                } else return error.UnsupportedEncoding;
            }
        }
    } else if (enc != .null) return error.UnsupportedEncoding;
    var font = Font{ .face = kind, .glyphs = glyphs, .widths = undefined, .pdf_name = if (is_truetype) base.name else null };
    for (glyphs, 0..) |glyph, i| {
        const width = metrics.glyphs[glyph].metrics[@backingInt(kind)].width;
        if (width < 0 and !is_truetype) {
            font.glyphs[i] = 0;
            font.widths[i] = 0;
        } else font.widths[i] = if (width >= 0) @floatFromInt(width) else 0;
    }
    const widths = try resolved(doc, value, "Widths");
    if (is_truetype and widths == .null) return error.UnsupportedFont;
    if (widths != .null) {
        const first = s.uint(try resolved(doc, value, "FirstChar")) catch return error.UnsupportedFont;
        const last = s.uint(try resolved(doc, value, "LastChar")) catch return error.UnsupportedFont;
        if (widths != .array or first > last or last > 255 or widths.array.len != last - first + 1) return error.UnsupportedFont;
        const missing = if (descriptor == .dict) try resolved(doc, descriptor, "MissingWidth") else s.Value.null;
        const default = if (missing == .null) 0 else try s.number(missing);
        if (!std.math.isFinite(default) or default < 0 or default > 1e6) return error.InvalidFontWidth;
        @memset(&font.widths, default);
        for (widths.array, first..) |raw, i| {
            const width = try s.number(try doc.resolve(raw));
            if (!std.math.isFinite(width) or width < 0 or width > 1e6) return error.InvalidFontWidth;
            font.widths[i] = width;
        }
    }
    if (is_truetype) try loadEmbedded(doc, descriptor, enc, &font);
    if (s.get(value, "ToUnicode")) |unicode_map| {
        const mapping = try cmap.load(doc, unicode_map);
        for (mapping.ranges.items) |r| if (r.first.length != 1) return error.InvalidCMap;
        for (&font.extraction, 0..) |*entry, i| entry.* = mapping.get(@intCast(i), 1);
    }
    const result = try doc.allocator().create(Font);
    result.* = font;
    try doc.pdf_fonts.put(doc.allocator(), key, result);
    return result;
}

fn mapOrZero(program: truetype.Font, cm: []const u8, code: u32) !u16 {
    return program.mappedGlyph(cm, code) catch |err| if (err == error.MissingGlyph) 0 else return err;
}
fn loadEmbedded(doc: *d.Document, descriptor: s.Value, enc: s.Value, font: *Font) !void {
    if (descriptor != .dict) return error.UnsupportedFont;
    const program = try cid_font.loadProgram(doc, descriptor);
    const flags = s.uint(try resolved(doc, descriptor, "Flags")) catch return error.InvalidFont;
    if (flags & 36 == 0 or flags & 36 == 36 or flags > std.math.maxInt(u32)) return error.InvalidFont;
    const named = enc == .name and (eq(enc.name, "WinAnsiEncoding") or eq(enc.name, "MacRomanEncoding"));
    const symbolic = !named and flags & 4 != 0;
    var embedded = Embedded{ .program = program };
    const mac = try program.subtable(1, 0);
    if (symbolic) {
        if (try program.subtable(3, 0)) |symbols| {
            var prefix: ?u32 = null;
            for ([_]u32{ 0, 0xf000, 0xf100, 0xf200 }) |candidate| {
                var any = false;
                for (0..256) |code| if (try mapOrZero(program, symbols, candidate + @as(u32, @intCast(code))) != 0) {
                    any = true;
                    break;
                };
                if (any) {
                    if (prefix != null) return error.UnsupportedFontCmap;
                    prefix = candidate;
                }
            }
            const high = prefix orelse return error.UnsupportedFontCmap;
            for (&embedded.ids, 0..) |*id, code| id.* = try mapOrZero(program, symbols, high + @as(u32, @intCast(code)));
        } else if (mac) |cm| {
            for (&embedded.ids, 0..) |*id, code| id.* = try mapOrZero(program, cm, @intCast(code));
        } else return error.UnsupportedFontCmap;
        // Symbolic source bytes are arbitrary selectors, not WinAnsi text.
        @memset(&font.glyphs, 0);
    } else {
        const unicode_map = try program.subtable(3, 1) orelse try program.subtable(3, 10) orelse if (program.cmap.len != 0) program.cmap else null;
        if (unicode_map == null and mac == null) return error.UnsupportedFontCmap;
        for (font.glyphs, 0..) |glyph, code| {
            if (glyph == 0) continue;
            if (unicode_map) |cm| {
                const cp = metrics.glyphs[glyph].unicode;
                if (cp != 0) embedded.ids[code] = try mapOrZero(program, cm, cp);
            } else if (mac) |cm| {
                // A PDF MacRoman name is remapped into the actual Mac OS cmap.
                for (metrics.mac_roman, 0..) |candidate, mac_code| if (candidate == glyph and mac_code != 219) {
                    embedded.ids[code] = try mapOrZero(program, cm, @intCast(mac_code));
                    break;
                };
                if (eq(metrics.glyphs[glyph].name, "Euro")) embedded.ids[code] = try mapOrZero(program, cm, 219);
            }
        }
    }
    const ascent = try s.number(try resolved(doc, descriptor, "Ascent"));
    const descent = try s.number(try resolved(doc, descriptor, "Descent"));
    if (!std.math.isFinite(ascent) or !std.math.isFinite(descent) or @abs(ascent) > 1e6 or @abs(descent) > 1e6 or descent > ascent) return error.InvalidFont;
    for (embedded.ids, 0..) |id, code| {
        if (id == 0) continue;
        const box = try program.glyphBounds(id);
        embedded.boxes[code] = .{ box[0] / program.units, @min(descent / 1000, box[1] / program.units), box[2] / program.units, @max(ascent / 1000, box[3] / program.units) };
    }
    font.embedded = embedded;
}

test "PDF encoding, Differences and explicit metrics" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "test");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    const cases = .{
        .{ "/WinAnsiEncoding", "\xe9\x80\xff", "é€ÿ" },
        .{ "/MacRomanEncoding", "\x8e\xdb", "é¤" },
        .{ "/StandardEncoding", "\x60\x27\xae", "‘’ﬁ" },
        .{ "<< /BaseEncoding /WinAnsiEncoding /Differences [65 /eacute /Euro /fi] >>", "ABC", "é€ﬁ" },
    };
    inline for (cases) |case| {
        var parser = s.Parser{ .allocator = doc.allocator(), .bytes = "<< /Font << /F1 << /Subtype /Type1 /BaseFont /Helvetica /Encoding " ++ case[0] ++ " >> >> >>" };
        const resources = try parser.value();
        const font = try load(&doc, resources, "F1");
        try std.testing.expect(font == try load(&doc, resources, "F1"));
        var decoded: std.ArrayList(u8) = .empty;
        try font.decode(doc.allocator(), case[1], &decoded);
        try std.testing.expectEqualStrings(case[2], decoded.items);
        try std.testing.expectEqualStrings(case[1], try font.encode(doc.allocator(), case[2]));
        try std.testing.expectError(error.UnsupportedEncoding, font.encode(doc.allocator(), "😀"));
        try std.testing.expectError(error.UnsupportedEncoding, font.encode(doc.allocator(), "\xff"));
    }
    var parser = s.Parser{ .allocator = doc.allocator(), .bytes = "<< /Font << /F1 << /Subtype /Type1 /BaseFont /Helvetica /FirstChar 65 /LastChar 66 /Widths [900 300] /FontDescriptor << /MissingWidth 250 >> >> >> >>" };
    const font = try load(&doc, try parser.value(), "F1");
    try std.testing.expectEqual(@as(f64, 900), font.widths['A']);
    try std.testing.expectEqual(@as(f64, 300), font.widths['B']);
    try std.testing.expectEqual(@as(f64, 250), font.widths['C']);
}

test "font mutation invalidates cached metrics" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "test");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    const pages = try doc.inspect();
    const resource = pages[0].resources;
    const old = try load(&doc, resource, "F1");
    try std.testing.expectEqualStrings("Courier", old.name());
    try doc.set(try doc.object(.{ .id = 4, .generation = 0 }), "BaseFont", .{ .name = "Helvetica" });
    const changed = try load(&doc, resource, "F1");
    try std.testing.expectEqualStrings("Helvetica", changed.name());
    try std.testing.expectEqual(@as(f64, 222), changed.widths['i']);
    try std.testing.expectEqual(@as(f64, 600), old.widths['i']);
}

test "ToUnicode changes extraction but preserves glyph selection" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "ABC");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    var parser = s.Parser{ .allocator = doc.allocator(), .bytes = "<< >>" };
    const cmap_id = try doc.addObject(try parser.value(), "begincmap 1 begincodespacerange <00> <ff> endcodespacerange 3 beginbfchar <41> <00660069> <42> <D83DDE00> <43> <000a> endbfchar endcmap");
    try doc.set(try doc.object(.{ .id = 4, .generation = 0 }), "ToUnicode", .{ .ref = .{ .id = cmap_id, .generation = 0 } });
    const runs = (try doc.inspect())[0].runs;
    try std.testing.expectEqualStrings("fi😀\n", runs[0].text);
    try std.testing.expectEqualStrings("AB", try runs[0].font.encode(doc.allocator(), "fi😀"));
    try std.testing.expectEqual(@as(f64, 21.6), runs[0].advance);
    const next = runs[1].x;
    try doc.replace(1, 0, "fi");
    const saved = try doc.save(a);
    defer a.free(saved);
    var copy = try d.Document.open(a, saved);
    defer copy.deinit();
    const edited = (try copy.inspect())[0].runs;
    try std.testing.expectEqualStrings("fi", edited[0].text);
    try std.testing.expectApproxEqAbs(next, edited[1].x, 1e-8);
}

test "ToUnicode reverse mapping finds an encoding when greedy longest match fails" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var font = Font{ .face = .courier, .glyphs = @splat(0), .widths = @splat(600) };
    font.glyphs['A'] = glyphIndex("A").?;
    font.glyphs['B'] = glyphIndex("B").?;
    font.glyphs['C'] = glyphIndex("C").?;
    font.extraction['A'] = "ab";
    font.extraction['B'] = "a";
    font.extraction['C'] = "bc";
    try std.testing.expectEqualStrings("BC", try font.encode(arena.allocator(), "abc"));
    try std.testing.expectEqualStrings("A", try font.encode(arena.allocator(), "ab"));
    try std.testing.expectError(error.UnsupportedEncoding, font.encode(arena.allocator(), "ac"));
}

test "ToUnicode inheritance cycles and stream mutation" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "A");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    const program = "begincmap 1 begincodespacerange <00> <ff> endcodespacerange 1 beginbfchar <41> <0058> endbfchar endcmap";
    var parser = s.Parser{ .allocator = doc.allocator(), .bytes = "<< >>" };
    const id = try doc.addObject(try parser.value(), program);
    const ref = s.Value{ .ref = .{ .id = id, .generation = 0 } };
    const obj = try doc.object(ref.ref);
    try doc.set(try doc.object(.{ .id = 4, .generation = 0 }), "ToUnicode", ref);
    const resources = (try doc.inspect())[0].resources;
    try std.testing.expectEqualStrings("X", (try load(&doc, resources, "F1")).extraction['A'].?);
    try doc.replaceStream(obj, "begincmap 1 begincodespacerange <00> <ff> endcodespacerange 1 beginbfchar <41> <0059> endbfchar endcmap");
    try std.testing.expectEqualStrings("Y", (try load(&doc, resources, "F1")).extraction['A'].?);
    try std.testing.expectEqualStrings("Y", (try doc.inspect())[0].runs[0].text);
    try doc.set(obj, "UseCMap", ref);
    try std.testing.expectError(error.CMapCycle, load(&doc, resources, "F1"));
}

test "Unicode extraction limits expansion before appending" {
    var font = Font{ .face = .courier, .glyphs = @splat(0), .widths = @splat(600) };
    font.extraction['A'] = "mapped";
    var text: std.ArrayList(u8) = .empty;
    // Existing decoded text already fills the per-run budget. No append is allowed.
    const memory = try std.testing.allocator.alloc(u8, max_decoded_text);
    defer std.testing.allocator.free(memory);
    text.items = memory;
    text.capacity = memory.len;
    try std.testing.expectError(error.TextLimit, font.decode(std.testing.allocator, "A", &text));
    try std.testing.expectEqual(max_decoded_text, text.items.len);
}
