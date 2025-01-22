const std = @import("std");
const name = @import("opts").name;
const Toml = @import("toml").Toml;

fn decoder(allocator: std.mem.Allocator, toml_text: []const u8) !void {
  var toml = try Toml.build(.{
    .allocator = allocator,
    .input = toml_text,
  });
  defer toml.deinit(allocator);
  std.debug.print("{}", .{toml.fmtJson()});
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
  @field(@This(), name)(allocator, input) catch std.process.exit(1);
}