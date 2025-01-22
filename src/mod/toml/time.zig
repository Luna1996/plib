const std = @import("std");
const zeit = @import("zeit");

/// millisecond
timestamp: i64 = 0,
/// second
offset:    i32 = 0,

const Self = @This();

pub fn fromRFC3339(str: []const u8) !Self {
  return fromTime(try zeit.Time.fromISO8601(str));
}

pub fn fromLocalTime(str: []const u8) !Self {
  var time = zeit.Time {};
  time.hour   = try std.fmt.parseUnsigned(u5, str[0..2], 10);
  time.minute = try std.fmt.parseUnsigned(u6, str[3..5], 10);
  if (str.len > 5)
  time.second = try std.fmt.parseUnsigned(u6, str[6..8], 10);
  if (str.len > 8)
  time.millisecond = try std.fmt.parseUnsigned(u6, str[9..if (str.len < 12) str.len else 12], 10);
  return fromTime(time);
}

pub fn fromTime(time: zeit.Time) Self {
  const days = zeit.daysFromCivil(.{
    .year  = time.year ,
    .month = time.month,
    .day   = time.day  ,
  });
  return .{
    .timestamp =
      @as(i64,      days       ) * std.time.ms_per_day  +
      @as(i64, time.hour       ) * std.time.ms_per_hour +
      @as(i64, time.minute     ) * std.time.ms_per_min  +
      @as(i64, time.second     ) * std.time.ms_per_s    +
      @as(i64, time.millisecond),
    .offset =  time.offset,
  };
}

pub fn toTime(self: Self) zeit.Time {
  const inst = zeit.Instant {
    .timestamp = self.timestamp * std.time.ns_per_ms,
    .timezone = &zeit.utc,
  };
  var time = inst.time();
  time.offset = self.offset;
  return time;
}

pub fn format(
  self: Self,
  comptime _: []const u8,
  _: std.fmt.FormatOptions,
  writer: anytype,
) !void {
  const time = self.toTime();
  if (self.timestamp < std.time.ms_per_day and self.timestamp >= 0 and self.offset == 0) {
    try printLocalTime(time, writer);
  } else {
    try printRFC3339(time, writer);
  }
}

fn printLocalTime(time: zeit.Time, writer: anytype) !void {
  try writer.print("{d:02}:{d:02}:{d:02}", .{ time.hour, time.minute, time.second });
  try printSecFrac(time.millisecond, 1000, writer);
}

fn printRFC3339(time: zeit.Time, writer: anytype) !void {
  if (time.year < 0) return error.InvalidTime;
  try writer.print("{d:04}-{d:02}-{d:02}T{d:02}:{d:02}:{d:02}", .{
    @as(u32, @intCast(time.year)), @intFromEnum(time.month), time.day,
    time.hour, time.minute, time.second,
  });
  try printSecFrac(time.millisecond, 1000, writer);
  if (time.offset == 0) {
    try writer.writeByte('Z');
  } else {
    try writer.print("{c}{d:02}:{d:02}", .{
      @as(u8, if (time.offset > 0) '+' else '-'),
      @abs(time.offset) / std.time.s_per_hour,
      (@abs(time.offset) % std.time.s_per_hour) / std.time.s_per_min,
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