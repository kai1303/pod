const std = @import("std");
const s = @import("syntax.zig");
const A = std.mem.Allocator;
pub const Object = struct {
    value: s.Value,
    body: []const u8,
    stream: ?[]const u8 = null,
    changed: ?[]const u8 = null,
    dirty: bool = false,
    members: ?@import("object_stream.zig").Index = null,
    decoded: ?struct { source: []const u8, data: []const u8, revision: u64 } = null,
};
pub const Xref = struct { object_stream: u32 = 0, object_index: u32 = 0, offset: usize = 0, generation: u16 = 0, live: bool = false, seen: bool = false, busy: bool = false, object: ?*Object = null };
pub const Page = struct {
    object_id: u32 = 0,
    number: usize,
    resources: s.Value,
    media_box: s.Value,
    crop_box: ?s.Value = null,
    rotation: i32 = 0,
    contents: []u32,
    content_uses: []u32 = &.{},
    runs: []@import("content.zig").Run = &.{},
    annotation_refs: std.ArrayList(s.Value) = .empty,
    pub fn visibleBox(self: Page) ![4]f64 {
        var box = try rectangle(self.media_box);
        if (self.crop_box) |crop| {
            const c = rectangle(crop) catch return error.InvalidCropBox;
            box = .{ @max(box[0], c[0]), @max(box[1], c[1]), @min(box[2], c[2]), @min(box[3], c[3]) };
            if (box[2] <= box[0] or box[3] <= box[1]) return error.InvalidCropBox;
        }
        return box;
    }
};
pub fn rectangle(value: s.Value) ![4]f64 {
    if (value != .array or value.array.len != 4) return error.InvalidMediaBox;
    var box: [4]f64 = undefined;
    for (&box, value.array) |*v, n| {
        v.* = try s.number(n);
        if (!std.math.isFinite(v.*) or @abs(v.*) > 1e6) return error.InvalidMediaBox;
    }
    if (box[2] <= box[0] or box[3] <= box[1]) return error.InvalidMediaBox;
    return box;
}

pub const Document = struct {
    arena: std.heap.ArenaAllocator,
    bytes: []const u8,
    entries: []Xref = &.{},
    entries_storage: []Xref = &.{},
    // Read-only page views share the document index, but own objects they resolve.
    page_objects: ?std.AutoHashMapUnmanaged(u32, *Object) = null,
    trailer: s.Value = .null,
    pages: ?[]Page = null,
    page_numbers: std.AutoHashMapUnmanaged(u32, usize) = .empty,
    pdf_fonts: std.AutoHashMapUnmanaged(usize, *const @import("pdf_font.zig").Font) = .empty,
    icc_profiles: std.AutoHashMapUnmanaged(u32, *const @import("icc.zig").Profile) = .empty,
    destination_names: ?std.StringHashMapUnmanaged(s.Value) = null,
    unsupported_appearance: bool = false,
    resolving_depth: usize = 0,
    decoded_bytes: usize = 0,
    stream_revision: u64 = 0,
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
        try @import("xref.zig").load(&self, offset, start);
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
        if (self.page_objects) |*cache| {
            if (cache.get(ref.id)) |o| return o;
            if (x.object) |shared| {
                // Decoded bytes belong to this page view, not to the longer-lived index.
                const local = try self.allocator().create(Object);
                local.* = shared.*;
                local.decoded = null;
                local.members = null;
                try cache.put(self.allocator(), ref.id, local);
                return local;
            }
        } else if (x.object) |o| return o;
        if (x.busy) return error.ReferenceCycle;
        x.busy = true;
        defer x.busy = false;
        const o = if (x.object_stream != 0)
            try @import("object_stream.zig").read(self, ref, x.*)
        else
            (try self.readIndirect(x.offset, ref)).object;
        if (self.page_objects) |*cache| try cache.put(self.allocator(), ref.id, o) else x.object = o;
        return o;
    }
    pub const Indirect = struct { ref: s.Ref, object: *Object, end: usize };
    pub fn readIndirect(self: *Document, offset: usize, expected: ?s.Ref) anyerror!Indirect {
        if (offset >= self.bytes.len or s.ws(self.bytes[offset]) or self.bytes[offset] == '%') return error.InvalidXrefOffset;
        var p = s.Parser{ .bytes = self.bytes, .pos = offset, .allocator = self.allocator() };
        const id = std.fmt.parseInt(u32, try p.token(), 10) catch return error.InvalidXrefOffset;
        const gen = std.fmt.parseInt(u16, try p.token(), 10) catch return error.InvalidXrefOffset;
        if (id == 0 or id >= 1_000_000 or !p.keyword("obj")) return error.InvalidXrefOffset;
        if (expected) |ref| if (id != ref.id or gen != ref.generation) return error.InvalidXrefOffset;
        p.skip();
        const body_start = p.pos;
        const val = try p.value();
        if (expected == null) {
            const typ = s.get(val, "Type") orelse return error.InvalidXrefOffset;
            if (typ != .name or !std.mem.eql(u8, typ.name, "XRef")) return error.InvalidXrefOffset;
            if (s.get(val, "Length")) |length| if (length == .ref) return error.InvalidXref;
        }
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
        return .{ .ref = .{ .id = id, .generation = gen }, .object = o, .end = p.pos };
    }
    pub fn streamData(self: *Document, obj: *Object) ![]const u8 {
        const source = obj.changed orelse obj.stream orelse return error.InvalidStream;
        if (obj.decoded) |cached| {
            if (cached.revision == self.stream_revision and source.ptr == cached.source.ptr and source.len == cached.source.len) return cached.data;
        }
        const budget = 256 * 1024 * 1024 - self.decoded_bytes;
        const limit = @min(64 * 1024 * 1024, budget);
        const data = try @import("filters.zig").decode(self, obj, self.allocator(), limit);
        if (s.get(obj.value, "Filter") != null) {
            self.decoded_bytes += data.len;
            obj.decoded = .{ .source = source, .data = data, .revision = self.stream_revision };
        }
        return data;
    }
    // Stage the dictionary before committing so an allocation failure leaves the stream valid.
    pub fn replaceStream(self: *Document, obj: *Object, data: []const u8) !void {
        if (obj.value != .dict) return error.ExpectedDictionary;
        var entries: std.ArrayList(s.Entry) = .empty;
        for (obj.value.dict) |entry| {
            if (std.mem.eql(u8, entry.key, "Filter") or std.mem.eql(u8, entry.key, "DecodeParms") or
                std.mem.eql(u8, entry.key, "DL")) continue;
            try entries.append(self.allocator(), entry);
        }
        obj.value = .{ .dict = try entries.toOwnedSlice(self.allocator()) };
        self.pdf_fonts.clearRetainingCapacity();
        self.icc_profiles.clearRetainingCapacity();
        self.pages = null;
        obj.changed = data;
        obj.decoded = null;
        obj.members = null;
        obj.dirty = true;
    }
    pub fn addObject(self: *Document, value: s.Value, stream: ?[]const u8) !u32 {
        if (self.entries.len >= 1000000) return error.ObjectLimit;
        if (self.entries_storage.len <= self.entries.len or self.entries_storage.ptr != self.entries.ptr) {
            const capacity = @min(1000000, @max(self.entries.len + 1, self.entries.len * 2));
            const storage = try self.allocator().alloc(Xref, capacity);
            @memcpy(storage[0..self.entries.len], self.entries);
            self.entries_storage = storage;
        }
        const entries = self.entries_storage[0 .. self.entries.len + 1];
        const obj = try self.allocator().create(Object);
        obj.* = .{ .value = value, .body = "", .stream = stream, .changed = stream, .dirty = true };
        const id: u32 = @intCast(self.entries.len);
        entries[id] = .{ .live = true, .seen = true, .object = obj };
        self.entries = entries;
        for (self.trailer.dict) |*entry| if (std.mem.eql(u8, entry.key, "Size")) {
            entry.value = .{ .integer = @intCast(entries.len) };
        };
        return id;
    }
    pub fn set(self: *Document, obj: *Object, key: []const u8, value: s.Value) !void {
        if (obj.value != .dict) return error.ExpectedDictionary;
        self.stream_revision +%= 1;
        self.destination_names = null;
        self.pdf_fonts.clearRetainingCapacity();
        self.icc_profiles.clearRetainingCapacity();
        obj.decoded = null;
        obj.members = null;
        for (obj.value.dict) |*entry| if (std.mem.eql(u8, entry.key, key)) {
            entry.value = value;
            obj.dirty = true;
            return;
        };
        const entries = try self.allocator().alloc(s.Entry, obj.value.dict.len + 1);
        @memcpy(entries[0..obj.value.dict.len], obj.value.dict);
        entries[obj.value.dict.len] = .{ .key = key, .value = value };
        obj.value = .{ .dict = entries };
        obj.dirty = true;
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
    fn walk(self: *Document, value: s.Value, resources: ?s.Value, box: ?s.Value, crop: ?s.Value, rotation: ?s.Value, path: *std.ArrayList(u32), visited: []bool, result: *std.ArrayList(Page)) anyerror!void {
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
        for ([_][]const u8{ "UserUnit", "Group" }) |key| {
            if (s.get(v, key) != null) self.unsupported_appearance = true;
        }
        const res = s.get(v, "Resources") orelse resources;
        const media = s.get(v, "MediaBox") orelse box;
        const crop_box = s.get(v, "CropBox") orelse crop;
        const rotate = s.get(v, "Rotate") orelse rotation;
        const kind = s.get(v, "Type") orelse return error.InvalidPageTree;
        if (kind != .name) return error.InvalidPageTree;
        if (std.mem.eql(u8, kind.name, "Pages")) {
            if (s.get(v, "Annots") != null) self.unsupported_appearance = true;
            const kids = try self.resolve(s.get(v, "Kids") orelse return error.InvalidPageTree);
            if (kids != .array) return error.InvalidPageTree;
            for (kids.array) |k| try self.walk(k, res, media, crop_box, rotate, path, visited, result);
        } else if (std.mem.eql(u8, kind.name, "Page")) {
            const mb = try self.resolve(media orelse return error.MissingMediaBox);
            if (mb != .array or mb.array.len != 4) return error.InvalidMediaBox;
            _ = try rectangle(mb);
            const cb = if (crop_box) |value_| try self.resolve(value_) else null;
            var degrees: i32 = 0;
            if (rotate) |value_| {
                const n = try self.resolve(value_);
                if (n != .integer or @mod(n.integer, 90) != 0) return error.InvalidRotation;
                degrees = @intCast(@mod(n.integer, 360));
            }
            try result.append(self.allocator(), .{ .object_id = value.ref.id, .number = result.items.len + 1, .resources = try self.resolve(res orelse return error.MissingResources), .media_box = mb, .crop_box = cb, .rotation = degrees, .contents = &.{} });
        } else return error.InvalidPageTree;
    }
    pub fn indexPages(self: *Document) anyerror![]Page {
        const root = try self.resolve(s.get(self.trailer, "Root").?);
        for ([_][]const u8{ "OCProperties", "OutputIntents" }) |key| {
            if (s.get(root, key) != null) self.unsupported_appearance = true;
        }
        if (s.get(root, "AcroForm")) |raw| {
            const form = try self.resolve(raw);
            if (form != .dict) {
                self.unsupported_appearance = true;
            } else for (form.dict) |entry| {
                const value = try self.resolve(entry.value);
                // Resource-only forms supply FreeText fonts without introducing widgets.
                if (std.mem.eql(u8, entry.key, "DR") and value == .dict) continue;
                if (std.mem.eql(u8, entry.key, "Fields") and value == .array and value.array.len == 0) continue;
                self.unsupported_appearance = true;
            }
        }
        var path: std.ArrayList(u32) = .empty;
        var pages: std.ArrayList(Page) = .empty;
        const visited = try self.allocator().alloc(bool, self.entries.len);
        @memset(visited, false);
        try self.walk(s.get(root, "Pages") orelse return error.InvalidCatalog, null, null, null, null, &path, visited, &pages);
        self.page_numbers = .empty;
        for (pages.items, 0..) |page, i| {
            _ = try page.visibleBox();
            try self.page_numbers.put(self.allocator(), page.object_id, i);
        }
        return pages.toOwnedSlice(self.allocator());
    }
    // The page tree already holds each page dictionary. Leave its streams on
    // disk until this particular page is opened (including indirect arrays).
    pub fn resolveContents(self: *Document, page: *Page) !void {
        const object_ = try self.object(.{ .id = page.object_id, .generation = self.entries[page.object_id].generation });
        const contents = s.get(object_.value, "Contents") orelse return;
        if (contents == .ref and (try self.object(contents.ref)).stream != null) {
            page.contents = try self.allocator().dupe(u32, &.{contents.ref.id});
            return;
        }
        const array = try self.resolve(contents);
        if (array != .array) return error.InvalidContents;
        const ids = try self.allocator().alloc(u32, array.array.len);
        for (array.array, ids) |item, *id| {
            if (item != .ref or (try self.object(item.ref)).stream == null) return error.InvalidContents;
            id.* = item.ref.id;
        }
        page.contents = ids;
    }
    pub fn inspect(self: *Document) anyerror![]Page {
        if (self.pages) |pages| return pages;
        const pages = try self.indexPages();
        for (pages) |*page| {
            self.context.page = page.number;
            try self.resolveContents(page);
            page.runs = try @import("content.zig").inspect(self, page);
        }
        self.pages = pages;
        return pages;
    }
    pub fn replace(self: *Document, page: usize, run: usize, text: []const u8) !void {
        try @import("content.zig").replace(self, page, run, text);
    }
    fn reachableObjects(self: *Document, a: A) ![]bool {
        const reachable = try a.alloc(bool, self.entries.len);
        errdefer a.free(reachable);
        @memset(reachable, false);
        var pending: std.ArrayList(s.Value) = .empty;
        defer pending.deinit(a);
        try pending.append(a, self.trailer);
        while (pending.pop()) |value| switch (value) {
            .ref => |ref| {
                if (ref.id == 0 or ref.id >= self.entries.len) return error.MissingReference;
                const entry = self.entries[ref.id];
                if (!entry.live or entry.generation != ref.generation) return error.MissingReference;
                if (reachable[ref.id]) continue;
                reachable[ref.id] = true;
                try pending.append(a, (try self.object(ref)).value);
            },
            .array => |values| try pending.appendSlice(a, values),
            .dict => |entries| for (entries) |entry| {
                try pending.append(a, entry.value);
            },
            else => {},
        };
        return reachable;
    }
    pub fn save(self: *Document, a: A) ![]u8 {
        const reachable = try self.reachableObjects(a);
        defer a.free(reachable);
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(a);
        try out.appendSlice(a, "%PDF-1.7\n%\xe2\xe3\xcf\xd3\n");
        const offsets = try a.alloc(usize, self.entries.len);
        defer a.free(offsets);
        @memset(offsets, 0);
        for (self.entries, 0..) |x, i| {
            if (!x.live or !reachable[i]) continue;
            const o = try self.object(.{ .id = @intCast(i), .generation = x.generation });
            offsets[i] = out.items.len;
            try out.print(a, "{d} {d} obj\n", .{ i, x.generation });
            if (o.changed orelse (if (o.dirty) o.stream else null)) |data| {
                try out.appendSlice(a, "<<");
                for (o.value.dict) |entry| {
                    if (std.mem.eql(u8, entry.key, "Length")) continue;
                    try serialize(a, &out, .{ .name = entry.key });
                    try serialize(a, &out, entry.value);
                }
                try out.print(a, " /Length {d} >>\nstream\n", .{data.len});
                try out.appendSlice(a, data);
                try out.appendSlice(a, "\nendstream\n");
            } else if (o.dirty) try serialize(a, &out, o.value) else try out.appendSlice(a, o.body);
            try out.appendSlice(a, "\nendobj\n");
        }
        const xref = out.items.len;
        var next_free: usize = 0;
        var free_index = self.entries.len;
        while (free_index > 1) {
            free_index -= 1;
            if (!self.entries[free_index].live or !reachable[free_index]) {
                offsets[free_index] = next_free;
                next_free = free_index;
            }
        }
        try out.print(a, "xref\n0 {d}\n{d:0>10} 65535 f \n", .{ self.entries.len, next_free });
        for (self.entries[1..], 1..) |x, i| {
            if (x.live and reachable[i]) try out.print(a, "{d:0>10} {d:0>5} n \n", .{ offsets[i], x.generation }) else try out.print(a, "{d:0>10} {d:0>5} f \n", .{ offsets[i], if (x.live) x.generation +| 1 else x.generation });
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
