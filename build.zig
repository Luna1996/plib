const std = @import("std");

pub fn build(b: *std.Build) void {
  const target = b.standardTargetOptions(.{});
  const optimize = b.standardOptimizeOption(.{});
  if (b.args == null or b.args.?.len == 0) return;
  const file = b.args.?[0];
  const base = std.fs.path.basename(b.args.?[0]);
  const opts = .{
    .name = base[0..base.len - 4],
    .root_source_file = .{ .path = file },
    .target = target,
    .optimize = optimize,
    .main_pkg_path = std.Build.LazyPath.relative("src"),
  };

  b.installArtifact(b.addExecutable(opts));

  b.step("test", "build test binary for current module")
    .dependOn(&b.addInstallArtifact(b.addTest(opts), .{}).step);
}
