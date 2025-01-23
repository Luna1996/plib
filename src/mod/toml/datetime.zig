const std = @import("std");
const Toml = @import("root.zig").Toml;
const Tag = Toml.Parser.Tag;
const Ast = Toml.Ast;

pub const DateTime = packed struct {
  /// 0000-9999
  year: u14 = 1970,
  /// 01-12
  month: u4 = 0,
  /// 01-31
  day: u5 = 0,
  /// 00-23
  hour: u5 = 0,
  /// 00-59
  minute: u6 = 0,
  /// 00-59
  second: u6 = 0, // 0-60
  /// 000-999
  millisecond: u10 = 0,
  /// ±5999 minutes
  offset: i14 = 0,
  /// .offset_date_time, .local_date_time, .local_date, .local_time
  tag: Tag = .local_time,

  const Self = @This();

  pub fn fromRFC3339(text: []const u8) !Self {
    var self = Self{};
    if (text[4] == '-') {
      try self.setFullDate(text);
      if (text.len == 10) {
        self.tag = .local_date;
      } else {
        const l = try self.setFullTime(text[11..]);
        if (text.len > 11 + l) {
          self.tag = .offset_date_time;
          try self.setOffset(text[11+l..]);
        } else {
          self.tag = .local_date_time;
        }
      }
    } else {
      self.tag = .local_time;
      _ = try self.setFullTime(text);
    }
    return self;
  }

  fn setFullDate(self: *Self, text: []const u8) !void {
    self.year   = try std.fmt.parseUnsigned(u14, text[0..4 ], 10);
    self.month  = try std.fmt.parseUnsigned(u4 , text[5..7 ], 10);
    if (self.month < 1 or self.month > 12) return error.DateTimeError;
    self.day    = try std.fmt.parseUnsigned(u5 , text[8..10], 10);
    if (self.day < 1 or self.day > dayInMonth(self.year, self.month)) return error.DateTimeError;
  }

  fn setFullTime(self: *Self, text: []const u8) !usize {
    self.hour   = try std.fmt.parseUnsigned(u5 , text[0..2 ], 10);
    if (self.hour > 23) return error.DateTimeError;
    self.minute = try std.fmt.parseUnsigned(u6 , text[3..5 ], 10);
    if (self.minute > 59) return error.DateTimeError;
    self.second = try std.fmt.parseUnsigned(u6 , text[6..8 ], 10);
    if (self.second > 59) return error.DateTimeError;
    if (text.len > 8 and text[8] == '.') {
      return 9 + self.setTimeFrac(text[9..]);
    } else {
      return 8;
    }
  }

  fn setTimeFrac(self: *Self, text: []const u8) usize {
    var d: u10 = 100;
    for (text, 0..) |c, i| switch (c) {
      '0'...'9' => if (d > 0) {
        self.millisecond += (c - '0') * d;
        d /= 10;
      },
      else => return i,
    };
    return text.len;
  }

  fn setOffset(self: *Self, text: []const u8) !void {
    if (text.len == 1) return;
    const h = try std.fmt.parseInt(i14 , text[1..3], 10);
    if (h > 24) return error.DateTimeError;
    const m = try std.fmt.parseInt(i14 , text[4..6], 10);
    if (m > 60) return error.DateTimeError;
    self.offset = h * 60 + m;
    if (text[0] == '-') self.offset *= -1; 
  }

  fn dayInMonth(year: u14, month: u4) u5 {
    return switch (month) {
      1, 3, 5, 7, 8, 10, 12 => 31,
      2 => if (isLeapYear(year)) 29 else 28,
      else => 30,
    };
  }

  fn isLeapYear(year: u14) bool {
    if (year % 4 != 0) return false;
    if (year % 100 != 0) return true;
    return year % 400 == 0;
  }

  pub fn format(
    self: Self,
    comptime _: []const u8,
    _: std.fmt.FormatOptions,
    writer: anytype,
  ) !void {
    if (self.tag != .local_time)
      try writer.print("{d:04}-{d:02}-{d:02}", .{self.year, self.month, self.day});
    if (self.tag == .local_date) return;
    if (self.tag != .local_time) try writer.writeByte('T');
    try writer.print("{d:02}:{d:02}:{d:02}", .{ self.hour, self.minute, self.second });
    try printSecFrac(self.millisecond, 1000, writer);
    if (self.tag != .offset_date_time) return;
    if (self.offset == 0) {
      try writer.writeByte('Z');
    } else {
      try writer.print("{c}{d:02}:{d:02}", .{
        @as(u8, if (self.offset > 0) '+' else '-'),
        @abs(self.offset) / 60,
        @abs(self.offset) % 60,
      });
    }
  }

  fn printSecFrac(frac: usize, max: usize, writer: anytype) !void {
    if (frac == 0) return;
    var n = max;
    var z: usize = 0;
    while (n != 1){
      n /= 10;
      const d: u8 = @intCast((frac / n) % 10);
      if (d == 0) {
        z += 1;
      } else {
        if (z != 0) try writer.writeByteNTimes('0', z);
        try  writer.writeByte(d + '0');
      }
    }
  }
};