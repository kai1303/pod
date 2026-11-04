const std = @import("std");
const d = @import("document.zig");
const s = @import("syntax.zig");
pub const Matrix = [6]f64;
const identity: Matrix = .{ 1, 0, 0, 1, 0, 0 };
pub fn multiply(a: Matrix, b: Matrix) Matrix {
    return .{ a[0] * b[0] + a[1] * b[2], a[0] * b[1] + a[1] * b[3], a[2] * b[0] + a[3] * b[2], a[2] * b[1] + a[3] * b[3], a[4] * b[0] + a[5] * b[2] + b[4], a[4] * b[1] + a[5] * b[3] + b[5] };
}
fn move(m: *Matrix, x: f64, y: f64) void {
    m.* = multiply(.{ 1, 0, 0, 1, x, y }, m.*);
}
pub const State = struct { ctm: Matrix = identity, size: f64 = 0, char: f64 = 0, word: f64 = 0, scale: f64 = 1, leading: f64 = 0, rise: f64 = 0, mode: i64 = 0, font: bool = false, standard_encoding: bool = true };
pub const Run = struct { bounds: [4]f64 = .{ 0, 0, 0, 0 }, id: usize, text: []const u8, x: f64, y: f64, font_size: f64, advance: f64, object_id: u32, start: usize, end: usize, char_space: f64, word_space: f64, scale: f64 };
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
fn checkFont(doc: *d.Document, resources: s.Value, name: []const u8) !bool {
    const fonts = try doc.resolve(s.get(resources, "Font") orelse return error.MissingFont);
    const font = try doc.resolve(s.get(fonts, name) orelse return error.MissingFont);
    const base = s.get(font, "BaseFont") orelse return error.UnsupportedFont;
    const sub = s.get(font, "Subtype") orelse return error.UnsupportedFont;
    if (base != .name or !same(base.name, "Courier") or sub != .name or !same(sub.name, "Type1")) return error.UnsupportedFont;
    var standard = true;
    if (s.get(font, "Encoding")) |enc| {
        const e = try doc.resolve(enc);
        if (e != .name or (!same(e.name, "WinAnsiEncoding") and !same(e.name, "StandardEncoding"))) return error.UnsupportedEncoding;
        standard = same(e.name, "StandardEncoding");
    }
    if (s.get(font, "Widths") != null or s.get(font, "FontDescriptor") != null or s.get(font, "ToUnicode") != null) return error.UnsupportedFont;
    return standard;
}
fn advance(text: []const u8, state: State) !f64 {
    var width: f64 = 0;
    for (text) |c| {
        if (c < 32 or c > 126) return error.UnsupportedEncoding;
        width += (state.size * 0.6 + state.char + (if (c == 32) state.word else @as(f64, 0))) * state.scale;
    }
    if (!std.math.isFinite(width) or @abs(width) > 1e12) return error.InvalidTextAdvance;
    return width;
}
pub const Sink = struct {
    context: *anyopaque,
    operator: *const fn (*anyopaque, []const u8, []s.Value, State) anyerror!void,
    glyph: *const fn (*anyopaque, u8, Matrix, State) anyerror!void,
};
pub fn inspect(doc: *d.Document, page: *d.Page) anyerror![]Run {
    return interpret(doc, page, null);
}
pub fn interpret(doc: *d.Document, page: *d.Page, sink: ?Sink) anyerror![]Run {
    return interpretAllocated(doc, page, sink, doc.allocator());
}
pub fn interpretAllocated(doc: *d.Document, page: *d.Page, sink: ?Sink, a: std.mem.Allocator) anyerror![]Run {
    var runs: std.ArrayList(Run) = .empty;
    var stack: std.ArrayList(State) = .empty;
    var state: State = .{};
    var tm = identity;
    var line = identity;
    var in_text = false;
    for (page.contents) |id| {
        const object = try doc.object(.{ .id = id, .generation = doc.entries[id].generation });
        if (s.get(object.value, "Filter") != null) return error.UnsupportedFilter;
        const bytes = object.changed orelse object.stream orelse return error.InvalidContents;
        var p = s.Parser{ .bytes = bytes, .allocator = a };
        var values: std.ArrayList(s.Value) = .empty;
        p.skip();
        var start = p.pos;
        while (p.pos < bytes.len) {
            const c = bytes[p.pos];
            if (c == '/' or c == '(' or c == '<' or c == '[' or c == '+' or c == '-' or c == '.' or (c >= '0' and c <= '9')) {
                if (values.items.len >= 128) return error.OperandLimit;
                try values.append(a, try p.value());
                p.skip();
                continue;
            }
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
            } else if (same(op, "cm")) {
                try arity(v, 6);
                var m: Matrix = undefined;
                for (v, 0..) |n, i| m[i] = try num(n);
                state.ctm = multiply(m, state.ctm);
            } else if (same(op, "Tf")) {
                try arity(v, 2);
                if (v[0] != .name) return error.InvalidOperands;
                state.standard_encoding = try checkFont(doc, page.resources, v[0].name);
                state.size = try num(v[1]);
                if (state.size <= 0) return error.UnsupportedTextState;
                state.font = true;
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
                if (!in_text or !state.font) return error.InvalidTextObject;
                var text: std.ArrayList(u8) = .empty;
                var width: f64 = 0;
                var bounds: [4]f64 = .{ std.math.inf(f64), std.math.inf(f64), -std.math.inf(f64), -std.math.inf(f64) };
                if (same(op, "Tj")) {
                    if (v[0] != .string) return error.InvalidOperands;
                    try text.appendSlice(a, v[0].string);
                    width = try advance(v[0].string, state);
                    try emitText(v[0].string, 0, tm, state, sink, &bounds);
                } else {
                    if (v[0] != .array) return error.InvalidOperands;
                    for (v[0].array) |item| {
                        if (item == .string) {
                            try text.appendSlice(a, item.string);
                            try emitText(item.string, width, tm, state, sink, &bounds);
                            width += try advance(item.string, state);
                        } else if (item == .integer or item == .real) width -= (try num(item)) * state.size * state.scale / 1000 else return error.InvalidOperands;
                    }
                }
                if (!std.math.isFinite(width) or @abs(width) > 1e12) return error.InvalidTextAdvance;
                const transform = multiply(tm, state.ctm);
                const x = transform[4] + state.rise * transform[2];
                const y = transform[5] + state.rise * transform[3];
                if (!std.math.isFinite(x) or !std.math.isFinite(y)) return error.InvalidTransform;
                if (!std.math.isFinite(bounds[0])) bounds = .{ x, y, x, y };
                try runs.append(a, .{ .bounds = bounds, .id = runs.items.len, .text = try text.toOwnedSlice(a), .x = x, .y = y, .font_size = state.size, .advance = width, .object_id = id, .start = start, .end = p.pos, .char_space = state.char, .word_space = state.word, .scale = state.scale });
                move(&tm, width, 0);
            } else {
                // These graphics operators cannot change text positioning or font selection.
                const count: ?usize = if (same(op, "m") or same(op, "l")) 2 else if (same(op, "c")) 6 else if (same(op, "v") or same(op, "y") or same(op, "re") or same(op, "k") or same(op, "K")) 4 else if (same(op, "rg") or same(op, "RG")) 3 else if (same(op, "w") or same(op, "J") or same(op, "j") or same(op, "M") or same(op, "g") or same(op, "G")) 1 else if (same(op, "h") or same(op, "S") or same(op, "s") or same(op, "f") or same(op, "F") or same(op, "f*") or same(op, "B") or same(op, "B*") or same(op, "b") or same(op, "b*") or same(op, "n")) 0 else null;
                if (count) |n| {
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
    return runs.toOwnedSlice(a);
}
fn emitText(text: []const u8, initial: f64, tm: Matrix, state: State, sink: ?Sink, bounds: *[4]f64) !void {
    var offset = initial;
    for (text) |c| {
        if (c < 32 or c > 126) return error.UnsupportedEncoding;
        const transform = multiply(multiply(.{ state.size * state.scale, 0, 0, state.size, offset, state.rise }, tm), state.ctm);
        for (transform) |n| if (!std.math.isFinite(n) or @abs(n) > 1e12) return error.InvalidTransform;
        // Conservative Courier cell bounds, including ascenders and descenders.
        for ([_][2]f64{ .{ -0.1, -0.3 }, .{ 0.7, -0.3 }, .{ -0.1, 1.0 }, .{ 0.7, 1.0 } }) |p| {
            const x = p[0] * transform[0] + p[1] * transform[2] + transform[4];
            const y = p[0] * transform[1] + p[1] * transform[3] + transform[5];
            bounds[0] = @min(bounds[0], x);
            bounds[1] = @min(bounds[1], y);
            bounds[2] = @max(bounds[2], x);
            bounds[3] = @max(bounds[3], y);
        }
        if (sink) |target| try target.glyph(target.context, c, transform, state);
        offset += (state.size * 0.6 + state.char + (if (c == 32) state.word else @as(f64, 0))) * state.scale;
    }
}
pub fn replace(doc: *d.Document, page_number: usize, run_id: usize, text: []const u8) !void {
    const pages = try doc.inspect();
    if (page_number == 0 or page_number > pages.len) return error.PageNotFound;
    const page = &pages[page_number - 1];
    if (run_id >= page.runs.len) return error.RunNotFound;
    const run = page.runs[run_id];
    const state = State{ .size = run.font_size, .char = run.char_space, .word = run.word_space, .scale = run.scale };
    if (text.len > 1048576) return error.TextLimit;
    const width = try advance(text, state);
    if (width < 0 or run.advance < 0 or width > run.advance + 0.0000001) return error.TextOverflow;
    // Shared streams would change more than the selected page/run; require an explicit future clone operation.
    var uses: usize = 0;
    for (pages) |other| for (other.contents) |id| {
        if (id == run.object_id) {
            uses += 1;
        }
    };
    if (uses != 1) return error.UnsupportedSharedContent;
    const object = try doc.object(.{ .id = run.object_id, .generation = doc.entries[run.object_id].generation });
    const bytes = object.changed orelse object.stream.?;
    var out: std.ArrayList(u8) = .empty;
    const a = doc.allocator();
    try out.appendSlice(a, bytes[0..run.start]);
    try out.append(a, '[');
    try d.serialize(a, &out, .{ .string = text });
    const adjustment = -(run.advance - width) * 1000 / (run.font_size * run.scale);
    if (!std.math.isFinite(adjustment) or @abs(adjustment) > 1e12) return error.UnsupportedTextState;
    try out.print(a, " {d}] TJ", .{adjustment});
    try out.appendSlice(a, bytes[run.end..]);
    object.changed = try out.toOwnedSlice(a);
    doc.pages = null;
}
