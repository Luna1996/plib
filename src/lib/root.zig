const std = @import("std");
pub const ABNF = @import("abnf").ABNF;
pub const Rule = @import("rule.zig").Rule;
pub const Parser = @import("parser.zig").Parser;

pub fn main() !void {}

test "main" {
  std.debug.print("\n", .{});
  const allocator = std.testing.allocator;
  const file_path = "src/raw/abnf.abnf";
  const input = try std.fs.cwd().readFileAlloc(allocator, file_path, std.math.maxInt(usize));
  defer allocator.free(input);
  const real_path = try std.fs.cwd().realpathAlloc(allocator, file_path);
  defer allocator.free(real_path);
  _ = try ABNF.parse(.{
    .allocator = allocator, 
    .file_path = real_path,
    .input = input,
  });
}