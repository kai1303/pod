const std = @import("std");
const pod = @import("pod.zig");
test "renderer paints ordered rectangles into bounded opaque RGBA" {
    const a = std.testing.allocator;
    const bytes = try pod.create(a, "test");
    defer a.free(bytes);
    var doc = try pod.Document.open(a, bytes);
    defer doc.deinit();
    (try doc.object(.{ .id = 5, .generation = 0 })).changed = "1 0 0 rg 0 0 612 792 re f 0 0 1 rg 0 0 306 396 re f";
    const bitmap = try render(a, &doc, 0, &.{}, 612);
    defer a.free(bitmap.pixels);
    try std.testing.expectEqual(@as(u32, 792), bitmap.height);
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, bitmap.pixels[0..4]);
    const at = (700 * 612 + 10) * 4;
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 255, 255 }, bitmap.pixels[at..][0..4]);
    try std.testing.expectError(error.BitmapLimit, render(a, &doc, 0, &.{}, 4097));
}

const d = @import("document.zig");
const c = @import("content.zig");
const s = @import("syntax.zig");
const f = @import("font.zig");
const annotations = @import("annotations.zig");
const A = std.mem.Allocator;
const P = extern struct { x: f64, y: f64 };
pub const Edge = extern struct { a: P, b: P };
const Color = [3]u8;
pub const Bitmap = struct { width: u32, height: u32, pixels: []u8 };
const Paint = struct { fill: Color = .{ 0, 0, 0 }, stroke: Color = .{ 0, 0, 0 }, width: f64 = 1, round_cap: bool = false, join: u8 = 0, miter: f64 = 10 };
const Contour = struct { start: usize, closed: bool = false };
const Path = struct {
    // Stroking expands one input segment into several polygons (and round arcs).
    point_limit: usize = 65536,
    contour_limit: usize = 16384,
    points: std.ArrayList(P) = .empty,
    contours: std.ArrayList(Contour) = .empty,
    fn clear(self: *Path) void {
        self.points.clearRetainingCapacity();
        self.contours.clearRetainingCapacity();
    }
    fn begin(self: *Path, a: A, p: P) !void {
        if (self.contours.items.len >= self.contour_limit) return error.PathLimit;
        try self.contours.append(a, .{ .start = self.points.items.len });
        try self.add(a, p);
    }
    fn add(self: *Path, a: A, p: P) !void {
        if (!std.math.isFinite(p.x) or !std.math.isFinite(p.y) or @abs(p.x) > 1e9 or @abs(p.y) > 1e9) return error.InvalidTransform;
        if (self.points.items.len >= self.point_limit) return error.PathLimit;
        if (self.contours.items.len == 0) return error.InvalidPath;
        try self.points.append(a, p);
    }
    fn current(self: *Path) !P {
        if (self.contours.items.len == 0) return error.InvalidPath;
        const contour = self.contours.items[self.contours.items.len - 1];
        if (contour.closed) return error.UnsupportedPathContinuation;
        return self.points.items[self.points.items.len - 1];
    }
    fn close(self: *Path) !void {
        if (self.contours.items.len == 0) return error.InvalidPath;
        self.contours.items[self.contours.items.len - 1].closed = true;
    }
};
fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
fn point(m: c.Matrix, x: f64, y: f64) P {
    return .{ .x = x * m[0] + y * m[2] + m[4], .y = x * m[1] + y * m[3] + m[5] };
}
fn mid(a: P, b: P) P {
    return .{ .x = (a.x + b.x) / 2, .y = (a.y + b.y) / 2 };
}
fn len(a: P, b: P) f64 {
    return @sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));
}
fn flat(a: P, control: P, b: P) f64 {
    const distance = len(a, b);
    if (distance < 1e-12) return len(a, control);
    // Distance to the finite chord also catches a collinear curve reversing direction.
    const projection = (control.x - a.x) * (b.x - a.x) + (control.y - a.y) * (b.y - a.y);
    if (projection < 0) return len(a, control);
    if (projection > distance * distance) return len(b, control);
    return @abs((b.x - a.x) * (a.y - control.y) - (a.x - control.x) * (b.y - a.y)) / distance;
}
fn quadratic(path: *Path, a: A, p: P, q: P, r: P, depth: u8) anyerror!void {
    if (depth >= 12 or flat(p, q, r) <= 0.15) return path.add(a, r);
    const pq = mid(p, q);
    const qr = mid(q, r);
    const center = mid(pq, qr);
    try quadratic(path, a, p, pq, center, depth + 1);
    try quadratic(path, a, center, qr, r, depth + 1);
}
fn cubic(path: *Path, a: A, p: P, q: P, r: P, t: P, depth: u8) anyerror!void {
    if (depth >= 12 or @max(flat(p, q, t), flat(p, r, t)) <= 0.15) return path.add(a, t);
    const pq = mid(p, q);
    const qr = mid(q, r);
    const rt = mid(r, t);
    const pqr = mid(pq, qr);
    const qrt = mid(qr, rt);
    const center = mid(pqr, qrt);
    try cubic(path, a, p, pq, pqr, center, depth + 1);
    try cubic(path, a, center, qrt, rt, t, depth + 1);
}
fn checkResources(doc: *d.Document, page: d.Page) !void {
    if (s.get(page.resources, "ColorSpace")) |spaces| {
        const dict = try doc.resolve(spaces);
        for ([_][]const u8{ "DefaultGray", "DefaultRGB", "DefaultCMYK" }) |key| if (s.get(dict, key) != null) return error.UnsupportedColorSpace;
    }
}
pub fn validate(doc: *d.Document) !void {
    const pages = try doc.inspect();
    if (doc.unsupported_appearance) return error.UnsupportedPageAppearance;
    for (pages) |*page| {
        try checkResources(doc, page.*);
        _ = try pageBox(page.*);
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        var r = Renderer{ .allocator = arena.allocator() };
        _ = try c.interpretAllocated(doc, page, r.sink(), arena.allocator());
        if (r.path.contours.items.len != 0) return error.UnpaintedPath;
        try renderAnnotations(doc, page.number - 1, &r);
    }
}
fn pageBox(page: d.Page) ![4]f64 {
    return page.visibleBox();
}
const Layout = struct { page: *d.Page, height: u32, view: c.Matrix };
pub const PaintCallback = *const fn (*anyopaque, [*]const Edge, usize, u32, f64, bool, bool) callconv(.c) bool;
pub const Collector = struct { context: *anyopaque, paint: PaintCallback, hairlines: *bool };

fn layout(doc: *d.Document, page_index: usize, width: u32) !Layout {
    if (width == 0 or width > 4096) return error.BitmapLimit;
    const pages = try doc.inspect();
    if (doc.unsupported_appearance) return error.UnsupportedPageAppearance;
    if (page_index >= pages.len) return error.PageNotFound;
    const page = &pages[page_index];
    try checkResources(doc, page.*);
    const box = try pageBox(page.*);
    const swap = @mod(page.rotation, 180) != 0;
    const display_width = if (swap) box[3] - box[1] else box[2] - box[0];
    const display_height = if (swap) box[2] - box[0] else box[3] - box[1];
    const scale = @as(f64, @floatFromInt(width)) / display_width;
    const h = @ceil(display_height * scale);
    const view: c.Matrix = switch (page.rotation) {
        0 => .{ scale, 0, 0, -scale, -box[0] * scale, box[3] * scale },
        90 => .{ 0, scale, scale, 0, -box[1] * scale, -box[0] * scale },
        180 => .{ -scale, 0, 0, scale, box[2] * scale, -box[1] * scale },
        270 => .{ 0, -scale, -scale, 0, box[3] * scale, box[2] * scale },
        else => return error.InvalidRotation,
    };
    if (h < 1 or h > 16384 or h * @as(f64, @floatFromInt(width)) * 4 > 64 * 1024 * 1024) return error.BitmapLimit;
    const height: u32 = @intFromFloat(h);
    return .{ .page = page, .height = height, .view = view };
}
pub fn collect(a: A, doc: *d.Document, page_index: usize, font_bytes: []const u8, width: u32, collector: Collector) !u32 {
    const target = try layout(doc, page_index, width);
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    var r = Renderer{ .allocator = arena.allocator(), .collector = collector, .view = target.view, .font_bytes = font_bytes };
    try r.paintPage(doc, target.page, page_index);
    return target.height;
}
pub fn render(a: A, doc: *d.Document, page_index: usize, font_bytes: []const u8, width: u32) !Bitmap {
    const target = try layout(doc, page_index, width);
    const height = target.height;
    const pixels = try a.alloc(u8, @as(usize, width) * height * 4);
    errdefer a.free(pixels);
    @memset(pixels, 255);
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    var r = Renderer{ .allocator = arena.allocator(), .bitmap = .{ .width = width, .height = height, .pixels = pixels }, .view = target.view, .font_bytes = font_bytes };
    try r.paintPage(doc, target.page, page_index);
    return r.bitmap.?;
}
fn renderAnnotations(doc: *d.Document, page_index: usize, renderer: *Renderer) !void {
    for (try annotations.list(doc, page_index)) |ann| {
        renderer.opacity = annotations.effectiveOpacity(ann);
        renderer.multiply_blend = annotations.isImportedMarkup(ann) and ann.kind == .highlight;
        if (ann.imported_ink) {
            const lo = point(renderer.view, ann.rect[0], ann.rect[1]);
            const hi = point(renderer.view, ann.rect[2], ann.rect[3]);
            const clip = [4]f64{ @min(lo.x, hi.x), @min(lo.y, hi.y), @max(lo.x, hi.x), @max(lo.y, hi.y) };
            renderer.paint = .{ .width = ann.style.width, .round_cap = true, .join = 1 };
            for (&renderer.paint.stroke, ann.style.stroke) |*channel, v| channel.* = @intFromFloat(@round(v * 255));
            for (0..@max(1, ann.ink.starts.len)) |i| {
                const points = ann.ink.subpath(ann.points, i);
                // PDFKit emits a solitary move for move-only paths, which paints no mark.
                if (ann.pdfkit_ink and points.len == 1) continue;
                try renderer.path.begin(renderer.allocator, point(renderer.view, points[0].x, points[0].y));
                const tail = if (points.len == 1) points else points[1..];
                for (tail) |p| try renderer.path.add(renderer.allocator, point(renderer.view, p.x, p.y));
                if (ann.pdfkit_ink) {
                    try renderer.stroke(renderer.view, clip);
                    renderer.path.clear();
                }
            }
            if (!ann.pdfkit_ink) {
                try renderer.stroke(renderer.view, clip);
                renderer.path.clear();
            }
            continue;
        }
        if (annotations.isImportedMarkup(ann)) {
            var color: Color = undefined;
            for (&color, ann.style.stroke) |*channel, v| channel.* = @intFromFloat(@round(v * 255));
            var i: usize = 0;
            while (i < ann.points.len) : (i += 4) {
                var buf: annotations.MarkupPolygon = undefined;
                const outline = annotations.markupPolygon(ann, i, &buf);
                var transformed: [buf.len]P = undefined;
                for (transformed[0..outline.len], outline) |*p, q| p.* = point(renderer.view, q.x, q.y);
                try polygon(&renderer.path, renderer.allocator, transformed[0..outline.len]);
                try renderer.fill(&renderer.path, color, false);
                renderer.path.clear();
            }
            continue;
        }
        const obj = try annotations.appearanceObject(doc, ann);
        const saved = obj.changed;
        defer obj.changed = saved;
        // The canonical AP is already validated; alpha is applied by our rasterizer.
        obj.changed = try annotations.appearance(renderer.allocator, ann, false);
        const annotation = try doc.object(.{ .id = ann.id, .generation = doc.entries[ann.id].generation });
        const normal = s.get(s.get(annotation.value, "AP").?, "N").?.ref.id;
        var ids = [_]u32{normal};
        var page = d.Page{ .number = page_index + 1, .resources = s.get(obj.value, "Resources").?, .media_box = (try doc.inspect())[page_index].media_box, .contents = &ids };
        renderer.paint = .{};
        _ = try c.interpretAllocated(doc, &page, renderer.sink(), renderer.allocator);
        if (renderer.path.contours.items.len != 0) return error.UnpaintedPath;
    }
}
const Renderer = struct {
    allocator: A,
    bitmap: ?Bitmap = null,
    collector: ?Collector = null,
    view: c.Matrix = .{ 1, 0, 0, 1, 0, 0 },
    font_bytes: []const u8 = &.{},
    font: ?f.Font = null,
    opacity: f64 = 1,
    multiply_blend: bool = false,
    paint: Paint = .{},
    stack: std.ArrayList(Paint) = .empty,
    path: Path = .{},
    glyph_path: Path = .{},
    outline: f.Outline = .{},
    fn paintPage(self: *Renderer, doc: *d.Document, page: *d.Page, page_index: usize) !void {
        _ = try c.interpretAllocated(doc, page, self.sink(), self.allocator);
        if (self.path.contours.items.len != 0) return error.UnpaintedPath;
        try renderAnnotations(doc, page_index, self);
    }
    fn sink(self: *Renderer) c.Sink {
        return .{ .context = self, .operator = operator, .glyph = glyph };
    }
    fn operator(ctx: *anyopaque, op: []const u8, values: []s.Value, state: c.State) anyerror!void {
        const self: *Renderer = @ptrCast(@alignCast(ctx));
        var ns: [6]f64 = @splat(0);
        for (values[0..@min(values.len, 6)], 0..) |v, i| {
            if (v == .integer or v == .real) ns[i] = try s.number(v);
            if (!std.math.isFinite(ns[i]) or @abs(ns[i]) > 1e12) return error.InvalidNumber;
        }
        const m = c.multiply(state.ctm, self.view);
        if (eq(op, "q")) {
            try self.stack.append(self.allocator, self.paint);
        } else if (eq(op, "Q")) {
            self.paint = self.stack.pop() orelse return error.GraphicsStackUnderflow;
        } else if (eq(op, "Tr")) {
            if (ns[0] != 0 and ns[0] != 3) return error.UnsupportedTextRendering;
        } else if (eq(op, "g") or eq(op, "G") or eq(op, "rg") or eq(op, "RG")) {
            const gray = op.len == 1;
            var rgb: Color = undefined;
            for (&rgb, 0..) |*v, i| v.* = @intFromFloat(@round(std.math.clamp(ns[if (gray) 0 else i], 0, 1) * 255));
            if (op[0] == 'g' or op[0] == 'r') self.paint.fill = rgb else self.paint.stroke = rgb;
        } else if (eq(op, "k") or eq(op, "K")) return error.UnsupportedColorSpace else if (eq(op, "w")) {
            if (ns[0] < 0 or ns[0] > 1e6) return error.UnsupportedStroke;
            self.paint.width = ns[0];
        } else if (eq(op, "J")) {
            if (ns[0] != 0 and ns[0] != 1) return error.UnsupportedStroke;
            self.paint.round_cap = ns[0] == 1;
        } else if (eq(op, "j")) {
            if (ns[0] != 0 and ns[0] != 1 and ns[0] != 2) return error.UnsupportedStroke;
            self.paint.join = @intFromFloat(ns[0]);
        } else if (eq(op, "M")) {
            if (ns[0] < 1 or ns[0] > 1e6) return error.UnsupportedStroke;
            self.paint.miter = ns[0];
        } else if (eq(op, "m")) {
            try self.path.begin(self.allocator, point(m, ns[0], ns[1]));
        } else if (eq(op, "l")) {
            _ = try self.path.current();
            try self.path.add(self.allocator, point(m, ns[0], ns[1]));
        } else if (eq(op, "h")) {
            try self.path.close();
        } else if (eq(op, "re")) {
            try self.path.begin(self.allocator, point(m, ns[0], ns[1]));
            try self.path.add(self.allocator, point(m, ns[0] + ns[2], ns[1]));
            try self.path.add(self.allocator, point(m, ns[0] + ns[2], ns[1] + ns[3]));
            try self.path.add(self.allocator, point(m, ns[0], ns[1] + ns[3]));
            try self.path.close();
        } else if (eq(op, "c") or eq(op, "v") or eq(op, "y")) {
            const p = try self.path.current();
            const q = if (eq(op, "v")) p else point(m, ns[0], ns[1]);
            const r = if (eq(op, "c")) point(m, ns[2], ns[3]) else if (eq(op, "v")) point(m, ns[0], ns[1]) else point(m, ns[2], ns[3]);
            const t = if (eq(op, "c")) point(m, ns[4], ns[5]) else point(m, ns[2], ns[3]);
            try cubic(&self.path, self.allocator, p, q, r, t, 0);
        } else if (eq(op, "n")) {
            self.path.clear();
        } else if (eq(op, "f") or eq(op, "F") or eq(op, "f*")) {
            try self.fill(&self.path, self.paint.fill, eq(op, "f*"));
            self.path.clear();
        } else if (eq(op, "S") or eq(op, "s") or eq(op, "B") or eq(op, "B*") or eq(op, "b") or eq(op, "b*")) {
            if (op[0] == 's' or op[0] == 'b') try self.path.close();
            if (op[0] == 'B' or op[0] == 'b') try self.fill(&self.path, self.paint.fill, op.len == 2);
            try self.stroke(m, null);
            self.path.clear();
        }
    }
    fn glyph(ctx: *anyopaque, char: u8, transform: c.Matrix, state: c.State) anyerror!void {
        const self: *Renderer = @ptrCast(@alignCast(ctx));
        if (state.mode == 3 or (self.bitmap == null and self.collector == null)) return;
        if (state.mode != 0) return error.UnsupportedTextRendering;
        if (self.font == null) self.font = try f.Font.init(self.font_bytes);
        const font = self.font.?;
        self.outline.points.clearRetainingCapacity();
        self.outline.ends.clearRetainingCapacity();
        const codepoint: u16 = if (state.standard_encoding and char == 39) 0x2019 else if (state.standard_encoding and char == 96) 0x2018 else char;
        try font.outline(self.allocator, try font.glyph(codepoint), &self.outline);
        self.glyph_path.clear();
        const m = c.multiply(c.multiply(.{ 1 / font.units, 0, 0, 1 / font.units, 0, 0 }, transform), self.view);
        var first: usize = 0;
        for (self.outline.ends.items) |end| {
            const pts = self.outline.points.items[first .. end + 1];
            first = end + 1;
            const start = if (pts[0].on) point(m, pts[0].x, pts[0].y) else if (pts[pts.len - 1].on) point(m, pts[pts.len - 1].x, pts[pts.len - 1].y) else mid(point(m, pts[0].x, pts[0].y), point(m, pts[pts.len - 1].x, pts[pts.len - 1].y));
            try self.glyph_path.begin(self.allocator, start);
            var current = start;
            var i: usize = if (pts[0].on) 1 else 0;
            while (i < pts.len) {
                const p = point(m, pts[i].x, pts[i].y);
                if (pts[i].on) {
                    try self.glyph_path.add(self.allocator, p);
                    current = p;
                    i += 1;
                } else {
                    const next = if (i + 1 < pts.len) pts[i + 1] else pts[0];
                    const next_p = point(m, next.x, next.y);
                    const dest = if (next.on) next_p else mid(p, next_p);
                    try quadratic(&self.glyph_path, self.allocator, current, p, dest, 0);
                    current = dest;
                    i += if (next.on) @as(usize, 2) else 1;
                }
            }
            try self.glyph_path.close();
        }
        try self.fill(&self.glyph_path, self.paint.fill, false);
    }
    fn stroke(self: *Renderer, m: c.Matrix, clip: ?[4]f64) !void {
        const sx = @sqrt(m[0] * m[0] + m[1] * m[1]);
        const sy = @sqrt(m[2] * m[2] + m[3] * m[3]);
        if (@abs(sx - sy) > 1e-6 * @max(1, sx) or @abs(m[0] * m[2] + m[1] * m[3]) > 1e-6 * @max(1, sx * sy)) return error.UnsupportedStrokeTransform;
        if (self.paint.width == 0) {
            if (self.collector) |collector| collector.hairlines.* = true;
        }
        const radius = if (self.paint.width == 0) @as(f64, 0.5) else self.paint.width * sx / 2;
        var outline: Path = .{ .point_limit = 2_000_000, .contour_limit = 262144 };
        defer {
            outline.points.deinit(self.allocator);
            outline.contours.deinit(self.allocator);
        }
        for (self.path.contours.items, 0..) |contour, ci| {
            const end = if (ci + 1 < self.path.contours.items.len) self.path.contours.items[ci + 1].start else self.path.points.items.len;
            var pts = self.path.points.items[contour.start..end];
            if (pts.len < 2) continue;
            if (self.paint.join == 1) {
                var used: usize = 1;
                for (pts[1..]) |p| {
                    if (len(p, pts[used - 1]) > 1e-10) {
                        pts[used] = p;
                        used += 1;
                    }
                }
                pts = pts[0..used];
            }
            if (!contour.closed and self.paint.round_cap) {
                try roundSector(&outline, self.allocator, pts[0], radius, 0, 2 * std.math.pi);
                if (len(pts[0], pts[pts.len - 1]) > 1e-10)
                    try roundSector(&outline, self.allocator, pts[pts.len - 1], radius, 0, 2 * std.math.pi);
            }
            const segments = if (contour.closed) pts.len else pts.len - 1;
            for (0..segments) |i| {
                const a = pts[i];
                const b = pts[(i + 1) % pts.len];
                const distance = len(a, b);
                if (distance < 1e-10) continue;
                const n = P{ .x = -(b.y - a.y) * radius / distance, .y = (b.x - a.x) * radius / distance };
                try polygon(&outline, self.allocator, &.{ .{ .x = a.x + n.x, .y = a.y + n.y }, .{ .x = b.x + n.x, .y = b.y + n.y }, .{ .x = b.x - n.x, .y = b.y - n.y }, .{ .x = a.x - n.x, .y = a.y - n.y } });
                if (i + 1 < segments or contour.closed) {
                    const next = pts[(i + 2) % pts.len];
                    const nd = len(b, next);
                    if (nd < 1e-10) continue;
                    const n2 = P{ .x = -(next.y - b.y) * radius / nd, .y = (next.x - b.x) * radius / nd };
                    const cross = (b.x - a.x) * (next.y - b.y) - (b.y - a.y) * (next.x - b.x);
                    if (self.paint.join == 1 and @abs(cross) < 1e-12 and n.x * n2.x + n.y * n2.y < 0) {
                        try roundSector(&outline, self.allocator, b, radius, 0, 2 * std.math.pi);
                    }
                    if (@abs(cross) < 1e-12) continue;
                    const sign: f64 = if (cross > 0) -1 else 1;
                    const p = P{ .x = b.x + sign * n.x, .y = b.y + sign * n.y };
                    const q = P{ .x = b.x + sign * n2.x, .y = b.y + sign * n2.y };
                    if (self.paint.join == 1) {
                        const start = if (cross > 0) q else p;
                        const angle = std.math.atan2(start.y - b.y, start.x - b.x);
                        const sweep = std.math.atan2(@abs(n.x * n2.y - n.y * n2.x), n.x * n2.x + n.y * n2.y);
                        try roundSector(&outline, self.allocator, b, radius, angle, sweep);
                        continue;
                    }
                    var tip = b;
                    if (self.paint.join == 0) {
                        const dot = (n.x * n2.x + n.y * n2.y) / (radius * radius);
                        if (1 + dot > 1e-10) {
                            const candidate = P{ .x = b.x + sign * (n.x + n2.x) / (1 + dot), .y = b.y + sign * (n.y + n2.y) / (1 + dot) };
                            if (len(candidate, b) <= radius * self.paint.miter) tip = candidate;
                        }
                    }
                    if (cross > 0) try polygon(&outline, self.allocator, &.{ p, b, q, tip }) else try polygon(&outline, self.allocator, &.{ q, b, p, tip });
                }
            }
        }
        if (clip) |box| {
            for (outline.points.items) |p| {
                if (p.x < box[0] or p.y < box[1] or p.x > box[2] or p.y > box[3]) {
                    const clipped = try clipPolygons(self.allocator, outline, box);
                    return self.fill(&clipped, self.paint.stroke, false);
                }
            }
        }
        try self.fill(&outline, self.paint.stroke, false);
    }
    fn fill(self: *Renderer, path: *const Path, color: Color, even: bool) !void {
        if (self.bitmap == null and self.collector == null) return;
        var edges: std.ArrayList(Edge) = .empty;
        defer edges.deinit(self.allocator);
        var miny: f64 = std.math.inf(f64);
        var maxy: f64 = 0;
        for (path.contours.items, 0..) |contour, ci| {
            const end = if (ci + 1 < path.contours.items.len) path.contours.items[ci + 1].start else path.points.items.len;
            const pts = path.points.items[contour.start..end];
            if (pts.len < 2) continue;
            for (pts, 0..) |a, i| {
                const b = pts[(i + 1) % pts.len];
                if (a.y == b.y) continue;
                miny = @min(miny, @min(a.y, b.y));
                maxy = @max(maxy, @max(a.y, b.y));
                try edges.append(self.allocator, .{ .a = a, .b = b });
            }
        }
        if (edges.items.len == 0) return;
        if (self.collector) |collector| {
            const rgb = (@as(u32, color[0]) << 16) | (@as(u32, color[1]) << 8) | color[2];
            if (!collector.paint(collector.context, edges.items.ptr, edges.items.len, rgb, self.opacity, even, self.multiply_blend)) return error.SceneLimit;
            return;
        }
        const bitmap = self.bitmap.?;
        const y0: usize = @intFromFloat(std.math.clamp(@floor(miny), 0, @as(f64, @floatFromInt(bitmap.height))));
        const y1: usize = @intFromFloat(std.math.clamp(@ceil(maxy), 0, @as(f64, @floatFromInt(bitmap.height))));
        if (y0 >= y1) return;
        const Hit = struct { x: f64, w: i32 };
        const hits = try self.allocator.alloc(Hit, edges.items.len);
        defer self.allocator.free(hits);
        const coverage = try self.allocator.alloc(u8, bitmap.width);
        defer self.allocator.free(coverage);
        for (y0..y1) |y| {
            @memset(coverage, 0);
            for (0..4) |sample| {
                const sy = @as(f64, @floatFromInt(y)) + (@as(f64, @floatFromInt(sample)) + 0.5) / 4;
                var n: usize = 0;
                for (edges.items) |edge| {
                    if (sy < @min(edge.a.y, edge.b.y) or sy >= @max(edge.a.y, edge.b.y)) continue;
                    hits[n] = .{ .x = edge.a.x + (sy - edge.a.y) * (edge.b.x - edge.a.x) / (edge.b.y - edge.a.y), .w = if (edge.b.y > edge.a.y) 1 else -1 };
                    n += 1;
                }
                std.mem.sort(Hit, hits[0..n], {}, struct {
                    fn less(_: void, a: Hit, b: Hit) bool {
                        return a.x < b.x;
                    }
                }.less);
                var winding: i32 = 0;
                var previous: f64 = 0;
                for (hits[0..n]) |hit| {
                    if (if (even) @mod(winding, 2) != 0 else winding != 0) {
                        const begin: usize = @intFromFloat(std.math.clamp(@ceil(previous * 4 - 0.5), 0, @as(f64, @floatFromInt(bitmap.width)) * 4));
                        const end: usize = @intFromFloat(std.math.clamp(@ceil(hit.x * 4 - 0.5), 0, @as(f64, @floatFromInt(bitmap.width)) * 4));
                        for (begin..@max(begin, end)) |x| coverage[x / 4] += 1;
                    }
                    winding += hit.w;
                    previous = hit.x;
                }
            }
            for (coverage, 0..) |alpha, x| {
                if (alpha == 0) continue;
                const at = (y * bitmap.width + x) * 4;
                const coverage_alpha = @as(f64, @floatFromInt(alpha)) / 16 * self.opacity;
                for (color, 0..) |v, i| {
                    const background: f64 = @floatFromInt(bitmap.pixels[at + i]);
                    var ink: f64 = @floatFromInt(v);
                    if (self.multiply_blend) ink *= background / 255;
                    bitmap.pixels[at + i] = @intFromFloat(@round(ink * coverage_alpha + background * (1 - coverage_alpha)));
                }
            }
        }
    }
};
// Walk clockwise so the sector and the segment rectangles share a nonzero winding.
fn clipPolygons(a: A, input: Path, box: [4]f64) !Path {
    var output: Path = .{ .point_limit = input.point_limit, .contour_limit = input.contour_limit };
    var buffers = [2]std.ArrayList(P){ .empty, .empty };
    defer for (&buffers) |*b| b.deinit(a);
    for (input.contours.items, 0..) |contour, i| {
        const end = if (i + 1 < input.contours.items.len) input.contours.items[i + 1].start else input.points.items.len;
        var vertices: []const P = input.points.items[contour.start..end];
        for (box, 0..) |boundary, side| {
            if (vertices.len == 0) break;
            const next = &buffers[side % 2];
            next.clearRetainingCapacity();
            var prev = vertices[vertices.len - 1];
            for (vertices) |p| {
                const from = if (side % 2 == 0) prev.x else prev.y;
                const to = if (side % 2 == 0) p.x else p.y;
                const prev_in = if (side < 2) from >= boundary else from <= boundary;
                const inside = if (side < 2) to >= boundary else to <= boundary;
                if (prev_in != inside) {
                    const t = (boundary - from) / (to - from);
                    try next.append(a, .{ .x = prev.x + t * (p.x - prev.x), .y = prev.y + t * (p.y - prev.y) });
                }
                if (inside) try next.append(a, p);
                prev = p;
            }
            vertices = next.items;
        }
        if (vertices.len >= 3) try polygon(&output, a, vertices);
    }
    return output;
}

fn roundSector(path: *Path, a: A, center: P, radius: f64, angle: f64, sweep: f64) !void {
    const step = @max(0.01, @min(std.math.pi / 6.0, 2 * std.math.acos(@max(0, 1 - 0.12 / radius))));
    const count: usize = @intFromFloat(@max(1, @ceil(sweep / step)));
    try path.begin(a, center);
    for (0..count + 1) |i| {
        const t = angle - sweep * @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(count));
        try path.add(a, .{ .x = center.x + radius * @cos(t), .y = center.y + radius * @sin(t) });
    }
    try path.close();
}
fn polygon(path: *Path, a: A, points: []const P) !void {
    try path.begin(a, points[0]);
    for (points[1..]) |p| try path.add(a, p);
    try path.close();
}

test "system Courier outlines render all printable ASCII with holes and antialiasing" {
    if (@import("builtin").os.tag != .macos) return error.SkipZigTest;
    const a = std.testing.allocator;
    const font_bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "/System/Library/Fonts/Supplemental/Courier New.ttf", a, .limited(8 * 1024 * 1024));
    defer a.free(font_bytes);
    const font = try f.Font.init(font_bytes);
    var outline: f.Outline = .{};
    defer outline.points.deinit(a);
    defer outline.ends.deinit(a);
    for (32..127) |ch| {
        outline.points.clearRetainingCapacity();
        outline.ends.clearRetainingCapacity();
        try font.outline(a, try font.glyph(@intCast(ch)), &outline);
        if (ch != 32) try std.testing.expect(outline.points.items.len > 0);
    }
    const bytes = try pod.create(a, "Hello native renderer");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    const bitmap = try render(a, &doc, 0, font_bytes, 1224);
    defer a.free(bitmap.pixels);
    var dark: usize = 0;
    var aa: usize = 0;
    for (0..bitmap.pixels.len / 4) |i| {
        const v = bitmap.pixels[i * 4];
        if (v < 128) dark += 1;
        if (v > 0 and v < 255) aa += 1;
    }
    try std.testing.expect(dark > 100);
    try std.testing.expect(aa > 100);
}
test "render validation rejects unsupported appearance and text states" {
    const a = std.testing.allocator;
    const bytes = try pod.create(a, "test");
    defer a.free(bytes);
    const cases = .{
        .{ "BT /F1 12 Tf 1 Tr (x) Tj ET", error.UnsupportedTextRendering },
        .{ "1 0 0 0 k", error.UnsupportedColorSpace },
        .{ "2 J", error.UnsupportedStroke },
        .{ "2 0 0 1 0 0 cm 1 1 m 10 10 l S", error.UnsupportedStrokeTransform },
        .{ "0 0 m", error.UnpaintedPath },
    };
    inline for (cases) |case| {
        var doc = try d.Document.open(a, bytes);
        defer doc.deinit();
        (try doc.object(.{ .id = 5, .generation = 0 })).changed = case[0];
        try std.testing.expectError(case[1], validate(&doc));
    }
}
test "even odd holes and stroke width are preserved" {
    const a = std.testing.allocator;
    const bytes = try pod.create(a, "test");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    (try doc.object(.{ .id = 5, .generation = 0 })).changed = "0 0 100 100 re 20 20 60 60 re f* 1 0 0 RG 10 w 200 50 m 300 50 l S";
    const bitmap = try render(a, &doc, 0, &.{}, 612);
    defer a.free(bitmap.pixels);
    try std.testing.expectEqual(@as(u8, 0), bitmap.pixels[((792 - 10) * 612 + 10) * 4]);
    try std.testing.expectEqual(@as(u8, 255), bitmap.pixels[((792 - 50) * 612 + 50) * 4]);
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, bitmap.pixels[((792 - 50) * 612 + 250) * 4 ..][0..4]);
    try std.testing.expectEqual(@as(u8, 255), bitmap.pixels[((792 - 60) * 612 + 250) * 4 + 1]);
}

test "TJ offsets and transformed text match equivalent text matrices" {
    if (@import("builtin").os.tag != .macos) return error.SkipZigTest;
    const a = std.testing.allocator;
    const font_bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "/System/Library/Fonts/Supplemental/Courier New.ttf", a, .limited(8 * 1024 * 1024));
    defer a.free(font_bytes);
    const bytes = try pod.create(a, "test");
    defer a.free(bytes);
    var doc1 = try d.Document.open(a, bytes);
    defer doc1.deinit();
    var doc2 = try d.Document.open(a, bytes);
    defer doc2.deinit();
    (try doc1.object(.{ .id = 5, .generation = 0 })).changed = "q 1 .2 .1 1 20 30 cm .2 .4 .6 rg BT /F1 30 Tf 50 Tz 4 Ts 1 0 0 1 40 500 Tm [(A) 100 (B)] TJ ET Q";
    (try doc2.object(.{ .id = 5, .generation = 0 })).changed = "q 1 .2 .1 1 20 30 cm .2 .4 .6 rg BT /F1 30 Tf 50 Tz 4 Ts 1 0 0 1 40 500 Tm (A) Tj 1 0 0 1 47.5 500 Tm (B) Tj ET Q";
    const b1 = try render(a, &doc1, 0, font_bytes, 612);
    defer a.free(b1.pixels);
    const b2 = try render(a, &doc2, 0, font_bytes, 612);
    defer a.free(b2.pixels);
    try std.testing.expectEqualSlices(u8, b1.pixels, b2.pixels);
    const run = (try doc1.inspect())[0].runs[0];
    try std.testing.expect(run.bounds[0] < run.x and run.bounds[2] > run.x);
    try std.testing.expect(run.bounds[1] < run.y and run.bounds[3] > run.y);
}
test "closed path followed by line explicitly rejects unsupported continuation" {
    const a = std.testing.allocator;
    const bytes = try pod.create(a, "test");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    (try doc.object(.{ .id = 5, .generation = 0 })).changed = "0 0 m 10 0 l 10 10 l h 20 20 l S";
    try std.testing.expectError(error.UnsupportedPathContinuation, validate(&doc));
}

test "StandardEncoding quotes differ from WinAnsi quotes" {
    if (@import("builtin").os.tag != .macos) return error.SkipZigTest;
    const a = std.testing.allocator;
    const font_bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "/System/Library/Fonts/Supplemental/Courier New.ttf", a, .limited(8 * 1024 * 1024));
    defer a.free(font_bytes);
    const bytes = try pod.create(a, "'`");
    defer a.free(bytes);
    var win = try d.Document.open(a, bytes);
    defer win.deinit();
    var standard = try d.Document.open(a, bytes);
    defer standard.deinit();
    const font = try standard.object(.{ .id = 4, .generation = 0 });
    for (font.value.dict) |*entry| if (eq(entry.key, "Encoding")) {
        entry.value = .{ .name = "StandardEncoding" };
    };
    const b1 = try render(a, &win, 0, font_bytes, 1224);
    defer a.free(b1.pixels);
    const b2 = try render(a, &standard, 0, font_bytes, 1224);
    defer a.free(b2.pixels);
    try std.testing.expect(!std.mem.eql(u8, b1.pixels, b2.pixels));
}

test "inherited page appearance metadata is rejected before rendering" {
    const a = std.testing.allocator;
    const bytes = try pod.create(a, "test");
    defer a.free(bytes);
    inline for (.{ "Annots", "Group", "UserUnit" }) |key| {
        var doc = try d.Document.open(a, bytes);
        defer doc.deinit();
        const pages = try doc.object(.{ .id = 2, .generation = 0 });
        const old = pages.value.dict;
        const dict = try doc.allocator().alloc(s.Entry, old.len + 1);
        @memcpy(dict[0..old.len], old);
        dict[old.len] = .{ .key = key, .value = .{ .integer = 0 } };
        pages.value = .{ .dict = dict };
        try std.testing.expectError(error.UnsupportedPageAppearance, validate(&doc));
    }
}
