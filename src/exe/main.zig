const std = @import("std");
const ABNF = @import("abnf").ABNF;

pub fn main() !void {}

fn gen_abnf(allocator: std.mem.Allocator, name: []const u8) !void {
  const file_path = try std.fmt.allocPrint(allocator, "src/raw/{s}.abnf", .{name});
  defer allocator.free(file_path);
  const input = try std.fs.cwd().readFileAlloc(allocator, file_path, std.math.maxInt(usize));
  defer allocator.free(input);
  const real_path = try std.fs.cwd().realpathAlloc(allocator, file_path);
  defer allocator.free(real_path);
  var abnf = try @import("abnf").ABNF.build(.{
    .allocator = allocator, 
    .file_path = real_path,
    .input = input,
  });
  defer abnf.deinit();
}

test "main" {
  std.debug.print("\n", .{});
  const allocator = std.testing.allocator;
  const name = "abnf";
  try gen_abnf(allocator, name);
}