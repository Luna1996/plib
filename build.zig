const std = @import("std");

pub fn build(b: *std.Build) void {
  const target = b.standardTargetOptions(.{});
  const optimize = b.standardOptimizeOption(.{});
  const file = b.option([]const u8, "file", "The file to be built.") orelse {
    std.log.err("Require a .zig file to be built.", .{});
    return;
  };
  const base = std.fs.path.basename(file);
  const opts = .{
    .name = base[0..base.len - 4],
    .root_source_file = .{ .path = file },
    .target = target,
    .optimize = optimize,
    .main_pkg_path = std.Build.LazyPath.relative("src"),
  };

  b.getInstallStep().dependOn(&b.addInstallArtifact(b.addExecutable(opts), .{}).step);
  
  b.step("test", "build test binary for current module")
    .dependOn(&b.addInstallArtifact(b.addTest(opts), .{}).step);
}