const std = @import("std");

pub fn Node(comptime Tag: type) type {
  return struct {
    const Self = @This();

    tag: ?Tag,
    val: union (enum) {
      str: []const u8,
      sub: std.ArrayListUnmanaged(Self),
    },

    pub fn initSub(tag: ?Tag) Self {
      return .{
        .tag = tag,
        .val = .{ .sub = std.ArrayListUnmanaged(Self).empty },
      };
    }

    pub fn initStr(str: []const u8) Self {
      return .{
        .tag = null,
        .val = .{ .str = str },
      };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
      switch (self.val) {
        .str => {},
        .sub => |*sub| {
          for (sub.items) |*item| item.deinit(allocator);
          sub.deinit(allocator);
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

    pub fn reset(self: *Self, allocator: std.mem.Allocator, old_len: usize) void {
      switch (self.val) {
        .str => unreachable,
        .sub => |*sub| if (sub.items.len > old_len) {
          for (old_len..sub.items.len) |i|
            sub.items[i].deinit(allocator);
          sub.shrinkAndFree(allocator, old_len);
        },
      }
    }

    pub fn subLen(self: Self) usize {
      return self.val.sub.items.len;
    }

    pub fn get(self: Self, i: usize) *Self {
      return &self.val.sub.items[i];
    }

    pub fn getStr(self: Self, i: usize) []const u8 {
      return self.val.sub.items[i].val.str;
    }

    pub fn add(self: *Self, allocator: std.mem.Allocator, i: usize, item: Self) !void {
      try self.val.sub.insert(allocator, i, item);
    }

    pub fn del(self: *Self, i: usize) Self {
      return self.val.sub.orderedRemove(i);
    }

    pub fn appendSub(self: *Self, allocator: std.mem.Allocator, item: *Self) !void {
      try self.val.sub.appendSlice(allocator, item.val.sub.items);
      item.val.sub.clearAndFree(allocator);
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