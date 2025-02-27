const Self = @This();

const std = @import("std");

const Toml = @import("root.zig").Toml;
const Ast = Toml.Ast;

allocator: std.mem.Allocator,

ast: Ast = Ast.initStr(""),
val: Toml = Toml.init(.table),

this_index: usize = undefined,
this_table: *Toml = undefined,

last_exist: bool = undefined,
skip_block: bool = undefined,
impend_str: []const u8 = undefined,

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

fn resetFormatState(self: *Self) void {
  self.this_index = 0;
  self.this_table = &self.val;
  self.last_exist = true;
  self.skip_block = false;
  self.impend_str = "";
}

pub fn format(
  self: *Self, 
  comptime _: []const u8,
  _: std.fmt.FormatOptions,
  writer: anytype,
) !void {
  self.resetFormatState();
  switch (self.ast.val) {
    .str => |str| if (str.len != 0) {
      try writer.writeAll(str);
      if (str[str.len - 1] != '\n') try writer.writeByte('\n');
    },
    .sub => |sub| for (sub.items) |ast| {
      if (ast.tag) |tag| switch (tag) {
        .keyval => try self.formatKeyVal(ast, writer),
        else => try self.formatSectionHead(ast, writer),
      } else self.formatStr(ast, writer);
      self.this_index += 1;
    },
  }
  try self.formatRemain(true, writer);
}

fn formatStr(self: *Self, ast: Ast, writer: anytype) !void {
  const str = ast.val.str;
  var p1: usize = 0;
  var p2: usize = str.len;
  if (self.this_index != 0) {
    p1 = if (std.mem.indexOfScalar(u8, str, '\n')) |i| i + 1 else str.len;
    if (self.last_exist) try writer.writeAll(str[0..p1]);
  }
  if (self.this_index != self.ast.val.sub.items.len - 1) {
    while (p1 != p2) {
      const p3 = p1 + if (std.mem.lastIndexOfScalar(u8, str[p1..p2], '\n')) |i| i + 1 else 0;
      if (p2 != str.len and std.mem.indexOfScalar(u8, str[p3..p2], '#') == null) break;
      p2 = p3;
    }
  }
  if (p1 != p2) try writer.writeAll(str[p1..p2]);
  self.impend_str = str[p2..];
}

fn impendStr(str: []const u8) []const u8 {
  var cur = str;
  while (std.mem.lastIndexOfScalar(u8, cur, '\n')) |pos| {
    if (cur.len != str.len and std.mem.indexOfScalarPos(u8, cur, pos + 1, '#') == null) break;
    cur = str[0..pos];
  }
  cur.len += 1;
  return str[cur.len..];
}

fn formatKeyVal(self: *Self, ast: Ast, writer: anytype) !void {}

fn formatSectionHead(self: *Self, ast: Ast, writer: anytype) !void {
  try self.formatRemain(false, writer);
}

fn formatRemain(self: *Self, rest: bool, writer: anytype) !void {}