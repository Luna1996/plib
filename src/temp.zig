const std = @import("std");

pub fn main() void {
  var list = [_]u8{6, 2, 5, 3, 13, 8, 8, 5, 1, 5, 6, 29, 4, 7, 2, 29, 12, 6, 3, 5, 29, 5, 5, 3, 29, 2, 3, 4, 11, 3, 9, 6, 3, 18, 13, 2};
  std.mem.sort(u8, &list, {}, std.sort.desc(u8));
  std.debug.print("{any}\n", .{list});
  var sum = @as(u8, 0);
  for (list[0..list.len/2]) |item| { sum += item - 1; }
  std.debug.print("{any}\n", .{sum});
}