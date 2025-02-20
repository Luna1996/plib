const std = @import("std");
const asTag = std.meta.activeTag;
const deinit_any = @import("plib").deinit_any;
const isArray = deinit_any.isArray;
const isTable = deinit_any.isTable;
const Conf = Toml.Conf;
const Toml = @import("root.zig").Toml;
const DateTime = @import("datetime.zig").DateTime;

pub const deinitAny = deinit_any.deinitAny;

pub fn build(conf: Conf, comptime T: type, toml: Toml) Toml.Error!T {
  return switch (@typeInfo(T)) {
    .bool      => try buildBool  (         toml),
    .int       => try buildInt   (      T, toml),
    .float     => try buildFloat (      T, toml),
    .@"enum"   => try buildEnum  (conf, T, toml),
    .optional  => try buildOpt   (conf, T, toml),
    .array     => try buildVector(conf, T, toml),
    .vector    => try buildVector(conf, T, toml),
    .@"struct" => try buildStruct(conf, T, toml),
    .@"union"  => try buildUnion (conf, T, toml),
    .pointer   => |info| switch (info.size) {
      .One     => try buildPtr   (conf, T, toml),
      .Slice   => try buildSlice (conf, T, toml),
      else     => @compileError("unsupported type: " ++ @typeName(T)),
    },
    else       => @compileError("unsupported type: " ++ @typeName(T)),
  };
}

inline fn buildBool(toml: Toml) Toml.Error!bool {
  if (asTag(toml) != .boolean) return error.TomlError;
  return toml.boolean;
}

inline fn buildDateTime(toml: Toml) Toml.Error!DateTime {
  if (asTag(toml) != .datetime) return error.TomlError;
  return toml.datetime;
}

inline fn buildInt(comptime T: type, toml: Toml) Toml.Error!T {
  if (asTag(toml) != .integer) return error.TomlError;
  return @intCast(toml.integer);
}

inline fn buildFloat(comptime T: type, toml: Toml) Toml.Error!T {
  if (asTag(toml) != .float) return error.TomlError;
  return @floatCast(toml.float);
}

inline fn buildEnum(conf: Conf, comptime T: type, toml: Toml) Toml.Error!T {
  if (comptime getCustomBuildFn(T)) |build_fn| try build_fn(conf, toml);
  if (asTag(toml) != .string) return error.TomlError;
  return std.meta.stringToEnum(T, toml.string) orelse error.TomlError;
}

inline fn buildOpt(conf: Conf, comptime T: type, toml: Toml) Toml.Error!T {
  return try build(conf, @typeInfo(T).optional.child, toml);
}

inline fn buildPtr(conf: Conf, comptime T: type, toml: Toml) Toml.Error!T {
  const V = @typeInfo(T).pointer.child;
  const v = try conf.allocator.create(V);
  errdefer conf.allocator.destroy(v);
  v.* = try build(conf, V, toml);
  return v;
}

fn buildSlice(conf: Conf, comptime T: type, toml: Toml) Toml.Error!T {
  const info = @typeInfo(T).pointer;
  const V = info.child;
  const A = std.ArrayListAlignedUnmanaged(V, info.alignment);
  if (V == u8) {
    if (T != []const u8 and T != []u8) @compileError("unsupported type: " ++ @typeName(T));
    if (asTag(toml) != .string) return error.TomlError;
    return try conf.allocator.dupe(u8, toml.string);
  } else {
    const list = try buildArray(conf, A, toml);
    return list.items;
  }
}

fn buildVector(conf: Conf, comptime T: type, toml: Toml) Toml.Error!T {
  const V, const len = switch (@typeInfo(T)) {
    .array  => |val| .{val.child, val.len},
    .vector => |val| .{val.child, val.len},
    else => unreachable,
  };
  if (asTag(toml) != .array) return error.TomlError;
  if (toml.array.items.len != len) return error.TomlError;
  var vali: usize = 0;
  var list: T = undefined;
  errdefer for (0..vali) |i| deinitAny(list[i], conf.allocator);
  for (toml.array.items, 0..) |item, i| {
    list[i] = try build(conf, V, item);
    vali += 1;
  }
  return list;
}

fn buildStruct(conf: Conf, comptime T: type, toml: Toml) Toml.Error!T {
  if (T == DateTime) return try buildDateTime(toml);
  if (comptime getCustomBuildFn(T)) |build_fn| return try build_fn(conf, toml);
  if (comptime isArray(T)) return try buildArray(conf, T, toml);
  if (comptime isTable(T)) return try buildTable(conf, T, toml);
  if (asTag(toml) != .table) return error.TomlError;
  const fields = @typeInfo(T).@"struct".fields;
  var item: T = undefined;
  var used: usize = 0;
  var vali: usize = 0;
  errdefer inline for (fields, 0..) |field, i| {
    if (i >= vali) break;
    deinitAny(@field(item, field.name), conf.allocator);
  };
  inline for (fields) |field| {
    if (toml.table.get(field.name)) |sub_toml| {
      used += 1;
      @field(item, field.name) = try build(conf, field.type, sub_toml);
    } else if (comptime field.default_value) |value| {
      @field(item, field.name) = @as(*const field.type, @ptrCast(value)).*;
    } else if (comptime asTag(@typeInfo(field.type)) == .optional) {
      @field(item, field.name) = null;
    } else return error.TomlError;
    vali += 1;
  }
  if (used < toml.table.count()) return error.TomlError;
  return item;
}

fn buildArray(conf: Conf, comptime T: type, toml: Toml) Toml.Error!T {
  const info = @typeInfo(T.Slice).pointer;
  const V = info.child;
  const A = std.ArrayListAlignedUnmanaged(V, info.alignment);
  if (asTag(toml) != .array) return error.TomlError;
  var list = try A.initCapacity(conf.allocator, toml.array.items.len);
  errdefer deinitAny(list, conf.allocator);
  for (toml.array.items) |item|
    list.appendAssumeCapacity(try build(conf, V, item));
  return if (T == A) list else list.toManaged(conf.allocator);
}

fn buildTable(conf: Conf, comptime T: type, toml: Toml) Toml.Error!T {
  const is_managed = @hasField(T, "unmanaged");
  const Table = if (is_managed) T.Unmanaged else T;
  const Value = std.meta.FieldType(Table.KV, .value);
  if (asTag(toml) != .table) return error.TomlError;
  var table = Table.empty;
  errdefer deinitAny(table, conf.allocator);
  try table.ensureTotalCapacity(conf.allocator, @intCast(toml.table.count()));
  var iter = toml.table.iterator();
  while (iter.next()) |entry|
    table.putAssumeCapacity(
      try conf.allocator.dupe(u8, entry.key_ptr.*),
      try build(conf, Value, entry.value_ptr.*));
  return if (is_managed) table.promote(conf.allocator) else table;
}

fn buildUnion(conf: Conf, comptime T: type, toml: Toml) Toml.Error!T {
  if (T == Toml) return toml.clone(conf.allocator);
  if (comptime getCustomBuildFn(T)) |build_fn| return try build_fn(conf, toml);
  inline for (@typeInfo(T).@"union".fields) |field| loop: {
    return @unionInit(T, field.name, build(conf, field.type, toml) catch break :loop);
  }
  return error.TomlError;
}

fn BuildFn(comptime T: type) type {
  return fn (Conf, Toml) Toml.Error!T;
}

fn getCustomBuildFn(comptime T: type) ?BuildFn(T) {
  if (!@hasDecl(T, "fromToml")) return null;
  const build_fn = T.fromToml;
  if (@TypeOf(build_fn) != BuildFn(T)) @compileError(
    "unsupported fromToml type: " ++ @typeName(T.fromToml) ++
    ", should be: " ++ @typeName(BuildFn(T)));
  return build_fn;
}