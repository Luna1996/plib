const Self = @This();

const std = @import("std");

const Toml = @import("root.zig").Toml;
const Ast = Toml.Ast;

allocator: std.mem.Allocator,

ast: Ast = Ast.initStr(""),
val: Toml = Toml.init(.table),

pub fn deinit(self: *Self) void {
  self.ast.deinit(self.allocator);
  self.val.deinit(self.allocator);
}

pub fn setVal(self: *Self, val: anytype) !void {
  self.val = try Toml.fromAny(val, self.allocator);
}

// pub fn format(
//   self: *Self, 
//   comptime _: []const u8,
//   _: std.fmt.FormatOptions,
//   writer: anytype,
// ) !void {
// }