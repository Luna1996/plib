const std = @import("std");
const abnf = @import("abnf/abnf.zig");

pub fn main() !void {
  var gpa = std.heap.GeneralPurposeAllocator(.{}){};
  defer if (gpa.deinit() != .ok) std.debug.panic("leak", .{});
  const allocator = gpa.allocator();
  var args = try std.process.argsAlloc(allocator);
  defer std.process.argsFree(allocator, args);

  if (args.len == 1) {
    std.debug.print("Usage: gen-abnf path-to-abnf [path-to-output-file]", .{});
    return;
  }

  if (args.len > 2) {
    try gen_abnf(allocator, args[1], args[2]);
  } else {
    const output_path = try std.mem.concat(allocator, u8, &.{args[1], ".zig"});
    defer allocator.free(output_path);
    try gen_abnf(allocator, args[1], output_path);
  }
}

pub fn gen_abnf(allocator: std.mem.Allocator, input_path: []const u8, output_path: []const u8) !void {
  const abnf_text = try std.fs.cwd().readFileAlloc(allocator, input_path, std.math.maxInt(usize));
  defer allocator.free(abnf_text);
  const output_file = try std.fs.cwd().createFile(output_path, .{});
  defer output_file.close();
  const real_path = try std.fs.cwd().realpathAlloc(allocator, input_path);
  defer allocator.free(real_path);
  const rule_set = try abnf.parse(allocator, .{.path = real_path, .text = abnf_text});
  defer rule_set.deinit(allocator);
  try rule_set.format("p", .{}, output_file.writer());
}

test {
  std.debug.print("\n", .{});
  gen_abnf(std.testing.allocator, "src/abnf/abnf.abnf", "src/abnf/abnf.abnf.zig") catch {};
}