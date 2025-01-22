const std = @import("std");
const Self = @import("root.zig").Toml;
const Parser = Self.Parser;
const Ast = Self.Ast;
const Tag = Self.Tag;
const Array = Self.Array;
const Table = Self.Table;

const Conf = struct {
  allocator: std.mem.Allocator,
  file_path: ?[]const u8 = null,
  input: []const u8,
  edit_inplace: bool = false,
};

pub fn parse(conf: Conf) !Ast {
  var result = try Parser.parse(.{
    .allocator = conf.allocator,
    .input = conf.input,
    .keeps = &.{
      .toml, .key, .std_table, .array_table,
      .unquoted_key, .basic_string, .literal_string,
      .ml_basic_string, .ml_literal_string,
      .boolean, .array, .inline_table, .float, .integer,
      .offset_date_time, .local_date_time, .local_date, .local_time,
    },
    .file_path = conf.file_path,
  });
  errdefer result.root.deinit(conf.allocator);

  if (result.fail) |fail| {
    std.debug.print("{}", .{fail});
    return error.ParseError;
  } else {
    return result.root;
  }
}

pub fn build(conf: Conf) !Self {
  var root = try parse(conf);
  defer root.deinit(conf.allocator);
  return try Self.buildToml(conf.allocator, &root);
}

pub fn init(comptime tag: Tag) Self {
  return switch (tag) {
    .string  => .{ .string  = ""          },
    .integer => .{ .integer = 0           },
    .float   => .{ .float   = 0           },
    .boolean => .{ .boolean = false       },
    .instant => .{ .instant = .{}         },
    .array   => .{ .array   = Array.empty },
    .table   => .{ .table   = Table.empty },
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