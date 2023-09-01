const std = @import("std");

pub fn build(b: *std.Build) void {
  const file = b.args.?[0];
  const base = std.fs.path.basename(b.args.?[0]);
  const opts = .{
    .name = base[0..base.len - 4],
    .root_source_file = .{ .path = file },
    .target = b.standardTargetOptions(.{}),
    .optimize = b.standardOptimizeOption(.{}),
  };

  b.installArtifact(b.addExecutable(opts));

  b.step("test", "build test binary for current module")
    .dependOn(&b.addInstallArtifact(b.addTest(opts), .{}).step);
}
