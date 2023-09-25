const std = @import("std");

const Rule = union(enum) {
  alt: []const Rule,
  con: []const Rule,
  rep: struct {
    min: usize = 0,
    max: ?usize = null,
    sub: *const Rule,
  },
  str: []const u8,
  val: struct {
    min: u8,
    max: u8
  },
  jmp: usize,
};

test Rule {
  const r: []const Rule = @import("abnf.tmp.zig").rule_set;
  std.debug.print("\n{any}\n", .{r});
}