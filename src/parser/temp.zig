const std = @import("std");

pub fn main() void {
  const a: []u8 = .{0,1,2,3};
  std.debug.print("{any}\n", .{a});
}