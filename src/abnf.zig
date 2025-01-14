const std = @import("std");
const abnf = @import("gen.abnf").getABNF(ABNF);
const Rule = @import("rule.zig").Rule;
const Node = @import("node.zig").Node;
const gen_parser = @import("parser.zig").gen_parser;

pub const ABNF = struct {
  const Self = @This();

  names: []const [:0]const u8,
  rules: []const Rule,

  pub fn Tag(comptime self: Self) type {
    comptime var fields: [self.names.len]std.builtin.Type.EnumField = undefined;
    inline for (&fields, self.names, 0..) |*field, name, i| field.* = .{ .name = name, .value = i };
    return @Type(.{.@"enum" = .{
      .tag_type = std.math.Log2Int(std.meta.Int(.unsigned, self.names.len)),
      .decls = &.{},
      .fields = &fields,
      .is_exhaustive = true,
    }});
  }

  pub fn parse(allocator: std.mem.Allocator, input: []const u8) !ABNF {
    
  }

  // pub fn deinit(self: Self, allocator: std.mem.Allocator) void {}
};