const std = @import("std");

pub fn build(b: *std.Build) void {
  const target = b.standardTargetOptions(.{});
  const optimize = b.standardOptimizeOption(.{});
  
  const root_mod = b.addModule("root", .{
    .target = target,
    .optimize = optimize,
    .root_source_file = b.path("src/root.zig"),
  });

  const test_exe = b.addTest(.{
    .target = target,
    .optimize = optimize,
    .root_module = root_mod,
  });
  const test_ins = b.addInstallArtifact(test_exe, .{});

  const test_step = b.step("test", "test library");
  test_step.dependOn(&test_ins.step);
}