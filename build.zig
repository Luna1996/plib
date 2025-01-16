const std = @import("std");

pub fn build(b: *std.Build) !void {
  const target = b.standardTargetOptions(.{});
  const optimize = b.standardOptimizeOption(.{});

  const plib_mod = b.addModule("plib", .{
    .target = target,
    .optimize = optimize,
    .root_source_file = b.path("src/lib/root.zig"),
  });

  try addMods(b);

  const main_mod = b.createModule(.{
    .target = target,
    .optimize = optimize,
    .root_source_file = b.path("src/exe/main.zig"),
  });
  main_mod.addImport("plib", plib_mod);
  main_mod.addImport("abnf", b.modules.get("abnf").?);

  const test_exe = b.addTest(.{
    .optimize = optimize,
    .root_module = main_mod,
  });

  const test_step = b.step("test", "test full library");
  test_step.dependOn(&b.addInstallArtifact(test_exe, .{}).step);

  const gen_step = b.step("gen", "generate src/gen/<name>.zig using src/raw/<name>.abnf");
  const opt_gen_name = b.option([]const u8, "name", "base file name without extension of the abnf input file in gen step");
  if (opt_gen_name) |gen_name| {
    const gen_run = b.addRunArtifact(b.addExecutable(.{
      .name = "gen",
      .optimize = optimize,
      .root_module = main_mod,
    }));
    gen_run.setCwd(b.path("."));
    gen_run.addArg(gen_name);
    gen_run.stdio = .inherit;
    gen_step.dependOn(&gen_run.step);
  } else {
    gen_step.dependOn(&b.addFail("The -Dname=... option is required for this step").step);
  }
}

fn addMods(b: *std.Build) !void {
  var gen_dir = try b.build_root.handle.openDir("src/mod", .{ .iterate = true });
  defer gen_dir.close();
  var iter = gen_dir.iterate();
  while (try iter.next()) |entry| switch (entry.kind) {
    .file => try addMod(b, entry.name),
    else => {},
  };
}

fn addMod(b: *std.Build, file_name: []const u8) !void {
  const plib_mod = b.modules.get("plib").?;
  const target = plib_mod.resolved_target;
  const optimize = plib_mod.optimize orelse .Debug;
  
  const mod_name = file_name[0..file_name.len - 4];
  const mod_path = try std.fmt.allocPrint(b.allocator, "src/mod/{s}", .{file_name});
  defer b.allocator.free(mod_path);
  const mod_mod = b.addModule(mod_name, .{
    .target = target,
    .optimize = optimize,
    .root_source_file = b.path(mod_path),
  });

  const gen_name = try std.fmt.allocPrint(b.allocator, "gen.{s}", .{mod_name});
  defer b.allocator.free(gen_name);
  const gen_path = try std.fmt.allocPrint(b.allocator, "src/gen/{s}", .{file_name});
  defer b.allocator.free(gen_path);
  const gen_mod = b.createModule(.{
    .target = target,
    .optimize = optimize,
    .root_source_file = b.path(gen_path),
  });
  gen_mod.addImport("plib", plib_mod);
  mod_mod.addImport(gen_name, gen_mod);
  mod_mod.addImport("plib", plib_mod);
}