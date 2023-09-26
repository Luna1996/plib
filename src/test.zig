const std = @import("std");

const A = union(enum) {
  a: u1,
  b: u1,
};

test {
  var a = A{.a=0};
  switch (a) {
    .a => |*t| {
      t.* = 1;
    },
    else => {},
  }
  std.debug.print("\n{d}\n", .{a.a});
}