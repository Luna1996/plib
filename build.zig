const std = @import("std");

const Builder = struct {
  b: *std.Build,
  
  conf: Conf,
  mods: std.enums.EnumArray(Name, *std.Build.Module),

  const Self = @This();

  const Conf = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    step: []Step,
    name: ?Name,
    need: std.enums.EnumSet(Name),
  }; 

  const Step = enum {
    @"test", gen_abnf, toml_test,
  };

  const step_fns = std.enums.EnumArray(Step, *const fn(Self) void).init(.{
    .@"test" = buildTest,
    .gen_abnf = buildGenABNF,
    .toml_test = buildAllTomlTest,
  });

  const Name = enum {
    plib, abnf, toml,
  };

  const mod_fns = std.enums.EnumArray(Name, *const fn(Self) *std.Build.Module).init(.{
    .plib = buildPlib,
    .abnf = buildABNF,
    .toml = buildToml,
  });

  fn init(b: *std.Build) Self {
    var self: Self = undefined;
    self.b = b;
    self.initOpts();
    return self;
  }

  fn initOpts(self: *Self) void {
    self.conf.target = self.b.standardTargetOptions(.{});
    self.conf.optimize = self.b.standardOptimizeOption(.{});

    self.conf.step = self.b.option([]Step, "step", "Which step to take") orelse &.{};
    self.conf.name = self.b.option(Name, "name", "Input file base name");

    const need = self.b.option([]Name, "need", "list of needed mod names") orelse &.{};
    for (need) |name| self.conf.need.setPresent(name, true);

    self.conf.need.setPresent(.plib, true);

    for (self.conf.step) |step| switch (step) {
      .@"test" => if (self.conf.name) |name| 
        self.conf.need.setPresent(name, true),
      .gen_abnf =>
        self.conf.need.setPresent(.abnf, true),
      .toml_test =>
        self.conf.need.setPresent(.toml, true),
    };
  }

  fn build(b: *std.Build) void {
    var self = init(b);
    
    for (std.meta.tags(Name)) |name|
      if (self.conf.need.contains(name))
        self.mods.set(name, mod_fns.get(name)(self));

    for (self.conf.step) |step|
      step_fns.get(step)(self);
  }

  fn buildPlib(self: Self) *std.Build.Module {
    return self.b.addModule("plib", .{
      .target = self.conf.target,
      .optimize = self.conf.optimize,
      .root_source_file = self.b.path("src/lib/root.zig"),
    });
  }

  fn buildABNF(self: Self) *std.Build.Module {
    return self.buildSubMod(.abnf);
  }

  fn buildToml(self: Self) *std.Build.Module {
    return self.buildSubMod(.toml);
  }

  fn buildSubMod(self: Self, comptime file: Name) *std.Build.Module {
    const mod_name = @tagName(file);
    const mod_path = "src/mod/" ++ mod_name ++ "/root.zig";
    const gen_path = "src/gen/" ++ mod_name ++ ".zig";

    const mod_mod = self.b.addModule(mod_name, .{
      .target = self.conf.target,
      .optimize = self.conf.optimize,
      .root_source_file = self.b.path(mod_path),
    });
    
    const gen_mod = self.b.createModule(.{
      .target = self.conf.target,
      .optimize = self.conf.optimize,
      .root_source_file = self.b.path(gen_path),
    });
    
    mod_mod.addImport("gen", gen_mod);
    self.addImport(gen_mod, .plib);
    self.addImport(mod_mod, .plib);

    return mod_mod;
  }

  fn buildTest(self: Self) void {
    const step = self.b.default_step;

    const name = self.conf.name orelse {
      step.dependOn(&self.b.addFail("The -Dname=... option is required for this step").step);
      return;
    };

    step.dependOn(&self.b.addInstallArtifact(self.b.addTest(.{
      .optimize = self.conf.optimize,
      .root_module = self.mods.get(name),
    }), .{}).step);
  }

  fn buildGenABNF(self: Self) void {
    const step = self.b.default_step;
    const name = self.conf.name orelse {
      step.dependOn(&self.b.addFail("The -Dname=... option is required for this step").step);
      return;
    };

    const exe = self.b.addExecutable(.{
      .name = "gen_abnf",
      .target = self.conf.target,
      .optimize = self.conf.optimize,
      .root_source_file = self.b.path("src/exe/gen_abnf.zig"),
    });
    self.addImport(exe.root_module, .abnf);

    const run = self.b.addRunArtifact(exe);
    run.addArg(@tagName(name));
    run.stdio = .inherit;

    step.dependOn(&run.step);
  }

  fn buildAllTomlTest(self: Self) void {
    // self.buildOneTomlTest("decoder");
    self.buildOneTomlTest("encoder");
  }

  fn buildOneTomlTest(self: Self, comptime name: []const u8) void {
    const exe_name = "toml_" ++ name;
    
    const test_exe = self.b.addExecutable(.{
      .name = exe_name,
      .target = self.conf.target,
      .optimize = self.conf.optimize,
      .root_source_file = self.b.path("src/exe/toml_test.zig"),
    });
    self.addImport(test_exe.root_module, .toml);

    const test_opt = self.b.addOptions();
    test_opt.addOption([]const u8, "name", name);
    test_exe.root_module.addOptions("opts", test_opt);
    
    var run_step = std.Build.Step.Run.create(self.b, exe_name);
    run_step.addArg("toml-test");
    run_step.addArtifactArg(test_exe);
    run_step.addArgs(&.{"-timeout", "10s"});
    if (std.mem.eql(u8, name, "encoder"))
    run_step.addArg("-" ++ name);

    self.b.default_step.dependOn(&self.b.addInstallArtifact(test_exe, .{}).step); 
    self.b.default_step.dependOn(&run_step.step);
  }

  fn addImport(self: Self, mod: *std.Build.Module, name: Name) void {
    mod.addImport(@tagName(name), self.mods.get(name));
  }
};

pub fn build(b: *std.Build) !void { Builder.build(b); }