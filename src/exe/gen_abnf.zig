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

  const raw = try std.fs.cwd().readFileAlloc(allocator, raw_path, std.math.maxInt(usize));
  defer allocator.free(raw);
 
  const raw_real_path = try std.fs.cwd().realpathAlloc(allocator, raw_path);
  defer allocator.free(raw_real_path);
 
  var abnf = try ABNF.build(.{
    .allocator = allocator, 
    .file_path = raw_real_path,
    .input = raw,
  });
  defer abnf.deinit();

  const gen_path = try std.fmt.allocPrint(allocator, "src/gen/{s}.zig", .{name});
  defer allocator.free(gen_path);

  const gen_file = try std.fs.cwd().createFile(gen_path, .{});
  defer gen_file.close();

  try gen_file.writer().print("{}", .{abnf});
}