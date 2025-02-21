const Self = @This();

const std = @import("std");

const Toml = @import("root.zig").Toml;
const Ast = Toml.Ast;

allocator: std.mem.Allocator,

ast: ?Ast = null,
val: ?Toml = null,

pub fn deinit(self: *Self) void {
  if (self.ast) |*ast| ast.deinit(self.allocator);
  if (self.val) |*val| val.deinit(self.allocator);
}

pub fn setVal(self: *Self, val: anytype) !void {
  self.val = try Toml.fromAny(val, self.allocator);
}