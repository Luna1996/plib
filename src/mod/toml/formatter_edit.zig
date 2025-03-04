const Self = @This();

const std = @import("std");
const esc = @import("escape.zig");

const Toml = @import("root.zig").Toml;
const Ast = Toml.Ast;

const asTag = std.meta.activeTag;

allocator: std.mem.Allocator,

ast: Ast = Ast.initStr(""),
val: Toml = Toml.init(.table),

this_table: *Toml = undefined,
arrays_len: std.AutoHashMapUnmanaged(*Toml, usize) = undefined,

pub fn init(allocator: std.mem.Allocator) Self {
  return .{.allocator = allocator};
}

pub fn deinit(self: *Self) void {
  self.ast.deinit(self.allocator);
  self.val.deinit(self.allocator);
}

pub fn setVal(self: *Self, val: anytype) !void {
  self.val = try Toml.fromAny(val, self.allocator);
}

fn initFormatState(self: *Self) void {
  self.this_table = &self.val;
  self.arrays_len = .empty;
}

fn deinitFormatState(self: *Self) void {
  self.arrays_len.deinit(self.allocator);
}

pub fn format(
  self: *Self, 
  comptime _: []const u8,
  _: std.fmt.FormatOptions,
  writer: anytype,
) !void {
  self.initFormatState();
  defer self.deinitFormatState();
  switch (self.ast.val) {
    .str => |str| try writer.writeAll(str),
    .sub => |sub| for (sub.items) |ast| {
      if (ast.tag) |tag| switch (tag) {
        .keyval => try self.formatKeyVal(ast, writer),
        else => try self.formatSectionHead(ast, writer),
      } else try writer.writeAll(ast.val.str);
    },
  }
}

fn formatKeyVal(self: *Self, ast: Ast, writer: anytype) !void {
  const subs = ast.val.sub.items;
  const last_table = self.this_table;
  defer self.this_table = last_table;
  self.this_table = try self.resolveKey(subs[0]);
  try writer.print("{f}{s}{f}", .{subs[0], subs[1].val.str, self.this_table});
}

fn formatSectionHead(self: *Self, ast: Ast, writer: anytype) !void {
  self.this_table = &self.val;
  self.this_table = try self.resolveKey(ast.val.sub.items[1]);
  try writer.print("{f}", .{ast});
}

fn resolveKey(self: *Self, ast: Ast) !*Toml {
  var iter = ast.iterator();
  var toml = self.this_table;
  while (iter.next()) |item| {
    const key, const need_free = try esc.unescape(self.allocator, item.val.str);
    defer if (need_free) self.allocator.free(key);
    if (asTag(toml.*) == .array) {
      if (self.arrays_len.get(toml)) |len| {
        toml = &toml.array.items[len - 1];
      } else return error.TomlError;
    }
    if (asTag(toml.*) != .table) return error.TomlError;
    toml = toml.table.getPtr(key) orelse return error.TomlError;
  }
  return toml;
}