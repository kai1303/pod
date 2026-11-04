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
const Page = extern struct { x: f64, y: f64, width: f64, height: f64, runs: usize };
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
    const b = pages[index].media_box.array;
    var box: [4]f64 = undefined;
    for (b, 0..) |v, i| box[i] = pod.syntax.number(v) catch |err| return fail(err);
    out.* = .{ .x = box[0], .y = box[1], .width = box[2]-box[0], .height = box[3]-box[1], .runs = pages[index].runs.len };
    return 1;
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
const Annotation = extern struct { id: u32, kind: u32, points: [*]const annotations.Point, point_count: usize, rect: [4]f64, text: [*]const u8, text_length: usize, style: AnnotationStyle };
export fn pod_annotation_count(h: *Handle, page: usize, out: *usize) c_int {
    const list = h.list(page) catch |err| return fail(err);
    out.* = list.len;
    return 1;
}
export fn pod_annotation(h: *Handle, page: usize, index: usize, out: *Annotation) c_int {
    const list = h.list(page) catch |err| return fail(err);
    if(index >= list.len) return fail(error.AnnotationNotFound);
    const n = list[index];
    out.* = .{.id=n.id, .kind=@intFromEnum(n.kind), .points=n.points.ptr, .point_count=n.points.len, .rect=n.rect, .text=n.text.ptr, .text_length=n.text.len, .style=AnnotationStyle.from(n.style)};
    return 1;
}
export fn pod_annotation_put(h:*Handle, page:usize, existing_id:u32, kind:u32, points:[*]const annotations.Point, point_count:usize, text:[*]const u8, text_length:usize, style:AnnotationStyle) c_int {
    const k = std.enums.fromInt(annotations.Kind, kind) orelse return fail(error.UnsupportedAnnotation);
    if(point_count > 4096 or text_length > 1048576) return fail(error.AnnotationLimit);
    if(existing_id == 0) {
        _ = annotations.add(&h.document,page,k,points[0..point_count],text[0..text_length],style.native()) catch |err| return fail(err);
    } else annotations.update(&h.document,page,existing_id,k,points[0..point_count],text[0..text_length],style.native()) catch |err| return fail(err);
    @memset(h.annotation_cache,null);
    return 1;
}
export fn pod_annotation_remove(h:*Handle, page:usize, id:u32) c_int {
    annotations.remove(&h.document,page,id) catch |err| return fail(err);
    @memset(h.annotation_cache,null);
    return 1;
}
