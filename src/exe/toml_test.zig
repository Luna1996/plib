const std = @import("std");
const name = @import("opts").name;
const Toml = @import("toml").Toml;

fn decoder(allocator: std.mem.Allocator, toml_text: []const u8, writer: std.fs.File.Writer) !void {
  var toml = try Toml.build(.{
    .allocator = allocator,
    .input = toml_text,
  });
  defer toml.deinit(allocator);
  try writer.print("{}", .{toml.fmtJson()});
}

fn encoder(allocator: std.mem.Allocator, json_text: []const u8) !void {
  _ = allocator;
  _ = json_text;
}

pub fn main() !void {
  var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
  defer _ = gpa.deinit();
  defer _ = gpa.detectLeaks();
  const allocator = gpa.allocator();
  const input = try std.io.getStdIn().readToEndAlloc(allocator, std.math.maxInt(usize));
  defer allocator.free(input);
  const writer = std.io.getStdOut().writer();
  try @field(@This(), name)(allocator, input, writer);
}