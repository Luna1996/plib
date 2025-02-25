const Self = @This();

const std = @import("std");

const Toml = @import("root.zig").Toml;
const Ast = Toml.Ast;

allocator: std.mem.Allocator,

ast: Ast = Ast.initStr(""),
val: Toml = Toml.init(.table),

current_table: *Toml = undefined,

last_expression_exist: bool = true,
next_expression_comment: []const u8 = "",
skip_until_next_table: bool = false,

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

pub fn format(
  self: *Self, 
  comptime _: []const u8,
  _: std.fmt.FormatOptions,
  writer: anytype,
) !void {
  self.current_table = &self.val;
  switch (self.ast.val) {
    .str => |str| if (str.len != 0) {
      try writer.writeAll(str);
      if (str[str.len - 1] != '\n') try writer.writeByte('\n');
    },
    .sub => |sub| for (sub.items, 0..) |ast, i| if (ast.tag) |tag| switch (tag) {
      .keyval => try self.formatKeyVal(ast, writer),
      else => try self.formatSectionHead(ast, writer),
    } else self.formatFiller(ast.val.str, i == 0, writer),
  }
  try self.formatRemain(true, writer);
}

fn formatFiller(self: *Self, filler: []const u8, is_start: bool, writer: anytype) !void {
  if (self.skip_until_next_table) return;
  const res = splitFiller(filler, is_start);
  if (self.last_expression_exist) try writer.writeAll(res[0]);
  try writer.writeAll(res[1]);
  self.next_expression_comment = res[2];
}

fn splitFiller(filler: []const u8, is_start: bool) [3][]const u8 {}

fn formatKeyVal(self: *Self, ast: Ast, writer: anytype) !void {}

fn formatSectionHead(self: *Self, ast: Ast, writer: anytype) !void {
  try self.formatRemain(false, writer);
}

fn formatRemain(self: *Self, rest: bool, writer: anytype) !void {}