const std = @import("std");
const asTag = std.meta.activeTag;

const Toml = @import("root.zig").Toml;
const DateTime = @import("datetime.zig").DateTime;

const Conf = Toml.Conf;

pub const Error = error { TomlError } || std.mem.Allocator.Error;

pub fn BuildFn(comptime T: type) type {
  return fn (Conf, Toml) Error!T;
}

pub fn Result(comptime T: type) type {
  return struct {
    arena: *std.heap.ArenaAllocator,
    value: T,

    pub fn deinit(self: @This()) void {
      const allocator = self.arena.child_allocator;
      self.arena.deinit();
      allocator.destroy(self.arena);
    }
  };
}

pub fn build(conf: Conf, comptime T: type, toml: Toml) Error!Result(T) {
  var result = Result(T) {
    .arena = try conf.allocator.create(std.heap.ArenaAllocator),
    .value = undefined,
  };
  result.arena.* = std.heap.ArenaAllocator.init(conf.allocator);
  errdefer result.deinit();
  var mut_conf = conf;
  mut_conf.allocator = result.arena.allocator();
  result.value = try buildUnmanaged(mut_conf, T, toml);
  return result;
}

pub fn buildUnmanaged(conf: Conf, comptime T: type, toml: Toml) Error!T {
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

inline fn buildBool(toml: Toml) Error!bool {
  if (asTag(toml) != .boolean) return error.TomlError;
  return toml.boolean;
}

inline fn buildDateTime(toml: Toml) Error!DateTime {
  if (asTag(toml) != .datetime) return error.TomlError;
  return toml.datetime;
}

inline fn buildInt(comptime T: type, toml: Toml) Error!T {
  if (asTag(toml) != .integer) return error.TomlError;
  return @as(T, @intCast(toml.integer));
}

inline fn buildFloat(comptime T: type, toml: Toml) Error!T {
  if (asTag(toml) != .float) return error.TomlError;
  return @as(T, @floatCast(toml.float));
}

inline fn buildEnum(conf: Conf, comptime T: type, toml: Toml) Error!T {
  if (getCustomBuildFn(T)) |build_fn| try build_fn(conf, toml);
  if (asTag(toml) != .string) return error.TomlError;
  return std.meta.stringToEnum(T, toml.string) orelse error.TomlError;
}

inline fn buildOpt(conf: Conf, comptime T: type, toml: Toml) Error!T {
  return try buildUnmanaged(conf, @typeInfo(T).optional.child, toml);
}

inline fn buildPtr(conf: Conf, comptime T: type, toml: Toml) Error!T {
  const V = @typeInfo(T).pointer.child;
  const v = try conf.allocator.create(V);
  v.* = try buildUnmanaged(conf, V, toml);
  return v;
}

fn buildSlice(conf: Conf, comptime T: type, toml: Toml) Error!T {
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

fn buildVector(conf: Conf, comptime T: type, toml: Toml) Error!T {
  const V, const len = switch (@typeInfo(T)) {
    .array  => |val| .{val.child, val.len},
    .vector => |val| .{val.child, val.len},
    else => unreachable,
  };
  if (asTag(toml) != .array) return error.TomlError;
  if (toml.array.items.len != len) return error.TomlError;
  var vali: usize = 0;
  var list: T = undefined;
  for (toml.array.items, 0..) |item, i| {
    list[i] = try buildUnmanaged(conf, V, item);
    vali = i + 1;
  }
  return list;
}

fn buildStruct(conf: Conf, comptime T: type, toml: Toml) Error!T {
  if (T == DateTime) return try buildDateTime(toml);
  if (getCustomBuildFn(T)) |build_fn| return try build_fn(conf, toml);
  if (comptime isArray(T)) return try buildArray(conf, T, toml);
  if (comptime isTable(T)) return try buildTable(conf, T, toml);
  if (asTag(toml) != .table) return error.TomlError;
  var item: T = undefined;
  var used: usize = 0;
  inline for (@typeInfo(T).@"struct".fields) |field| {
    if (toml.table.get(field.name)) |sub_toml| {
      used += 1;
      @field(item, field.name) = try buildUnmanaged(conf, field.type, sub_toml);
    } else if (comptime field.default_value) |value| {
      @field(item, field.name) = @as(*const field.type, @ptrCast(value)).*;
    } else if (comptime asTag(@typeInfo(field.type)) == .optional) {
      @field(item, field.name) = null;
    } else return error.TomlError;
  }
  if (used < toml.table.size) return error.TomlError;
  return item;
}

fn isArray(comptime T: type) bool {
  if (!@hasDecl(T, "Slice")) return false;
  return switch (@typeInfo(T.Slice)) {
    .pointer => |info|
      T == std.ArrayListAligned(info.child, info.alignment) or
      T == std.ArrayListAlignedUnmanaged(info.child, info.alignment),
    else => false,
  };
}

fn isTable(comptime T: type) bool {
  if (!@hasDecl(T, "KV")) return false;
  switch (@typeInfo(T.KV)) {
    .@"struct" => {
      if (!@hasField(T.KV, "value")) return false;
      const V = std.meta.FieldType(T.KV, .value);
      if (T == std.StringHashMap(V) or
          T == std.StringHashMapUnmanaged(V) or
          T == std.StringArrayHashMap(V) or
          T == std.StringArrayHashMapUnmanaged(V)) return true;
    },
    else => return false,
  }
}

fn buildArray(conf: Conf, comptime T: type, toml: Toml) Error!T {
  const info = @typeInfo(T.Slice).pointer;
  const V = info.child;
  const A = std.ArrayListAlignedUnmanaged(V, info.alignment);
  if (asTag(toml) != .array) return error.TomlError;
  var list = try A.initCapacity(conf.allocator, toml.array.items.len);
  for (toml.array.items) |item|
    list.appendAssumeCapacity(try buildUnmanaged(conf, V, item));
  return if (T == A) list else list.toManaged(conf.allocator);
}

fn buildTable(conf: Conf, comptime T: type, toml: Toml) Error!T {
  const is_managed = @hasField(T, "unmanaged");
  const Table = if (is_managed) T.Unmanaged else T;
  const Value = std.meta.FieldType(Table.KV, .value);
  if (asTag(toml) != .table) return error.TomlError;
  var table = Table.empty;
  try table.ensureTotalCapacity(conf.allocator, toml.table.size);
  var iter = toml.table.iterator();
  while (iter.next()) |entry|
    table.putAssumeCapacity(
      entry.key_ptr.*,
      try buildUnmanaged(conf, Value, entry.value_ptr.*));
  return if (is_managed) table.promote(conf.allocator) else table;
}

fn buildUnion(conf: Conf, comptime T: type, toml: Toml) Error!T {
  if (T == Toml) return toml.clone(conf.allocator);
  if (getCustomBuildFn(T)) |build_fn| return try build_fn(conf, toml);
  std.debug.print("{f} => {s}\n", .{toml, @typeName(T)});
  inline for (@typeInfo(T).@"union".fields) |field| loop: {
    return @unionInit(T, field.name, buildUnmanaged(conf, field.type, toml) catch break :loop);
  }
  return error.TomlError;
}

fn getCustomBuildFn(comptime T: type) ?BuildFn(T) {
  if (!@hasDecl(T, "fromToml")) return null;
  const build_fn = T.fromToml;
  if (@TypeOf(build_fn) != BuildFn(T)) @compileError(
    "unsupported fromToml type: " ++ @typeName(T.fromToml) ++
    ", should be: " ++ @typeName(BuildFn(T)));
  return build_fn;
}