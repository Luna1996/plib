const std = @import("std");
const abnf = @import("gen.abnf").abnf;
const plib = @import("plib");
const Rule = plib.Rule;

pub const ABNF = struct {
  const Self = @This();
  const Tag: type = abnf.toTag();
  const Node = plib.Node(Tag);
  const keep = [_]Tag {
    .rulelist, .comment, .rule, .rulename, .defined_as,
    .alternation, .concatenation, .repetition, .option,
    .repeat, .char_val, .bin_val, .dec_val, .hex_val,
  };

  names: []const [:0]const u8,
  rules: []const Rule,

  pub fn toTag(comptime self: Self) type {
    comptime var fields: [self.names.len]std.builtin.Type.EnumField = undefined;
    inline for (&fields, self.names, 0..) |*field, name, i| field.* = .{ .name = name, .value = i };
    return @Type(.{.@"enum" = .{
      .tag_type = std.math.Log2Int(std.meta.Int(.unsigned, self.names.len)),
      .decls = &.{},
      .fields = &fields,
      .is_exhaustive = true,
    }});
  }

  pub fn parse(allocator: std.mem.Allocator, input: []const u8) !void {
    var root = try plib.gen_parser(abnf, &keep)(allocator, input);
    defer root.deinit();
    std.debug.print("{}", .{root});
  }
};

pub fn main() !void {}