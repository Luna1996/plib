const std = @import("std");

pub fn Node(comptime Tag: type) type {
  return struct {
    const Self = @This();

    tag: ?Tag,
    val: union (enum) {
      str: []const u8,
      sub: std.ArrayList(Self),
    },

    pub fn initSub(allocator: std.mem.Allocator, tag: ?Tag) Self {
      return .{
        .tag = tag,
        .val = .{ .sub = std.ArrayList(Self).init(allocator) },
      };
    }

    pub fn initStr(str: []const u8) Self {
      return .{
        .tag = null,
        .val = .{ .str = str },
      };
    }

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
}