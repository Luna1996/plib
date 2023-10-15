const std = @import("std");
const abnf = @import("abnf/abnf.zig");
const Args = @import("args.zig").Args;

const Conf = struct {
  input: []const u8,
  output: ?[]const u8 = null,
  output_ast: ?[]const u8 = null,
};

pub fn main() !void {
  var gpa = std.heap.GeneralPurposeAllocator(.{}){};
  defer if (gpa.deinit() != .ok) std.debug.panic("leak", .{});
  const allocator = gpa.allocator();

  const args = try Args(
    Conf,
    .{
      .input = .{.is_unnamed = true, .desc = "the path of input abnf file."},
      .output = .{.alias = "o", .desc = "the path for output zig file."},
      .output_ast = .{.alias = "a", .desc = "dump ast tree to the file if set."},
    },
  ).init(allocator);
  defer args.deinit();

  try gen_abnf(allocator, args.args);
}

pub fn gen_abnf(allocator: std.mem.Allocator, conf: Conf) !void {
  const abnf_text = try std.fs.cwd().readFileAlloc(allocator, conf.input, std.math.maxInt(usize));
  defer allocator.free(abnf_text);
  const output_path = try std.mem.concat(allocator, u8, &.{conf.input, ".zig"});
  defer allocator.free(output_path);
  const output_file = try std.fs.cwd().createFile(conf.output orelse output_path, .{});
  defer output_file.close();
  const real_path = try std.fs.cwd().realpathAlloc(allocator, conf.input);
  defer allocator.free(real_path);
  const output_ast_file: ?std.fs.File =
    if (conf.output_ast) |output_ast|
      try std.fs.cwd().createFile(output_ast, .{})
    else null;
  const rule_set = try abnf.parse(allocator, .{.path = real_path, .text = abnf_text}, output_ast_file);
  defer rule_set.deinit(allocator);
  try rule_set.format("p", .{}, output_file.writer());
}

test {
  std.debug.print("\n", .{});
  var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
  defer arena.deinit();
  try gen_abnf(arena.allocator(), .{.input = "src/toml/toml.abnf"});
}