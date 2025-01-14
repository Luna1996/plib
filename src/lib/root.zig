const std = @import("std");
pub const ABNF = @import("abnf").ABNF;
pub const Rule = @import("rule.zig").Rule;
pub const Node = @import("node.zig").Node;
pub const gen_parser = @import("gen_parser.zig").gen_parser;

pub fn main() !void {}

test "main" {
  std.debug.print("\n", .{});
  const allocator = std.testing.allocator;
  const input = try std.fs.cwd().readFileAlloc(allocator, "src/raw/abnf.abnf", std.math.maxInt(usize));
  defer allocator.free(input);
  try ABNF.parse(allocator, input);
}