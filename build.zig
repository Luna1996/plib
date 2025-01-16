const std = @import("std");

const Builder = struct {
  const Self = @This();

  b: *std.Build,
  target: std.Build.ResolvedTarget,
  optimize: std.builtin.OptimizeMode,
  plib_mod: *std.Build.Module,
  name: ?[]const u8 = null,

  fn init(b: *std.Build) Self {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const plib_mod = b.addModule("plib", .{
      .target = target,
      .optimize = optimize,
      .root_source_file = b.path("src/lib/root.zig"),
    });
    return .{
      .b = b,
      .target = target,
      .optimize = optimize,
      .plib_mod = plib_mod,
      .name = b.option([]const u8, "name", "input file/module name"),
    };
  }

  fn build(self: Self) !void {
    try self.buildMods();
    try self.buildMain();
    try self.buildTest();
  }

  fn buildMods(self: Self) !void {
    var gen_dir = try self.b.build_root.handle.openDir("src/mod", .{ .iterate = true });
    defer gen_dir.close();
    var iter = gen_dir.iterate();
    while (try iter.next()) |entry| switch (entry.kind) {
      .file => try self.buildMod(entry.name),
      else => {},
    };
  }

  fn buildMod(self: Self, file_name: []const u8) !void {
    const mod_name = file_name[0..file_name.len - 4];
    const mod_path = try std.fmt.allocPrint(self.b.allocator, "src/mod/{s}", .{file_name});
    defer self.b.allocator.free(mod_path);
    const mod_mod = self.b.addModule(mod_name, .{
      .target = self.target,
      .optimize = self.optimize,
      .root_source_file = self.b.path(mod_path),
    });

    const gen_name = try std.fmt.allocPrint(self.b.allocator, "gen.{s}", .{mod_name});
    defer self.b.allocator.free(gen_name);
    const gen_path = try std.fmt.allocPrint(self.b.allocator, "src/gen/{s}", .{file_name});
    defer self.b.allocator.free(gen_path);
    const gen_mod = self.b.createModule(.{
      .target = self.target,
      .optimize = self.optimize,
      .root_source_file = self.b.path(gen_path),
    });
    gen_mod.addImport("plib", self.plib_mod);
    mod_mod.addImport("gen", gen_mod);
    mod_mod.addImport("plib", self.plib_mod);
  }

  fn buildMain(self: Self) !void {
    const gen_step = self.b.step("gen", "generate src/gen/<name>.zig using src/raw/<name>.abnf");
    if (self.name) |gen_name| {
      const gen_exe = self.b.addExecutable(.{
        .name = "gen",
        .target = self.target,
        .optimize = self.optimize,
        .root_source_file = self.b.path("src/exe/main.zig"),
      });
      gen_exe.root_module.addImport("abnf", self.b.modules.get("abnf").?);
      const gen_run = self.b.addRunArtifact(gen_exe);
      gen_run.setCwd(self.b.path("."));
      gen_run.addArg(gen_name);
      gen_run.stdio = .inherit;
      gen_step.dependOn(&gen_run.step);
    } else {
      gen_step.dependOn(&self.b.addFail("The -Dname=... option is required for this step").step);
    }
  }

  fn buildTest(self: Self) !void {
    const test_step = self.b.step("test", "test [name] module");
    if (self.name) |mod_name| {
      if (self.b.modules.get(mod_name)) |test_mod| {
        test_step.dependOn(&self.b.addInstallArtifact(self.b.addTest(.{
          .optimize = self.optimize,
          .root_module = test_mod,
        }), .{}).step);
      } else {
        test_step.dependOn(&self.b.addFail(try std.fmt.allocPrint(self.b.allocator, "{s} is not a module name", .{mod_name})).step);
      }
    } else {
      test_step.dependOn(&self.b.addFail("The -Dname=... option is required for this step").step);
    }
  }
};

pub fn build(b: *std.Build) !void { try Builder.init(b).build();}