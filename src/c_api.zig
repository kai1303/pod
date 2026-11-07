const std = @import("std");
const pod = @import("pod.zig");
const renderer = @import("render.zig");
const links = @import("links.zig");
const a = std.heap.c_allocator;
const Handle = struct {
    bytes: []u8,
    document: pod.Document,
    annotation_cache: []?[]annotations.Annotation,
    link_cache: []?[]links.Link,
    fn linkList(self: *Handle, page: usize) ![]links.Link {
        if (page >= self.link_cache.len) return error.PageNotFound;
        if (self.link_cache[page]) |cached| return cached;
        const items = try links.list(&self.document, page);
        self.link_cache[page] = items;
        return items;
    }
    fn list(self: *Handle, page: usize) ![]annotations.Annotation {
        if (page >= self.annotation_cache.len) return error.PageNotFound;
        if (self.annotation_cache[page]) |cached| return cached;
        const items = try annotations.list(&self.document, page);
        self.annotation_cache[page] = items;
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
export fn pod_error() [*:0]const u8 {
    return &last_error;
}
export fn pod_open(data: [*]const u8, length: usize) ?*Handle {
    return open(data[0..length]) catch |err| {
        _ = fail(err);
        return null;
    };
}
fn open(bytes: []const u8) !*Handle {
    if (bytes.len > 256 * 1024 * 1024) return error.FileLimit;
    const owned = try a.dupe(u8, bytes);
    errdefer a.free(owned);
    var document = try pod.Document.open(a, owned);
    errdefer document.deinit();
    _ = try document.inspect();
    try renderer.validate(&document);
    const cache = try a.alloc(?[]annotations.Annotation, (try document.inspect()).len);
    errdefer a.free(cache);
    @memset(cache, null);
    const link_cache = try a.alloc(?[]links.Link, cache.len);
    errdefer a.free(link_cache);
    @memset(link_cache, null);
    const h = try a.create(Handle);
    h.* = .{ .bytes = owned, .document = document, .annotation_cache = cache, .link_cache = link_cache };
    return h;
}
export fn pod_close(h: *Handle) void {
    a.free(h.link_cache);
    a.free(h.annotation_cache);
    h.document.deinit();
    a.free(h.bytes);
    a.destroy(h);
}
export fn pod_page_count(h: *Handle) usize {
    return (h.document.inspect() catch return 0).len;
}
export fn pod_page(h: *Handle, index: usize, out: *Page) c_int {
    const pages = h.document.inspect() catch |err| return fail(err);
    if (index >= pages.len) return fail(error.PageNotFound);
    return pageInfo(pages[index], out);
}
fn pageInfo(page: @import("document.zig").Page, out: *Page) c_int {
    const box = page.visibleBox() catch |err| return fail(err);
    const media = @import("document.zig").rectangle(page.media_box) catch |err| return fail(err);
    out.* = .{ .x = box[0], .y = box[1], .width = box[2] - box[0], .height = box[3] - box[1], .runs = page.runs.len, .media = media, .rotation = page.rotation };
    return 1;
}
// The index borrows immutable input bytes for its entire lifetime. Each page
// gets a separate arena for parsed text, annotations and rendering scratch.
const PageIndex = struct { document: pod.Document, pages: []@import("document.zig").Page, has_outlines: bool };
export fn pod_index_open(data: [*]const u8, length: usize) ?*PageIndex {
    return indexOpen(data[0..length]) catch |err| {
        _ = fail(err);
        return null;
    };
}
fn indexOpen(bytes: []const u8) !*PageIndex {
    var document = try pod.Document.open(a, bytes);
    errdefer document.deinit();
    const pages = try document.indexPages();
    if (document.unsupported_appearance) return error.UnsupportedPageAppearance;
    const syntax = @import("syntax.zig");
    const catalog = try document.resolve(syntax.get(document.trailer, "Root").?);
    const index = try a.create(PageIndex);
    index.* = .{ .document = document, .pages = pages, .has_outlines = syntax.get(catalog, "Outlines") != null };
    return index;
}
export fn pod_index_close(index: *PageIndex) void {
    index.document.deinit();
    a.destroy(index);
}
export fn pod_index_count(index: *PageIndex) usize {
    return index.pages.len;
}
export fn pod_index_has_outlines(index: *PageIndex) bool {
    return index.has_outlines;
}
export fn pod_index_geometry(index: *PageIndex, page: usize, out: *Page) c_int {
    if (page >= index.pages.len) return fail(error.PageNotFound);
    return pageInfo(index.pages[page], out);
}
export fn pod_index_open_page(index: *PageIndex, page: usize) ?*Handle {
    return openPage(index, page) catch |err| {
        _ = fail(err);
        return null;
    };
}
fn openPage(index: *PageIndex, number: usize) !*Handle {
    if (number >= index.pages.len) return error.PageNotFound;
    var doc = pod.Document{
        .arena = std.heap.ArenaAllocator.init(a),
        .bytes = index.document.bytes,
        .trailer = index.document.trailer,
        .page_numbers = index.document.page_numbers,
        .entries = index.document.entries,
        .page_objects = .empty,
    };
    errdefer doc.deinit();
    const pages = try doc.allocator().alloc(@import("document.zig").Page, 1);
    pages[0] = index.pages[number];
    pages[0].number = 1;
    doc.pages = pages;
    try doc.resolveContents(&pages[0]);
    pages[0].runs = try @import("content.zig").inspect(&doc, &pages[0]);
    const cache = try a.alloc(?[]annotations.Annotation, 1);
    errdefer a.free(cache);
    cache[0] = null;
    const link_cache = try a.alloc(?[]links.Link, 1);
    errdefer a.free(link_cache);
    link_cache[0] = null;
    const h = try a.create(Handle);
    h.* = .{ .bytes = &.{}, .document = doc, .annotation_cache = cache, .link_cache = link_cache };
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
// Font bytes are borrowed for this synchronous call; face IDs match pdf_font.Face.
const FontSource = extern struct { face: u32, data: ?[*]const u8, length: usize };
fn fontSources(raw: ?[*]const FontSource, count: usize, buffer: *[14]renderer.FontSource) ![]const renderer.FontSource {
    if (count > buffer.len or (count != 0 and raw == null)) return error.InvalidFontSource;
    var seen: u16 = 0;
    for (0..count) |i| {
        const source = raw.?[i];
        if (source.face >= 14 or source.data == null or source.length == 0 or source.length > 64 * 1024 * 1024) return error.InvalidFontSource;
        const mask = @as(u16, 1) << @as(u4, @intCast(source.face));
        if (seen & mask != 0) return error.InvalidFontSource;
        seen |= mask;
        buffer[i] = .{ .face = @fromBackingInt(@intCast(source.face)), .bytes = source.data.?[0..source.length] };
    }
    return buffer[0..count];
}
const String = extern struct { data: ?[*]const u8 = null, length: usize = 0 };
export fn pod_run_font(h: *Handle, page: usize, run: usize, out: *String) c_int {
    out.* = .{};
    const pages = h.document.inspect() catch |err| return fail(err);
    if (page >= pages.len) return fail(error.PageNotFound);
    if (run >= pages[page].runs.len) return fail(error.RunNotFound);
    const name = pages[page].runs[run].font.name();
    out.* = .{ .data = name.ptr, .length = name.len };
    return 1;
}
export fn pod_render_with_fonts(h: *Handle, page: usize, sources: ?[*]const FontSource, count: usize, width: u32, out: *Bitmap) c_int {
    out.* = .{};
    var buffer: [14]renderer.FontSource = undefined;
    const fonts = fontSources(sources, count, &buffer) catch |err| return fail(err);
    const bitmap = renderer.renderWithFonts(a, &h.document, page, fonts, width) catch |err| return fail(err);
    out.* = .{ .data = bitmap.pixels.ptr, .length = bitmap.pixels.len, .width = bitmap.width, .height = bitmap.height };
    return 1;
}
export fn pod_render_annotation_appearance_with_fonts(h: *Handle, page: usize, annotation: u32, sources: ?[*]const FontSource, count: usize, width: u32, out: *Bitmap) c_int {
    out.* = .{};
    var buffer: [14]renderer.FontSource = undefined;
    const fonts = fontSources(sources, count, &buffer) catch |err| return fail(err);
    const result = renderer.renderAnnotationAppearanceWithFonts(a, &h.document, page, annotation, fonts, width) catch |err| return fail(err);
    out.* = .{ .data = result.pixels.ptr, .length = result.pixels.len, .width = result.width, .height = result.height };
    return 1;
}
export fn pod_collect_annotation_appearance(h: *Handle, page: usize, annotation: u32, sources: ?[*]const FontSource, count: usize, width: u32, context: *anyopaque, paint: renderer.PaintCallback, height: *u32, hairlines: *bool) c_int {
    height.* = 0;
    hairlines.* = false;
    var buffer: [14]renderer.FontSource = undefined;
    const fonts = fontSources(sources, count, &buffer) catch |err| return fail(err);
    height.* = renderer.collectAnnotationAppearanceWithFonts(a, &h.document, page, annotation, fonts, width, .{ .context = context, .paint = paint, .hairlines = hairlines }) catch |err| return fail(err);
    return 1;
}
export fn pod_render_page_view(h: *Handle, page: usize, sources: ?[*]const FontSource, count: usize, width: u32, zoom: f64, rotation: i32, out: *Bitmap) c_int {
    out.* = .{};
    var buffer: [14]renderer.FontSource = undefined;
    const fonts = fontSources(sources, count, &buffer) catch |err| return fail(err);
    const result = renderer.renderPageViewWithFonts(a, &h.document, page, fonts, width, .{ .zoom = zoom, .rotation = rotation }) catch |err| return fail(err);
    out.* = .{ .data = result.pixels.ptr, .length = result.pixels.len, .width = result.width, .height = result.height };
    return 1;
}
export fn pod_collect_page_view(h: *Handle, page: usize, sources: ?[*]const FontSource, count: usize, width: u32, zoom: f64, rotation: i32, context: *anyopaque, paint: renderer.PaintCallback, height: *u32, hairlines: *bool) c_int {
    height.* = 0;
    hairlines.* = false;
    var buffer: [14]renderer.FontSource = undefined;
    const fonts = fontSources(sources, count, &buffer) catch |err| return fail(err);
    height.* = renderer.collectPageViewWithFonts(a, &h.document, page, fonts, width, .{ .context = context, .paint = paint, .hairlines = hairlines }, .{ .zoom = zoom, .rotation = rotation }) catch |err| return fail(err);
    return 1;
}
export fn pod_collect_paints_with_fonts(h: *Handle, page: usize, sources: ?[*]const FontSource, count: usize, width: u32, context: *anyopaque, paint: BlendPaintCallback, height: *u32, hairlines: *bool) c_int {
    var adapter = BlendCollector{ .context = context, .paint = paint };
    return pod_collect_compositing_paints(h, page, sources, count, width, &adapter, BlendCollector.emit, height, hairlines);
}
export fn pod_collect_paints_with_state(h: *Handle, page: usize, sources: ?[*]const FontSource, count: usize, width: u32, context: *anyopaque, paint: StatePaintCallback, height: *u32, hairlines: *bool) c_int {
    var adapter = StateCollector{ .context = context, .paint = paint };
    return pod_collect_compositing_paints(h, page, sources, count, width, &adapter, StateCollector.emit, height, hairlines);
}
export fn pod_collect_image_scene(h: *Handle, page: usize, annotation: u32, sources: ?[*]const FontSource, count: usize, width: u32, zoom: f64, rotation: i32, context: *anyopaque, paint: renderer.PaintCallback, image: renderer.ImageCallback, height: *u32, hairlines: *bool) c_int {
    height.* = 0;
    hairlines.* = false;
    var buffer: [14]renderer.FontSource = undefined;
    const fonts = fontSources(sources, count, &buffer) catch |err| return fail(err);
    const collector = renderer.Collector{ .context = context, .paint = paint, .image = image, .hairlines = hairlines };
    if (annotation != 0) {
        if (zoom != 1 or rotation != 0) return fail(error.InvalidTransform);
        height.* = renderer.collectAnnotationAppearanceWithFonts(a, &h.document, page, annotation, fonts, width, collector) catch |err| return fail(err);
    } else {
        height.* = renderer.collectPageViewWithFonts(a, &h.document, page, fonts, width, collector, .{ .zoom = zoom, .rotation = rotation }) catch |err| return fail(err);
    }
    return 1;
}
export fn pod_collect_compositing_paints(h: *Handle, page: usize, sources: ?[*]const FontSource, count: usize, width: u32, context: *anyopaque, paint: renderer.PaintCallback, height: *u32, hairlines: *bool) c_int {
    height.* = 0;
    hairlines.* = false;
    var buffer: [14]renderer.FontSource = undefined;
    const fonts = fontSources(sources, count, &buffer) catch |err| return fail(err);
    height.* = renderer.collectWithFonts(a, &h.document, page, fonts, width, .{ .context = context, .paint = paint, .hairlines = hairlines }) catch |err| return fail(err);
    return 1;
}
export fn pod_page_content_bounds_with_fonts(h: *Handle, page: usize, sources: ?[*]const FontSource, count: usize, out: *Bounds) c_int {
    out.* = .{};
    var buffer: [14]renderer.FontSource = undefined;
    const fonts = fontSources(sources, count, &buffer) catch |err| return fail(err);
    const bounds = renderer.contentBoundsWithFonts(a, &h.document, page, fonts) catch |err| return fail(err);
    if (bounds) |rect| out.* = .{ .present = 1, .rect = rect };
    return 1;
}
export fn pod_render(h: *Handle, index: usize, font: [*]const u8, font_length: usize, width: u32, out: *Bitmap) c_int {
    out.* = .{};
    const bitmap = renderer.render(a, &h.document, index, font[0..font_length], width) catch |err| return fail(err);
    out.* = .{ .data = bitmap.pixels.ptr, .length = bitmap.pixels.len, .width = bitmap.width, .height = bitmap.height };
    return 1;
}
const SolidPaintCallback = *const fn (*anyopaque, [*]const renderer.Edge, usize, u32, f64, bool) callconv(.c) bool;
const BlendPaintCallback = *const fn (*anyopaque, [*]const renderer.Edge, usize, u32, f64, bool, bool) callconv(.c) bool;
const StatePaintCallback = *const fn (*anyopaque, [*]const renderer.Edge, usize, u32, f64, bool, bool, u32) callconv(.c) bool;
const StateCollector = struct {
    context: *anyopaque,
    paint: StatePaintCallback,
    fn emit(raw: *anyopaque, edges: [*]const renderer.Edge, count: usize, rgb: u32, opacity: f64, even: bool, mode: u32, group: u32) callconv(.c) bool {
        const self: *StateCollector = @ptrCast(@alignCast(raw));
        return mode <= 1 and self.paint(self.context, edges, count, rgb, opacity, even, mode == 1, group);
    }
};
const BlendCollector = struct {
    context: *anyopaque,
    paint: BlendPaintCallback,
    fn emit(raw: *anyopaque, edges: [*]const renderer.Edge, count: usize, rgb: u32, opacity: f64, even: bool, mode: u32, group: u32) callconv(.c) bool {
        const self: *BlendCollector = @ptrCast(@alignCast(raw));
        // Legacy clients cannot composite translucent knockout groups correctly.
        return mode <= 1 and !(group != 0 and (opacity != 1 or mode != 0)) and self.paint(self.context, edges, count, rgb, opacity, even, mode == 1);
    }
};
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
export fn pod_collect_paints_with_blend(h: *Handle, page: usize, font: [*]const u8, font_length: usize, width: u32, context: *anyopaque, paint: BlendPaintCallback, height: *u32, hairlines: *bool) c_int {
    hairlines.* = false;
    var adapter = BlendCollector{ .context = context, .paint = paint };
    height.* = renderer.collect(a, &h.document, page, font[0..font_length], width, .{ .context = &adapter, .paint = BlendCollector.emit, .hairlines = hairlines }) catch |err| return fail(err);
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
export fn pod_buffer_free(bytes: ?[*]u8, length: usize) void {
    if (bytes) |p| a.free(p[0..length]);
}

const annotations = @import("annotations.zig");
const AnnotationStyle = extern struct {
    stroke: [3]f64,
    fill: [3]f64,
    opacity: f64,
    width: f64,
    font_size: f64,
    has_fill: i32,
    fn native(self: @This()) annotations.Style {
        return .{ .stroke = self.stroke, .fill = if (self.has_fill != 0) self.fill else null, .opacity = self.opacity, .width = self.width, .font_size = self.font_size };
    }
    fn from(s: annotations.Style) @This() {
        return .{ .stroke = s.stroke, .fill = s.fill orelse .{ 0, 0, 0 }, .opacity = s.opacity, .width = s.width, .font_size = s.font_size, .has_fill = if (s.fill != null) 1 else 0 };
    }
};
const Annotation = extern struct { id: u32, kind: u32, points: [*]const annotations.Point, point_count: usize, rect: [4]f64, text: [*]const u8, text_length: usize, style: AnnotationStyle, ink_starts: [*]const usize, ink_start_count: usize, link: [*]const u8, link_length: usize, legacy_ink: c_int, imported_ink: c_int, ink_locked: c_int, imported_comment: c_int };
export fn pod_annotation_count(h: *Handle, page: usize, out: *usize) c_int {
    const list = h.list(page) catch |err| return fail(err);
    out.* = list.len;
    return 1;
}
export fn pod_annotation(h: *Handle, page: usize, index: usize, out: *Annotation) c_int {
    const list = h.list(page) catch |err| return fail(err);
    if (index >= list.len) return fail(error.AnnotationNotFound);
    const n = list[index];
    out.* = .{ .id = n.id, .kind = @backingInt(n.kind), .points = n.points.ptr, .point_count = n.points.len, .rect = n.rect, .text = n.text.ptr, .text_length = n.text.len, .style = AnnotationStyle.from(n.style), .ink_starts = n.ink.starts.ptr, .ink_start_count = n.ink.starts.len, .link = n.ink.link.ptr, .link_length = n.ink.link.len, .legacy_ink = @intFromBool(n.ink.legacy), .imported_ink = @intFromBool(n.imported_ink), .ink_locked = @intFromBool(n.locked), .imported_comment = @intFromBool(n.imported_comment) };
    return 1;
}
export fn pod_annotation_imported_shape(h: *Handle, page: usize, index: usize, out: *c_int) c_int {
    out.* = 0;
    const items = h.list(page) catch |err| return fail(err);
    if (index >= items.len) return fail(error.AnnotationNotFound);
    out.* = @intFromBool(items[index].imported_shape);
    return 1;
}
export fn pod_annotation_shape_editable(h: *Handle, page: usize, index: usize, out: *c_int) c_int {
    out.* = 0;
    const items = h.list(page) catch |err| return fail(err);
    if (index >= items.len) return fail(error.AnnotationNotFound);
    out.* = @intFromBool(items[index].shape_editable and !items[index].locked);
    return 1;
}
export fn pod_annotation_imported_free_text(h: *Handle, page: usize, index: usize, out: *c_int) c_int {
    out.* = 0;
    const items = h.list(page) catch |err| return fail(err);
    if (index >= items.len) return fail(error.AnnotationNotFound);
    out.* = @intFromBool(items[index].imported_free_text);
    return 1;
}
export fn pod_annotation_free_text_editable(h: *Handle, page: usize, index: usize, out: *c_int) c_int {
    out.* = 0;
    const items = h.list(page) catch |err| return fail(err);
    if (index >= items.len) return fail(error.AnnotationNotFound);
    out.* = @intFromBool(items[index].free_text_editable and !items[index].locked);
    return 1;
}
export fn pod_annotation_has_caption(h: *Handle, page: usize, index: usize, out: *c_int) c_int {
    out.* = 0;
    const items = h.list(page) catch |err| return fail(err);
    if (index >= items.len) return fail(error.AnnotationNotFound);
    out.* = @intFromBool(items[index].caption);
    return 1;
}
const CommentInfo = extern struct {
    author: String = .{},
    subject: String = .{},
    popup_rect: [4]f64 = @splat(0),
    has_popup: c_int = 0,
    initially_open: c_int = 0,
    rich_text: c_int = 0,
    reply_to: u32 = 0,
    thread_root: u32 = 0,
    review_state: String = .{},
    state_model: String = .{},
};
export fn pod_comment_info(h: *Handle, page: usize, index: usize, out: *CommentInfo) c_int {
    out.* = .{};
    const items = h.list(page) catch |err| return fail(err);
    if (index >= items.len) return fail(error.AnnotationNotFound);
    const mark = items[index];
    const info = mark.comment;
    out.* = .{
        .author = .{ .data = info.author.ptr, .length = info.author.len },
        .subject = .{ .data = info.subject.ptr, .length = info.subject.len },
        .popup_rect = info.popup_rect orelse @splat(0),
        .has_popup = @intFromBool(info.popup_rect != null),
        .initially_open = @intFromBool(info.initially_open),
        .rich_text = @intFromBool(info.rich_text),
        .reply_to = info.reply_to,
        .thread_root = info.thread_root,
        .review_state = .{ .data = info.review_state.ptr, .length = info.review_state.len },
        .state_model = .{ .data = info.state_model.ptr, .length = info.state_model.len },
    };
    return 1;
}
export fn pod_comment_reply(h: *Handle, page: usize, parent_id: u32, text: ?[*]const u8, text_length: usize, author: ?[*]const u8, author_length: usize, out: *u32) c_int {
    out.* = 0;
    if (text_length > 16384 or author_length > 16384) return fail(error.TextLimit);
    if (text == null or (author == null and author_length != 0)) return fail(error.InvalidAnnotationReply);
    out.* = annotations.addReply(&h.document, page, parent_id, text.?[0..text_length], if (author) |name| name[0..author_length] else "") catch |err| return fail(err);
    @memset(h.annotation_cache, null);
    return 1;
}
export fn pod_annotation_put(h: *Handle, page: usize, existing_id: u32, kind: u32, points: [*]const annotations.Point, point_count: usize, text: [*]const u8, text_length: usize, style: AnnotationStyle) c_int {
    return pod_annotation_put_with_ink(h, page, existing_id, kind, points, point_count, text, text_length, style, null, 0, null, 0);
}
export fn pod_annotation_put_with_ink(h: *Handle, page: usize, existing_id: u32, kind: u32, points: [*]const annotations.Point, point_count: usize, text: [*]const u8, text_length: usize, style: AnnotationStyle, ink_starts: ?[*]const usize, ink_start_count: usize, link: ?[*]const u8, link_length: usize) c_int {
    const k = std.enums.fromInt(annotations.Kind, kind) orelse return fail(error.UnsupportedAnnotation);
    if (point_count > 4096 or text_length > 1048576) return fail(error.AnnotationLimit);
    if (ink_start_count > point_count or link_length > 8192) return fail(error.AnnotationLimit);
    if ((ink_starts == null and ink_start_count != 0) or (link == null and link_length != 0)) return fail(error.InvalidAnnotationGeometry);
    const ink = annotations.Ink{ .starts = if (ink_starts) |starts| starts[0..ink_start_count] else &.{}, .link = if (link) |value| value[0..link_length] else "" };
    if (existing_id == 0) {
        _ = annotations.addWithInk(&h.document, page, k, points[0..point_count], text[0..text_length], style.native(), ink) catch |err| return fail(err);
    } else annotations.updateWithInk(&h.document, page, existing_id, k, points[0..point_count], text[0..text_length], style.native(), ink) catch |err| return fail(err);
    @memset(h.annotation_cache, null);
    @memset(h.link_cache, null);
    return 1;
}
export fn pod_annotation_remove(h: *Handle, page: usize, id: u32) c_int {
    annotations.remove(&h.document, page, id) catch |err| return fail(err);
    @memset(h.annotation_cache, null);
    @memset(h.link_cache, null);
    return 1;
}

const page_tools = @import("page_tools.zig");
fn pageOutput(result: anyerror![]u8, out: *Buffer) c_int {
    out.* = .{};
    const bytes = result catch |err| return fail(err);
    if (bytes.len > 256 * 1024 * 1024) {
        a.free(bytes);
        return fail(error.FileLimit);
    }
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

const Link = extern struct { id: u32, rect: [4]f64, uri: [*]const u8, uri_length: usize, base: [*]const u8, base_length: usize, quads: [*]const annotations.Point, point_count: usize, hidden: c_int };
export fn pod_link_count(h: *Handle, page: usize, out: *usize) c_int {
    out.* = 0;
    const items = h.linkList(page) catch |err| return fail(err);
    out.* = items.len;
    return 1;
}
export fn pod_link(h: *Handle, page: usize, index: usize, out: *Link) c_int {
    const items = h.linkList(page) catch |err| return fail(err);
    if (index >= items.len) return fail(error.AnnotationNotFound);
    const link = items[index];
    out.* = .{ .id = link.id, .rect = link.rect, .uri = link.uri.ptr, .uri_length = link.uri.len, .base = link.base.ptr, .base_length = link.base.len, .quads = link.quads.ptr, .point_count = link.quads.len, .hidden = @intFromBool(link.hidden) };
    return 1;
}

const Destination = extern struct { present: c_int = 0, page: usize = 0, mode: u32 = 0, fields: u32 = 0, parameters: [4]f64 = @splat(0) };
export fn pod_link_destination(h: *Handle, page: usize, index: usize, out: *Destination) c_int {
    out.* = .{};
    const items = h.linkList(page) catch |err| return fail(err);
    if (index >= items.len) return fail(error.AnnotationNotFound);
    if (items[index].destination) |dest| {
        out.present = 1;
        out.page = dest.page;
        out.mode = @backingInt(dest.mode);
        for (dest.parameters, 0..) |parameter, i| if (parameter) |n| {
            out.fields |= @as(u32, 1) << @as(u5, @intCast(i));
            out.parameters[i] = n;
        };
    }
    return 1;
}
const Bounds = extern struct { present: c_int = 0, rect: [4]f64 = @splat(0) };
export fn pod_page_content_bounds(h: *Handle, page: usize, font: [*]const u8, font_length: usize, out: *Bounds) c_int {
    out.* = .{};
    const bounds = renderer.contentBounds(a, &h.document, page, font[0..font_length]) catch |err| return fail(err);
    if (bounds) |rect| out.* = .{ .present = 1, .rect = rect };
    return 1;
}
