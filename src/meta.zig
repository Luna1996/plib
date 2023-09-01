const std = @import("std");

pub fn makeStruct(comptime pairs: anytype) type {
  var fields: [pairs.len]std.builtin.Type.StructField = undefined;
  for (pairs, 0..) |item, i| {
    fields[i] = .{
      .name = item[0],
      .type = item[1],
      .default_value = null,
      .is_comptime = false,
      .alignment = 0,
    };
  }
  return @Type(.{
    .Struct = .{
      .layout = .Auto,
      .fields = &fields,
      .decls  = &[_]std.builtin.Type.Declaration{},
      .is_tuple = false,
    },
  });
}