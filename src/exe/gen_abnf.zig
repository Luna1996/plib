const std = @import("std");
const ABNF = @import("abnf").ABNF;

pub fn main() !void {
  var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
  defer _ = gpa.deinit();
  defer _ = gpa.detectLeaks();
  const allocator = gpa.allocator();

  const args = try std.process.argsAlloc(allocator);
  defer std.process.argsFree(allocator, args);

  const name = args[1];

  const raw_path = try std.fmt.allocPrint(allocator, "src/raw/{s}.abnf", .{name});
  defer allocator.free(raw_path);

  const gen_path = try std.fmt.allocPrint(allocator, "src/gen/{s}.zig", .{name});
  defer allocator.free(gen_path);

  try ABNF.gen_abnf(allocator, raw_path, gen_path);
}