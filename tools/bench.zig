//! macOS-only benchmark harness; not part of the shipped library or CLI.
const std = @import("std");
const pod = @import("pod");
extern "c" fn fopen([*:0]const u8, [*:0]const u8) ?*anyopaque;
extern "c" fn fclose(*anyopaque) c_int;
extern "c" fn fread([*]u8, usize, usize, *anyopaque) usize;
extern "c" fn write(c_int, [*]const u8, usize) isize;
extern "c" fn mach_absolute_time() u64;
const Timebase = extern struct { numer: u32, denom: u32 };
extern "c" fn mach_timebase_info(*Timebase) c_int;

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const file = fopen("test-out/benchmark/1000-runs.pdf", "rb") orelse return error.MissingFixture;
    defer _ = fclose(file);
    const buffer = try allocator.alloc(u8, 1024 * 1024);
    defer allocator.free(buffer);
    const length = fread(buffer.ptr, 1, buffer.len, file);
    if (length == 0 or length == buffer.len) return error.InvalidFixture;
    var timebase: Timebase = undefined;
    if (mach_timebase_info(&timebase) != 0) return error.Clock;
    const scale = @as(f64, @floatFromInt(timebase.numer)) / @as(f64, @floatFromInt(timebase.denom)) / 1e6;
    const labels = [_][]const u8{ "open", "inspect", "replace", "save" };
    for (labels, 0..) |label, operation| {
        var samples: [31]u64 = undefined;
        var checksum: usize = 0;
        for (&samples) |*sample| {
            var elapsed: u64 = 0;
            for (0..50) |_| {
                const open_start = mach_absolute_time();
                var document = try pod.Document.open(allocator, buffer[0..length]);
                if (operation == 0) elapsed += mach_absolute_time() - open_start;
                defer document.deinit();
                if (operation == 1) {
                    const start = mach_absolute_time();
                    const pages = try document.inspect();
                    elapsed += mach_absolute_time() - start;
                    checksum +%= pages.len;
                } else if (operation >= 2) {
                    _ = try document.inspect();
                    const edit_start = mach_absolute_time();
                    try document.replace(1, 0, "Hi");
                    if (operation == 2) elapsed += mach_absolute_time() - edit_start;
                    if (operation == 3) {
                        const save_start = mach_absolute_time();
                        const output = try document.save(allocator);
                        elapsed += mach_absolute_time() - save_start;
                        checksum +%= output.len;
                        allocator.free(output);
                    }
                }
            }
            sample.* = elapsed;
        }
        // Drop the first batch; each remaining sample amortizes clock overhead.
        std.mem.sort(u64, samples[1..], {}, std.sort.asc(u64));
        var output_buffer: [512]u8 = undefined;
        const output = try std.fmt.bufPrint(&output_buffer, "{{\"operation\":\"{s}\",\"batches\":30,\"operations_per_batch\":50,\"median_ms\":{d:.6},\"p95_ms\":{d:.6},\"checksum\":{d}}}\n", .{ label, (@as(f64, @floatFromInt(samples[15])) + @as(f64, @floatFromInt(samples[16]))) * 0.5 * scale / 50, @as(f64, @floatFromInt(samples[29])) * scale / 50, checksum });
        if (write(1, output.ptr, output.len) != output.len) return error.Write;
    }
}
