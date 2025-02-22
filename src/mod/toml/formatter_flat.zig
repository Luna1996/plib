const std = @import("std");
const Self = @import("root.zig").Toml;
const esc = @import("escape.zig");

fn FormatError(comptime Writer: type) type {
  return std.mem.Allocator.Error || Writer.Error;
}

pub fn format(
  self: *const Self,
  comptime fmt: []const u8,
  _: std.fmt.FormatOptions,
  writer: anytype,
) !void {
  if (std.mem.eql(u8, fmt, "f")) {
    try printFlat(self, writer);
  } else {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();
    defer _ = gpa.detectLeaks();
    const allocator = gpa.allocator();
    var path = std.ArrayListUnmanaged([]const u8).empty;
    defer path.deinit(allocator);
    try printToml(self, allocator, &path, writer);
  }
}

fn printToml(
  self: *const Self,
  allocator: std.mem.Allocator,
  path: ?*std.ArrayListUnmanaged([]const u8),
  writer: anytype,
) !void {
  var not_flat = std.ArrayListUnmanaged(Self.Table.Entry).empty;
  defer not_flat.deinit(allocator);

  var need_path = path != null and path.?.items.len != 0;

  if (need_path and self.table.count() == 0) {
    try writer.writeByte('[');
    try printMulKey(path.?, writer);
    try writer.writeAll("]\n");
    return;
  }
  
  var iter = self.table.iterator();
  while (iter.next()) |entry| if (
    path == null or
    isFlat(entry.value_ptr)
  ) {
    if (need_path) {
      try writer.writeByte('[');
      try printMulKey(path.?, writer);
      try writer.writeAll("]\n");
      need_path = false;
    }
    try printKeyVal(entry.value_ptr, entry.key_ptr.*, writer);
    try writer.writeByte('\n');
  } else {
    try not_flat.append(allocator, entry);
  };

  for (not_flat.items) |*entry| switch (entry.value_ptr.*) {
    .array => |*array| {
      for (array.items) |*item| {
        try writer.writeAll("[[");
        try printMulKey(path.?, writer);
        if (path.?.items.len != 0)
        try writer.writeByte('.');
        try printOneKey(entry.key_ptr.*, writer);
        try writer.writeAll("]]\n");
        try printToml(item, allocator, null, writer);
      }
    },
    .table => {
      const len = path.?.items.len;
      try path.?.append(allocator, entry.key_ptr.*);
      const item = try advenceTableUntilNotSingleValue(entry.value_ptr, allocator, path.?);
      try printToml(item, allocator, path, writer);
      path.?.items.len = len;
    },
    else => unreachable,
  };
}

fn printKeyVal(self: *const Self, key: []const u8, writer: anytype) !void {
  try printOneKey(key, writer);
  if (isSingleValueTable(self)) {
    try writer.writeByte('.');
    var iter = self.table.iterator();
    const entry = iter.next().?;
    try printKeyVal(entry.value_ptr, entry.key_ptr.*, writer);
  } else {
    try writer.writeAll(" = ");
    try printFlat(self, writer);
  }
}

fn printOneKey(key: []const u8, writer: anytype) !void {
  if (esc.needEscape(key)) {
    try writer.print("\"{}\"", .{esc.escape(key)});
  } else {
    try writer.writeAll(key);
  }
}

fn printMulKey(path: *std.ArrayListUnmanaged([]const u8), writer: anytype) !void {
  for (path.items, 1..) |key, i| {
    try printOneKey(key, writer);
    if (i != path.items.len) try writer.writeByte('.');
  }
}

fn printFlat(self: *const Self, writer: anytype) FormatError(@TypeOf(writer))!void {
  switch (self.*) {
    .string   => |string| try writer.print("\"{}\"", .{ esc.escape(string) }),
    .integer  => |number| try writer.print("{d}", .{number}),
    .float    => |number| try writer.print("{e}", .{number}),
    .boolean  => | value| try writer.print("{}", .{value}),
    .datetime => | value| try writer.print("{}", .{value}),
    .array    => |*array| {
      try writer.writeByte('[');
      const len = array.items.len;
      for (array.items, 1..) |*item, i| {
        try printFlat(item, writer);
        if (i != len) try writer.writeAll(", ");
      }
      try writer.writeByte(']');
    },
    .table    => |*table| {
      try writer.writeByte('{');
      const len = table.count();
      var i = len;
      var iter = table.iterator();
      while (iter.next()) |entry| : (i -= 1) {
        try printKeyVal(entry.value_ptr, entry.key_ptr.*, writer);
        if (i != 1) try writer.writeAll(", ");
      }
      try writer.writeByte('}');
    }
  }
}

fn isFlat(self: *const Self) bool {
  return switch (self.*) {
    .string, .integer, .float, .boolean, .datetime,
      => true,
    .array => |*array| array: {
      if (array.items.len == 0) break :array true;
      for (array.items) |item|
        if (std.meta.activeTag(item) != .table) break :array true else continue;
      break :array false;
    },
    .table,
      => false,
  };
}

fn isSingleValueTable(self: *const Self) bool {
  return std.meta.activeTag(self.*) == .table and self.table.count() == 1;
}

fn advenceTableUntilNotSingleValue(
  self: *const Self,
  allocator: std.mem.Allocator,
  path: *std.ArrayListUnmanaged([]const u8),
) !*const Self {
  if (self.table.count() != 1) return self;
  var iter = self.table.iterator();
  const entry = iter.next().?;
  const key = entry.key_ptr.*;
  const val = entry.value_ptr;
  if (std.meta.activeTag(val.*) != .table) return self;
  try path.append(allocator, key);
  return try advenceTableUntilNotSingleValue(val, allocator, path);
}