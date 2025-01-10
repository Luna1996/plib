const std = @import("std");

pub const Node = struct {
  const Self = @This();

  tag: ?usize,
  val: union (enum) {
    str: []const u8,
    sub: std.ArrayList(Self),
  },

  pub fn deinit(self: Self) void {
    switch (self.val) {
      .str => {},
      .sub => |sub| {
        for (sub.items) |item| item.deinit();
        sub.deinit();
      },
    }
  }

  pub fn deinitOwned(self: Self, allocator: std.mem.Allocator) void {
    switch (self.val) {
      .str => |str| allocator.free(str),
      .sub => |sub| {
        for (sub.items) |item| item.deinitOwned(allocator);
        sub.deinit();
      },
    }
  }
};