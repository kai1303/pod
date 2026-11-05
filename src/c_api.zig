const std = @import("std");
const pod = @import("pod.zig");
const renderer = @import("render.zig");
const a = std.heap.c_allocator;
const Handle = struct {
    bytes: []u8, document: pod.Document, annotation_cache: []?[]annotations.Annotation,
    fn list(self:*Handle,page:usize) ![]annotations.Annotation {
        if(page>=self.annotation_cache.len) return error.PageNotFound;
        if(self.annotation_cache[page]) |cached| return cached;
        const items=try annotations.list(&self.document,page);
        self.annotation_cache[page]=items;
        return items;
    }
};
const Buffer = extern struct { data: ?[*]u8 = null, length: usize = 0 };
const Bitmap = extern struct { data: ?[*]u8 = null, length: usize = 0, width: u32 = 0, height: u32 = 0 };
const Page = extern struct { x: f64, y: f64, width: f64, height: f64, runs: usize, media: [4]f64, rotation: i32 };
const Run = extern struct { text: [*]const u8, length: usize, x: f64, y: f64, size: f64, advance: f64, bounds: [4]f64 };
threadlocal var last_error: [256:0]u8 = @splat(0);
fn fail(err: anyerror) c_int {
    const name = @errorName(err);
    const n = @min(name.len, 255);
    @memcpy(last_error[0..n], name[0..n]);
    last_error[n] = 0;
    return 0;
}
export fn pod_error() [*:0]const u8 { return &last_error; }
export fn pod_open(data: [*]const u8, length: usize) ?*Handle {
    return open(data[0..length]) catch |err| { _ = fail(err); return null; };
}
fn open(bytes: []const u8) !*Handle {
    if (bytes.len > 256 * 1024 * 1024) return error.FileLimit;
    const owned = try a.dupe(u8, bytes);
    errdefer a.free(owned);
    var document = try pod.Document.open(a, owned);
    errdefer document.deinit();
    _ = try document.inspect();
    try renderer.validate(&document);
    const cache=try a.alloc(?[]annotations.Annotation,(try document.inspect()).len);
    errdefer a.free(cache);
    @memset(cache,null);
    const h = try a.create(Handle);
    h.* = .{ .bytes = owned, .document = document, .annotation_cache=cache };
    return h;
}
export fn pod_close(h: *Handle) void { a.free(h.annotation_cache); h.document.deinit(); a.free(h.bytes); a.destroy(h); }
export fn pod_page_count(h: *Handle) usize { return (h.document.inspect() catch return 0).len; }
export fn pod_page(h: *Handle, index: usize, out: *Page) c_int {
    const pages = h.document.inspect() catch |err| return fail(err);
    if (index >= pages.len) return fail(error.PageNotFound);
    return pageInfo(pages[index], out);
}
fn pageInfo(page: @import("document.zig").Page, out: *Page) c_int {
    const box = page.visibleBox() catch |err| return fail(err);
    const media = @import("document.zig").rectangle(page.media_box) catch |err| return fail(err);
    out.* = .{ .x = box[0], .y = box[1], .width = box[2]-box[0], .height = box[3]-box[1], .runs = page.runs.len, .media = media, .rotation = page.rotation };
    return 1;
}
// The index borrows immutable input bytes for its entire lifetime. Each page
// gets a separate arena for parsed text, annotations and rendering scratch.
const PageIndex = struct { document: pod.Document, pages: []@import("document.zig").Page };
export fn pod_index_open(data: [*]const u8, length: usize) ?*PageIndex {
    return indexOpen(data[0..length]) catch |err| { _ = fail(err); return null; };
}
fn indexOpen(bytes: []const u8) !*PageIndex {
    var document = try pod.Document.open(a, bytes);
    errdefer document.deinit();
    const pages = try document.indexPages();
    if (document.unsupported_appearance) return error.UnsupportedPageAppearance;
    const index = try a.create(PageIndex);
    index.* = .{ .document = document, .pages = pages };
    return index;
}
export fn pod_index_close(index: *PageIndex) void {
    index.document.deinit();
    a.destroy(index);
}
export fn pod_index_count(index: *PageIndex) usize { return index.pages.len; }
export fn pod_index_geometry(index: *PageIndex, page: usize, out: *Page) c_int {
    if (page >= index.pages.len) return fail(error.PageNotFound);
    return pageInfo(index.pages[page], out);
}
export fn pod_index_open_page(index: *PageIndex, page: usize) ?*Handle {
    return openPage(index, page) catch |err| { _ = fail(err); return null; };
}
fn openPage(index: *PageIndex, number: usize) !*Handle {
    if (number >= index.pages.len) return error.PageNotFound;
    var doc = pod.Document{
        .arena = std.heap.ArenaAllocator.init(a),
        .bytes = index.document.bytes,
        .entries = index.document.entries,
        .page_objects = .empty,
    };
    errdefer doc.deinit();
    const pages = try doc.allocator().alloc(@import("document.zig").Page, 1);
    pages[0] = index.pages[number];
    pages[0].number = 1;
    doc.pages = pages;
    pages[0].runs = try @import("content.zig").inspect(&doc, &pages[0]);
    const cache = try a.alloc(?[]annotations.Annotation, 1);
    errdefer a.free(cache);
    cache[0] = null;
    const h = try a.create(Handle);
    h.* = .{ .bytes = &.{}, .document = doc, .annotation_cache = cache };
    return h;
}
export fn pod_run(h: *Handle, index: usize, run: usize, out: *Run) c_int {
    const pages = h.document.inspect() catch |err| return fail(err);
    if (index >= pages.len) return fail(error.PageNotFound);
    if (run >= pages[index].runs.len) return fail(error.RunNotFound);
    const r = pages[index].runs[run];
    out.* = .{ .text = r.text.ptr, .length = r.text.len, .x = r.x, .y = r.y, .size = r.font_size, .advance = r.advance, .bounds = r.bounds };
    return 1;
}
export fn pod_render(h: *Handle, index: usize, font: [*]const u8, font_length: usize, width: u32, out: *Bitmap) c_int {
    out.* = .{};
    const bitmap = renderer.render(a, &h.document, index, font[0..font_length], width) catch |err| return fail(err);
    out.* = .{ .data = bitmap.pixels.ptr, .length = bitmap.pixels.len, .width = bitmap.width, .height = bitmap.height };
    return 1;
}
const SolidPaintCallback = *const fn (*anyopaque, [*]const renderer.Edge, usize, u32, f64, bool) callconv(.c) bool;
const SolidCollector = struct {
    context: *anyopaque,
    paint: SolidPaintCallback,
    fn emit(raw: *anyopaque, edges: [*]const renderer.Edge, count: usize, rgb: u32, opacity: f64, even: bool, multiply: bool) callconv(.c) bool {
        const self: *SolidCollector = @ptrCast(@alignCast(raw));
        return !multiply and self.paint(self.context, edges, count, rgb, opacity, even);
    }
};
export fn pod_collect_paints(h: *Handle, page: usize, font: [*]const u8, font_length: usize, width: u32, context: *anyopaque, paint: SolidPaintCallback, height: *u32, hairlines: *bool) c_int {
    var adapter = SolidCollector{ .context = context, .paint = paint };
    return pod_collect_paints_with_blend(h, page, font, font_length, width, &adapter, SolidCollector.emit, height, hairlines);
}
export fn pod_collect_paints_with_blend(h: *Handle, page: usize, font: [*]const u8, font_length: usize, width: u32, context: *anyopaque, paint: renderer.PaintCallback, height: *u32, hairlines: *bool) c_int {
    hairlines.* = false;
    height.* = renderer.collect(a, &h.document, page, font[0..font_length], width, .{ .context = context, .paint = paint, .hairlines = hairlines }) catch |err| return fail(err);
    return 1;
}
export fn pod_replace(h: *Handle, page: usize, run: usize, text: [*]const u8, length: usize) c_int {
    if (page == std.math.maxInt(usize)) return fail(error.PageNotFound);
    h.document.replace(page + 1, run, text[0..length]) catch |err| return fail(err);
    return 1;
}
export fn pod_save(h: *Handle, out: *Buffer) c_int {
    out.* = .{};
    const bytes = h.document.save(a) catch |err| return fail(err);
    out.* = .{ .data = bytes.ptr, .length = bytes.len };
    return 1;
}
export fn pod_buffer_free(bytes: ?[*]u8, length: usize) void { if (bytes) |p| a.free(p[0..length]); }

const annotations = @import("annotations.zig");
const AnnotationStyle = extern struct {
    stroke: [3]f64, fill: [3]f64, opacity: f64, width: f64, font_size: f64, has_fill: i32,
    fn native(self: @This()) annotations.Style {
        return .{ .stroke = self.stroke, .fill = if (self.has_fill != 0) self.fill else null, .opacity = self.opacity, .width = self.width, .font_size = self.font_size };
    }
    fn from(s: annotations.Style) @This() {
        return .{ .stroke = s.stroke, .fill = s.fill orelse .{0,0,0}, .opacity = s.opacity, .width = s.width, .font_size = s.font_size, .has_fill = if(s.fill != null) 1 else 0 };
    }
};
const Annotation = extern struct { id: u32, kind: u32, points: [*]const annotations.Point, point_count: usize, rect: [4]f64, text: [*]const u8, text_length: usize, style: AnnotationStyle, ink_starts: [*]const usize, ink_start_count: usize, link: [*]const u8, link_length: usize, legacy_ink: c_int, imported_ink: c_int, ink_locked: c_int };
export fn pod_annotation_count(h: *Handle, page: usize, out: *usize) c_int {
    const list = h.list(page) catch |err| return fail(err);
    out.* = list.len;
    return 1;
}
export fn pod_annotation(h: *Handle, page: usize, index: usize, out: *Annotation) c_int {
    const list = h.list(page) catch |err| return fail(err);
    if(index >= list.len) return fail(error.AnnotationNotFound);
    const n = list[index];
    out.* = .{.id=n.id, .kind=@intFromEnum(n.kind), .points=n.points.ptr, .point_count=n.points.len, .rect=n.rect, .text=n.text.ptr, .text_length=n.text.len, .style=AnnotationStyle.from(n.style), .ink_starts=n.ink.starts.ptr, .ink_start_count=n.ink.starts.len, .link=n.ink.link.ptr, .link_length=n.ink.link.len, .legacy_ink=@intFromBool(n.ink.legacy), .imported_ink=@intFromBool(n.imported_ink), .ink_locked=@intFromBool(n.locked)};
    return 1;
}
export fn pod_annotation_put(h:*Handle, page:usize, existing_id:u32, kind:u32, points:[*]const annotations.Point, point_count:usize, text:[*]const u8, text_length:usize, style:AnnotationStyle) c_int {
    return pod_annotation_put_with_ink(h,page,existing_id,kind,points,point_count,text,text_length,style,null,0,null,0);
}
export fn pod_annotation_put_with_ink(h:*Handle, page:usize, existing_id:u32, kind:u32, points:[*]const annotations.Point, point_count:usize, text:[*]const u8, text_length:usize, style:AnnotationStyle, ink_starts:?[*]const usize, ink_start_count:usize, link:?[*]const u8, link_length:usize) c_int {
    const k = std.enums.fromInt(annotations.Kind, kind) orelse return fail(error.UnsupportedAnnotation);
    if(point_count > 4096 or text_length > 1048576) return fail(error.AnnotationLimit);
    if(ink_start_count > point_count or link_length > 8192) return fail(error.AnnotationLimit);
    if((ink_starts == null and ink_start_count != 0) or (link == null and link_length != 0)) return fail(error.InvalidAnnotationGeometry);
    const ink = annotations.Ink{ .starts=if (ink_starts) |starts| starts[0..ink_start_count] else &.{}, .link=if (link) |value| value[0..link_length] else "" };
    if(existing_id == 0) {
        _ = annotations.addWithInk(&h.document,page,k,points[0..point_count],text[0..text_length],style.native(),ink) catch |err| return fail(err);
    } else annotations.updateWithInk(&h.document,page,existing_id,k,points[0..point_count],text[0..text_length],style.native(),ink) catch |err| return fail(err);
    @memset(h.annotation_cache,null);
    return 1;
}
export fn pod_annotation_remove(h:*Handle, page:usize, id:u32) c_int {
    annotations.remove(&h.document,page,id) catch |err| return fail(err);
    @memset(h.annotation_cache,null);
    return 1;
}


const page_tools = @import("page_tools.zig");
fn pageOutput(result: anyerror![]u8, out: *Buffer) c_int {
    out.* = .{};
    const bytes = result catch |err| return fail(err);
    if (bytes.len > 256 * 1024 * 1024) { a.free(bytes); return fail(error.FileLimit); }
    out.* = .{ .data = bytes.ptr, .length = bytes.len };
    return 1;
}
// Page operations return a new document and leave source handles and their caches intact.
export fn pod_select_pages(h: *Handle, indices: ?[*]const usize, count: usize, out: *Buffer) c_int {
    out.* = .{};
    if (count == 0 or indices == null) return fail(error.EmptyPageSelection);
    if (count > 100000) return fail(error.PageLimit);
    return pageOutput(page_tools.assemble(a, &.{.{ .doc = &h.document, .pages = indices.?[0..count] }}), out);
}
export fn pod_merge(h: *Handle, other: *Handle, out: *Buffer) c_int {
    out.* = .{};
    const first = pod_page_count(h);
    const second = pod_page_count(other);
    if (first == 0 or second == 0 or first + second > 100000) return fail(error.PageLimit);
    const indices = a.alloc(usize, first + second) catch |err| return fail(err);
    defer a.free(indices);
    for (indices[0..first], 0..) |*v, i| v.* = i;
    for (indices[first..], 0..) |*v, i| v.* = i;
    return pageOutput(page_tools.assemble(a, &.{ .{ .doc = &h.document, .pages = indices[0..first] }, .{ .doc = &other.document, .pages = indices[first..] } }), out);
}
export fn pod_rotate_page(h: *Handle, index: usize, degrees: i32, out: *Buffer) c_int {
    return pageOutput(page_tools.rotate(a, &h.document, index, degrees), out);
}
export fn pod_crop_page(h: *Handle, index: usize, x0: f64, y0: f64, x1: f64, y1: f64, out: *Buffer) c_int {
    return pageOutput(page_tools.crop(a, &h.document, index, .{ x0, y0, x1, y1 }), out);
}
