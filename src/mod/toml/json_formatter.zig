const std = @import("std");
const esc = @import("escape.zig");
const Self = @import("root.zig").Toml;

pub fn fmtJson(self: Self) std.fmt.Formatter(jsonFormat) { return .{ .data = self }; }

fn jsonFormat(
  self: Self,
  comptime fmt: []const u8,
  opt: std.fmt.FormatOptions,
  wrt: anytype,
) !void {
  const is_array = std.meta.activeTag(self) == .array;
  try wrt.writeByte(if (is_array) '[' else '{');
  switch (self) {
    .string  => |value| try wrt.print("\"type\":\"string\",\"value\":\"{}\"",   .{esc.escape(value)}),
    .integer => |value| try wrt.print("\"type\":\"integer\",\"value\":\"{d}\"", .{value}),
    .float   => |value| try wrt.print("\"type\":\"float\",\"value\":\"{d}\"",   .{value}),
    .boolean => |value| try wrt.print("\"type\":\"bool\",\"value\":\"{}\"",     .{value}),
    .instant => |value| try wrt.print("\"type\":\"{1s}\",\"value\":\"{0}\"",    .{value,
      switch (value.tag) {
        .offset_date_time => "datetime",
        .local_date_time  => "datetime-local",
        .local_date       => "date-local",
        .local_time       => "time-local",
        else              => unreachable,
      }
    }),
    .array   => |*value| {
      const len = value.items.len;
      for (value.items, 1..) |item, i| {
        try jsonFormat(item, fmt, opt, wrt);
        if (i != len) try wrt.writeByte(',');
      }
    },
    .table   => |*value| {
      const len = value.count();
      var i = len;
      var iter = value.iterator();
      while (iter.next()) |entry| : (i -= 1) {
        try wrt.print("\"{}\":", .{esc.escape(entry.key_ptr.*)});
        try jsonFormat(entry.value_ptr.*, fmt, opt, wrt);
        if (i != 1) try wrt.writeByte(',');
      }
    },
  }
  try wrt.writeByte(if (is_array) ']' else '}');
}