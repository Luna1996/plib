const std = @import("std");
const Self = @import("root.zig").Toml;
const Parser = Self.Parser;
const Ast = Self.Ast;
const Tag = Self.Tag;
const Array = Self.Array;
const Table = Self.Table;
const ast_to_toml = @import("ast_to_toml.zig");
const toml_to_any = @import("toml_to_any.zig");

pub const Conf = struct {
  allocator: std.mem.Allocator,
  
  file_path: ?[]const u8 = null,
  input: []const u8,
  
  log_error: bool = true,

  error_unknown_key: bool = true,
  union_inference: bool = true,
};

pub fn parse(comptime T: type, conf: Conf) !T {
  var ast = try Parser.parse(.{
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
  if (T == Ast) return ast;
  defer ast.deinit(conf.allocator);
  var toml = try ast_to_toml.build(conf.allocator, &ast, .{
    .file = conf.file_path,
    .text = conf.input,
  });
  if (T == Self) return toml;
  defer toml.deinit(conf.allocator);
  return try toml_to_any.build(conf, T, toml);
}

pub const fromAny = @import("any_to_toml.zig").build;

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

pub const deinitAny = toml_to_any.deinitAny;

pub fn clone(self: Self, allocator: std.mem.Allocator) std.mem.Allocator.Error!Self {
  return switch (self) {
    .string => |string| .{.string = try allocator.dupe(u8, string)},
    .array  => |*array| array: {
      var new_array = try Array.initCapacity(allocator, array.items.len);
      for (array.items) |item|
        new_array.appendAssumeCapacity(try item.clone(allocator));
      break :array new_array;
    },
    .table  => |*table| table: {
      var new_table = Table.empty;
      try new_table.ensureTotalCapacity(allocator, table.size);
      var iter = table.iterator();
      while (iter.next()) |entry|
        new_table.putAssumeCapacity(entry.key_ptr.*, try entry.value_ptr.clone(allocator));
      break :table new_table;
    },
    else => self,
  };
}