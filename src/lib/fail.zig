const std = @import("std");

fn Fail(comptime What: type) type {
  return struct {
    file: []const u8 = "???",
    text: []const u8,
    pos: usize,
    what: What,

    const Self = @This();

    pub fn format(
      self: Self,
      comptime _: []const u8,
      _: std.fmt.FormatOptions,
      writer: anytype,
    ) !void {
      const loc = std.zig.findLineColumn(self.text, self.pos);
      try writer.print("{s}:{d}:{d}: {s}\n{s}\n", .{self.file, loc.line+1, loc.column+1, self.what, loc.source_line});
      try writer.writeByteNTimes(' ', loc.column);
      try writer.writeAll("^\n");
    }
  };
}

pub fn fmtFail(what: anytype, conf: struct {
  file: ?[]const u8 = null,
  text: []const u8,
  pos : ?usize = null,
  span: ?[]const u8 = null,
}) Fail(@TypeOf(what)) {
  std.debug.assert(conf.pos != null or conf.span != null);
  return .{
    .file = conf.file orelse "???",
    .text = conf.text,
    .what = what,
    .pos  = if (conf.pos)  |pos|  pos
       else if (conf.span) |span| @intFromPtr(&span[0]) - @intFromPtr(&conf.text[0])
       else unreachable,
  };
}