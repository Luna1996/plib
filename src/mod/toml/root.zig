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
    \\# Top comment.
    \\  # Top comment.
    \\# Top comment.
    \\
    \\# [no-extraneous-groups-please]
    \\
    \\[group] # Comment
    \\answer = 42 # Comment
    \\# no-extraneous-keys-please = 999
    \\# Inbetween comment.
    \\more = [ # Comment
    \\  # What about multiple # comments?
    \\  # Can you handle it?
    \\  #
    \\          # Evil.
    \\# Evil.
    \\  42, 42, # Comments within arrays are fun.
    \\  # What about multiple # comments?
    \\  # Can you handle it?
    \\  #
    \\          # Evil.
    \\# Evil.
    \\# ] Did I fool you?
    \\] # Hopefully not.
    \\
    \\# Make sure the space between the datetime and "#" isn't lexed.
    \\dt = 1979-05-27T07:32:12-07:00  # c
    \\d = 1979-05-27 # Comment
    \\
  ;
  var edit = @import("formatter_edit.zig").init(allocator);
  defer edit.deinit();
  var toml = try Toml.parse(Toml, .{
    .allocator = allocator,
    .input = file_text,
    .edit_formatter = &edit,
  });
  toml.table.getPtr("group").?.table.getPtr("answer").?.integer = 66;
  try edit.setVal(toml);
  std.debug.print("{}", .{&edit});
}