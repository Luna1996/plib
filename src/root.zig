const std = @import("std");
const abnf = @import("abnf.gen.zig");
pub const Rule = @import("rule.zig").Rule;
pub const Node = @import("node.zig").Node;
pub const gen_parser = @import("parser.zig").gen_parser;

test "main" {
  const allocator = std.testing.allocator;
  const input = try std.fs.cwd().readFileAlloc(allocator, "old/toml/toml.abnf", std.math.maxInt(usize));
  defer allocator.free(input);
  const keep: []const abnf.Tag = &.{
    .rulelist, .comment, .rule, .rulename, .defined_as,
  };
  const parse = gen_parser(abnf, keep);
  const ast = try parse(allocator, input);
  defer ast.deinit();
  std.debug.print("\n{}", .{ast});
}