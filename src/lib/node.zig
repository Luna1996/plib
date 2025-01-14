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

    pub fn reset(self: *Self, old_len: usize) void {
      switch (self.val) {
        .str => unreachable,
        .sub => |*sub| if (sub.items.len > old_len) {
          for (old_len..sub.items.len) |i|
            sub.items[i].deinit();
          sub.shrinkAndFree(old_len);
        },
      }
    }

    pub fn format(
      self: Self, 
      comptime fmt: []const u8,
      options: std.fmt.FormatOptions,
      writer: anytype,
    ) !void {
      if (fmt.len != 0 and self.tag == null) return;
      const deep = options.width orelse 0;
      if (deep > 0) try writer.writeByteNTimes(' ', deep * 2);
      try writer.writeAll(if (self.tag) |tag| @tagName(tag) else "[null]");
      switch (self.val) {
        .str => |str| try writer.print(": \"{}\"\n", .{std.zig.fmtEscapes(str)}),
        .sub => |sub| {
          try writer.print("[{d}]\n", .{sub.items.len});
          var opt = options;
          opt.width = deep + 1;
          for (sub.items) |item| try item.format(fmt, opt, writer);
        },
      }
    }
  };
}