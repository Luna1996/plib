const std = @import("std");

pub fn build(b: *std.Build) !void {
  const target = b.standardTargetOptions(.{});
  const optimize = b.standardOptimizeOption(.{});
  
  const root_mod = b.addModule("root", .{
    .target = target,
    .optimize = optimize,
    .root_source_file = b.path("src/root.zig"),
  });

  addGeneratedModules(b, root_mod);

  const test_exe = b.addTest(.{
    .target = target,
    .optimize = optimize,
    .root_module = root_mod,
  });
  const test_ins = b.addInstallArtifact(test_exe, .{});

  const test_step = b.step("test", "test library");
  test_step.dependOn(&test_ins.step);
}

fn addGeneratedModules(b: *std.Build, root_mod: *std.Build.Module) !void {
  const gen_dir = try std.fs.cwd().openDir("gen", .{ .iterate = true });
  defer gen_dir.close();
  var iter = gen_dir.iterate();
  while (try iter.next()) |entry| switch (entry.kind) {
    .file => {
      const mod_name = try std.fmt.allocPrint(b.allocator, "gen.{s}", .{entry.name[0..entry.name.len - 4]});
      defer b.allocator.free(mod_name);
      const mod_path = try std.fmt.allocPrint(b.allocator, "gen/{s}", .{entry.name});
      defer b.allocator.free(mod_path);
      const gen_mod = b.addModule(mod_name, .{
        .target = root_mod.resolved_target,
        .optimize = root_mod.optimize,
        .root_source_file = b.path(mod_path),
      });
      root_mod.addImport(mod_name, gen_mod);
    },
    else => {},
  };
}