// Integration test for the library model; the strict native open/render gate stays intact.
const std = @import("std");
const pod = @import("pod");
extern "c" fn fopen([*:0]const u8, [*:0]const u8) ?*anyopaque;
extern "c" fn fclose(*anyopaque) c_int;
extern "c" fn fseek(*anyopaque, c_long, c_int) c_int;
extern "c" fn ftell(*anyopaque) c_long;
extern "c" fn fread([*]u8, usize, usize, *anyopaque) usize;
extern "c" fn fwrite([*]const u8, usize, usize, *anyopaque) usize;
fn writeFile(path: [*:0]const u8, bytes: []const u8) !void {
    const file = fopen(path, "wb") orelse return error.CannotOpen;
    defer _ = fclose(file);
    if (fwrite(bytes.ptr, 1, bytes.len, file) != bytes.len) return error.CannotWrite;
}
fn check(root: []const u8, name: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const path = try std.fmt.allocPrintSentinel(a, "{s}/{s}.pdf", .{ root, name }, 0);
    const file = fopen(path, "rb") orelse return error.CannotOpen;
    defer _ = fclose(file);
    if (fseek(file, 0, 2) != 0) return error.CannotRead;
    const size = ftell(file);
    if (size < 0 or size > 4 * 1024 * 1024 or fseek(file, 0, 0) != 0) return error.CannotRead;
    const bytes = try a.alloc(u8, @intCast(size));
    if (fread(bytes.ptr, 1, bytes.len, file) != bytes.len) return error.CannotRead;
    var doc = try pod.Document.open(a, bytes);
    defer doc.deinit();
    const annotations = pod.annotations;
    const marks = try annotations.list(&doc, 0);
    try std.testing.expectEqual(@as(usize, 1), marks.len);
    const old = marks[0];
    try std.testing.expectEqualStrings("Bài học ✓ 😀", old.text);
    try annotations.update(&doc, 0, old.id, .comment, old.points, "Cần dẫn chứng — 已阅", old.style);
    const saved = try doc.save(a);
    try writeFile(try std.fmt.allocPrintSentinel(a, "{s}/{s}-edited.pdf", .{ root, name }, 0), saved);
    var reopened = try pod.Document.open(a, saved);
    defer reopened.deinit();
    try std.testing.expectEqualStrings("Cần dẫn chứng — 已阅", (try annotations.list(&reopened, 0))[0].text);
    try annotations.remove(&reopened, 0, old.id);
    try std.testing.expectEqual(@as(usize, 0), (try annotations.refs(&reopened, 0)).len);
    try writeFile(try std.fmt.allocPrintSentinel(a, "{s}/{s}-removed.pdf", .{ root, name }, 0), try reopened.save(a));
}
pub export fn main(argc: c_int, argv: [*][*:0]u8) c_int {
    if (argc != 2) return 2;
    for ([_][]const u8{ "pdfkit", "mupdf" }) |name| {
        check(std.mem.span(argv[1]), name) catch |err| {
            std.debug.print("FAIL: {s}: {s}\n", .{ name, @errorName(err) });
            return 1;
        };
        std.debug.print("PASS: library imported {s} comment read/edit/save/reopen/delete\n", .{name});
    }
    return 0;
}
