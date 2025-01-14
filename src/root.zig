const std = @import("std");
const abnf = @import("abnf.gen.zig");
pub const Rule = @import("rule.zig").Rule;
pub const Node = @import("node.zig").Node;
pub const gen_parser = @import("parser.zig").gen_parser;

test "main" {
  std.debug.print("\n", .{});
  const allocator = std.testing.allocator;
  const input = try std.fs.cwd().readFileAlloc(allocator, "old/abnf/abnf.abnf", std.math.maxInt(usize));
  defer allocator.free(input);
  const keep: []const abnf.Tag = &.{
    .rulelist, .comment, .rule, .rulename, .defined_as,
    .alternation, .concatenation, .repetition, .option,
    .repeat, .char_val, .bin_val, .dec_val, .hex_val,
  };
  const parse = gen_parser(abnf, keep);
  const ast = try parse(allocator, input);
  defer ast.deinit();
  std.debug.print("{}", .{ast});
}