const std = @import("std");

const Builder = struct {
  b: *std.Build,
  
  conf: Conf,
  mods: std.enums.EnumArray(Name, *std.Build.Module),

  const Self = @This();

  const Conf = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    step: ?Step,
    name: ?Name,
    need: std.enums.EnumSet(Name),
  }; 



  const Step = enum {
    @"test", gen_abnf,
  };

  const step_fns = std.enums.EnumArray(Step, *const fn(Self) void).init(.{
    .@"test" = buildTest,
    .gen_abnf = buildGenABNF,
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

    self.conf.step = self.b.option(Step, "step", "Which step to take");
    self.conf.name = self.b.option(Name, "name", "Input file base name");

    inline for (comptime std.meta.tags(Name)) |tag| {
      const name = @tagName(tag);
      self.conf.need.setPresent(tag,
        self.b.option(bool, name, "Need " ++ name ++ " module") orelse false);
    }

    self.conf.need.setPresent(.plib, true);

    if (self.conf.step) |step| switch (step) {
      .@"test" => if (self.conf.name) |name| 
        self.conf.need.setPresent(name, true),
      .gen_abnf =>
        self.conf.need.setPresent(.abnf, true),
    };
  }

  fn build(b: *std.Build) void {
    var self = init(b);
    
    for (std.meta.tags(Name)) |name| {
      if (self.conf.need.contains(name))
        self.mods.set(name, mod_fns.get(name)(self));
    }
    if (self.conf.step) |step|
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
    const toml_mod = self.buildSubMod(.toml);
    if (self.b.lazyDependency("zeit", .{})) |zeit| {
      toml_mod.addImport("zeit", zeit.module("zeit"));
    }
    return toml_mod;
  }

  fn buildSubMod(self: Self, comptime file: Name) *std.Build.Module {
    const mod_name = @tagName(file);
    const mod_path = "src/mod/" ++ mod_name ++ ".zig";
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
    
    gen_mod.addImport("plib", self.mods.get(.plib));
    mod_mod.addImport("gen", gen_mod);
    mod_mod.addImport("plib", self.mods.get(.plib));

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
    exe.root_module.addImport("abnf", self.mods.get(.abnf));

    const run = self.b.addRunArtifact(exe);
    run.setCwd(self.b.path("."));
    run.addArg(@tagName(name));
    run.stdio = .inherit;

    step.dependOn(&run.step);
  }
};

pub fn build(b: *std.Build) !void { Builder.build(b); }