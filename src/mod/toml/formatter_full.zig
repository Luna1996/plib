const Self = @This();

const std = @import("std");
const esc = @import("escape.zig");

const Toml = @import("root.zig").Toml;
const Ast = Toml.Ast;

const asTag = std.meta.activeTag;

allocator: std.mem.Allocator,

ast: Ast = Ast.initStr(""),
val: Toml = Toml.init(.table),

this_index: usize = undefined,
this_table: *Toml = undefined,

last_exist: bool = undefined,
skip_block: bool = undefined,
impend_str: []const u8 = undefined,
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
  self.this_index = 0;
  self.this_table = &self.val;
  self.last_exist = true;
  self.skip_block = false;
  self.impend_str = "";
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
  if (self.skip_block) return;
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

fn formatKeyVal(self: *Self, ast: Ast, writer: anytype) Error(writer)!void {
  if (self.skip_block) return;
  const subs = ast.val.sub.items;
  const last_table = self.this_table;
  defer self.this_table = last_table;
  self.this_table = (try self.resolveKey(subs[0])) orelse {
    self.last_exist = false;
    return;
  };
  if (!self.isTypeMatch(subs[2])) return error.TomlError;
  try writer.print("{f}{s}", .{subs[0], subs[1].val.str});
  try self.formatVal(subs[2], writer);
}

fn formatVal(self: *Self, ast: Ast, writer: anytype) !void {

}

fn formatInteger(self: *Self, ast: Ast, writer: anytype) !void {
  const str = ast.val.str;
  const val = self.this_table.integer;
  try writer.print(if (str[0] == '0' and str.len > 1) switch (str[1]) {
    'x' => try writer.print("0x{x}", .{val}),
    'o' => try writer.print("0o{o}", .{val}),
    'b' => try writer.print("0b{b}", .{val}),
    else => unreachable,
  } else   try writer.print("{d}",   .{val}), .{val});
}

fn formatFloat(self: *Self, ast: Ast, writer: anytype) !void {
  const str = ast.val.str;
  const val = self.this_table.float;
  if (std.mem.indexOfAny(u8, str, "eE") != null)
       try writer.print("{e}", .{val})
  else try writer.print("{d}", .{val});
}

fn formatBoolean(self: *Self, _: Ast, writer: anytype) !void {
  try writer.print("{}", .{self.this_table.boolean});
}

fn formatDateTime(self: *Self, _: Ast, writer: anytype) !void {
  try writer.print("{}", .{self.this_table.datetime});
}

fn formatString(self: *Self, ast: Ast, writer: anytype) !void {}

fn formatSectionHead(self: *Self, ast: Ast, writer: anytype) !void {
  if (!self.skip_block) try self.formatRemain(false, writer);
  self.this_table = &self.val;

}

fn formatRemain(self: *Self, rest: bool, writer: anytype) !void {
  _ = self;
  _ = rest;
  _ = writer;
}

fn resolveKey(self: *Self, ast: Ast) !?*Toml {
  var iter = ast.iterator();
  var toml = self.this_table;
  while (iter.next()) |item| {
    const key, const need_free = try esc.unescape(self.allocator, item.val.str);
    defer if (need_free) self.allocator.free(key);
    if (asTag(toml.*) == .array) {
      if (self.arrays_len.get(toml)) |len| {
        toml = &toml.array.items[len - 1];
      } else return null;
    }
    if (asTag(toml.*) != .table) return null;
    toml = toml.table.getPtr(key) orelse return null;
  }
  return toml;
}

fn isTypeMatch(self: *Self, ast: Ast) bool {
  return ast.tag == switch (self.this_table.*) {
    .string   => .string,
    .boolean  => .boolean,
    .integer  => .integer,
    .float    => .float,
    .datetime => .date_time,
    .array    => .array,
    .table    => .inline_table,
  };
}

fn Error(writer: anytype) type {
  return @TypeOf(writer).Error || std.mem.Allocator.Error || error { TomlError };
}