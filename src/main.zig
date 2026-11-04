const std = @import("std");
const pod = @import("pod");
const builtin = @import("builtin");
const A = std.mem.Allocator;
extern "c" fn fopen([*:0]const u8, [*:0]const u8) ?*anyopaque;
extern "c" fn fclose(*anyopaque) c_int;
extern "c" fn fseek(*anyopaque, c_long, c_int) c_int;
extern "c" fn ftell(*anyopaque) c_long;
extern "c" fn fread([*]u8, usize, usize, *anyopaque) usize;
extern "c" fn open([*:0]const u8, c_int, ...) c_int;
extern "c" fn close(c_int) c_int;
extern "c" fn write(c_int, [*]const u8, usize) isize;
extern "c" fn unlink([*:0]const u8) c_int;
fn emit(fd: c_int, bytes: []const u8) !void {
    var offset: usize = 0;
    while (offset < bytes.len) {
        const n = write(fd, bytes[offset..].ptr, bytes.len - offset);
        if (n <= 0) return error.WriteFailed;
        offset += @intCast(n);
    }
}
fn readFile(a: A, path: [*:0]const u8) ![]u8 {
    const f = fopen(path, "rb") orelse return error.CannotOpenInput;
    defer _ = fclose(f);
    if (fseek(f, 0, 2) != 0) return error.CannotReadInput;
    const length = ftell(f);
    if (length < 0 or length > 256 * 1024 * 1024) return error.FileLimit;
    if (fseek(f, 0, 0) != 0) return error.CannotReadInput;
    const bytes = try a.alloc(u8, @intCast(length));
    errdefer a.free(bytes);
    if (fread(bytes.ptr, 1, bytes.len, f) != bytes.len) return error.CannotReadInput;
    return bytes;
}
fn writeNew(path: [*:0]const u8, bytes: []const u8) !void {
    const flags: c_int = if (builtin.os.tag == .macos) 1 | 0x200 | 0x800 else 1 | 0x40 | 0x80;
    const fd = open(path, flags, @as(c_uint, 0o644));
    if (fd < 0) return error.OutputExistsOrCannotCreate;
    errdefer _ = unlink(path);
    emit(fd, bytes) catch |err| {
        _ = close(fd);
        return err;
    };
    if (close(fd) != 0) return error.WriteFailed;
}
fn quoted(a: A, out: *std.ArrayList(u8), text: []const u8) !void {
    try out.append(a, '"');
    for (text) |c| {
        if (c == '"' or c == '\\') try out.append(a, '\\');
        try out.append(a, c);
    }
    try out.append(a, '"');
}
fn inspectJson(a: A, doc: *pod.Document) ![]u8 {
    const pages = try doc.inspect();
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(a);
    try out.appendSlice(a, "{\"pages\":[");
    for (pages, 0..) |page, i| {
        if (i != 0) try out.append(a, ',');
        try out.print(a, "{{\"number\":{d},\"runs\":[", .{page.number});
        for (page.runs, 0..) |run, j| {
            if (j != 0) try out.append(a, ',');
            try out.print(a, "{{\"id\":{d},\"text\":", .{run.id});
            try quoted(a, &out, run.text);
            try out.print(a, ",\"x\":{d},\"y\":{d},\"font_size\":{d},\"advance\":{d}}}", .{ run.x, run.y, run.font_size, run.advance });
        }
        try out.appendSlice(a, "]}");
    }
    try out.appendSlice(a, "]}\n");
    return out.toOwnedSlice(a);
}
fn context(doc: *pod.Document) void {
    var buffer: [256]u8 = undefined;
    const c = doc.context;
    const message = std.fmt.bufPrint(&buffer, "context: page {d}, object {d}, operator {s}\n", .{ c.page, c.object_id, c.operator }) catch return;
    emit(2, message) catch {};
}
fn command(a: A, args: []const [*:0]u8) !void {
    if (args.len < 2) return error.Usage;
    const verb = std.mem.span(args[1]);
    if (std.mem.eql(u8, verb, "create")) {
        if (args.len < 3 or args.len > 4) return error.Usage;
        const bytes = try pod.create(a, if (args.len == 4) std.mem.span(args[3]) else "Hello from Pod");
        defer a.free(bytes);
        try writeNew(args[2], bytes);
    } else if (std.mem.eql(u8, verb, "inspect") or std.mem.eql(u8, verb, "replace")) {
        const editing = std.mem.eql(u8, verb, "replace");
        if (args.len != (if (editing) @as(usize, 7) else @as(usize, 3))) return error.Usage;
        const bytes = try readFile(a, args[2]);
        defer a.free(bytes);
        var doc = try pod.Document.open(a, bytes);
        defer doc.deinit();
        if (editing) {
            const page = std.fmt.parseInt(usize, std.mem.span(args[4]), 10) catch return error.InvalidPageNumber;
            const run = std.fmt.parseInt(usize, std.mem.span(args[5]), 10) catch return error.InvalidRunID;
            doc.replace(page, run, std.mem.span(args[6])) catch |err| {
                context(&doc);
                return err;
            };
            const saved = doc.save(a) catch |err| {
                context(&doc);
                return err;
            };
            defer a.free(saved);
            try writeNew(args[3], saved);
        } else {
            const json = inspectJson(a, &doc) catch |err| {
                context(&doc);
                return err;
            };
            defer a.free(json);
            try emit(1, json);
        }
    } else return error.Usage;
}
pub export fn main(argc: c_int, argv: [*][*:0]u8) c_int {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    command(arena.allocator(), argv[0..@intCast(argc)]) catch |err| {
        emit(2, "pod: ") catch {};
        emit(2, @errorName(err)) catch {};
        if (argc > 2) {
            emit(2, " — ") catch {};
            emit(2, std.mem.span(argv[2])) catch {};
        }
        emit(2, "\n") catch {};
        if (err == error.Usage) emit(2, "usage: pod create OUTPUT.pdf [TEXT]\n       pod inspect INPUT.pdf\n       pod replace INPUT.pdf OUTPUT.pdf PAGE RUN_ID REPLACEMENT\n") catch {};
        return 1;
    };
    return 0;
}
