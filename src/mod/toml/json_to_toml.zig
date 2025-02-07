const Self = @This();

const std = @import("std");
const Json = std.json.Value;

const esc = @import("escape.zig");
const Toml = @import("root.zig").Toml;
const DateTime = @import("datetime.zig").DateTime;

const asTag = std.meta.activeTag;

allocator: std.mem.Allocator,

const Error = error {TomlJsonConverterError}
  || std.mem.Allocator.Error
  || std.fmt.ParseIntError
  || std.fmt.ParseFloatError;

pub fn fromJson(allocator: std.mem.Allocator, json: Json) !Toml {
  const self = Self {.allocator = allocator};
  return try self.buildTable(json);
}

fn buildArray(self: Self, json: Json) Error!Toml {
  var toml = Toml.init(.array);
  errdefer toml.deinit(self.allocator);
  for (json.array.items) |item|
    try toml.array.append(
      self.allocator,
      try self.buildValue(item));
  return toml;
}

fn buildTable(self: Self, json: Json) Error!Toml {
  var toml = Toml.init(.table);
  errdefer toml.deinit(self.allocator);
  var iter = json.object.iterator();
  while (iter.next()) |entry|
    try toml.table.put(
      self.allocator,
      try self.allocator.dupe(u8, entry.key_ptr.*),
      try self.buildValue(entry.value_ptr.*));
  return toml;
}


fn buildValue(self: Self, json: Json) Error!Toml {
  return switch (json) {
    .array => try self.buildArray(json),
    .object => self.buildTagVal(json) catch try self.buildTable(json),
    else => unreachable,
  };
}

fn buildTagVal(self: Self, json: Json) !Toml {
  if (json.object.count() > 2)                return error.TomlJsonConverterError;
  const typ = json.object.get("type")  orelse return error.TomlJsonConverterError;
  if (asTag(typ) != .string)                  return error.TomlJsonConverterError;
  const val = json.object.get("value") orelse return error.TomlJsonConverterError;
  if (asTag(val) != .string)                  return error.TomlJsonConverterError;

  if        (std.mem.eql(u8, typ.string, "string")) {
    return Toml{.string = try self.allocator.dupe(u8, val.string)};
  } else if (std.mem.eql(u8, typ.string, "integer")) {
    return Toml{.integer = try std.fmt.parseInt(i64, val.string, 0)};
  } else if (std.mem.eql(u8, typ.string, "float")) {
    return Toml{.float = try std.fmt.parseFloat(f64, val.string)};
  } else if (std.mem.eql(u8, typ.string, "bool")) {
    return Toml{.boolean = std.mem.eql(u8, val.string, "true")};
  } else if (std.mem.eql(u8, typ.string, "datetime")) {
    return Toml{.datetime = try DateTime.fromRFC3339(val.string)};
  } else if (std.mem.eql(u8, typ.string, "datetime-local")) {
    return Toml{.datetime = try DateTime.fromRFC3339(val.string)};
  } else if (std.mem.eql(u8, typ.string, "date-local")) {
    return Toml{.datetime = try DateTime.fromRFC3339(val.string)};
  } else if (std.mem.eql(u8, typ.string, "time-local")) {
    return Toml{.datetime = try DateTime.fromRFC3339(val.string)};
  } else unreachable;
}