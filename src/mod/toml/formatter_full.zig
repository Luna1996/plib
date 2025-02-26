const Self = @This();

const std = @import("std");

const Toml = @import("root.zig").Toml;
const Ast = Toml.Ast;

allocator: std.mem.Allocator,

ast: Ast = Ast.initStr(""),
val: Toml = Toml.init(.table),

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
  switch (self.ast.val) {
    .str => |str| if (str.len != 0) {
      try writer.writeAll(str);
      if (str[str.len - 1] != '\n') try writer.writeByte('\n');
    },
    .sub => |sub| for (sub.items) |ast| if (ast.tag) |tag| switch (tag) {
      .keyval => try self.formatKeyVal(ast, writer),
      else => try self.formatSectionHead(ast, writer),
    } else self.formatFiller(ast, writer),
  }
  try self.formatRemain(true, writer);
}

fn formatFiller(self: *Self, ast: Ast, writer: anytype) !void {
  if (self.skip_until_next_table) return;
  const res = splitNull(ast.val.str);
  if (self.last_expression_exist) try writer.writeAll(res[0]);
  try writer.writeAll(res[1]);
  self.next_expression_comment = res[2];
}

fn splitNull(str: []const u8) [3][]const u8 {}

fn formatKeyVal(self: *Self, ast: Ast, writer: anytype) !void {}

fn formatSectionHead(self: *Self, ast: Ast, writer: anytype) !void {
  try self.formatRemain(false, writer);
}

fn formatRemain(self: *Self, rest: bool, writer: anytype) !void {}