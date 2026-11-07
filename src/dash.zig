//! PDF line dash pattern, in user-space units (ISO 32000-1, 8.4.3.6).
const std = @import("std");
const d = @import("document.zig");
const s = @import("syntax.zig");
pub const Pattern = struct {
    values: [128]f64 = @splat(0),
    count: usize = 0,
    phase: f64 = 0,
    period: f64 = 0,
    pub fn parse(doc: *d.Document, raw: s.Value, offset: s.Value) !Pattern {
        const array = try doc.resolve(raw);
        if (array != .array) return error.InvalidDash;
        if (array.array.len > 128) return error.DashLimit;
        var result = Pattern{ .count = array.array.len };
        const phase = try number(doc, offset);
        for (array.array, 0..) |item, i| {
            const value = try number(doc, item);
            if (value < 0) return error.InvalidDash;
            result.values[i] = value;
            result.period += value;
        }
        if (result.count == 0) return result;
        if (result.period == 0) return error.InvalidDash;
        if (result.count % 2 != 0) result.period *= 2;
        result.phase = @mod(phase, result.period);
        return result;
    }
    pub fn cursor(self: *const Pattern) Cursor {
        std.debug.assert(self.count != 0);
        var current = Cursor{ .pattern = self, .remaining = self.values[0] };
        var phase = self.phase;
        while (phase > 0) {
            if (phase < current.remaining) {
                current.remaining -= phase;
                break;
            }
            phase -= current.remaining;
            current.next();
        }
        return current;
    }
};
fn number(doc: *d.Document, raw: s.Value) !f64 {
    const value = try s.number(try doc.resolve(raw));
    if (!std.math.isFinite(value) or @abs(value) > 1e12) return error.InvalidDash;
    return value;
}
pub const Cursor = struct {
    pattern: *const Pattern,
    index: usize = 0,
    remaining: f64,
    pub fn on(self: Cursor) bool {
        return self.index % 2 == 0;
    }
    pub fn next(self: *Cursor) void {
        self.index = (self.index + 1) % (self.pattern.count * (1 + self.pattern.count % 2));
        self.remaining = self.pattern.values[self.index % self.pattern.count];
    }
};
