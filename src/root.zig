const std = @import("std");
pub const Rule = @import("rule.zig").Rule;
pub const Node = @import("node.zig").Node;

test "main" {
  std.debug.print("{d}\n", .{@sizeOf(Node)});
}