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
const pdf_font = @import("pdf_font.zig");
pub const FontSource = struct { face: pdf_font.Face, bytes: []const u8 };
const annotations = @import("annotations.zig");
const A = std.mem.Allocator;
const clipping = @import("clip.zig");
const blend = @import("blend.zig");
const P = clipping.Point;
pub const Edge = clipping.Edge;
const Color = [3]u8;
const images = @import("images.zig");
pub const Bitmap = struct { width: u32, height: u32, pixels: []u8 };
const Paint = struct { fill: Color = .{ 0, 0, 0 }, stroke: Color = .{ 0, 0, 0 }, width: f64 = 1, cap: u8 = 0, join: u8 = 0, miter: f64 = 10, dash: @import("dash.zig").Pattern = .{} };
const Contour = struct { start: usize, closed: bool = false, dot_direction: ?P = null };
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
    fn edges(self: *const Path, a: A) ![]Edge {
        var result: std.ArrayList(Edge) = .empty;
        errdefer result.deinit(a);
        for (self.contours.items, 0..) |contour, ci| {
            const end = if (ci + 1 < self.contours.items.len) self.contours.items[ci + 1].start else self.points.items.len;
            const pts = self.points.items[contour.start..end];
            if (pts.len < 2) continue;
            for (pts, 0..) |p, i| {
                const next = pts[(i + 1) % pts.len];
                if (p.y != next.y) try result.append(a, .{ .a = p, .b = next });
            }
        }
        return result.toOwnedSlice(a);
    }
};
fn samePoint(a: P, b: P) bool {
    return a.x == b.x and a.y == b.y;
}
fn contourPoints(path: *const Path, index: usize) []P {
    const end = if (index + 1 < path.contours.items.len) path.contours.items[index + 1].start else path.points.items.len;
    return path.points.items[path.contours.items[index].start..end];
}
fn appendContour(target: *Path, a: A, points: []const P, closed: bool) !void {
    if (points.len == 0) return;
    try target.begin(a, points[0]);
    for (points[1..]) |p| try target.add(a, p);
    if (closed) try target.close();
}
fn dashDot(path: *Path, a: A, p: P, direction: P) !void {
    try appendContour(path, a, &.{ p, p }, false);
    path.contours.items[path.contours.items.len - 1].dot_direction = direction;
}
fn copyContour(target: *Path, a: A, source: *const Path, index: usize) !void {
    try appendContour(target, a, contourPoints(source, index), source.contours.items[index].closed);
    target.contours.items[target.contours.items.len - 1].dot_direction = source.contours.items[index].dot_direction;
}
fn dashPath(out: *Path, a: A, source: *const Path, pattern: *const @import("dash.zig").Pattern, matrix: c.Matrix) !void {
    // Paths retain device-space points; dash distances use user-space units,
    // including zero-width strokes whose painted thickness is one device pixel.
    const det = matrix[0] * matrix[3] - matrix[1] * matrix[2];
    const sx = @sqrt(matrix[0] * matrix[0] + matrix[1] * matrix[1]);
    const sy = @sqrt(matrix[2] * matrix[2] + matrix[3] * matrix[3]);
    if (sx == 0 or sy == 0 or @abs(det) / (sx * sy) < 1e-12) return error.InvalidTransform;
    const inverse: c.Matrix = .{ matrix[3] / det, -matrix[1] / det, -matrix[2] / det, matrix[0] / det, 0, 0 };
    var parts: Path = .{};
    defer parts.points.deinit(a);
    defer parts.contours.deinit(a);
    var work: usize = 0;
    for (source.contours.items, 0..) |contour, ci| {
        const points = contourPoints(source, ci);
        if (points.len < 2) continue;
        parts.clear();
        var cursor = pattern.cursor();
        var active = false;
        var last_direction = P{ .x = 0, .y = 0 };
        var has_length = false;
        const segments = if (contour.closed) points.len else points.len - 1;
        for (0..segments) |i| {
            const start = points[i];
            const end = points[(i + 1) % points.len];
            const delta = point(inverse, end.x - start.x, end.y - start.y);
            const distance = len(.{ .x = 0, .y = 0 }, delta);
            if (!std.math.isFinite(distance)) return error.InvalidTransform;
            if (distance != 0) {
                last_direction = .{ .x = end.x - start.x, .y = end.y - start.y };
                has_length = true;
            }
            var position: f64 = 0;
            while (position < distance) {
                work += 1;
                if (work > 1_000_000) return error.DashLimit;
                const p = P{ .x = start.x + (end.x - start.x) * (position / distance), .y = start.y + (end.y - start.y) * (position / distance) };
                if (cursor.remaining == 0) {
                    if (cursor.on() and !active) try dashDot(&parts, a, p, last_direction);
                    cursor.next();
                    active = false;
                    continue;
                }
                const amount = @min(cursor.remaining, distance - position);
                if (position + amount == position) return error.DashLimit;
                position += amount;
                const q = if (position == distance) end else P{ .x = start.x + (end.x - start.x) * (position / distance), .y = start.y + (end.y - start.y) * (position / distance) };
                if (cursor.on()) {
                    if (!active) try parts.begin(a, p);
                    try parts.add(a, q);
                    active = true;
                } else active = false;
                cursor.remaining -= amount;
            }
        }
        // A dash beginning exactly after a nonzero path ends is not painted.
        // A genuinely zero-length subpath still uses the current cap style.
        if (!has_length and cursor.on()) try dashDot(&parts, a, points[0], last_direction);
        const count = parts.contours.items.len;
        if (count == 0) continue;
        const first = contourPoints(&parts, 0);
        const last = contourPoints(&parts, count - 1);
        if (contour.closed and parts.contours.items[0].dot_direction == null and parts.contours.items[count - 1].dot_direction == null and samePoint(first[0], points[0]) and samePoint(last[last.len - 1], points[0])) {
            if (count == 1) {
                try appendContour(out, a, first[0 .. first.len - 1], true);
            } else {
                // The dash straddling the closed seam has a join, not two caps.
                try appendContour(out, a, last, false);
                for (first[1..]) |p| try out.add(a, p);
                for (1..count - 1) |part| try copyContour(out, a, &parts, part);
            }
        } else {
            for (0..count) |part| try copyContour(out, a, &parts, part);
        }
    }
}

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
pub fn validate(doc: *d.Document) !void {
    const pages = try doc.inspect();
    if (doc.unsupported_appearance) return error.UnsupportedPageAppearance;
    for (pages) |*page| {
        _ = try pageBox(page.*);
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        var r = Renderer{ .allocator = arena.allocator() };
        _ = try c.interpretAllocated(doc, page, r.sink(), arena.allocator());
        if (r.path.contours.items.len != 0 or r.pending_clip != null) return error.UnpaintedPath;
        try renderAnnotations(doc, page.number - 1, &r);
    }
}
fn pageBox(page: d.Page) ![4]f64 {
    return page.visibleBox();
}
const Layout = struct { page: *d.Page, height: u32, view: c.Matrix };
pub const PaintCallback = *const fn (*anyopaque, [*]const Edge, usize, u32, f64, bool, u32, u32) callconv(.c) bool;
pub const ImagePaint = extern struct {
    pixels: [*]const u8,
    width: u32,
    height: u32,
    inverse: [6]f64,
    interpolate: bool,
    mask_alpha: ?[*]const f32 = null,
    mask_width: u32 = 0,
    mask_height: u32 = 0,
    mask_interpolate: bool = false,
};
pub const ImageCallback = *const fn (*anyopaque, [*]const Edge, usize, *const ImagePaint, f64, u32, u32) callconv(.c) bool;
pub const Collector = struct { context: *anyopaque, paint: PaintCallback, hairlines: *bool, image: ?ImageCallback = null, geometry_only: bool = false };

fn layout(doc: *d.Document, page_index: usize, width: u32, view_rotation: i32) !Layout {
    if (width == 0 or width > 4096) return error.BitmapLimit;
    const pages = try doc.inspect();
    if (doc.unsupported_appearance) return error.UnsupportedPageAppearance;
    if (page_index >= pages.len) return error.PageNotFound;
    const page = &pages[page_index];
    const box = try pageBox(page.*);
    const rotation = @mod(page.rotation + view_rotation, 360);
    const swap = @mod(rotation, 180) != 0;
    const display_width = if (swap) box[3] - box[1] else box[2] - box[0];
    const display_height = if (swap) box[2] - box[0] else box[3] - box[1];
    const scale = @as(f64, @floatFromInt(width)) / display_width;
    const h = @ceil(display_height * scale);
    const view: c.Matrix = switch (rotation) {
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
    return collectWithFonts(a, doc, page_index, &.{.{ .face = .courier, .bytes = font_bytes }}, width, collector);
}
pub fn collectWithFonts(a: A, doc: *d.Document, page_index: usize, fonts: []const FontSource, width: u32, collector: Collector) !u32 {
    return collectPage(a, doc, page_index, fonts, width, collector, .{});
}
pub fn collectPageViewWithFonts(a: A, doc: *d.Document, page_index: usize, fonts: []const FontSource, width: u32, collector: Collector, view: PageView) !u32 {
    try view.validate();
    return collectPage(a, doc, page_index, fonts, width, collector, view);
}
fn collectPage(a: A, doc: *d.Document, page_index: usize, fonts: []const FontSource, width: u32, collector: Collector, view: PageView) !u32 {
    const target = try layout(doc, page_index, width, view.rotation);
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    var r = Renderer{ .allocator = arena.allocator(), .collector = collector, .view = target.view, .font_sources = fonts, .annotation_zoom = view.zoom };
    try r.paintPage(doc, target.page, page_index);
    return target.height;
}
// Bounds of painted page content in unrotated PDF coordinates, excluding
// annotations. FitB destinations need actual content extents, not the page box.
pub fn contentBounds(a: A, doc: *d.Document, page_index: usize, font_bytes: []const u8) !?[4]f64 {
    return contentBoundsWithFonts(a, doc, page_index, &.{.{ .face = .courier, .bytes = font_bytes }});
}
pub fn contentBoundsWithFonts(a: A, doc: *d.Document, page_index: usize, fonts: []const FontSource) !?[4]f64 {
    const pages = try doc.inspect();
    if (doc.unsupported_appearance) return error.UnsupportedPageAppearance;
    if (page_index >= pages.len) return error.PageNotFound;
    const page = &pages[page_index];
    const CollectorBounds = struct {
        box: ?[4]f64 = null,
        fn paint(ctx: *anyopaque, edges: [*]const Edge, count: usize, _: u32, opacity: f64, _: bool, _: u32, _: u32) callconv(.c) bool {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            if (opacity == 0) return true;
            for (edges[0..count]) |edge| for ([_]P{ edge.a, edge.b }) |p| {
                if (self.box) |*box| {
                    box.* = .{ @min(box[0], p.x), @min(box[1], p.y), @max(box[2], p.x), @max(box[3], p.y) };
                } else self.box = .{ p.x, p.y, p.x, p.y };
            };
            return true;
        }
    };
    var result = CollectorBounds{};
    var hairlines = false;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    var r = Renderer{ .allocator = arena.allocator(), .font_sources = fonts, .collector = .{ .context = &result, .paint = CollectorBounds.paint, .hairlines = &hairlines, .geometry_only = true } };
    _ = try c.interpretAllocated(doc, page, r.sink(), arena.allocator());
    if (r.path.contours.items.len != 0 or r.pending_clip != null) return error.UnpaintedPath;
    if (result.box) |box| {
        const crop = try page.visibleBox();
        const clipped = [4]f64{ @max(box[0], crop[0]), @max(box[1], crop[1]), @min(box[2], crop[2]), @min(box[3], crop[3]) };
        if (clipped[2] > clipped[0] and clipped[3] > clipped[1]) return clipped;
    }
    return null;
}
pub fn render(a: A, doc: *d.Document, page_index: usize, font_bytes: []const u8, width: u32) !Bitmap {
    return renderWithFonts(a, doc, page_index, &.{.{ .face = .courier, .bytes = font_bytes }}, width);
}
pub fn renderWithFonts(a: A, doc: *d.Document, page_index: usize, fonts: []const FontSource, width: u32) !Bitmap {
    return renderPage(a, doc, page_index, fonts, width, .{});
}
fn renderPage(a: A, doc: *d.Document, page_index: usize, fonts: []const FontSource, width: u32, view: PageView) !Bitmap {
    const target = try layout(doc, page_index, width, view.rotation);
    const height = target.height;
    const pixels = try a.alloc(u8, @as(usize, width) * height * 4);
    errdefer a.free(pixels);
    @memset(pixels, 255);
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    var r = Renderer{ .allocator = arena.allocator(), .bitmap = .{ .width = width, .height = height, .pixels = pixels }, .view = target.view, .font_sources = fonts, .annotation_zoom = view.zoom };
    try r.paintPage(doc, target.page, page_index);
    return r.bitmap.?;
}
fn renderAnnotations(doc: *d.Document, page_index: usize, renderer: *Renderer) !void {
    // Annotation appearances start independently of the page's final graphics state.
    const marks = try annotations.list(doc, page_index);
    const links = try @import("links.zig").list(doc, page_index);
    var mark_index: usize = 0;
    var link_index: usize = 0;
    for (try annotations.refs(doc, page_index)) |ref| {
        renderer.clip = null;
        renderer.alpha = 1;
        renderer.group = 0;
        if (link_index < links.len and links[link_index].id == ref.ref.id) {
            const link = links[link_index];
            link_index += 1;
            if (link.hidden or link.width == 0 or link.rect[0] == link.rect[2] or link.rect[1] == link.rect[3]) continue;
            renderer.opacity = 1;
            renderer.blend_mode = .normal;
            renderer.paint = .{ .width = link.width };
            for (&renderer.paint.stroke, link.color) |*channel, v| channel.* = @intFromFloat(@round(v * 255));
            const box = link.rect;
            try renderer.path.begin(renderer.allocator, point(renderer.view, box[0], box[1]));
            try renderer.path.add(renderer.allocator, point(renderer.view, box[2], box[1]));
            if (!link.underline) {
                try renderer.path.add(renderer.allocator, point(renderer.view, box[2], box[3]));
                try renderer.path.add(renderer.allocator, point(renderer.view, box[0], box[3]));
                try renderer.path.close();
            }
            try renderer.stroke(renderer.view, null);
            renderer.path.clear();
            continue;
        }
        // Popup dictionaries are UI companions, not independent painted annotations.
        if (mark_index == marks.len or marks[mark_index].id != ref.ref.id) continue;
        const ann = marks[mark_index];
        mark_index += 1;
        // Replies are presented in their parent's thread, not as separate icons.
        if (ann.comment.reply_to != 0) continue;
        if (ann.kind == .comment or ann.imported_shape or ann.imported_free_text) {
            const item = try appearance.load(doc, page_index, ann.id);
            const saved_view = renderer.view;
            defer renderer.view = saved_view;
            renderer.view = try item.view(saved_view, renderer.annotation_zoom);
            renderer.opacity = 1;
            renderer.blend_mode = .normal;
            renderer.paint = .{};
            try renderer.paintAppearance(doc, item);
            continue;
        }
        renderer.opacity = annotations.effectiveOpacity(ann);
        renderer.blend_mode = if (annotations.isImportedMarkup(ann) and ann.kind == .highlight) .multiply else .normal;
        if (ann.imported_ink) {
            const lo = point(renderer.view, ann.rect[0], ann.rect[1]);
            const hi = point(renderer.view, ann.rect[2], ann.rect[3]);
            const clip = [4]f64{ @min(lo.x, hi.x), @min(lo.y, hi.y), @max(lo.x, hi.x), @max(lo.y, hi.y) };
            renderer.paint = .{ .width = ann.style.width, .cap = 1, .join = 1 };
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
        if (renderer.path.contours.items.len != 0 or renderer.pending_clip != null) return error.UnpaintedPath;
    }
}
const Renderer = struct {
    const Texture = struct { image: images.Image, inverse: c.Matrix, tint: Color };
    const Backdrop = struct { group: u32 = 0, color: Color = .{ 0, 0, 0 } };
    const Saved = struct { paint: Paint, clip: ?clipping.Region };
    texture: ?Texture = null,
    allocator: A,
    bitmap: ?Bitmap = null,
    collector: ?Collector = null,
    view: c.Matrix = .{ 1, 0, 0, 1, 0, 0 },
    annotation_zoom: f64 = 1,
    font_sources: []const FontSource = &.{},
    fonts: [14]?f.Font = @splat(null),
    alpha: f64 = 1,
    group: u32 = 0,
    next_group: u32 = 0,
    backdrop_rows: []?[]Backdrop = &.{},
    opacity: f64 = 1,
    blend_mode: blend.Mode = .normal,
    paint: Paint = .{},
    stack: std.ArrayList(Saved) = .empty,
    clip: ?clipping.Region = null,
    pending_clip: ?bool = null,
    clip_edges: usize = 0,
    path: Path = .{},
    glyph_path: Path = .{},
    combine_glyphs: bool = false,
    glyph_edges: std.ArrayList(Edge) = .empty,
    outline: f.Outline = .{},
    fn paintPage(self: *Renderer, doc: *d.Document, page: *d.Page, page_index: usize) !void {
        _ = try c.interpretAllocated(doc, page, self.sink(), self.allocator);
        if (self.path.contours.items.len != 0 or self.pending_clip != null) return error.UnpaintedPath;
        try renderAnnotations(doc, page_index, self);
    }
    fn paintAppearance(self: *Renderer, doc: *d.Document, item: appearance.Appearance) !void {
        switch (item.source) {
            // AP streams carry their own opacity; do not apply /CA twice.
            .form => |appearance_form| {
                var target = self.sink();
                target.glyph_run = glyphRun;
                _ = try c.interpretFormAllocated(doc, appearance_form, item.placement, target, self.allocator);
            },
            .icon => |icon| try self.paintCommentIcon(item.rect, icon),
            .shape => |shape| {
                try form(self, true, item.rect, .{});
                try self.paintShape(shape);
                try form(self, false, item.rect, .{});
            },
            .free_text => |text| try self.paintFreeText(text),
        }
        if (self.path.contours.items.len != 0 or self.pending_clip != null) return error.UnpaintedPath;
    }
    fn paintFreeText(self: *Renderer, text: @import("free_text.zig").Text) !void {
        try form(self, true, text.rect, .{});
        if (text.callout) |callout| try self.paintShape(callout);
        self.opacity = text.border.opacity;
        if (text.background) |color| {
            const b = text.box;
            try polygon(&self.path, self.allocator, &.{ point(self.view, b[0], b[1]), point(self.view, b[2], b[1]), point(self.view, b[2], b[3]), point(self.view, b[0], b[3]) });
            try self.fill(&self.path, color, false);
            self.path.clear();
        }
        try self.paintShape(text.border);
        const w = text.border.width;
        const clip = [4]f64{ text.box[0] + w, text.box[1] + w, text.box[2] - w, text.box[3] - w };
        if (clip[2] > clip[0] and clip[3] > clip[1]) {
            try form(self, true, clip, .{});
            try self.beginGroup();
            const state = c.State{ .font = text.font, .fill = .{ .rgb = text.color }, .char = text.spacing.character, .word = text.spacing.word };
            for (text.lines, 0..) |line, i| {
                const matrix = text.lineMatrix(i);
                var advance: f64 = 0;
                var at: usize = 0;
                try glyphRun(self, true, state);
                while (try text.font.nextCode(line.text, &at)) |code| {
                    try glyph(self, code, c.multiply(.{ text.size * (text.horizontal_scale / 100), 0, 0, text.size, advance, 0 }, matrix), state);
                    advance += (text.font.width(code) * text.size / 1000 + text.spacing.extra(text.font, code)) * (text.horizontal_scale / 100);
                }
                try glyphRun(self, false, state);
            }
            self.group = 0;
            try form(self, false, clip, .{});
        }
        try form(self, false, text.rect, .{});
    }
    fn paintShape(self: *Renderer, shape: @import("shape_appearance.zig").Shape) !void {
        var drawing = try shape.drawing(self.allocator);
        defer drawing.deinit(self.allocator);
        defer self.path.clear();
        self.opacity = shape.opacity;
        self.blend_mode = .normal;
        defer self.group = 0;
        for (drawing.layers.items) |layer| {
            for (drawing.commands.items[layer.start..layer.end]) |command| switch (command) {
                .move => |p| try self.path.begin(self.allocator, point(self.view, p[0], p[1])),
                .line => |p| try self.path.add(self.allocator, point(self.view, p[0], p[1])),
                .curve => |p| try cubic(&self.path, self.allocator, try self.path.current(), point(self.view, p[0], p[1]), point(self.view, p[2], p[3]), point(self.view, p[4], p[5]), 0),
                .close => try self.path.close(),
            };
            self.paint = .{ .width = shape.width, .dash = shape.pattern };
            try self.beginGroup();
            if (layer.fill) if (shape.fill) |rgb| {
                var color: Color = undefined;
                for (&color, rgb) |*channel, value| channel.* = @intFromFloat(@round(value * 255));
                try self.fill(&self.path, color, false);
            };
            if (shape.stroke) |rgb| if (shape.width > 0) {
                for (&self.paint.stroke, rgb) |*channel, value| channel.* = @intFromFloat(@round(value * 255));
                try self.stroke(self.view, null);
            };
            self.path.clear();
        }
        if (shape.captionLayout()) |placement| try self.paintCaption(shape.caption.?, placement);
    }

    fn paintCaption(self: *Renderer, caption: @import("line_caption.zig").Caption, placement: @import("line_caption.zig").Layout) !void {
        try self.beginGroup();
        defer self.group = 0;
        for (caption.lines, 0..) |line, i| {
            const matrix = caption.lineMatrix(placement, i);
            var advance: f64 = 0;
            for (line.text) |byte| {
                const code = pdf_font.Code{ .value = byte, .length = 1 };
                const size = @import("line_caption.zig").size;
                const transform = c.multiply(.{ size, 0, 0, size, advance, 0 }, matrix);
                try glyph(self, code, transform, .{ .font = caption.font });
                advance += caption.font.width(code) * size / 1000;
            }
        }
    }
    fn paintCommentIcon(self: *Renderer, rect: [4]f64, icon: @import("comment_icon.zig").Icon) !void {
        if (rect[2] <= rect[0] or rect[3] <= rect[1]) return;
        const transform = c.multiply(.{ (rect[2] - rect[0]) / 24, 0, 0, (rect[3] - rect[1]) / 24, rect[0], rect[1] }, self.view);
        var color: Color = undefined;
        for (&color, icon.color) |*channel, value| channel.* = @intFromFloat(@round(value * 255));
        const luminance = icon.color[0] * 0.3 + icon.color[1] * 0.59 + icon.color[2] * 0.11;
        const ink: Color = if (luminance < 0.3) .{ 255, 255, 255 } else .{ 20, 20, 20 };
        self.opacity = icon.opacity;
        self.blend_mode = .normal;
        // Knock out overlapping details against one backdrop so /CA is applied once.
        try self.beginGroup();
        defer self.group = 0;
        for (@import("comment_icon.zig").layers(icon.kind)) |layer| {
            for (layer.path) |command| switch (command) {
                .move => |p| try self.path.begin(self.allocator, point(transform, p[0], p[1])),
                .line => |p| try self.path.add(self.allocator, point(transform, p[0], p[1])),
                .curve => |p| try cubic(&self.path, self.allocator, try self.path.current(), point(transform, p[0], p[1]), point(transform, p[2], p[3]), point(transform, p[4], p[5]), 0),
                .close => try self.path.close(),
            };
            const paint = if (layer.dark) ink else color;
            if (layer.stroke > 0) {
                self.paint = .{ .stroke = paint, .width = layer.stroke, .cap = 1, .join = 1 };
                try self.stroke(transform, null);
            } else try self.fill(&self.path, paint, layer.even_odd);
            self.path.clear();
        }
    }
    fn beginGroup(self: *Renderer) !void {
        if (self.next_group == std.math.maxInt(u32)) return error.SceneLimit;
        self.next_group += 1;
        self.group = self.next_group;
    }
    fn sink(self: *Renderer) c.Sink {
        return .{ .context = self, .operator = operator, .glyph = glyph, .form = form, .image = image };
    }
    fn image(ctx: *anyopaque, source: images.Image, state: c.State) anyerror!void {
        const self: *Renderer = @ptrCast(@alignCast(ctx));
        const m = c.multiply(state.ctm, self.view);
        const det = m[0] * m[3] - m[1] * m[2];
        if (det == 0) return;
        const inverse: c.Matrix = .{ m[3] / det, -m[1] / det, -m[2] / det, m[0] / det, (m[2] * m[5] - m[3] * m[4]) / det, (m[1] * m[4] - m[0] * m[5]) / det };
        for (inverse) |n| if (!std.math.isFinite(n) or @abs(n) > 1e12) return error.InvalidTransform;
        var path = Path{};
        defer path.points.deinit(self.allocator);
        defer path.contours.deinit(self.allocator);
        var box = [4]f64{ 0, 0, 1, 1 };
        if (self.collector) |collector| if (collector.geometry_only) {
            box = (try source.visibleBox()) orelse return;
        };
        try polygon(&path, self.allocator, &.{ point(m, box[0], box[1]), point(m, box[2], box[1]), point(m, box[2], box[3]), point(m, box[0], box[3]) });
        self.alpha = state.fill_alpha;
        self.blend_mode = state.blend_mode;
        self.texture = .{ .image = source, .inverse = inverse, .tint = state.fill.rgb };
        defer self.texture = null;
        try self.fill(&path, state.fill.rgb, false);
    }
    fn form(ctx: *anyopaque, begin: bool, bbox: [4]f64, state: c.State) anyerror!void {
        const self: *Renderer = @ptrCast(@alignCast(ctx));
        if (self.path.contours.items.len != 0 or self.pending_clip != null) return error.UnpaintedPath;
        if (begin) {
            try self.stack.append(self.allocator, .{ .paint = self.paint, .clip = self.clip });
            const m = c.multiply(state.ctm, self.view);
            try self.path.begin(self.allocator, point(m, bbox[0], bbox[1]));
            try self.path.add(self.allocator, point(m, bbox[2], bbox[1]));
            try self.path.add(self.allocator, point(m, bbox[2], bbox[3]));
            try self.path.add(self.allocator, point(m, bbox[0], bbox[3]));
            try self.path.close();
            self.pending_clip = false;
            try self.endPath();
        } else {
            const saved = self.stack.pop() orelse return error.GraphicsStackUnderflow;
            self.paint = saved.paint;
            self.clip = saved.clip;
        }
    }
    fn endPath(self: *Renderer) !void {
        if (self.pending_clip) |even| {
            const edges = try self.path.edges(self.allocator);
            var next = clipping.Region{ .edges = edges, .even = even };
            if (self.clip) |old| {
                next = .{ .edges = try clipping.intersect(self.allocator, old, next) };
                self.allocator.free(edges);
            }
            // Saved clips are immutable and live for the render arena's lifetime.
            if (next.edges.len > 1024 * 1024 -| self.clip_edges) return error.ClippingLimit;
            self.clip_edges += next.edges.len;
            self.clip = next;
            self.pending_clip = null;
        }
        self.path.clear();
    }
    fn operator(ctx: *anyopaque, op: []const u8, values: []s.Value, state: c.State) anyerror!void {
        const self: *Renderer = @ptrCast(@alignCast(ctx));
        var ns: [6]f64 = @splat(0);
        for (values[0..@min(values.len, 6)], 0..) |v, i| {
            if (v == .integer or v == .real) ns[i] = try s.number(v);
            if (!std.math.isFinite(ns[i]) or @abs(ns[i]) > 1e12) return error.InvalidNumber;
        }
        if (eq(op, "cm") and self.path.contours.items.len != 0) return error.InvalidPath;
        self.paint.fill = state.fill.rgb;
        self.paint.stroke = state.stroke.rgb;
        self.paint.width = state.width;
        self.paint.cap = state.cap;
        self.paint.join = state.join;
        self.paint.miter = state.miter;
        self.paint.dash = state.dash;
        self.alpha = state.fill_alpha;
        self.blend_mode = state.blend_mode;
        const m = c.multiply(state.ctm, self.view);
        if (eq(op, "q")) {
            try self.stack.append(self.allocator, .{ .paint = self.paint, .clip = self.clip });
        } else if (eq(op, "Q")) {
            const saved = self.stack.pop() orelse return error.GraphicsStackUnderflow;
            self.paint = saved.paint;
            self.clip = saved.clip;
        } else if (eq(op, "Tr")) {
            if (ns[0] != 0 and ns[0] != 3) return error.UnsupportedTextRendering;
        } else if (eq(op, "BT")) {
            if (state.text_knockout) try self.beginGroup();
        } else if (eq(op, "ET")) {
            self.group = 0;
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
        } else if (eq(op, "W") or eq(op, "W*")) {
            self.pending_clip = eq(op, "W*");
        } else if (eq(op, "n")) {
            try self.endPath();
        } else if (eq(op, "f") or eq(op, "F") or eq(op, "f*")) {
            try self.fill(&self.path, self.paint.fill, eq(op, "f*"));
            try self.endPath();
        } else if (eq(op, "S") or eq(op, "s") or eq(op, "B") or eq(op, "B*") or eq(op, "b") or eq(op, "b*")) {
            if (op[0] == 's' or op[0] == 'b') try self.path.close();
            if (op[0] == 'B' or op[0] == 'b') {
                try self.beginGroup();
                try self.fill(&self.path, self.paint.fill, op.len == 2);
            }
            self.alpha = state.stroke_alpha;
            try self.stroke(m, null);
            self.group = 0;
            try self.endPath();
        }
    }
    fn glyphRun(ctx: *anyopaque, begin: bool, state: c.State) anyerror!void {
        const self: *Renderer = @ptrCast(@alignCast(ctx));
        if (begin) {
            self.combine_glyphs = self.clip != null and state.text_knockout and (state.char < 0 or state.word < 0);
            self.glyph_edges.clearRetainingCapacity();
        } else if (self.combine_glyphs) {
            self.combine_glyphs = false;
            try self.paintEdges(self.glyph_edges.items, state.fill.rgb, false);
        }
    }
    fn glyph(ctx: *anyopaque, char: pdf_font.Code, transform: c.Matrix, state: c.State) anyerror!void {
        const self: *Renderer = @ptrCast(@alignCast(ctx));
        if (state.mode == 3 or (self.bitmap == null and self.collector == null)) return;
        if (state.mode != 0) return error.UnsupportedTextRendering;
        var font: f.Font = undefined;
        var glyph_id: u16 = undefined;
        if (state.font.?.composite) |composite| {
            font = composite.program;
            glyph_id = try composite.glyph(char);
        } else if (state.font.?.embedded) |*embedded| {
            font = embedded.program;
            glyph_id = embedded.ids[char.value];
            if (glyph_id == 0) return error.MissingGlyph;
        } else {
            const face = state.font.?.face;
            const index = @backingInt(face);
            if (self.fonts[index] == null) {
                for (self.font_sources) |source| {
                    if (source.face == face) {
                        self.fonts[index] = try f.Font.init(source.bytes);
                        break;
                    }
                }
            }
            font = self.fonts[index] orelse return error.MissingRenderFont;
            const codepoint: u16 = @intCast(try state.font.?.glyphUnicode(@intCast(char.value)));
            glyph_id = font.glyph(codepoint) catch |err| blk: {
                if (face != .symbol or err != error.MissingGlyph) return err;
                // Apple's Symbol cmap uses these alternate Unicode assignments.
                // Extraction keeps Adobe's canonical mapping; only outline lookup differs.
                const alternate: u16 = switch (codepoint) {
                    0x220b => 0x220d,
                    0x2206 => 0x0394,
                    0x2126 => 0x03a9,
                    0x00b5 => 0x03bc,
                    0xf6da => 0xf8e8,
                    0xf6d9 => 0xf8e9,
                    0xf6db => 0xf8ea,
                    0x2329 => 0x3008,
                    0x232a => 0x3009,
                    else => return err,
                };
                break :blk try font.glyph(alternate);
            };
        }
        self.outline.points.clearRetainingCapacity();
        self.outline.ends.clearRetainingCapacity();
        try font.outline(self.allocator, glyph_id, &self.outline);
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
        self.alpha = state.fill_alpha;
        self.blend_mode = state.blend_mode;
        try self.fill(&self.glyph_path, state.fill.rgb, false);
    }
    fn stroke(self: *Renderer, m: c.Matrix, clip: ?[4]f64) !void {
        var dashed: Path = .{};
        defer {
            dashed.points.deinit(self.allocator);
            dashed.contours.deinit(self.allocator);
        }
        const source = if (self.paint.dash.count != 0) blk: {
            try dashPath(&dashed, self.allocator, &self.path, &self.paint.dash, m);
            break :blk &dashed;
        } else &self.path;
        const sx = @sqrt(m[0] * m[0] + m[1] * m[1]);
        const sy = @sqrt(m[2] * m[2] + m[3] * m[3]);
        const affine = self.paint.width != 0 and (@abs(sx - sy) > 1e-6 * @max(1, sx) or @abs(m[0] * m[2] + m[1] * m[3]) > 1e-6 * @max(1, sx * sy));
        var stroke_points = source.points.items;
        var stroke_matrix: c.Matrix = .{ 1, 0, 0, 1, 0, 0 };
        var stroke_inverse: c.Matrix = .{ 1, 0, 0, 1, 0, 0 };
        var scale = sx;
        if (affine) {
            // Expand in isotropic stroke space, then transform the outline. Normalize
            // by a device-space scale bound so round-join tessellation stays accurate.
            scale = @sqrt(sx * sx + sy * sy);
            if (scale == 0) return error.InvalidTransform;
            stroke_matrix = .{ m[0] / scale, m[1] / scale, m[2] / scale, m[3] / scale, m[4], m[5] };
            const det = stroke_matrix[0] * stroke_matrix[3] - stroke_matrix[1] * stroke_matrix[2];
            if (@abs(det) < 1e-12) return error.InvalidTransform;
            const inverse: c.Matrix = .{ stroke_matrix[3] / det, -stroke_matrix[1] / det, -stroke_matrix[2] / det, stroke_matrix[0] / det, 0, 0 };
            stroke_inverse = inverse;
            stroke_points = try self.allocator.alloc(P, source.points.items.len);
            errdefer self.allocator.free(stroke_points);
            for (stroke_points, source.points.items) |*out, p| {
                out.* = point(inverse, p.x - m[4], p.y - m[5]);
                if (!std.math.isFinite(out.x) or !std.math.isFinite(out.y) or @abs(out.x) > 1e9 or @abs(out.y) > 1e9) return error.InvalidTransform;
            }
        }
        defer if (affine) self.allocator.free(stroke_points);
        if (self.paint.width == 0) {
            if (self.collector) |collector| collector.hairlines.* = true;
        }
        const radius = if (self.paint.width == 0) @as(f64, 0.5) else self.paint.width * scale / 2;
        if (radius == 0) return;
        var outline: Path = .{ .point_limit = 2_000_000, .contour_limit = 262144 };
        defer {
            outline.points.deinit(self.allocator);
            outline.contours.deinit(self.allocator);
        }
        for (source.contours.items, 0..) |contour, ci| {
            const end = if (ci + 1 < source.contours.items.len) source.contours.items[ci + 1].start else source.points.items.len;
            var pts = stroke_points[contour.start..end];
            if (pts.len < 2) continue;
            if (self.paint.cap == 2) if (contour.dot_direction) |direction| {
                const tangent = point(stroke_inverse, direction.x, direction.y);
                const distance = len(.{ .x = 0, .y = 0 }, tangent);
                if (distance != 0) {
                    const u = P{ .x = tangent.x * radius / distance, .y = tangent.y * radius / distance };
                    const v = P{ .x = -u.y, .y = u.x };
                    const center = pts[0];
                    try polygon(&outline, self.allocator, &.{
                        .{ .x = center.x - u.x + v.x, .y = center.y - u.y + v.y },
                        .{ .x = center.x + u.x + v.x, .y = center.y + u.y + v.y },
                        .{ .x = center.x + u.x - v.x, .y = center.y + u.y - v.y },
                        .{ .x = center.x - u.x - v.x, .y = center.y - u.y - v.y },
                    });
                }
                continue;
            };
            var used: usize = 1;
            for (pts[1..]) |p| {
                if (len(p, pts[used - 1]) > 1e-10) {
                    pts[used] = p;
                    used += 1;
                }
            }
            // A curve often ends at its starting point before h. The redundant
            // closing segment must not suppress the join between its neighbors.
            if (contour.closed and used > 1 and len(pts[0], pts[used - 1]) < 1e-10) used -= 1;
            pts = pts[0..used];
            if (!contour.closed and self.paint.cap == 1) {
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
                const square = self.paint.cap == 2 and !contour.closed;
                const cap_start = if (square and i == 0) P{ .x = a.x - n.y, .y = a.y + n.x } else a;
                const finish = if (square and i + 1 == segments) P{ .x = b.x + n.y, .y = b.y - n.x } else b;
                try polygon(&outline, self.allocator, &.{ .{ .x = cap_start.x + n.x, .y = cap_start.y + n.y }, .{ .x = finish.x + n.x, .y = finish.y + n.y }, .{ .x = finish.x - n.x, .y = finish.y - n.y }, .{ .x = cap_start.x - n.x, .y = cap_start.y - n.y } });
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
                    if (tip.x == b.x and tip.y == b.y) {
                        if (cross > 0) try polygon(&outline, self.allocator, &.{ p, b, q }) else try polygon(&outline, self.allocator, &.{ q, b, p });
                    } else if (cross > 0) try polygon(&outline, self.allocator, &.{ p, b, q, tip }) else try polygon(&outline, self.allocator, &.{ q, b, p, tip });
                }
            }
        }
        if (affine) for (outline.points.items) |*p| {
            p.* = point(stroke_matrix, p.x, p.y);
            if (!std.math.isFinite(p.x) or !std.math.isFinite(p.y) or @abs(p.x) > 1e9 or @abs(p.y) > 1e9) return error.InvalidTransform;
        };
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
        const source = try path.edges(self.allocator);
        defer self.allocator.free(source);
        const edges = if (self.clip) |clip| try clipping.intersect(self.allocator, .{ .edges = source, .even = even }, clip) else source;
        defer if (self.clip != null) self.allocator.free(edges);
        const rule = if (self.clip != null) false else even;
        if (self.combine_glyphs) {
            // Intersection emits consistently wound interiors. Their nonzero union
            // lets adjacent/overlapping glyph edges share subpixel coverage.
            if (edges.len > 65536 -| self.glyph_edges.items.len) return error.SceneLimit;
            try self.glyph_edges.appendSlice(self.allocator, edges);
            return;
        }
        try self.paintEdges(edges, color, rule);
    }
    fn paintEdges(self: *Renderer, edges: []const Edge, color: Color, rule: bool) !void {
        if (edges.len == 0) return;
        var miny: f64 = std.math.inf(f64);
        var maxy: f64 = -std.math.inf(f64);
        for (edges) |edge| {
            miny = @min(miny, @min(edge.a.y, edge.b.y));
            maxy = @max(maxy, @max(edge.a.y, edge.b.y));
        }
        if (self.collector) |collector| {
            if (self.texture) |texture| if (!collector.geometry_only) {
                const callback = collector.image orelse return error.UnsupportedImageCollection;
                const image_data = texture.image;
                const pixels = try self.allocator.alloc(u8, image_data.width * image_data.height * 4);
                defer self.allocator.free(pixels);
                for (0..image_data.height) |y| for (0..image_data.width) |x| {
                    const texel = try image_data.texel(x, y, texture.tint);
                    const at = (y * image_data.width + x) * 4;
                    for (0..3) |i| pixels[at + i] = @intFromFloat(@round(texel[i]));
                    pixels[at + 3] = @intFromFloat(@round(texel[3] * 255));
                };
                var payload = ImagePaint{ .pixels = pixels.ptr, .width = @intCast(image_data.width), .height = @intCast(image_data.height), .inverse = texture.inverse, .interpolate = image_data.interpolate };
                var mask_samples: []f32 = &.{};
                defer self.allocator.free(mask_samples);
                if (image_data.alpha_image) |mask| {
                    mask_samples = try self.allocator.alloc(f32, mask.width * mask.height);
                    for (0..mask.height) |y| for (0..mask.width) |x| {
                        mask_samples[y * mask.width + x] = @floatCast((try mask.texel(x, y, .{ 0, 0, 0 }))[3]);
                    };
                    payload.mask_alpha = mask_samples.ptr;
                    payload.mask_width = @intCast(mask.width);
                    payload.mask_height = @intCast(mask.height);
                    payload.mask_interpolate = mask.interpolate;
                }
                if (!callback(collector.context, edges.ptr, edges.len, &payload, self.opacity * self.alpha, @backingInt(self.blend_mode), self.group)) return error.SceneLimit;
                return;
            };
            const rgb = (@as(u32, color[0]) << 16) | (@as(u32, color[1]) << 8) | color[2];
            if (!collector.paint(collector.context, edges.ptr, edges.len, rgb, self.opacity * self.alpha, rule, @backingInt(self.blend_mode), self.group)) return error.SceneLimit;
            return;
        }
        const bitmap = self.bitmap.?;
        if (self.group != 0 and self.backdrop_rows.len == 0) {
            self.backdrop_rows = try self.allocator.alloc(?[]Backdrop, bitmap.height);
            @memset(self.backdrop_rows, null);
        }
        const y0: usize = @intFromFloat(std.math.clamp(@floor(miny), 0, @as(f64, @floatFromInt(bitmap.height))));
        const y1: usize = @intFromFloat(std.math.clamp(@ceil(maxy), 0, @as(f64, @floatFromInt(bitmap.height))));
        if (y0 >= y1) return;
        const Hit = struct { x: f64, w: i32 };
        const hits = try self.allocator.alloc(Hit, edges.len);
        defer self.allocator.free(hits);
        const coverage = try self.allocator.alloc(u8, bitmap.width);
        defer self.allocator.free(coverage);
        for (y0..y1) |y| {
            @memset(coverage, 0);
            var left: usize = bitmap.width;
            var right: usize = 0;
            for (0..4) |sample| {
                const sy = @as(f64, @floatFromInt(y)) + (@as(f64, @floatFromInt(sample)) + 0.5) / 4;
                var n: usize = 0;
                for (edges) |edge| {
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
                    if (if (rule) @mod(winding, 2) != 0 else winding != 0) {
                        const begin = scanlineSampleBoundary(previous, bitmap.width);
                        const end = scanlineSampleBoundary(hit.x, bitmap.width);
                        if (end > begin) {
                            left = @min(left, begin / 4);
                            right = @max(right, (end + 3) / 4);
                            addScanlineCoverage(coverage, begin, end);
                        }
                    }
                    winding += hit.w;
                    previous = hit.x;
                }
            }
            if (right <= left) continue;
            if (self.group != 0 and self.backdrop_rows[y] == null) {
                const row = try self.allocator.alloc(Backdrop, bitmap.width);
                @memset(row, .{});
                self.backdrop_rows[y] = row;
            }
            for (coverage[left..right], left..) |alpha, x| {
                if (alpha == 0) continue;
                const at = (y * bitmap.width + x) * 4;
                var backdrop: Color = bitmap.pixels[at..][0..3].*;
                if (self.group != 0) {
                    const stored = &self.backdrop_rows[y].?[x];
                    if (stored.group != self.group) stored.* = .{ .group = self.group, .color = backdrop };
                    backdrop = stored.color;
                }
                const coverage_alpha = @as(f64, @floatFromInt(alpha)) / 16;
                var ink_color = color;
                var sample_alpha: f64 = 1;
                if (self.texture) |texture| {
                    const uv = point(texture.inverse, @as(f64, @floatFromInt(x)) + 0.5, @as(f64, @floatFromInt(y)) + 0.5);
                    const sample = try texture.image.sample(uv.x, uv.y, texture.tint);
                    for (&ink_color, sample[0..3]) |*channel, value| channel.* = @intFromFloat(@round(std.math.clamp(value, 0, 255)));
                    sample_alpha = sample[3];
                }
                const opacity = self.opacity * self.alpha * sample_alpha;
                var background_rgb: [3]f64 = undefined;
                var source_rgb: [3]f64 = undefined;
                for (ink_color, backdrop, 0..) |v, b, i| {
                    background_rgb[i] = @as(f64, @floatFromInt(b)) / 255;
                    source_rgb[i] = @as(f64, @floatFromInt(v)) / 255;
                }
                const blended = blend.apply(self.blend_mode, background_rgb, source_rgb);
                for (blended, 0..) |v, i| {
                    const current: f64 = @floatFromInt(bitmap.pixels[at + i]);
                    const background: f64 = @floatFromInt(backdrop[i]);
                    const ink = v * 255;
                    const composite = ink * opacity + background * (1 - opacity);
                    bitmap.pixels[at + i] = @intFromFloat(@round(composite * coverage_alpha + current * (1 - coverage_alpha)));
                }
            }
        }
    }
};

test "overlapping spaced glyphs cover complementary samples against one backdrop" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var pixels: [4]u8 = @splat(255);
    var renderer = Renderer{ .allocator = arena.allocator(), .bitmap = .{ .width = 1, .height = 1, .pixels = &pixels }, .opacity = 0.5 };
    try Renderer.form(&renderer, true, .{ 0, 0, 1, 1 }, .{});
    try renderer.beginGroup();
    const state = c.State{ .word = -30, .fill = .{ .rgb = .{ 0, 0, 0 } } };
    try Renderer.glyphRun(&renderer, true, state);
    // Opposite winding, with neither outline alone covering the entire pixel.
    for ([_][2]f64{ .{ 0, 0.65 }, .{ 1, 0.35 } }) |range| {
        renderer.glyph_path.clear();
        try polygon(&renderer.glyph_path, renderer.allocator, &.{ .{ .x = range[0], .y = 0 }, .{ .x = range[1], .y = 0 }, .{ .x = range[1], .y = 1 }, .{ .x = range[0], .y = 1 } });
        try renderer.fill(&renderer.glyph_path, state.fill.rgb, false);
    }
    try Renderer.glyphRun(&renderer, false, state);
    try std.testing.expectEqualSlices(u8, &.{ 128, 128, 128, 255 }, &pixels);
}

// Four horizontal samples per pixel. Only the two ends of a span can
// contribute fewer than four samples on this scanline.
fn scanlineSampleBoundary(x: f64, width: u32) usize {
    const sample = x * 4 - 0.5;
    const nearest = @round(sample);
    // Transform/intersection roundoff must not flip samples exactly on an edge.
    const tolerance = 8 * std.math.floatEps(f64) * @max(1, @abs(sample));
    const stable = if (@abs(sample - nearest) <= tolerance) nearest else sample;
    return @intFromFloat(std.math.clamp(@ceil(stable), 0, @as(f64, @floatFromInt(width)) * 4));
}

fn addScanlineCoverage(coverage: []u8, begin: usize, end: usize) void {
    const first_full = (begin + 3) / 4;
    const past_full = end / 4;
    if (first_full >= past_full) {
        for (begin..end) |x| coverage[x / 4] += 1;
        return;
    }
    for (begin..first_full * 4) |x| coverage[x / 4] += 1;
    for (coverage[first_full..past_full]) |*value| value.* += 4;
    for (past_full * 4..end) |x| coverage[x / 4] += 1;
}
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
        .{ "3 J", error.UnsupportedStroke },
        .{ "2 0 0 0 0 0 cm 1 1 m 10 10 l S", error.InvalidTransform },
        .{ "0 0 m", error.UnpaintedPath },
    };
    inline for (cases) |case| {
        var doc = try d.Document.open(a, bytes);
        defer doc.deinit();
        (try doc.object(.{ .id = 5, .generation = 0 })).changed = case[0];
        try std.testing.expectError(case[1], validate(&doc));
    }
}
test "diagonal sample boundaries ignore transform roundoff but retain real offsets" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const pixels = try a.alloc(u8, 160 * 160 * 4);
    var renderer = Renderer{ .allocator = a, .bitmap = .{ .width = 160, .height = 160, .pixels = pixels } };
    for ([_]f64{ 0, 3e-14, -3e-14, 1e-9, -1e-9 }) |offset| {
        for ([_]bool{ false, true }) |reverse| {
            for ([_]bool{ false, true }) |even| {
                @memset(pixels, 255);
                var path: Path = .{};
                const tip = 150 + offset;
                const points = [_]P{ .{ .x = 0, .y = 0 }, .{ .x = tip, .y = 0 }, .{ .x = 0, .y = tip } };
                if (reverse) try polygon(&path, a, &.{ points[2], points[1], points[0] }) else try polygon(&path, a, &points);
                try renderer.fill(&path, .{ 0, 0, 0 }, even);
                // Six samples lie inside x+y<150; a real positive offset includes four more.
                const expected: u8 = if (offset == 1e-9) 96 else 159;
                try std.testing.expectEqual(expected, pixels[(52 * 160 + 97) * 4]);
            }
        }
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
test "closed strokes join across an explicitly repeated first point" {
    const a = std.testing.allocator;
    const bytes = try pod.create(a, "");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    const stream = try doc.object(.{ .id = 5, .generation = 0 });
    for ([_]u8{ 0, 1, 2 }) |join| {
        for ([_][]const u8{ "[] 0 d", "[9 4] 0 d" }) |pattern| {
            var expected: ?Bitmap = null;
            defer if (expected) |bitmap| a.free(bitmap.pixels);
            for ([_][]const u8{ "", "100 100 l" }) |closing_line| {
                const program = try std.fmt.allocPrint(doc.allocator(), "12 w {d} j {s} 100 100 m 200 100 l 200 200 l 100 200 l {s} h S", .{ join, pattern, closing_line });
                try doc.replaceStream(stream, program);
                const bitmap = try renderWithFonts(a, &doc, 0, &.{}, 306);
                if (expected) |before| {
                    defer a.free(bitmap.pixels);
                    try std.testing.expectEqualSlices(u8, before.pixels, bitmap.pixels);
                } else expected = bitmap;
            }
        }
    }
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

test "content fit bounds exclude annotations and intersect the visible page" {
    const a = std.testing.allocator;
    const bytes = try pod.create(a, "");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    (try doc.object(.{ .id = 5, .generation = 0 })).changed = "0 g 50 70 100 30 re f";
    _ = try annotations.add(&doc, 0, .rectangle, &.{ .{ .x = 300, .y = 400 }, .{ .x = 500, .y = 600 } }, "", .{});
    try std.testing.expectEqual([4]f64{ 50, 70, 150, 100 }, (try contentBounds(a, &doc, 0, &.{})).?);
    var crop_parser = s.Parser{ .allocator = doc.allocator(), .bytes = "[75 80 145 95]" };
    (try doc.inspect())[0].crop_box = try crop_parser.value();
    try std.testing.expectEqual([4]f64{ 75, 80, 145, 95 }, (try contentBounds(a, &doc, 0, &.{})).?);
}

test "square caps extend only open path ends and follow rotation" {
    const a = std.testing.allocator;
    const bytes = try pod.create(a, "test");
    defer a.free(bytes);
    var doc1 = try d.Document.open(a, bytes);
    defer doc1.deinit();
    var doc2 = try d.Document.open(a, bytes);
    defer doc2.deinit();
    (try doc1.object(.{ .id = 5, .generation = 0 })).changed = "q 0 1 -1 0 400 50 cm 2 J 10 w 100 100 m 100 100 l 200 100 l 200 100 l S Q 10 w 100 200 m 200 200 l S 2 J 100 300 100 50 re S";
    (try doc2.object(.{ .id = 5, .generation = 0 })).changed = "q 0 1 -1 0 400 50 cm 95 95 110 10 re f Q 100 195 100 10 re f 0 J 10 w 100 300 100 50 re S";
    const one = try render(a, &doc1, 0, &.{}, 612);
    defer a.free(one.pixels);
    const two = try render(a, &doc2, 0, &.{}, 612);
    defer a.free(two.pixels);
    try std.testing.expectEqualSlices(u8, one.pixels, two.pixels);
}

test "path clipping uses both fill rules, deferred application and graphics state" {
    const a = std.testing.allocator;
    const bytes = try pod.create(a, "clip");
    defer a.free(bytes);
    const Case = struct { stream: []const u8, inside: [2]usize, outside: [2]usize };
    const cases = [_]Case{
        .{ .stream = "100 100 200 200 re W n 0 0 612 792 re f", .inside = .{ 150, 150 }, .outside = .{ 50, 150 } },
        .{ .stream = "100 100 200 200 re 150 150 100 100 re W* n 0 0 612 792 re f", .inside = .{ 125, 125 }, .outside = .{ 200, 200 } },
        .{ .stream = "100 100 200 200 re 150 150 100 100 re W n 0 0 612 792 re f", .inside = .{ 200, 200 }, .outside = .{ 50, 150 } },
        .{ .stream = "100 100 200 200 re 150 250 100 -100 re W n 0 0 612 792 re f", .inside = .{ 125, 125 }, .outside = .{ 200, 200 } },
        .{ .stream = "100 100 200 200 re W n q 150 150 20 20 re W n Q 0 0 612 792 re f", .inside = .{ 200, 200 }, .outside = .{ 50, 150 } },
        .{ .stream = "100 100 200 200 re W n 150 150 20 20 re W n 0 0 612 792 re f", .inside = .{ 160, 160 }, .outside = .{ 200, 200 } },
        .{ .stream = "20 w 100 100 200 200 re W S", .inside = .{ 95, 150 }, .outside = .{ 200, 200 } },
        .{ .stream = "q 0 0 0 0 re W n 0 0 612 792 re f Q 100 100 20 20 re f", .inside = .{ 110, 110 }, .outside = .{ 200, 200 } },
        .{ .stream = "q 1 0.5 0 1 100 100 cm 0 0 100 100 re W n 0 0 612 792 re f Q", .inside = .{ 150, 175 }, .outside = .{ 150, 110 } },
    };
    for (cases) |case| {
        var doc = try pod.Document.open(a, bytes);
        defer doc.deinit();
        (try doc.object(.{ .id = 5, .generation = 0 })).changed = case.stream;
        try validate(&doc);
        const saved = try doc.save(a);
        defer a.free(saved);
        var reopened = try pod.Document.open(a, saved);
        defer reopened.deinit();
        const bitmap = try render(a, &reopened, 0, &.{}, 612);
        defer a.free(bitmap.pixels);
        for ([_][2]usize{ case.inside, case.outside }, [_]u8{ 0, 255 }) |p, expected| {
            const at = ((791 - p[1]) * 612 + p[0]) * 4;
            try std.testing.expectEqualSlices(u8, &.{ expected, expected, expected, 255 }, bitmap.pixels[at..][0..4]);
        }
    }
    var doc = try pod.Document.open(a, bytes);
    defer doc.deinit();
    const object = try doc.object(.{ .id = 5, .generation = 0 });
    object.changed = "100 100 200 200 re W n 0 0 612 792 re f";
    try std.testing.expectEqualSlices(f64, &.{ 100, 100, 300, 300 }, &(try contentBounds(a, &doc, 0, &.{})).?);
    object.changed = "W n 0 0 612 792 re f";
    try std.testing.expectEqual(null, try contentBounds(a, &doc, 0, &.{}));
    object.changed = "W";
    try std.testing.expectError(error.UnpaintedPath, validate(&doc));
    object.changed = "1 W n";
    try std.testing.expectError(error.InvalidOperands, validate(&doc));
}

test "path clipping masks glyph outlines without moving text runs" {
    if (@import("builtin").os.tag != .macos) return error.SkipZigTest;
    const a = std.testing.allocator;
    const font = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "/System/Library/Fonts/Supplemental/Courier New.ttf", a, .limited(8 * 1024 * 1024));
    defer a.free(font);
    const bytes = try pod.create(a, "clip text");
    defer a.free(bytes);
    var doc = try pod.Document.open(a, bytes);
    defer doc.deinit();
    const text = "BT /F1 70 Tf 1 0 0 1 100 300 Tm (OOOO) Tj ET";
    const object = try doc.object(.{ .id = 5, .generation = 0 });
    object.changed = text;
    const original = try render(a, &doc, 0, font, 612);
    defer a.free(original.pixels);
    object.changed = "130 310 80 30 re W n " ++ text;
    const clipped = try render(a, &doc, 0, font, 612);
    defer a.free(clipped.pixels);
    const pages = try doc.inspect();
    try std.testing.expectEqualStrings("OOOO", pages[0].runs[0].text);
    try std.testing.expectEqual(@as(f64, 100), pages[0].runs[0].x);
    var kept: usize = 0;
    var removed: usize = 0;
    for (0..792) |y| for (0..612) |x| {
        const at = (y * 612 + x) * 4;
        if (x >= 130 and x < 210 and y >= 452 and y < 482) {
            try std.testing.expectEqualSlices(u8, original.pixels[at..][0..4], clipped.pixels[at..][0..4]);
            if (clipped.pixels[at] < 255) kept += 1;
        } else {
            try std.testing.expectEqualSlices(u8, &.{ 255, 255, 255, 255 }, clipped.pixels[at..][0..4]);
            if (original.pixels[at] < 255) removed += 1;
        }
    };
    try std.testing.expect(kept > 100 and removed > 100);
}

test "named color spaces and saved fill stroke selections reach the rasterizer" {
    const a = std.testing.allocator;
    const bytes = try pod.create(a, "colors");
    defer a.free(bytes);
    var doc = try pod.Document.open(a, bytes);
    defer doc.deinit();
    (try doc.object(.{ .id = 5, .generation = 0 })).changed =
        "/DeviceRGB cs 1 0 0 sc 0 0 612 792 re f " ++
        "q /DeviceGray cs 0.5 scn 0 0 200 200 re f Q " ++
        "200 0 200 200 re f /DeviceRGB CS 0 0 1 SCN 20 w 0 300 m 612 300 l S";
    try validate(&doc);
    const bitmap = try render(a, &doc, 0, &.{}, 612);
    defer a.free(bitmap.pixels);
    const probes = [_]struct { x: usize, y: usize, rgb: Color }{
        .{ .x = 100, .y = 100, .rgb = .{ 128, 128, 128 } },
        .{ .x = 300, .y = 100, .rgb = .{ 255, 0, 0 } },
        .{ .x = 300, .y = 300, .rgb = .{ 0, 0, 255 } },
    };
    for (probes) |p| {
        const at = ((791 - p.y) * 612 + p.x) * 4;
        try std.testing.expectEqualSlices(u8, &p.rgb, bitmap.pixels[at..][0..3]);
    }
}

test "CMYK text inspection remains available while rendering is unsupported" {
    const a = std.testing.allocator;
    const bytes = try pod.create(a, "inspection");
    defer a.free(bytes);
    var doc = try pod.Document.open(a, bytes);
    defer doc.deinit();
    (try doc.object(.{ .id = 5, .generation = 0 })).changed = "1 0 0 0 k BT /F1 12 Tf (Text) Tj ET";
    try std.testing.expectEqualStrings("Text", (try doc.inspect())[0].runs[0].text);
    try std.testing.expectError(error.UnsupportedColorSpace, validate(&doc));
}

test "ExtGState separates fill stroke alpha and knocks out combined painting" {
    const a = std.testing.allocator;
    const bytes = try pod.create(a, "states");
    defer a.free(bytes);
    var doc = try pod.Document.open(a, bytes);
    defer doc.deinit();
    var parser = s.Parser{ .allocator = doc.allocator(), .bytes = "<< /ExtGState << /Half << /ca 0.5 /CA 0.25 /LW 20 /LC 2 /LJ 1 >> " ++
        "/Multiply << /BM /Multiply >> >> >>" };
    try doc.set(try doc.object(.{ .id = 3, .generation = 0 }), "Resources", try parser.value());
    (try doc.object(.{ .id = 5, .generation = 0 })).changed =
        "0 0 1 rg 0 0 612 792 re f q /Half gs 1 0 0 rg 0 1 0 RG " ++
        "100 100 200 200 re B /Multiply gs 400 100 100 100 re f Q " ++
        "1 0 0 rg 100 400 200 100 re f";
    try validate(&doc);
    const bitmap = try render(a, &doc, 0, &.{}, 612);
    defer a.free(bitmap.pixels);
    const probes = [_]struct { x: usize, y: usize, rgb: Color }{
        .{ .x = 200, .y = 200, .rgb = .{ 128, 0, 128 } },
        // The translucent border replaces the fill against the initial blue backdrop.
        .{ .x = 105, .y = 200, .rgb = .{ 0, 64, 191 } },
        .{ .x = 95, .y = 200, .rgb = .{ 0, 64, 191 } },
        .{ .x = 450, .y = 150, .rgb = .{ 0, 0, 128 } },
        .{ .x = 200, .y = 450, .rgb = .{ 255, 0, 0 } },
    };
    for (probes) |p| {
        const at = ((791 - p.y) * 612 + p.x) * 4;
        try std.testing.expectEqualSlices(u8, &p.rgb, bitmap.pixels[at..][0..3]);
    }
}

test "Screen and Difference graphics states blend and restore" {
    const a = std.testing.allocator;
    const bytes = try pod.create(a, "blends");
    defer a.free(bytes);
    var doc = try pod.Document.open(a, bytes);
    defer doc.deinit();
    var parser = s.Parser{ .allocator = doc.allocator(), .bytes = "<< /ExtGState << /Screen << /BM /Screen >> /Difference << /BM /Difference >> >> >>" };
    try doc.set(try doc.object(.{ .id = 3, .generation = 0 }), "Resources", try parser.value());
    (try doc.object(.{ .id = 5, .generation = 0 })).changed =
        "0.2 0.4 0.8 rg 0 0 612 792 re f /Screen gs 0.8 0.2 0.4 rg " ++
        "100 100 100 100 re f q /Difference gs 300 100 100 100 re f Q 100 300 100 100 re f";
    const bitmap = try render(a, &doc, 0, &.{}, 612);
    defer a.free(bitmap.pixels);
    const probes = [_]struct { x: usize, y: usize, rgb: Color }{
        .{ .x = 150, .y = 150, .rgb = .{ 214, 133, 224 } },
        .{ .x = 350, .y = 150, .rgb = .{ 153, 51, 102 } },
        .{ .x = 150, .y = 350, .rgb = .{ 214, 133, 224 } },
    };
    for (probes) |p| {
        const at = ((791 - p.y) * 612 + p.x) * 4;
        try std.testing.expectEqualSlices(u8, &p.rgb, bitmap.pixels[at..][0..3]);
    }
}

const appearance = @import("annotation_appearance.zig");
const AppearanceLayout = struct { appearance: appearance.Appearance, height: u32, view: c.Matrix };
fn appearanceLayout(doc: *d.Document, page_index: usize, annotation_id: u32, width: u32) !AppearanceLayout {
    if (width == 0 or width > 4096) return error.BitmapLimit;
    const item = try appearance.load(doc, page_index, annotation_id);
    const box = item.rect;
    const scale = @as(f64, @floatFromInt(width)) / (box[2] - box[0]);
    const height = @ceil((box[3] - box[1]) * scale);
    if (!std.math.isFinite(height) or height < 1 or height > 16384 or height * @as(f64, @floatFromInt(width)) * 4 > 64 * 1024 * 1024) return error.BitmapLimit;
    return .{ .appearance = item, .height = @intFromFloat(height), .view = .{ scale, 0, 0, -scale, -box[0] * scale, box[3] * scale } };
}
// Normal-appearance preview in its unrotated annotation rectangle, on white.
// This is not a page-view API: screen flags and popup interaction belong to the viewer.
pub fn renderAnnotationAppearanceWithFonts(a: A, doc: *d.Document, page_index: usize, annotation_id: u32, fonts: []const FontSource, width: u32) !Bitmap {
    const target = try appearanceLayout(doc, page_index, annotation_id, width);
    const pixels = try a.alloc(u8, @as(usize, width) * target.height * 4);
    errdefer a.free(pixels);
    @memset(pixels, 255);
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    var renderer = Renderer{ .allocator = arena.allocator(), .bitmap = .{ .width = width, .height = target.height, .pixels = pixels }, .view = target.view, .font_sources = fonts };
    try renderer.paintAppearance(doc, target.appearance);
    return renderer.bitmap.?;
}
pub fn collectAnnotationAppearanceWithFonts(a: A, doc: *d.Document, page_index: usize, annotation_id: u32, fonts: []const FontSource, width: u32, collector: Collector) !u32 {
    const target = try appearanceLayout(doc, page_index, annotation_id, width);
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    var renderer = Renderer{ .allocator = arena.allocator(), .collector = collector, .view = target.view, .font_sources = fonts };
    try renderer.paintAppearance(doc, target.appearance);
    return target.height;
}

// Width sets output resolution; zoom is magnification only, excluding pixel density.
// Recollect/rerender after zoom or rotation changes: fixed annotations are baked in.
pub const PageView = struct {
    zoom: f64 = 1,
    rotation: i32 = 0,
    fn validate(self: PageView) !void {
        if (!std.math.isFinite(self.zoom) or self.zoom <= 0 or self.zoom > 1e6) return error.InvalidTransform;
        if (self.rotation < 0 or self.rotation >= 360 or @mod(self.rotation, 90) != 0) return error.InvalidRotation;
    }
};
pub fn renderPageViewWithFonts(a: A, doc: *d.Document, page_index: usize, fonts: []const FontSource, width: u32, view: PageView) !Bitmap {
    try view.validate();
    return renderPage(a, doc, page_index, fonts, width, view);
}

test "dash phase and subpath restart preserve exact horizontal gaps" {
    const a = std.testing.allocator;
    const bytes = try pod.create(a, "");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    try doc.replaceStream(try doc.object(.{ .id = 5, .generation = 0 }), "8 w [20 10] 5 d 20 50 m 140 50 l 20 80 m 140 80 l S");
    const bitmap = try render(a, &doc, 0, &.{}, 612);
    defer a.free(bitmap.pixels);
    for ([_]usize{ 50, 80 }) |y| {
        for ([_]usize{ 25, 55, 85, 115 }) |x| try std.testing.expectEqual(@as(u8, 0), bitmap.pixels[((792 - y) * 612 + x) * 4]);
        for ([_]usize{ 40, 70, 100, 130 }) |x| try std.testing.expectEqual(@as(u8, 255), bitmap.pixels[((792 - y) * 612 + x) * 4]);
    }
}

test "dash pattern validation rejects unsafe lengths and illegal path transforms" {
    const a = std.testing.allocator;
    const bytes = try pod.create(a, "");
    defer a.free(bytes);
    const cases = [_]struct { stream: []const u8, err: anyerror }{
        .{ .stream = "[-1 2] 0 d", .err = error.InvalidDash },
        .{ .stream = "[0 0] 0 d", .err = error.InvalidDash },
        .{ .stream = "[1 2] 10000000000000 d", .err = error.InvalidDash },
        .{ .stream = "0 0 m 20 20 l 2 0 0 1 0 0 cm S", .err = error.InvalidPath },
        .{ .stream = "[0.000001 0.000001] 0 d 0 0 m 600 600 l S", .err = error.PathLimit },
    };
    for (cases) |case| {
        var doc = try d.Document.open(a, bytes);
        defer doc.deinit();
        try doc.replaceStream(try doc.object(.{ .id = 5, .generation = 0 }), case.stream);
        try std.testing.expectError(case.err, validate(&doc));
    }
}

test "dash cycles normalize phase and zero gaps retain cap geometry" {
    const a = std.testing.allocator;
    const bytes = try pod.create(a, "");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    const patterns = [_][2][]const u8{
        .{ "[30 10] 1000000012", "[30 10] 12" },
        .{ "[30 10] -5", "[30 10] 35" },
        .{ "[30 10 5] 7", "[30 10 5 30 10 5] 7" },
    };
    for (patterns) |pair| {
        var results: [2]Bitmap = undefined;
        for (pair, 0..) |pattern, i| {
            const stream = try std.fmt.allocPrint(doc.allocator(), "8 w 1 J {s} d 100 300 m 500 300 l S", .{pattern});
            try doc.replaceStream(try doc.object(.{ .id = 5, .generation = 0 }), stream);
            results[i] = try render(a, &doc, 0, &.{}, 100);
        }
        defer a.free(results[0].pixels);
        defer a.free(results[1].pixels);
        try std.testing.expectEqualSlices(u8, results[0].pixels, results[1].pixels);
    }
    try doc.replaceStream(try doc.object(.{ .id = 5, .generation = 0 }), "12 w 2 J [0 24] 0 d 100 300 m 500 300 l S");
    const bitmap = try render(a, &doc, 0, &.{}, 612);
    defer a.free(bitmap.pixels);
    for ([_]usize{ 96, 100, 104, 120, 124, 128 }) |x| try std.testing.expectEqual(@as(u8, 0), bitmap.pixels[(492 * 612 + x) * 4]);
    for ([_]usize{ 107, 112, 116, 500 }) |x| try std.testing.expectEqual(@as(u8, 255), bitmap.pixels[(492 * 612 + x) * 4]);
    // A dash longer than the closed contour is a solid closed stroke: all
    // corners use joins even when the selected cap is round.
    try doc.replaceStream(try doc.object(.{ .id = 5, .generation = 0 }), "14 w 1 J [2000 10] 0 d 100 200 300 240 re S");
    const closed = try render(a, &doc, 0, &.{}, 612);
    defer a.free(closed.pixels);
    for ([_]usize{ 94, 405 }) |x| {
        for ([_]usize{ 346, 597 }) |y| try std.testing.expectEqual(@as(u8, 0), closed.pixels[(y * 612 + x) * 4]);
    }
}
fn renderDashWithAllocator(a: A, bytes: []const u8) !void {
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    const bitmap = try render(a, &doc, 0, &.{}, 24);
    defer a.free(bitmap.pixels);
}
test "dash contours and affine outlines release failed allocations and isolate annotations" {
    const a = std.testing.allocator;
    const bytes = try pod.create(a, "");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    try doc.replaceStream(try doc.object(.{ .id = 5, .generation = 0 }), "q 1 .2 .3 1 0 0 cm 12 w 2 J [0 24] 0 d 100 300 m 500 300 l S Q [20 8] 0 d");
    _ = try annotations.add(&doc, 0, .rectangle, &.{ .{ .x = 100, .y = 100 }, .{ .x = 200, .y = 200 } }, "", .{ .width = 8, .stroke = .{ 0, 0, 0 } });
    const bitmap = try render(a, &doc, 0, &.{}, 612);
    defer a.free(bitmap.pixels);
    // The page's final dash state must not turn a solid annotation border into gaps.
    for (105..195) |x| try std.testing.expectEqual(@as(u8, 0), bitmap.pixels[(692 * 612 + x) * 4]);
    const saved = try doc.save(a);
    defer a.free(saved);
    try std.testing.checkAllAllocationFailures(a, renderDashWithAllocator, .{saved});
}

test "dash ending at a corner uses a cap while continuous corner dashes join" {
    const a = std.testing.allocator;
    const bytes = try pod.create(a, "");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    const obj = try doc.object(.{ .id = 5, .generation = 0 });
    try doc.replaceStream(obj, "4 w [9 4] 0 d 20 20 m 44 20 l 44 44 l 20 44 l h S");
    const dashed = try render(a, &doc, 0, &.{}, 612);
    defer a.free(dashed.pixels);
    // Explicit solid contours independently describe each nine-unit dash,
    // including the joined dash wrapping across the closed path's seam.
    try doc.replaceStream(obj, "4 w 20 25 m 20 20 l 29 20 l 33 20 m 42 20 l 44 22 m 44 31 l 44 35 m 44 44 l 40 44 m 31 44 l 27 44 m 20 44 l 20 42 l 20 38 m 20 29 l S");
    const explicit = try render(a, &doc, 0, &.{}, 612);
    defer a.free(explicit.pixels);
    try std.testing.expectEqualSlices(u8, explicit.pixels, dashed.pixels);
}
