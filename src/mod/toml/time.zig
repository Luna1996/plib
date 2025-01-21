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