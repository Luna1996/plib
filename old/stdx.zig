const std = @import("std");

pub fn printEscapedString(str: []const u8, writer: anytype) !void {
  for (str) |c| {
    switch (c) {
      '\\' => try writer.writeAll("\\\\"),
      '\'' => try writer.writeAll("\\\'"),
      '\"' => try writer.writeAll("\\\""),
      '\n' => try writer.writeAll("\\n"),
      '\r' => try writer.writeAll("\\r"),
      '\t' => try writer.writeAll("\\t"),
      else => {
        if (std.ascii.isPrint(c)) {
          try writer.writeByte(c);
        } else {
          try writer.print("\\x{X:0>2}", .{c});
        }
      },
    }
  }
}

pub fn printEscapedStringWithQuotes(str: []const u8, writer: anytype) !void {
  try writer.writeAll("\"");
  try printEscapedString(str, writer);
  try writer.writeAll("\"");
}