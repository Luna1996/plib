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
    .string   => |value| try wrt.print("\"type\":\"string\",\"value\":{}",   .{fmtJsonString(value)}),
    .integer  => |value| try wrt.print("\"type\":\"integer\",\"value\":\"{d}\"", .{value}),
    .float    => |value| try wrt.print("\"type\":\"float\",\"value\":\"{d}\"",   .{value}),
    .boolean  => |value| try wrt.print("\"type\":\"bool\",\"value\":\"{}\"",     .{value}),
    .datetime => |value| try wrt.print("\"type\":\"{1s}\",\"value\":\"{0}\"",    .{value,
      switch (value.tag) {
        .offset_date_time => "datetime",
        .local_date_time  => "datetime-local",
        .local_date       => "date-local",
        .local_time       => "time-local",
        else              => unreachable,
      }
    }),
    .array    => |*value| {
      const len = value.items.len;
      for (value.items, 1..) |item, i| {
        try jsonFormat(item, fmt, opt, wrt);
        if (i != len) try wrt.writeByte(',');
      }
    },
    .table    => |*value| {
      const len = value.count();
      var i = len;
      var iter = value.iterator();
      while (iter.next()) |entry| : (i -= 1) {
        try wrt.print("{}:", .{fmtJsonString(entry.key_ptr.*)});
        try jsonFormat(entry.value_ptr.*, fmt, opt, wrt);
        if (i != 1) try wrt.writeByte(',');
      }
    },
  }
  try wrt.writeByte(if (is_array) ']' else '}');
}

fn fmtJsonString(str: []const u8) std.fmt.Formatter(jsonStringFormat) {
  return .{.data = str};
}

fn jsonStringFormat(
  str: []const u8,
  comptime _: []const u8,
  _: std.fmt.FormatOptions,
  wrt: anytype,
) !void {
  try std.json.stringify(str, .{}, wrt);
}