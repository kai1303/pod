const std = @import("std");
const d = @import("document.zig");
const s = @import("syntax.zig");

pub const Kind = enum { note, comment, key, help, new_paragraph, paragraph, insert };
pub const Icon = struct {
    kind: Kind = .note,
    color: [3]f64 = .{ 1, 1, 0 },
    opacity: f64 = 1,
};
pub fn load(doc: *d.Document, annotation: s.Value) !Icon {
    var result = Icon{};
    if (s.get(annotation, "Name")) |raw| {
        const name = try doc.resolve(raw);
        if (name != .null) {
            if (name != .name) return error.UnsupportedAnnotation;
            inline for (.{ .{ "Comment", Kind.comment }, .{ "Key", Kind.key }, .{ "Help", Kind.help }, .{ "NewParagraph", Kind.new_paragraph }, .{ "Paragraph", Kind.paragraph }, .{ "Insert", Kind.insert } }) |pair| {
                if (std.mem.eql(u8, name.name, pair[0])) result.kind = pair[1];
            }
        }
    }
    if (s.get(annotation, "C")) |raw| {
        const color = try doc.resolve(raw);
        if (color != .null) {
            if (color != .array or (color.array.len != 1 and color.array.len != 3)) return error.InvalidAnnotationStyle;
            for (&result.color, 0..) |*channel, i| channel.* = try s.number(try doc.resolve(color.array[if (color.array.len == 1) 0 else i]));
        }
    }
    if (s.get(annotation, "CA")) |raw| {
        const opacity = try doc.resolve(raw);
        if (opacity != .null) result.opacity = try s.number(opacity);
    }
    for (result.color ++ .{result.opacity}) |value| if (!std.math.isFinite(value) or value < 0 or value > 1) return error.InvalidAnnotationStyle;
    return result;
}

// Original vector icons in a 24-by-24 PDF coordinate square. No host font or
// PDF objects are created while displaying an annotation without an AP stream.
pub const Command = union(enum) { move: [2]f64, line: [2]f64, curve: [6]f64, close };
pub const Layer = struct { path: []const Command, dark: bool = false, stroke: f64 = 0, even_odd: bool = false };
fn m(x: f64, y: f64) Command {
    return .{ .move = .{ x, y } };
}
fn l(x: f64, y: f64) Command {
    return .{ .line = .{ x, y } };
}
fn b(x1: f64, y1: f64, x2: f64, y2: f64, x: f64, y: f64) Command {
    return .{ .curve = .{ x1, y1, x2, y2, x, y } };
}
const note = [_]Command{ m(3, 2), l(21, 2), l(21, 17), l(16, 22), l(3, 22), .close };
const note_lines = [_]Command{ m(16, 22), l(16, 17), l(21, 17), m(7, 13), l(17, 13), m(7, 9), l(17, 9), m(7, 5), l(13, 5) };
const bubble = [_]Command{ m(2, 21), l(22, 21), l(22, 7), l(12, 7), l(6, 2), l(6, 7), l(2, 7), .close };
const bubble_lines = [_]Command{ m(6, 16), l(18, 16), m(6, 11), l(15, 11) };
const circle = [_]Command{ m(22, 12), b(22, 17.523, 17.523, 22, 12, 22), b(6.477, 22, 2, 17.523, 2, 12), b(2, 6.477, 6.477, 2, 12, 2), b(17.523, 2, 22, 6.477, 22, 12), .close };
const question = [_]Command{ m(8, 15), b(8, 20, 16, 20, 16, 15), b(16, 12, 12, 13, 12, 9), m(12, 5), l(12, 5.2) };
const pilcrow = [_]Command{ m(16, 5), l(16, 19), l(11, 19), b(5, 19, 5, 12, 11, 12), l(12, 12), m(12, 19), l(12, 5) };
const new_paragraph = [_]Command{ m(18, 7), l(18, 18), l(13, 18), b(7, 18, 7, 13, 13, 13), l(14, 13), m(14, 18), l(14, 7), m(3, 6), l(10, 6), m(7, 9), l(10, 6), l(7, 3) };
const key = [_]Command{ m(9, 22), b(5.1, 22, 2, 18.9, 2, 15), b(2, 11.1, 5.1, 8, 9, 8), l(11, 8), l(17, 2), l(22, 2), l(22, 6), l(18, 6), l(18, 9), l(15, 12), b(17, 17, 14, 22, 9, 22), .close, m(11, 16), b(11, 17.657, 9.657, 19, 8, 19), b(6.343, 19, 5, 17.657, 5, 16), b(5, 14.343, 6.343, 13, 8, 13), b(9.657, 13, 11, 14.343, 11, 16), .close };
const caret = [_]Command{ m(3, 4), l(12, 21), l(21, 4), l(17, 4), l(12, 14), l(7, 4), .close };
pub fn layers(kind: Kind) []const Layer {
    return switch (kind) {
        .note => &.{ .{ .path = &note }, .{ .path = &note, .dark = true, .stroke = 1.2 }, .{ .path = &note_lines, .dark = true, .stroke = 1.2 } },
        .comment => &.{ .{ .path = &bubble }, .{ .path = &bubble, .dark = true, .stroke = 1.2 }, .{ .path = &bubble_lines, .dark = true, .stroke = 1.4 } },
        .key => &.{ .{ .path = &key, .even_odd = true }, .{ .path = &key, .dark = true, .stroke = 1.2 } },
        .help => &.{ .{ .path = &circle }, .{ .path = &circle, .dark = true, .stroke = 1.2 }, .{ .path = &question, .dark = true, .stroke = 2 } },
        .paragraph => &.{ .{ .path = &circle }, .{ .path = &circle, .dark = true, .stroke = 1.2 }, .{ .path = &pilcrow, .dark = true, .stroke = 1.6 } },
        .new_paragraph => &.{ .{ .path = &note }, .{ .path = &note, .dark = true, .stroke = 1.2 }, .{ .path = &new_paragraph, .dark = true, .stroke = 1.4 } },
        .insert => &.{ .{ .path = &caret }, .{ .path = &caret, .dark = true, .stroke = 1.2 } },
    };
}
