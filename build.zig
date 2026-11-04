const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const mod = b.addModule("pod", .{ .root_source_file = b.path("src/pod.zig"), .target = target, .optimize = optimize });
    const exe = b.addExecutable(.{ .name = "pod", .root_module = b.createModule(.{ .root_source_file = b.path("src/main.zig"), .target = target, .optimize = optimize, .link_libc = true, .strip = optimize != .debug }) });
    exe.root_module.addImport("pod", mod);
    b.installArtifact(exe);
    const tests = b.addTest(.{ .root_module = mod });
    b.step("test", "Run engine tests").dependOn(&b.addRunArtifact(tests).step);
}
