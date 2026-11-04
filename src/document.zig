const std = @import("std");
const s = @import("syntax.zig");
const A = std.mem.Allocator;
pub const Object = struct { value: s.Value, body: []const u8, stream: ?[]const u8 = null, changed: ?[]const u8 = null };
const Xref = struct { offset: usize = 0, generation: u16 = 0, live: bool = false, seen: bool = false, busy: bool = false, object: ?*Object = null };
pub const Page = struct { number: usize, resources: s.Value, media_box: s.Value, contents: []u32, runs: []@import("content.zig").Run = &.{} };
pub const Document = struct {
    arena: std.heap.ArenaAllocator,
    bytes: []const u8,
    entries: []Xref = &.{},
    trailer: s.Value = .null,
    pages: ?[]Page = null,
    resolving_depth: usize = 0,
    context: struct { object_id: u32 = 0, page: usize = 0, operator: []const u8 = "" } = .{},
    pub fn allocator(self: *Document) A {
        return self.arena.allocator();
    }
    pub fn open(a: A, bytes: []const u8) !Document {
        if (bytes.len < 8 or !std.mem.startsWith(u8, bytes, "%PDF-")) return error.InvalidHeader;
        if (bytes.len > 256 * 1024 * 1024) return error.FileLimit;
        var self = Document{ .arena = std.heap.ArenaAllocator.init(a), .bytes = bytes };
        errdefer self.deinit();
        const end = std.mem.trimEnd(u8, bytes, " \t\r\n\x00");
        if (!std.mem.endsWith(u8, end, "%%EOF")) return error.MissingEOF;
        const start = std.mem.lastIndexOf(u8, end, "startxref") orelse return error.MissingXref;
        var tail = s.Parser{ .bytes = end[start + 9 .. end.len - 5], .allocator = self.allocator() };
        const offset = std.fmt.parseInt(usize, try tail.token(), 10) catch return error.InvalidXref;
        tail.skip();
        if (tail.pos != tail.bytes.len or offset >= start) return error.InvalidXref;
        var p = s.Parser{ .bytes = bytes, .pos = offset, .allocator = self.allocator() };
        if (!p.keyword("xref")) {
            _ = std.fmt.parseInt(u32, p.token() catch return error.InvalidXrefOffset, 10) catch return error.InvalidXrefOffset;
            _ = std.fmt.parseInt(u16, p.token() catch return error.InvalidXrefOffset, 10) catch return error.InvalidXrefOffset;
            if (!p.keyword("obj")) return error.InvalidXrefOffset;
            const candidate = p.value() catch |err| return if (err == error.OutOfMemory) err else error.InvalidXrefOffset;
            const kind = s.get(candidate, "Type") orelse return error.InvalidXrefOffset;
            if (kind == .name and std.mem.eql(u8, kind.name, "XRef")) return error.UnsupportedXrefStream;
            return error.InvalidXrefOffset;
        }
        var entries: std.ArrayList(Xref) = .empty;
        while (!p.keyword("trailer")) {
            const first = std.fmt.parseInt(usize, try p.token(), 10) catch return error.InvalidXref;
            const count = std.fmt.parseInt(usize, try p.token(), 10) catch return error.InvalidXref;
            const limit = std.math.add(usize, first, count) catch return error.ObjectLimit;
            if (limit > 1000000 or count == 0) return error.ObjectLimit;
            if (limit > entries.items.len) {
                const old = entries.items.len;
                try entries.resize(self.allocator(), limit);
                @memset(entries.items[old..], .{});
            }
            for (first..limit) |i| {
                if (entries.items[i].seen) return error.DuplicateXref;
                const at = std.fmt.parseInt(usize, try p.token(), 10) catch return error.InvalidXref;
                const gen = std.fmt.parseInt(u16, try p.token(), 10) catch return error.InvalidXref;
                const flag = try p.token();
                if (!std.mem.eql(u8, flag, "n") and !std.mem.eql(u8, flag, "f")) return error.InvalidXref;
                const live = flag[0] == 'n';
                if (live and (at >= offset or at == 0 or i == 0)) return error.InvalidXref;
                entries.items[i] = .{ .offset = at, .generation = gen, .live = live, .seen = true };
            }
        }
        self.entries = try entries.toOwnedSlice(self.allocator());
        self.trailer = try p.value();
        if (self.trailer != .dict) return error.InvalidTrailer;
        if (s.get(self.trailer, "Prev") != null) return error.UnsupportedRevisions;
        if (s.get(self.trailer, "XRefStm") != null) return error.UnsupportedXrefStream;
        if (s.get(self.trailer, "Encrypt") != null) return error.UnsupportedEncryption;
        const size = try s.uint(s.get(self.trailer, "Size") orelse return error.InvalidTrailer);
        if (size == 0 or size != self.entries.len) return error.InvalidXref;
        if (!self.entries[0].seen or self.entries[0].live or self.entries[0].generation != 65535) return error.InvalidXref;
        p.skip();
        if (p.pos != start) return error.InvalidTrailer;
        if (s.get(self.trailer, "Root") == null) return error.InvalidTrailer;
        return self;
    }
    pub fn deinit(self: *Document) void {
        self.arena.deinit();
    }
    pub fn object(self: *Document, ref: s.Ref) anyerror!*Object {
        self.context.object_id = ref.id;
        if (self.resolving_depth >= 64) return error.ReferenceLimit;
        self.resolving_depth += 1;
        defer self.resolving_depth -= 1;
        if (ref.id == 0 or ref.id >= self.entries.len) return error.MissingReference;
        const x = &self.entries[ref.id];
        if (!x.live or x.generation != ref.generation) return error.MissingReference;
        if (x.object) |o| return o;
        if (x.busy) return error.ReferenceCycle;
        x.busy = true;
        defer x.busy = false;
        var p = s.Parser{ .bytes = self.bytes, .pos = x.offset, .allocator = self.allocator() };
        if (s.ws(self.bytes[x.offset]) or self.bytes[x.offset] == '%') return error.InvalidXrefOffset;
        const id = std.fmt.parseInt(u32, try p.token(), 10) catch return error.InvalidXrefOffset;
        const gen = std.fmt.parseInt(u16, try p.token(), 10) catch return error.InvalidXrefOffset;
        if (id != ref.id or gen != ref.generation or !p.keyword("obj")) return error.InvalidXrefOffset;
        p.skip();
        const body_start = p.pos;
        const val = try p.value();
        var stream: ?[]const u8 = null;
        if (p.keyword("stream")) {
            if (val != .dict) return error.InvalidStream;
            if (p.pos >= self.bytes.len) return error.InvalidStream;
            if (self.bytes[p.pos] == 13) {
                p.pos += 1;
                if (p.pos < self.bytes.len and self.bytes[p.pos] == 10) p.pos += 1;
            } else if (self.bytes[p.pos] == 10) p.pos += 1 else return error.InvalidStream;
            const length = try s.uint(try self.resolve(s.get(val, "Length") orelse return error.InvalidStream));
            const finish = std.math.add(usize, p.pos, length) catch return error.InvalidStreamLength;
            if (finish > self.bytes.len) return error.InvalidStreamLength;
            stream = self.bytes[p.pos..finish];
            p.pos = finish;
            if (!p.keyword("endstream")) return error.InvalidStreamLength;
        }
        p.skip();
        const body_end = p.pos;
        if (!p.keyword("endobj")) return error.InvalidObject;
        const o = try self.allocator().create(Object);
        o.* = .{ .value = val, .stream = stream, .body = self.bytes[body_start..body_end] };
        x.object = o;
        return o;
    }
    pub fn resolve(self: *Document, value: s.Value) anyerror!s.Value {
        var v = value;
        var depth: usize = 0;
        while (v == .ref) : (depth += 1) {
            if (depth >= 64) return error.ReferenceCycle;
            v = (try self.object(v.ref)).value;
        }
        return v;
    }
    fn walk(self: *Document, value: s.Value, resources: ?s.Value, box: ?s.Value, path: *std.ArrayList(u32), visited: []bool, result: *std.ArrayList(Page)) anyerror!void {
        if (path.items.len >= 64 or result.items.len >= 100000) return error.PageLimit;
        if (value != .ref) return error.InvalidPageTree;
        if (std.mem.indexOfScalar(u32, path.items, value.ref.id) != null) return error.PageTreeCycle;
        if (value.ref.id >= visited.len) return error.MissingReference;
        if (visited[value.ref.id]) return error.InvalidPageTree;
        visited[value.ref.id] = true;
        try path.append(self.allocator(), value.ref.id);
        defer _ = path.pop();
        const v = try self.resolve(value);
        if (v != .dict) return error.InvalidPageTree;
        const res = s.get(v, "Resources") orelse resources;
        const media = s.get(v, "MediaBox") orelse box;
        const kind = s.get(v, "Type") orelse return error.InvalidPageTree;
        if (kind != .name) return error.InvalidPageTree;
        if (std.mem.eql(u8, kind.name, "Pages")) {
            const kids = try self.resolve(s.get(v, "Kids") orelse return error.InvalidPageTree);
            if (kids != .array) return error.InvalidPageTree;
            for (kids.array) |k| try self.walk(k, res, media, path, visited, result);
        } else if (std.mem.eql(u8, kind.name, "Page")) {
            const mb = try self.resolve(media orelse return error.MissingMediaBox);
            if (mb != .array or mb.array.len != 4) return error.InvalidMediaBox;
            for (mb.array) |n| _ = try s.number(n);
            var ids: std.ArrayList(u32) = .empty;
            if (s.get(v, "Contents")) |contents| {
                if (contents == .ref and (try self.object(contents.ref)).stream != null) {
                    try ids.append(self.allocator(), contents.ref.id);
                } else {
                    const arr = try self.resolve(contents);
                    if (arr != .array) return error.InvalidContents;
                    for (arr.array) |item| {
                        if (item != .ref or (try self.object(item.ref)).stream == null) return error.InvalidContents;
                        try ids.append(self.allocator(), item.ref.id);
                    }
                }
            }
            try result.append(self.allocator(), .{ .number = result.items.len + 1, .resources = try self.resolve(res orelse return error.MissingResources), .media_box = mb, .contents = try ids.toOwnedSlice(self.allocator()) });
        } else return error.InvalidPageTree;
    }
    pub fn inspect(self: *Document) anyerror![]Page {
        if (self.pages) |pages| return pages;
        const root = try self.resolve(s.get(self.trailer, "Root").?);
        var path: std.ArrayList(u32) = .empty;
        var pages: std.ArrayList(Page) = .empty;
        const visited = try self.allocator().alloc(bool, self.entries.len);
        @memset(visited, false);
        try self.walk(s.get(root, "Pages") orelse return error.InvalidCatalog, null, null, &path, visited, &pages);
        for (pages.items) |*page| {
            self.context.page = page.number;
            page.runs = try @import("content.zig").inspect(self, page);
        }
        self.pages = try pages.toOwnedSlice(self.allocator());
        return self.pages.?;
    }
    pub fn replace(self: *Document, page: usize, run: usize, text: []const u8) !void {
        try @import("content.zig").replace(self, page, run, text);
    }
    pub fn save(self: *Document, a: A) ![]u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(a);
        try out.appendSlice(a, "%PDF-1.7\n%\xe2\xe3\xcf\xd3\n");
        const offsets = try a.alloc(usize, self.entries.len);
        defer a.free(offsets);
        @memset(offsets, 0);
        for (self.entries, 0..) |x, i| {
            if (!x.live) continue;
            const o = try self.object(.{ .id = @intCast(i), .generation = x.generation });
            offsets[i] = out.items.len;
            try out.print(a, "{d} {d} obj\n", .{ i, x.generation });
            if (o.changed) |data| {
                try out.appendSlice(a, "<<");
                for (o.value.dict) |entry| {
                    if (std.mem.eql(u8, entry.key, "Length")) continue;
                    try serialize(a, &out, .{ .name = entry.key });
                    try serialize(a, &out, entry.value);
                }
                try out.print(a, " /Length {d} >>\nstream\n", .{data.len});
                try out.appendSlice(a, data);
                try out.appendSlice(a, "\nendstream\n");
            } else try out.appendSlice(a, o.body);
            try out.appendSlice(a, "\nendobj\n");
        }
        const xref = out.items.len;
        var next_free: usize = 0;
        var free_index = self.entries.len;
        while (free_index > 1) {
            free_index -= 1;
            if (!self.entries[free_index].live) {
                offsets[free_index] = next_free;
                next_free = free_index;
            }
        }
        try out.print(a, "xref\n0 {d}\n{d:0>10} 65535 f \n", .{ self.entries.len, next_free });
        for (self.entries[1..], 1..) |x, i| {
            if (x.live) try out.print(a, "{d:0>10} {d:0>5} n \n", .{ offsets[i], x.generation }) else try out.print(a, "{d:0>10} {d:0>5} f \n", .{ offsets[i], x.generation });
        }
        try out.appendSlice(a, "trailer\n");
        try serialize(a, &out, self.trailer);
        try out.print(a, "\nstartxref\n{d}\n%%EOF\n", .{xref});
        return out.toOwnedSlice(a);
    }
};
pub fn serialize(a: A, out: *std.ArrayList(u8), v: s.Value) anyerror!void {
    switch (v) {
        .null => try out.appendSlice(a, " null"),
        .boolean => |b| try out.appendSlice(a, if (b) " true" else " false"),
        .integer => |n| try out.print(a, " {d}", .{n}),
        .real => |n| try out.print(a, " {d}", .{n}),
        .ref => |r| try out.print(a, " {d} {d} R", .{ r.id, r.generation }),
        .name => |name| {
            try out.appendSlice(a, " /");
            for (name) |c| {
                if (s.delim(c) or c == '#' or c < 33 or c > 126) try out.print(a, "#{X:0>2}", .{c}) else try out.append(a, c);
            }
        },
        .string => |str| {
            try out.appendSlice(a, " <");
            for (str) |c| try out.print(a, "{X:0>2}", .{c});
            try out.append(a, '>');
        },
        .array => |arr| {
            try out.appendSlice(a, " [");
            for (arr) |item| try serialize(a, out, item);
            try out.append(a, ']');
        },
        .dict => |dict| {
            try out.appendSlice(a, " <<");
            for (dict) |entry| {
                try serialize(a, out, .{ .name = entry.key });
                try serialize(a, out, entry.value);
            }
            try out.appendSlice(a, " >>");
        },
    }
}
test "truncated document is rejected" {
    try std.testing.expectError(error.InvalidHeader, Document.open(std.testing.allocator, "garbage"));
}
