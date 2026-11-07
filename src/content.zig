const std = @import("std");
const d = @import("document.zig");
const s = @import("syntax.zig");
const color = @import("color.zig");
const blend = @import("blend.zig");
const images = @import("images.zig");
const pdf_font = @import("pdf_font.zig");
pub const Matrix = [6]f64;
const identity: Matrix = .{ 1, 0, 0, 1, 0, 0 };
pub fn multiply(a: Matrix, b: Matrix) Matrix {
    return .{ a[0] * b[0] + a[1] * b[2], a[0] * b[1] + a[1] * b[3], a[2] * b[0] + a[3] * b[2], a[2] * b[1] + a[3] * b[3], a[4] * b[0] + a[5] * b[2] + b[4], a[4] * b[1] + a[5] * b[3] + b[5] };
}
fn move(m: *Matrix, x: f64, y: f64) void {
    m.* = multiply(.{ 1, 0, 0, 1, x, y }, m.*);
}
pub const State = struct {
    fill: color.Color = .{},
    stroke: color.Color = .{},
    width: f64 = 1,
    cap: u8 = 0,
    join: u8 = 0,
    miter: f64 = 10,
    dash: @import("dash.zig").Pattern = .{},
    fill_alpha: f64 = 1,
    stroke_alpha: f64 = 1,
    blend_mode: blend.Mode = .normal,
    text_knockout: bool = true,
    ctm: Matrix = identity,
    size: f64 = 0,
    char: f64 = 0,
    word: f64 = 0,
    scale: f64 = 1,
    leading: f64 = 0,
    rise: f64 = 0,
    mode: i64 = 0,
    font: ?*const pdf_font.Font = null,
};
pub const Run = struct { font: *const pdf_font.Font, bounds: [4]f64 = .{ 0, 0, 0, 0 }, id: usize, text: []const u8, x: f64, y: f64, font_size: f64, advance: f64, object_id: u32, start: usize, end: usize, char_space: f64, word_space: f64, scale: f64 };
fn same(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
fn arity(values: []s.Value, n: usize) !void {
    if (values.len != n) return error.InvalidOperands;
}
fn num(v: s.Value) !f64 {
    const n = try s.number(v);
    if (!std.math.isFinite(n) or @abs(n) > 1e12) return error.InvalidNumber;
    return n;
}
fn strokeSetting(state: *State, key: []const u8, value: s.Value) !void {
    const n = try num(value);
    if (same(key, "LW")) {
        if (n < 0 or n > 1e6) return error.UnsupportedStroke;
        state.width = n;
    } else if (same(key, "ML")) {
        if (n < 1 or n > 1e6) return error.UnsupportedStroke;
        state.miter = n;
    } else {
        if (n != 0 and n != 1 and n != 2) return error.UnsupportedStroke;
        if (same(key, "LC")) state.cap = @intFromFloat(n) else state.join = @intFromFloat(n);
    }
}
fn blendMode(doc: *d.Document, value: s.Value) !blend.Mode {
    if (value == .array) {
        var selected: ?blend.Mode = null;
        for (value.array) |raw| {
            const item = try doc.resolve(raw);
            if (item != .name) return error.InvalidGraphicsState;
            if (selected == null) selected = blend.fromName(item.name);
        }
        return selected orelse .normal;
    }
    if (value != .name) return error.InvalidGraphicsState;
    return blend.fromName(value.name) orelse return error.UnsupportedBlendMode;
}
fn graphicsState(doc: *d.Document, resources: s.Value, name: []const u8, state: *State, in_text: bool) !void {
    const resource_dict = try doc.resolve(resources);
    const states = try doc.resolve(s.get(resource_dict, "ExtGState") orelse return error.MissingGraphicsState);
    if (states != .dict) return error.InvalidGraphicsState;
    const value = try doc.resolve(s.get(states, name) orelse return error.MissingGraphicsState);
    if (value != .dict) return error.InvalidGraphicsState;
    for (value.dict) |entry| {
        const key = entry.key;
        const v = try doc.resolve(entry.value);
        if (v == .null) continue;
        if (same(key, "LW") or same(key, "LC") or same(key, "LJ") or same(key, "ML")) {
            try strokeSetting(state, key, v);
        } else if (same(key, "ca") or same(key, "CA")) {
            const alpha = try num(v);
            if (alpha < 0 or alpha > 1) return error.InvalidGraphicsState;
            if (same(key, "ca")) state.fill_alpha = alpha else state.stroke_alpha = alpha;
        } else if (same(key, "BM")) {
            state.blend_mode = try blendMode(doc, v);
        } else if (same(key, "TK")) {
            if (in_text or v != .boolean) return error.InvalidGraphicsState;
            state.text_knockout = v.boolean;
        } else if (same(key, "Font")) {
            if (v != .array or v.array.len != 2 or v.array[0] != .ref) return error.InvalidGraphicsState;
            const size = try num(try doc.resolve(v.array[1]));
            if (size <= 0) return error.UnsupportedTextState;
            state.font = try pdf_font.loadValue(doc, v.array[0]);
            state.size = size;
        } else if (same(key, "Type")) {
            if (v != .name or !same(v.name, "ExtGState")) return error.InvalidGraphicsState;
        } else if (same(key, "SMask")) {
            if (v != .name or !same(v.name, "None")) return error.UnsupportedSoftMask;
        } else if (same(key, "AIS") or same(key, "OP") or same(key, "op") or same(key, "SA")) {
            if (v != .boolean) return error.InvalidGraphicsState;
            if (v.boolean) return error.UnsupportedGraphicsState;
        } else if (same(key, "OPM")) {
            if (v != .integer or v.integer != 0) return error.UnsupportedGraphicsState;
        } else if (same(key, "RI")) {
            if (v != .name or !same(v.name, "RelativeColorimetric")) return error.UnsupportedRenderingIntent;
        } else if (same(key, "D")) {
            if (v != .array or v.array.len != 2) return error.InvalidGraphicsState;
            state.dash = try @import("dash.zig").Pattern.parse(doc, v.array[0], v.array[1]);
        } else return error.UnsupportedGraphicsState;
    }
}
fn characterAdvance(code: pdf_font.Code, state: State) f64 {
    const font = state.font.?;
    const displacement = if (font.vertical()) font.verticalMetrics(code)[0] else font.width(code);
    return (state.size * displacement / 1000 + state.char + (if (font.wordSpacing(code)) state.word else @as(f64, 0))) * (if (font.vertical()) 1 else state.scale);
}
fn advance(text: []const u8, state: State) !f64 {
    var width: f64 = 0;
    var at: usize = 0;
    while (try state.font.?.nextCode(text, &at)) |c| {
        try state.font.?.validateGlyph(c);
        width += characterAdvance(c, state);
    }
    if (!std.math.isFinite(width) or @abs(width) > 1e12) return error.InvalidTextAdvance;
    return width;
}
pub const Sink = struct {
    context: *anyopaque,
    operator: *const fn (*anyopaque, []const u8, []s.Value, State) anyerror!void,
    glyph: *const fn (*anyopaque, pdf_font.Code, Matrix, State) anyerror!void,
    glyph_run: ?*const fn (*anyopaque, bool, State) anyerror!void = null,
    image: ?*const fn (*anyopaque, images.Image, State) anyerror!void = null,
    form: ?*const fn (*anyopaque, bool, [4]f64, State) anyerror!void = null,
};
const Execution = struct {
    runs: std.ArrayList(Run) = .empty,
    uses: ?*std.ArrayList(u32) = null,
    text_bytes: usize = 0,
    parsed_bytes: usize = 0,
    nodes: usize = 0,
    operators: usize = 0,
    invocations: usize = 0,
    image_bytes: usize = 0,
    active: [64]u32 = undefined,
    depth: usize = 0,
};
pub fn inspect(doc: *d.Document, page: *d.Page) anyerror![]Run {
    var uses: std.ArrayList(u32) = .empty;
    const runs = try interpretImpl(doc, page, null, doc.allocator(), &uses);
    page.content_uses = try uses.toOwnedSlice(doc.allocator());
    return runs;
}
pub fn interpret(doc: *d.Document, page: *d.Page, sink: ?Sink) anyerror![]Run {
    return interpretAllocated(doc, page, sink, doc.allocator());
}
pub fn interpretAllocated(doc: *d.Document, page: *d.Page, sink: ?Sink, a: std.mem.Allocator) anyerror![]Run {
    return interpretImpl(doc, page, sink, a, null);
}
fn interpretImpl(doc: *d.Document, page: *d.Page, sink: ?Sink, a: std.mem.Allocator, uses: ?*std.ArrayList(u32)) ![]Run {
    var execution = Execution{ .uses = uses };
    const initial_color = try color.Color.initial(try color.load(doc, page.resources, "DeviceGray"));
    try interpretStreams(doc, page.resources, page.contents, .{ .fill = initial_color, .stroke = initial_color }, sink, a, &execution);
    return execution.runs.toOwnedSlice(a);
}
fn interpretStreams(doc: *d.Document, resources: s.Value, ids: []const u32, initial: State, sink: ?Sink, a: std.mem.Allocator, execution: *Execution) anyerror!void {
    var stack: std.ArrayList(State) = .empty;
    defer stack.deinit(a);
    var state = initial;
    var tm = identity;
    var line = identity;
    var in_text = false;
    for (ids) |id| {
        const object = try doc.object(.{ .id = id, .generation = doc.entries[id].generation });
        const bytes = try doc.streamData(object);
        if (bytes.len > 256 * 1024 * 1024 -| execution.parsed_bytes) return error.ContentWorkLimit;
        execution.parsed_bytes += bytes.len;
        if (execution.uses) |uses| try uses.append(a, id);
        var p = s.Parser{ .bytes = bytes, .allocator = a };
        var values: std.ArrayList(s.Value) = .empty;
        defer values.deinit(a);
        p.skip();
        var start = p.pos;
        while (p.pos < bytes.len) {
            const c = bytes[p.pos];
            if (c == '/' or c == '(' or c == '<' or c == '[' or c == '+' or c == '-' or c == '.' or (c >= '0' and c <= '9')) {
                if (values.items.len >= 128) return error.OperandLimit;
                const before = p.nodes;
                try values.append(a, try p.value());
                execution.nodes += p.nodes - before;
                if (execution.nodes > 1000000) return error.ContentWorkLimit;
                p.skip();
                continue;
            }
            execution.operators += 1;
            if (execution.operators > 1000000) return error.ContentWorkLimit;
            const op = try p.token();
            const v = values.items;
            doc.context.object_id = id;
            doc.context.operator = op;
            if (sink) |target| try target.operator(target.context, op, v, state);
            if (same(op, "BT")) {
                try arity(v, 0);
                if (in_text) return error.InvalidTextObject;
                in_text = true;
                tm = identity;
                line = identity;
            } else if (same(op, "ET")) {
                try arity(v, 0);
                if (!in_text) return error.InvalidTextObject;
                in_text = false;
            } else if (same(op, "q")) {
                try arity(v, 0);
                if (stack.items.len >= 64) return error.GraphicsStackLimit;
                try stack.append(a, state);
            } else if (same(op, "Q")) {
                try arity(v, 0);
                state = stack.pop() orelse return error.GraphicsStackUnderflow;
            } else if (same(op, "BI")) {
                try arity(v, 0);
                if (in_text) return error.InvalidTextObject;
                var scratch = std.heap.ArenaAllocator.init(doc.arena.child_allocator);
                defer scratch.deinit();
                const before = p.nodes;
                const image = try @import("inline_image.zig").read(doc, &p, resources, scratch.allocator());
                execution.nodes += p.nodes - before;
                if (execution.nodes > 1000000) return error.ContentWorkLimit;
                try emitImage(image, state, sink, execution);
            } else if (same(op, "Do")) {
                try arity(v, 1);
                if (in_text) return error.InvalidTextObject;
                if (v[0] != .name) return error.InvalidOperands;
                try invokeXObject(doc, resources, v[0].name, state, sink, a, execution);
            } else if (same(op, "gs")) {
                try arity(v, 1);
                if (v[0] != .name) return error.InvalidOperands;
                try graphicsState(doc, resources, v[0].name, &state, in_text);
            } else if (same(op, "d")) {
                try arity(v, 2);
                state.dash = try @import("dash.zig").Pattern.parse(doc, v[0], v[1]);
            } else if (same(op, "w") or same(op, "J") or same(op, "j") or same(op, "M")) {
                try arity(v, 1);
                try strokeSetting(&state, if (same(op, "w")) "LW" else if (same(op, "J")) "LC" else if (same(op, "j")) "LJ" else "ML", v[0]);
            } else if (same(op, "ri")) {
                try arity(v, 1);
                if (v[0] != .name or !same(v[0].name, "RelativeColorimetric")) return error.UnsupportedRenderingIntent;
            } else if (same(op, "CS") or same(op, "cs")) {
                try arity(v, 1);
                if (v[0] != .name) return error.InvalidOperands;
                const selected = try color.Color.initial(try color.load(doc, resources, v[0].name));
                if (same(op, "cs")) state.fill = selected else state.stroke = selected;
            } else if (same(op, "SC") or same(op, "SCN") or same(op, "sc") or same(op, "scn")) {
                if (op[0] == 's') try state.fill.set(v) else try state.stroke.set(v);
            } else if (same(op, "g") or same(op, "G") or same(op, "rg") or same(op, "RG")) {
                const space = try color.load(doc, resources, if (op.len == 1) "DeviceGray" else "DeviceRGB");
                var selected = try color.Color.initial(space);
                try selected.set(v);
                if (op[0] == 'g' or op[0] == 'r') state.fill = selected else state.stroke = selected;
            } else if (same(op, "k") or same(op, "K")) {
                try arity(v, 4);
                for (v) |item| _ = try num(item);
                // Preserve text-only inspection of CMYK content.
                if (sink != null) return error.UnsupportedColorSpace;
            } else if (same(op, "cm")) {
                try arity(v, 6);
                var m: Matrix = undefined;
                for (v, 0..) |n, i| m[i] = try num(n);
                state.ctm = multiply(m, state.ctm);
                try validateMatrix(state.ctm);
            } else if (same(op, "Tf")) {
                try arity(v, 2);
                if (v[0] != .name) return error.InvalidOperands;
                state.font = try pdf_font.load(doc, resources, v[0].name);
                state.size = try num(v[1]);
                if (state.size <= 0) return error.UnsupportedTextState;
            } else if (same(op, "Tm")) {
                try arity(v, 6);
                if (!in_text) return error.InvalidTextObject;
                for (v, 0..) |n, i| tm[i] = try num(n);
                line = tm;
            } else if (same(op, "Td") or same(op, "TD")) {
                try arity(v, 2);
                if (!in_text) return error.InvalidTextObject;
                const x = try num(v[0]);
                const y = try num(v[1]);
                if (same(op, "TD")) state.leading = -y;
                move(&line, x, y);
                tm = line;
            } else if (same(op, "T*")) {
                try arity(v, 0);
                if (!in_text) return error.InvalidTextObject;
                move(&line, 0, -state.leading);
                tm = line;
            } else if (same(op, "Tc") or same(op, "Tw") or same(op, "Tz") or same(op, "TL") or same(op, "Ts") or same(op, "Tr")) {
                try arity(v, 1);
                const n = try num(v[0]);
                if (same(op, "Tc")) state.char = n else if (same(op, "Tw")) state.word = n else if (same(op, "Tz")) {
                    if (n <= 0) return error.UnsupportedTextState;
                    state.scale = n / 100;
                } else if (same(op, "TL")) state.leading = n else if (same(op, "Ts")) state.rise = n else {
                    if (v[0] != .integer or v[0].integer < 0 or v[0].integer > 3) return error.UnsupportedTextRendering;
                    state.mode = v[0].integer;
                }
            } else if (same(op, "Tj") or same(op, "TJ")) {
                try arity(v, 1);
                if (!in_text or state.font == null) return error.InvalidTextObject;
                var text: std.ArrayList(u8) = .empty;
                var width: f64 = 0;
                var bounds: [4]f64 = .{ std.math.inf(f64), std.math.inf(f64), -std.math.inf(f64), -std.math.inf(f64) };
                if (same(op, "Tj")) {
                    if (v[0] != .string) return error.InvalidOperands;
                    try state.font.?.decode(a, v[0].string, &text);
                    width = try advance(v[0].string, state);
                    try emitText(v[0].string, 0, tm, state, sink, &bounds);
                } else {
                    if (v[0] != .array) return error.InvalidOperands;
                    for (v[0].array) |item| {
                        if (item == .string) {
                            try state.font.?.decode(a, item.string, &text);
                            try emitText(item.string, width, tm, state, sink, &bounds);
                            width += try advance(item.string, state);
                        } else if (item == .integer or item == .real) width -= (try num(item)) * state.size * (if (state.font.?.vertical()) 1 else state.scale) / 1000 else return error.InvalidOperands;
                    }
                }
                if (!std.math.isFinite(width) or @abs(width) > 1e12) return error.InvalidTextAdvance;
                if (text.items.len > pdf_font.max_decoded_text -| execution.text_bytes) return error.TextLimit;
                execution.text_bytes += text.items.len;
                const transform = multiply(tm, state.ctm);
                const x = transform[4] + state.rise * transform[2];
                const y = transform[5] + state.rise * transform[3];
                if (!std.math.isFinite(x) or !std.math.isFinite(y)) return error.InvalidTransform;
                if (!std.math.isFinite(bounds[0])) bounds = .{ x, y, x, y };
                try execution.runs.append(a, .{ .font = state.font.?, .bounds = bounds, .id = execution.runs.items.len, .text = try text.toOwnedSlice(a), .x = x, .y = y, .font_size = state.size, .advance = width, .object_id = id, .start = start, .end = p.pos, .char_space = state.char, .word_space = state.word, .scale = state.scale });
                if (state.font.?.vertical()) move(&tm, 0, width) else move(&tm, width, 0);
            } else {
                // These graphics operators cannot change text positioning or font selection.
                const count: ?usize = if (same(op, "m") or same(op, "l")) 2 else if (same(op, "c")) 6 else if (same(op, "v") or same(op, "y") or same(op, "re")) 4 else if (same(op, "h") or same(op, "S") or same(op, "s") or same(op, "f") or same(op, "F") or same(op, "f*") or same(op, "B") or same(op, "B*") or same(op, "b") or same(op, "b*") or same(op, "n") or same(op, "W") or same(op, "W*")) 0 else null;
                if (count) |n| {
                    if (in_text) return error.InvalidTextObject;
                    try arity(v, n);
                    for (v) |item| _ = try num(item);
                } else return error.UnsupportedOperator;
            }
            values.clearRetainingCapacity();
            p.skip();
            start = p.pos;
        }
        if (values.items.len != 0) return error.InvalidOperands;
    }
    if (in_text) return error.UnclosedTextObject;
    if (stack.items.len != 0) return error.UnclosedGraphicsState;
}
fn validateMatrix(matrix: Matrix) !void {
    for (matrix) |n| if (!std.math.isFinite(n) or @abs(n) > 1e12) return error.InvalidTransform;
}
fn formNumbers(comptime count: usize, doc: *d.Document, value: s.Value) ![count]f64 {
    const resolved = try doc.resolve(value);
    if (resolved != .array or resolved.array.len != count) return error.InvalidForm;
    var result: [count]f64 = undefined;
    for (&result, resolved.array) |*n, v| n.* = try num(try doc.resolve(v));
    return result;
}
pub const Form = struct { id: u32, bbox: [4]f64, matrix: Matrix, resources: s.Value };
pub fn loadForm(doc: *d.Document, input: s.Value, resources: s.Value) !Form {
    var reference = input;
    var object: *d.Object = undefined;
    var id: u32 = undefined;
    var links: usize = 0;
    while (true) {
        if (reference != .ref) return error.InvalidXObject;
        if (links >= 64) return error.ReferenceLimit;
        links += 1;
        id = reference.ref.id;
        object = try doc.object(reference.ref);
        if (object.value != .ref) break;
        reference = object.value;
    }
    const value = object.value;
    if (value != .dict or (object.stream == null and object.changed == null)) return error.InvalidXObject;
    const subtype = try doc.resolve(s.get(value, "Subtype") orelse return error.InvalidXObject);
    if (subtype != .name) return error.InvalidXObject;
    if (!same(subtype.name, "Form")) return error.UnsupportedXObject;
    if (s.get(value, "Type")) |raw| {
        const v = try doc.resolve(raw);
        if (v != .null and (v != .name or !same(v.name, "XObject"))) return error.InvalidForm;
    }
    if (s.get(value, "FormType")) |raw| {
        const v = try doc.resolve(raw);
        if (v != .null and (v != .integer or v.integer != 1)) return error.InvalidForm;
    }
    for ([_][]const u8{ "Group", "Ref", "OPI", "OC" }) |key| {
        if (s.get(value, key)) |raw| if (try doc.resolve(raw) != .null) return error.UnsupportedForm;
    }
    const box = try formNumbers(4, doc, s.get(value, "BBox") orelse return error.InvalidForm);
    for (box) |n| if (@abs(n) > 1e6) return error.InvalidForm;
    const bbox: [4]f64 = .{ @min(box[0], box[2]), @min(box[1], box[3]), @max(box[0], box[2]), @max(box[1], box[3]) };
    var matrix = identity;
    if (s.get(value, "Matrix")) |raw| {
        if (try doc.resolve(raw) != .null) matrix = try formNumbers(6, doc, raw);
    }
    try validateMatrix(matrix);
    var local = resources;
    if (s.get(value, "Resources")) |raw| {
        const v = try doc.resolve(raw);
        if (v != .null) {
            if (v != .dict) return error.InvalidForm;
            local = v;
        }
    }
    return .{ .id = id, .bbox = bbox, .matrix = matrix, .resources = local };
}
fn invokeXObject(doc: *d.Document, resources: s.Value, name: []const u8, state: State, sink: ?Sink, a: std.mem.Allocator, execution: *Execution) anyerror!void {
    const objects = try doc.resolve(s.get(try doc.resolve(resources), "XObject") orelse return error.MissingXObject);
    if (objects != .dict) return error.InvalidXObject;
    const reference = s.get(objects, name) orelse return error.MissingXObject;
    var raw = reference;
    var object: *d.Object = undefined;
    var links: usize = 0;
    while (true) {
        if (raw != .ref) return error.InvalidXObject;
        if (links >= 64) return error.ReferenceLimit;
        links += 1;
        object = try doc.object(raw.ref);
        if (object.value != .ref) break;
        raw = object.value;
    }
    if (object.value != .dict or (object.stream == null and object.changed == null)) return error.InvalidXObject;
    const subtype = try doc.resolve(s.get(object.value, "Subtype") orelse return error.InvalidXObject);
    if (subtype == .name and same(subtype.name, "Image")) {
        const image = try images.load(doc, object, resources);
        try emitImage(image, state, sink, execution);
        return;
    }
    return executeForm(doc, try loadForm(doc, reference, resources), state, sink, a, execution);
}
fn emitImage(image: images.Image, state: State, sink: ?Sink, execution: *Execution) !void {
    const size = image.width * image.height * 4 + if (image.alpha_image) |mask| mask.width * mask.height * 4 else @as(usize, 0);
    if (size > 256 * 1024 * 1024 -| execution.image_bytes) return error.ImageWorkLimit;
    execution.image_bytes += size;
    execution.invocations += 1;
    if (execution.invocations > 16384) return error.ContentWorkLimit;
    if (sink) |target| {
        if (target.image) |callback| try callback(target.context, image, state) else return error.UnsupportedImageSink;
    }
}
pub fn interpretFormAllocated(doc: *d.Document, form: Form, placement: Matrix, sink: ?Sink, a: std.mem.Allocator) ![]Run {
    var execution = Execution{};
    const initial_color = try color.Color.initial(try color.load(doc, form.resources, "DeviceGray"));
    try executeForm(doc, form, .{ .ctm = placement, .fill = initial_color, .stroke = initial_color }, sink, a, &execution);
    return execution.runs.toOwnedSlice(a);
}
fn executeForm(doc: *d.Document, form: Form, state: State, sink: ?Sink, a: std.mem.Allocator, execution: *Execution) anyerror!void {
    const id = form.id;
    var child = state;
    child.ctm = multiply(form.matrix, state.ctm);
    try validateMatrix(child.ctm);
    if (execution.depth >= execution.active.len) return error.FormDepthLimit;
    for (execution.active[0..execution.depth]) |active| if (active == id) return error.CyclicForm;
    execution.invocations += 1;
    if (execution.invocations > 16384) return error.ContentWorkLimit;
    execution.active[execution.depth] = id;
    execution.depth += 1;
    defer execution.depth -= 1;
    if (sink) |target| if (target.form) |callback| try callback(target.context, true, form.bbox, child);
    try interpretStreams(doc, form.resources, &.{id}, child, sink, a, execution);
    if (sink) |target| if (target.form) |callback| try callback(target.context, false, form.bbox, state);
}
fn emitText(text: []const u8, initial: f64, tm: Matrix, state: State, sink: ?Sink, bounds: *[4]f64) !void {
    if (sink) |target| if (target.glyph_run) |callback| try callback(target.context, true, state);
    var offset = initial;
    var at: usize = 0;
    while (try state.font.?.nextCode(text, &at)) |c| {
        try state.font.?.validateGlyph(c);
        const vertical = state.font.?.vertical();
        const metrics = if (vertical) state.font.?.verticalMetrics(c) else [3]f64{ 0, 0, 0 };
        const x = if (vertical) -metrics[1] * state.size * state.scale / 1000 else offset;
        const y = state.rise + (if (vertical) offset - metrics[2] * state.size / 1000 else 0);
        const transform = multiply(multiply(.{ state.size * state.scale, 0, 0, state.size, x, y }, tm), state.ctm);
        for (transform) |n| if (!std.math.isFinite(n) or @abs(n) > 1e12) return error.InvalidTransform;
        const cell = try state.font.?.bounds(c);
        for ([_][2]f64{ .{ cell[0], cell[1] }, .{ cell[2], cell[1] }, .{ cell[0], cell[3] }, .{ cell[2], cell[3] } }) |p| {
            const px = p[0] * transform[0] + p[1] * transform[2] + transform[4];
            const py = p[0] * transform[1] + p[1] * transform[3] + transform[5];
            bounds[0] = @min(bounds[0], px);
            bounds[1] = @min(bounds[1], py);
            bounds[2] = @max(bounds[2], px);
            bounds[3] = @max(bounds[3], py);
        }
        if (sink) |target| try target.glyph(target.context, c, transform, state);
        offset += characterAdvance(c, state);
    }
    if (sink) |target| if (target.glyph_run) |callback| try callback(target.context, false, state);
}
// Appearance resources can reuse a page Form without executing it in page content.
fn usedByAppearance(doc: *d.Document, pages: []const d.Page, id: u32) !bool {
    var scratch = std.heap.ArenaAllocator.init(doc.allocator());
    defer scratch.deinit();
    const a = scratch.allocator();
    var pending: std.ArrayList(s.Value) = .empty;
    var seen: std.AutoHashMapUnmanaged(u32, void) = .empty;
    for (pages) |page| {
        const object = try doc.object(.{ .id = page.object_id, .generation = doc.entries[page.object_id].generation });
        const annots = try doc.resolve(s.get(object.value, "Annots") orelse continue);
        if (annots == .null) continue;
        if (annots != .array) return error.UnsupportedAnnotation;
        for (annots.array) |raw| {
            const annotation = try doc.resolve(raw);
            if (s.get(annotation, "AP")) |appearance| try pending.append(a, appearance);
        }
    }
    var visited: usize = 0;
    while (pending.pop()) |value| {
        visited += 1;
        if (visited > 1000000 or pending.items.len > 1000000) return error.ContentWorkLimit;
        switch (value) {
            .ref => |ref| {
                if (ref.id == id) return true;
                if ((try seen.getOrPut(a, ref.id)).found_existing) continue;
                try pending.append(a, (try doc.object(ref)).value);
            },
            .array => |array| try pending.appendSlice(a, array),
            .dict => |dict| for (dict) |entry| {
                try pending.append(a, entry.value);
            },
            else => {},
        }
    }
    return false;
}
pub fn replace(doc: *d.Document, page_number: usize, run_id: usize, text: []const u8) !void {
    if (doc.page_objects != null) return error.ReadOnlyPageView;
    const pages = try doc.inspect();
    if (page_number == 0 or page_number > pages.len) return error.PageNotFound;
    const page = &pages[page_number - 1];
    if (run_id >= page.runs.len) return error.RunNotFound;
    const run = page.runs[run_id];
    const state = State{ .font = run.font, .size = run.font_size, .char = run.char_space, .word = run.word_space, .scale = run.scale };
    if (text.len > 1048576) return error.TextLimit;
    const encoded = try run.font.encode(doc.allocator(), text);
    const width = try advance(encoded, state);
    const direction: f64 = if (run.font.vertical() and run.advance < 0) -1 else 1;
    if (width * direction < 0 or run.advance * direction < 0 or width * direction > run.advance * direction + 0.0000001) return error.TextOverflow;
    // Shared streams would change more than the selected page/run; require an explicit future clone operation.
    var uses: usize = 0;
    for (pages) |other| for (other.content_uses) |id| {
        if (id == run.object_id) {
            uses += 1;
        }
    };
    if (uses != 1 or try usedByAppearance(doc, pages, run.object_id)) return error.UnsupportedSharedContent;
    const object = try doc.object(.{ .id = run.object_id, .generation = doc.entries[run.object_id].generation });
    const bytes = try doc.streamData(object);
    var out: std.ArrayList(u8) = .empty;
    const a = doc.allocator();
    try out.appendSlice(a, bytes[0..run.start]);
    try out.append(a, '[');
    try d.serialize(a, &out, .{ .string = encoded });
    const adjustment = -(run.advance - width) * 1000 / (run.font_size * (if (run.font.vertical()) 1 else run.scale));
    if (!std.math.isFinite(adjustment) or @abs(adjustment) > 1e12) return error.UnsupportedTextState;
    try out.print(a, " {d}] TJ", .{adjustment});
    try out.appendSlice(a, bytes[run.end..]);
    try doc.replaceStream(object, try out.toOwnedSlice(a));
    doc.pages = null;
}

test "Helvetica proportional advances survive shorter replacement" {
    const a = std.testing.allocator;
    const bytes = try @import("pod.zig").create(a, "Wide iii");
    defer a.free(bytes);
    var doc = try d.Document.open(a, bytes);
    defer doc.deinit();
    try doc.set(try doc.object(.{ .id = 4, .generation = 0 }), "BaseFont", .{ .name = "Helvetica" });
    const pages = try doc.inspect();
    // W=944, i=222, d=556, e=556, space=278, i=222 each.
    try std.testing.expectApproxEqAbs(@as(f64, 38.664), pages[0].runs[0].advance, 0.000001);
    const next = pages[0].runs[1].x;
    try doc.replace(1, 0, "Hi");
    const saved = try doc.save(a);
    defer a.free(saved);
    var copy = try d.Document.open(a, saved);
    defer copy.deinit();
    const edited = try copy.inspect();
    try std.testing.expectEqualStrings("Hi", edited[0].runs[0].text);
    try std.testing.expectApproxEqAbs(next, edited[0].runs[1].x, 0.000001);
}
