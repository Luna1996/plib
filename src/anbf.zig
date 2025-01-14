const std = @import("std");
const anbf = @import("abnf.gen.zig");
const Rule = @import("rule.zig").Rule;

pub const ANBF = struct {
  const Self = @This();

  names: []const []const u8,
  rules: []const Rule,

  pub fn Tag(comptime self: Self) type {
  }

  pub fn parse(allocator: std.mem.Allocator, input: []const u8) !ANBF {

  }

  pub fn deinit(self: Self, allocator: std.mem.Allocator) void {}
};