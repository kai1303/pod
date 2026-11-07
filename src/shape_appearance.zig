//! Metadata-driven appearances for standard geometric annotations.
const std = @import("std");
const d = @import("document.zig");
const s = @import("syntax.zig");
const dash = @import("dash.zig");
const captions = @import("line_caption.zig");
const Command = @import("comment_icon.zig").Command;
pub const Kind = enum { rectangle, ellipse, line, polyline, polygon };
const Ending = enum { None, Square, Circle, Diamond, OpenArrow, ClosedArrow, Butt, ROpenArrow, RClosedArrow, Slash };
const Layer = struct { start: usize, end: usize, fill: bool };
pub const Drawing = struct {
    commands: std.ArrayList(Command) = .empty,
    layers: std.ArrayList(Layer) = .empty,
    pub fn deinit(self: *Drawing, a: std.mem.Allocator) void {
        self.commands.deinit(a);
        self.layers.deinit(a);
    }
    fn finish(self: *Drawing, a: std.mem.Allocator, fill: bool) !void {
        const start = if (self.layers.items.len == 0) 0 else self.layers.items[self.layers.items.len - 1].end;
        try self.layers.append(a, .{ .start = start, .end = self.commands.items.len, .fill = fill });
    }
};
pub const Shape = struct {
    kind: Kind,
    caption: ?captions.Caption = null,
    vertices: []const [2]f64 = &.{},
    origin: [2]f64 = .{ 0, 0 },
    endings: [2]Ending = .{ .None, .None },
    leader: f64 = 0,
    extension: f64 = 0,
    offset: f64 = 0,
    box: [4]f64,
    stroke: ?[3]f64 = null,
    fill: ?[3]f64 = null,
    width: f64 = 1,
    opacity: f64 = 1,
    pattern: dash.Pattern = .{},

    pub fn local(self: Shape, rect: [4]f64) Shape {
        var result = self;
        result.origin = .{ self.origin[0] + rect[0], self.origin[1] + rect[1] };
        for (&result.box, 0..) |*v, i| v.* -= rect[i % 2];
        return result;
    }

    pub fn program(self: Shape, a: std.mem.Allocator) ![]const u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(a);
        try out.appendSlice(a, "q /GS gs\n");
        if (self.stroke) |rgb| try out.print(a, "{d} {d} {d} RG\n", .{ rgb[0], rgb[1], rgb[2] });
        if (self.fill) |rgb| try out.print(a, "{d} {d} {d} rg\n", .{ rgb[0], rgb[1], rgb[2] });
        try out.print(a, "{d} w [", .{self.width});
        for (self.pattern.values[0..self.pattern.count]) |v| try out.print(a, " {d}", .{v});
        try out.appendSlice(a, " ] 0 d\n");
        var geometry = try self.drawing(a);
        defer geometry.deinit(a);
        for (geometry.layers.items) |layer| {
            for (geometry.commands.items[layer.start..layer.end]) |command| switch (command) {
                .move => |p| try out.print(a, "{d} {d} m\n", .{ p[0], p[1] }),
                .line => |p| try out.print(a, "{d} {d} l\n", .{ p[0], p[1] }),
                .curve => |p| try out.print(a, "{d} {d} {d} {d} {d} {d} c\n", .{ p[0], p[1], p[2], p[3], p[4], p[5] }),
                .close => try out.appendSlice(a, "h\n"),
            };
            const stroke = self.stroke != null and self.width > 0;
            try out.appendSlice(a, if (layer.fill and self.fill != null) (if (stroke) "B\n" else "f\n") else (if (stroke) "S\n" else "n\n"));
        }
        if (self.captionLayout()) |placement| try self.caption.?.write(a, &out, placement);
        try out.appendSlice(a, "Q\n");
        return out.toOwnedSlice(a);
    }

    pub fn drawing(self: Shape, a: std.mem.Allocator) !Drawing {
        var out: Drawing = .{};
        errdefer out.deinit(a);
        if (self.vertices.len == 0) {
            var buffer: [6]Command = undefined;
            try out.commands.appendSlice(a, self.path(&buffer));
            try out.finish(a, true);
            return out;
        }
        const points = try a.dupe([2]f64, self.vertices);
        defer a.free(points);
        for (points) |*p| p.* = .{ p[0] - self.origin[0], p[1] - self.origin[1] };
        if (self.kind == .line and self.leader != 0) {
            const t = direction(points[0], points[1]);
            const sign: f64 = if (self.leader < 0) -1 else 1;
            const n: [2]f64 = .{ -t[1] * sign, t[0] * sign };
            for (points) |*p| {
                try out.commands.append(a, .{ .move = add(p.*, n, self.offset) });
                try out.commands.append(a, .{ .line = add(p.*, n, self.offset + @abs(self.leader) + self.extension) });
                p.* = add(p.*, n, self.offset + @abs(self.leader));
            }
        }
        const caption_layout = self.captionLayout();
        if (caption_layout != null and caption_layout.?.gap != null) {
            const gap = caption_layout.?.gap.?;
            const t = direction(points[0], points[1]);
            try out.commands.append(a, .{ .move = points[0] });
            try out.commands.append(a, .{ .line = add(points[0], t, gap[0]) });
            try out.commands.append(a, .{ .move = add(points[0], t, gap[1]) });
            try out.commands.append(a, .{ .line = points[1] });
        } else {
            try out.commands.append(a, .{ .move = points[0] });
            for (points[1..]) |p| try out.commands.append(a, .{ .line = p });
        }
        if (self.kind == .polygon) try out.commands.append(a, .close);
        try out.finish(a, self.kind == .polygon);
        if (self.kind != .polygon) for (self.endings, 0..) |ending, side| {
            if (ending == .None) continue;
            const endpoint = if (side == 0) points[0] else points[points.len - 1];
            var tangent: [2]f64 = .{ 1, 0 };
            // Duplicate endpoint vertices do not change the direction of a marker.
            for (1..points.len) |i| {
                const candidate = points[if (side == 0) i else points.len - 1 - i];
                if (!std.meta.eql(candidate, endpoint)) {
                    tangent = direction(endpoint, candidate);
                    break;
                }
            }
            try self.marker(a, &out, ending, endpoint, tangent);
        };
        return out;
    }
    pub fn captionLayout(self: Shape) ?captions.Layout {
        const caption = self.caption orelse return null;
        var first = add(self.vertices[0], self.origin, -1);
        var last = add(self.vertices[1], self.origin, -1);
        if (self.leader != 0) {
            const t = direction(first, last);
            const n: [2]f64 = .{ -t[1], t[0] };
            const offset = self.leader + (if (self.leader < 0) -self.offset else self.offset);
            first = add(first, n, offset);
            last = add(last, n, offset);
        }
        return caption.layout(first, last, self.width);
    }
    fn marker(self: Shape, a: std.mem.Allocator, out: *Drawing, ending: Ending, p: [2]f64, tangent: [2]f64) !void {
        const w = @max(1, self.width);
        const r = 3 * w;
        var t = tangent;
        if (ending == .ROpenArrow or ending == .RClosedArrow) t = .{ -t[0], -t[1] };
        const n: [2]f64 = .{ -t[1], t[0] };
        var vertices: [4][2]f64 = undefined;
        var count: usize = 0;
        var closed = false;
        switch (ending) {
            .None => unreachable,
            .Circle => {
                const circle = Shape{ .kind = .ellipse, .box = .{ p[0] - r, p[1] - r, p[0] + r, p[1] + r } };
                var buffer: [6]Command = undefined;
                try out.commands.appendSlice(a, circle.path(&buffer));
                try out.finish(a, true);
                return;
            },
            .Square => {
                vertices = .{ .{ p[0] - r, p[1] - r }, .{ p[0] + r, p[1] - r }, .{ p[0] + r, p[1] + r }, .{ p[0] - r, p[1] + r } };
                count = 4;
                closed = true;
            },
            .Diamond => {
                vertices = .{ .{ p[0], p[1] + r }, .{ p[0] + r, p[1] }, .{ p[0], p[1] - r }, .{ p[0] - r, p[1] } };
                count = 4;
                closed = true;
            },
            .OpenArrow, .ClosedArrow, .ROpenArrow, .RClosedArrow => {
                vertices[0] = add(add(p, t, 8.8 * w), n, 4.5 * w);
                vertices[1] = p;
                vertices[2] = add(add(p, t, 8.8 * w), n, -4.5 * w);
                count = 3;
                closed = ending == .ClosedArrow or ending == .RClosedArrow;
            },
            .Butt => {
                vertices[0] = add(p, n, r);
                vertices[1] = add(p, n, -r);
                count = 2;
            },
            .Slash => {
                vertices[0] = add(add(p, t, 2.5 * w), n, 4.330127018922193 * w);
                vertices[1] = add(add(p, t, -2.5 * w), n, -4.330127018922193 * w);
                count = 2;
            },
        }
        try out.commands.append(a, .{ .move = vertices[0] });
        for (vertices[1..count]) |v| try out.commands.append(a, .{ .line = v });
        if (closed) try out.commands.append(a, .close);
        try out.finish(a, closed);
    }
    // Include control hulls, stroke strips and miter joins. Dash gaps cannot
    // enlarge this bound; retaining a small margin also covers invisible paths.
    pub fn bounds(self: Shape, a: std.mem.Allocator) ![4]f64 {
        var geometry = try self.drawing(a);
        defer geometry.deinit(a);
        var box: [4]f64 = .{ std.math.inf(f64), std.math.inf(f64), -std.math.inf(f64), -std.math.inf(f64) };
        var vertices: std.ArrayList([2]f64) = .empty;
        defer vertices.deinit(a);
        for (geometry.commands.items) |command| {
            switch (command) {
                .move => |p| {
                    includeJoins(&box, vertices.items, self.width, false);
                    vertices.clearRetainingCapacity();
                    try vertices.append(a, p);
                    include(&box, p);
                },
                .line => |p| {
                    if (vertices.items.len == 0 or !std.meta.eql(vertices.items[vertices.items.len - 1], p)) try vertices.append(a, p);
                    include(&box, p);
                },
                .curve => |p| {
                    for (0..3) |i| include(&box, .{ p[i * 2], p[i * 2 + 1] });
                    vertices.clearRetainingCapacity();
                },
                .close => {
                    if (vertices.items.len > 1 and std.meta.eql(vertices.items[0], vertices.items[vertices.items.len - 1])) _ = vertices.pop();
                    includeJoins(&box, vertices.items, self.width, true);
                    vertices.clearRetainingCapacity();
                },
            }
        }
        includeJoins(&box, vertices.items, self.width, false);
        if (self.captionLayout()) |placement| {
            // Leave room for the standard-font substitute's outline differences.
            include(&box, .{ placement.bounds[0] - 3, placement.bounds[1] - 3 });
            include(&box, .{ placement.bounds[2] + 3, placement.bounds[3] + 3 });
        }
        const margin = @max(0.05, self.width / 2);
        return .{ box[0] - margin, box[1] - margin, box[2] + margin, box[3] + margin };
    }
    pub fn path(self: Shape, buffer: *[6]Command) []const Command {
        const x0 = self.box[0];
        const y0 = self.box[1];
        const x1 = self.box[2];
        const y1 = self.box[3];
        if (self.kind != .ellipse) {
            buffer[0..5].* = .{ .{ .move = .{ x0, y0 } }, .{ .line = .{ x1, y0 } }, .{ .line = .{ x1, y1 } }, .{ .line = .{ x0, y1 } }, .close };
            return buffer[0..5];
        }
        const cx = (x0 + x1) / 2;
        const cy = (y0 + y1) / 2;
        const rx = (x1 - x0) / 2;
        const ry = (y1 - y0) / 2;
        const k = 0.5522847498307936;
        buffer.* = .{
            .{ .move = .{ cx, y1 } },
            .{ .curve = .{ cx + k * rx, y1, x1, cy + k * ry, x1, cy } },
            .{ .curve = .{ x1, cy - k * ry, cx + k * rx, y0, cx, y0 } },
            .{ .curve = .{ cx - k * rx, y0, x0, cy - k * ry, x0, cy } },
            .{ .curve = .{ x0, cy + k * ry, cx - k * rx, y1, cx, y1 } },
            .close,
        };
        return buffer;
    }
};
fn add(p: [2]f64, v: [2]f64, scale: f64) [2]f64 {
    return .{ p[0] + v[0] * scale, p[1] + v[1] * scale };
}
fn direction(p: [2]f64, q: [2]f64) [2]f64 {
    const dx = q[0] - p[0];
    const dy = q[1] - p[1];
    const length = @sqrt(dx * dx + dy * dy);
    return if (length == 0) .{ 1, 0 } else .{ dx / length, dy / length };
}
fn include(box: *[4]f64, p: [2]f64) void {
    box.* = .{ @min(box[0], p[0]), @min(box[1], p[1]), @max(box[2], p[0]), @max(box[3], p[1]) };
}
fn includeJoins(box: *[4]f64, vertices: []const [2]f64, width: f64, closed: bool) void {
    if (vertices.len < 3) return;
    for (vertices, 0..) |p, i| {
        if (!closed and (i == 0 or i + 1 == vertices.len)) continue;
        const previous = vertices[(i + vertices.len - 1) % vertices.len];
        const next = vertices[(i + 1) % vertices.len];
        if (std.meta.eql(previous, p) or std.meta.eql(next, p)) continue;
        const u = direction(previous, p);
        const v = direction(p, next);
        const dot = u[0] * v[0] + u[1] * v[1];
        if (1 + dot < 0.02) continue; // PDF's default miter limit is ten.
        const m: [2]f64 = .{ -(u[1] + v[1]) * width / (2 * (1 + dot)), (u[0] + v[0]) * width / (2 * (1 + dot)) };
        include(box, add(p, m, 1));
        include(box, add(p, m, -1));
    }
}
fn dictionary(a: std.mem.Allocator, entries: []const s.Entry) !s.Value {
    return .{ .dict = try a.dupe(s.Entry, entries) };
}
pub fn resources(a: std.mem.Allocator, opacity: f64, caption: bool) !s.Value {
    const gs = try dictionary(a, &.{ .{ .key = "CA", .value = .{ .real = opacity } }, .{ .key = "ca", .value = .{ .real = opacity } } });
    const states = try dictionary(a, &.{.{ .key = "GS", .value = gs }});
    if (!caption) return dictionary(a, &.{.{ .key = "ExtGState", .value = states }});
    const font = try dictionary(a, &.{.{ .key = "Caption", .value = try captions.fontResource(a) }});
    return dictionary(a, &.{ .{ .key = "ExtGState", .value = states }, .{ .key = "Font", .value = font } });
}
fn sameValue(doc: *d.Document, expected: s.Value, input: s.Value, references: bool) anyerror!bool {
    // A retained font/program reference must stay the exact resource selected by DA.
    if (references and expected == .ref) return input == .ref and std.meta.eql(expected.ref, input.ref);
    const actual = if (references) try doc.resolve(input) else input;
    switch (expected) {
        .integer, .real => {
            if (actual != .integer and actual != .real) return false;
            const v = try s.number(actual);
            return std.math.isFinite(v) and @abs(v - try s.number(expected)) <= 1e-7;
        },
        .array => |values| {
            if (actual != .array or actual.array.len != values.len) return false;
            for (values, actual.array) |left, right| if (!try sameValue(doc, left, right, references)) return false;
            return true;
        },
        .dict => |entries| {
            if (actual != .dict or actual.dict.len != entries.len) return false;
            for (entries) |entry| if (!try sameValue(doc, entry.value, s.get(actual, entry.key) orelse return false, references)) return false;
            return true;
        },
        .string => |v| return actual == .string and std.mem.eql(u8, v, actual.string),
        .name => |v| return actual == .name and std.mem.eql(u8, v, actual.name),
        .null => return actual == .null,
        .boolean => |v| return actual == .boolean and actual.boolean == v,
        else => return false,
    }
}
fn sameProgram(doc: *d.Document, expected: []const u8, actual: []const u8) !bool {
    var left = s.Parser{ .bytes = expected, .allocator = doc.allocator() };
    var right = s.Parser{ .bytes = actual, .allocator = doc.allocator() };
    while (true) {
        left.skip();
        right.skip();
        if (left.pos == left.bytes.len) return right.pos == right.bytes.len;
        const first = left.bytes[left.pos];
        if (std.ascii.isDigit(first) or first == '-' or first == '.' or first == '/' or first == '[' or first == '(' or first == '<') {
            if (!try sameValue(doc, try left.value(), try right.value(), false)) return false;
        } else if (!right.keyword(try left.token())) return false;
    }
}
// A marker alone cannot authorize replacing artwork changed by another editor.
pub fn canonical(doc: *d.Document, value: s.Value) !bool {
    const marker = try optional(doc, value, "PodShapeAppearance") orelse return false;
    if (marker != .integer or marker.integer != 1) return false;
    const shape = try load(doc, value);
    return matchesAppearance(doc, value, "PodShapeAppearance", try resources(doc.allocator(), shape.opacity, shape.caption != null), try shape.local(try d.rectangle(try optional(doc, value, "Rect") orelse return false)).program(doc.allocator()));
}
// Shared validation for regenerable appearances; never trust a producer marker alone.
pub fn matchesAppearance(doc: *d.Document, value: s.Value, marker_key: []const u8, expected_resources: s.Value, expected_program: []const u8) !bool {
    const marker = try optional(doc, value, marker_key) orelse return false;
    if (marker != .integer or marker.integer != 1) return false;
    const rect = try d.rectangle(try optional(doc, value, "Rect") orelse return false);
    const ap = try optional(doc, value, "AP") orelse return false;
    if (ap != .dict or ap.dict.len != 1) return false;
    const normal = s.get(ap, "N") orelse return false;
    if (normal != .ref) return false;
    const form = try doc.object(normal.ref);
    if (form.value != .dict) return false;
    for (form.value.dict) |entry| {
        var allowed = false;
        for ([_][]const u8{ "Type", "Subtype", "BBox", "Resources", "Length", "Filter", "DecodeParms" }) |key| {
            if (std.mem.eql(u8, entry.key, key)) allowed = true;
        }
        if (!allowed) return false;
    }
    if (!try sameValue(doc, .{ .name = "XObject" }, s.get(form.value, "Type") orelse return false, true) or
        !try sameValue(doc, .{ .name = "Form" }, s.get(form.value, "Subtype") orelse return false, true)) return false;
    var box = [_]s.Value{ .{ .integer = 0 }, .{ .integer = 0 }, .{ .real = rect[2] - rect[0] }, .{ .real = rect[3] - rect[1] } };
    if (!try sameValue(doc, .{ .array = &box }, s.get(form.value, "BBox") orelse return false, true)) return false;
    if (!try sameValue(doc, expected_resources, s.get(form.value, "Resources") orelse return false, true)) return false;
    return sameProgram(doc, expected_program, try @import("ink_appearance.zig").stream(doc, form, 1024 * 1024));
}
fn optional(doc: *d.Document, value: s.Value, key: []const u8) !?s.Value {
    const result = try doc.resolve(s.get(value, key) orelse .null);
    return if (result == .null) null else result;
}
fn number(doc: *d.Document, value: s.Value) !f64 {
    const result = try s.number(try doc.resolve(value));
    if (!std.math.isFinite(result) or @abs(result) > 1e6) return error.InvalidAnnotationStyle;
    return result;
}
fn color(doc: *d.Document, value: s.Value) !?[3]f64 {
    if (value != .array) return error.InvalidAnnotationStyle;
    if (value.array.len == 0) return null;
    if (value.array.len != 1 and value.array.len != 3) return error.UnsupportedColorSpace;
    var result: [3]f64 = undefined;
    for (&result, 0..) |*channel, i| {
        channel.* = try number(doc, value.array[if (value.array.len == 1) 0 else i]);
        if (channel.* < 0 or channel.* > 1) return error.InvalidAnnotationStyle;
    }
    return result;
}
pub fn load(doc: *d.Document, value: s.Value) !Shape {
    const subtype = try optional(doc, value, "Subtype") orelse return error.UnsupportedAnnotation;
    if (subtype != .name) return error.UnsupportedAnnotation;
    const kind: Kind = if (std.mem.eql(u8, subtype.name, "Circle")) .ellipse else if (std.mem.eql(u8, subtype.name, "Square")) .rectangle else if (std.mem.eql(u8, subtype.name, "Line")) .line else if (std.mem.eql(u8, subtype.name, "PolyLine")) .polyline else if (std.mem.eql(u8, subtype.name, "Polygon")) .polygon else return error.MissingAnnotationAppearance;
    const rect = try d.rectangle(try optional(doc, value, "Rect") orelse return error.InvalidAnnotationGeometry);
    for (rect) |v| if (!std.math.isFinite(v) or @abs(v) > 1e6) return error.InvalidAnnotationGeometry;
    var result = Shape{ .kind = kind, .box = rect };
    if (try optional(doc, value, "C")) |v| result.stroke = try color(doc, v);
    if (try optional(doc, value, "IC")) |v| result.fill = try color(doc, v);
    if (try optional(doc, value, "CA")) |v| result.opacity = try number(doc, v);
    if (result.opacity < 0 or result.opacity > 1) return error.InvalidAnnotationStyle;
    if (try optional(doc, value, "BS")) |border| {
        if (border != .dict) return error.InvalidAnnotationStyle;
        if (try optional(doc, border, "W")) |v| result.width = try number(doc, v);
        if (try optional(doc, border, "S")) |v| {
            if (v != .name) return error.InvalidAnnotationStyle;
            if (std.mem.eql(u8, v.name, "D")) {
                var default_dash = [_]s.Value{.{ .integer = 3 }};
                result.pattern = try dash.Pattern.parse(doc, (try optional(doc, border, "D")) orelse .{ .array = &default_dash }, .{ .integer = 0 });
            } else if (!std.mem.eql(u8, v.name, "S")) return error.UnsupportedAnnotationAppearance;
        }
    } else if (try optional(doc, value, "Border")) |border| {
        if (border != .array or (border.array.len != 3 and border.array.len != 4)) return error.InvalidAnnotationStyle;
        if (try number(doc, border.array[0]) != 0 or try number(doc, border.array[1]) != 0) return error.UnsupportedAnnotationAppearance;
        result.width = try number(doc, border.array[2]);
        if (border.array.len == 4) result.pattern = try dash.Pattern.parse(doc, border.array[3], .{ .integer = 0 });
    }
    if (result.width < 0) return error.InvalidAnnotationStyle;
    if (try optional(doc, value, "BE")) |effect| {
        if (effect != .dict) return error.InvalidAnnotationStyle;
        if (try optional(doc, effect, "S")) |v| if (v != .name or !std.mem.eql(u8, v.name, "S")) return error.UnsupportedAnnotationAppearance;
    }
    if (kind == .line or kind == .polyline or kind == .polygon) {
        const raw = try optional(doc, value, if (kind == .line) "L" else "Vertices") orelse return error.InvalidAnnotationGeometry;
        if (raw != .array or raw.array.len % 2 != 0 or raw.array.len > 8192 or raw.array.len < (if (kind == .polygon) @as(usize, 6) else 4) or (kind == .line and raw.array.len != 4)) return error.InvalidAnnotationGeometry;
        const points = try doc.allocator().alloc([2]f64, raw.array.len / 2);
        for (points, 0..) |*point, i| point.* = .{ try number(doc, raw.array[i * 2]), try number(doc, raw.array[i * 2 + 1]) };
        result.vertices = points;
        if (kind != .polygon) if (try optional(doc, value, "LE")) |ends| {
            if (ends != .array or ends.array.len != 2) return error.InvalidAnnotationStyle;
            for (&result.endings, ends.array) |*ending, input| {
                const v = try doc.resolve(input);
                if (v != .name) return error.InvalidAnnotationStyle;
                ending.* = std.meta.stringToEnum(Ending, v.name) orelse return error.UnsupportedAnnotationAppearance;
            }
        };
        if (kind == .line) {
            if (try captions.enabled(doc, value)) result.caption = try captions.load(doc, value);
            if (try optional(doc, value, "LL")) |v| result.leader = try number(doc, v);
            if (try optional(doc, value, "LLE")) |v| {
                if (try optional(doc, value, "LL") == null) return error.InvalidAnnotationStyle;
                result.extension = try number(doc, v);
            }
            if (try optional(doc, value, "LLO")) |v| result.offset = try number(doc, v);
            if (result.extension < 0 or result.offset < 0) return error.InvalidAnnotationStyle;
        }
        return result;
    }
    var insets: [4]f64 = @splat(result.width / 2);
    if (try optional(doc, value, "RD")) |v| {
        if (v != .array or v.array.len != 4) return error.InvalidAnnotationGeometry;
        var rd: [4]f64 = undefined;
        for (&rd, v.array) |*offset, item| {
            offset.* = try number(doc, item);
            if (offset.* < 0) return error.InvalidAnnotationGeometry;
        }
        if (rd[0] + rd[2] >= rect[2] - rect[0] or rd[1] + rd[3] >= rect[3] - rect[1]) return error.InvalidAnnotationGeometry;
        // RD follows the four Rect coordinates in interoperable PDF implementations.
        for (&insets, rd) |*inset, offset| inset.* = @max(inset.*, offset);
    }
    result.box = .{ rect[0] + insets[0], rect[1] + insets[1], rect[2] - insets[2], rect[3] - insets[3] };
    if (result.box[2] <= result.box[0] or result.box[3] <= result.box[1]) return error.InvalidAnnotationGeometry;
    return result;
}
