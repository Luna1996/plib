const std = @import("std");
const Self = @import("root.zig").Toml;
const Parser = Self.Parser;
const Ast = Self.Ast;
const Tag = Self.Tag;
const Array = Self.Array;
const Table = Self.Table;
const Builder = @import("builder.zig");

const Conf = struct {
  allocator: std.mem.Allocator,
  file_path: ?[]const u8 = null,
  input: []const u8,
  edit_inplace: bool = false,
  log_error: bool = true,
};

pub fn parse(conf: Conf) !Ast {
  return try Parser.parse(.{
    .allocator = conf.allocator,
    .input = conf.input,
    .keeps = &.{
      .toml,
      .keyval, .std_table, .array_table,
      .key, .unquoted_key, .quoted_key,
      .string, .boolean, .array, .inline_table, .float, .integer, .date_time,
    },
    .file_path = conf.file_path,
    .log_error = conf.log_error,
  });
}

pub fn build(conf: Conf) !Self {
  var root = try parse(conf);
  defer root.deinit(conf.allocator);
  return try Builder.build(conf.allocator, &root, .{
    .file = conf.file_path,
    .text = conf.input,
  });
}

pub fn init(tag: Tag) Self {
  return switch (tag) {
    .string   => .{ .string   = ""          },
    .integer  => .{ .integer  = 0           },
    .float    => .{ .float    = 0           },
    .boolean  => .{ .boolean  = false       },
    .datetime => .{ .datetime = .{}         },
    .array    => .{ .array    = Array.empty },
    .table    => .{ .table    = Table.empty },
  };
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
  switch (self.*) {
    .string  => |string| allocator.free(string),
    .array   => |*array| deinitArray(array, allocator),
    .table   => |*table| deinitTable(table, allocator),
    else     => {},
  }
}

fn deinitArray(array: *Array, allocator: std.mem.Allocator) void {
  for (array.items) |*item|
    item.deinit(allocator);
  array.deinit(allocator);
}

fn deinitTable(table: *Table, allocator: std.mem.Allocator) void {
  var iterator = table.iterator();
  while (iterator.next()) |entry| {
    allocator.free(entry.key_ptr.*);
    entry.value_ptr.deinit(allocator);
  }
  table.deinit(allocator);
}