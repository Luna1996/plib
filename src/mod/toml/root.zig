const std = @import("std");

pub const Toml = union(enum) {
  string  : []const u8,
  integer : i64,
  float   : f64,
  boolean : bool,
  datetime: DateTime,
  array   : Array,
  table   : Table,

  const Self = @This();

  pub const Error = error { TomlError } || std.mem.Allocator.Error;
  
  pub const Parser = @import("plib").Parser(@import("gen").abnf);
  pub const Ast = Parser.Ast;
  pub const AstTag = Parser.Tag;

  pub const Tag = @as(type, std.meta.Tag(Self));

  pub const DateTime = @import("datetime.zig").DateTime;
  pub const Array = std.ArrayListUnmanaged(Self);
  pub const Table = std.StringHashMapUnmanaged(Self);

  pub const Name = union(enum) {str: []const u8, num: usize};
  pub const Path = std.ArrayListUnmanaged(Name);

  pub usingnamespace @import("core.zig");
  pub usingnamespace @import("formatter_flat.zig");
  pub usingnamespace @import("formatter_json.zig");
  pub usingnamespace @import("json_to_toml.zig");
};

test {
  std.debug.print("\n", .{});
  const allocator = std.testing.allocator;
  const file_text =
    \\many.dots.here.dot.dot.dot = {a.b.c = 1, a.b.d = 2}
  ;
  var toml = try Toml.parse(Toml, .{
    .allocator = allocator,
    .input = file_text,
  });
  defer toml.deinit(allocator);
  std.debug.print("{}", .{toml});
}