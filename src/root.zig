const std = @import("std");
const abnf = @import("abnf.gen.zig");
pub const Rule = @import("rule.zig").Rule;
pub const Node = @import("node.zig").Node;
pub const gen_parser = @import("parser.zig").gen_parser;

test "main" {
  const parse = gen_parser(abnf, &.{.rulelist});
  std.debug.print("{any}\n", .{&parse});
}