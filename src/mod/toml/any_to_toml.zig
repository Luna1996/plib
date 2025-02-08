const std = @import("std");
const asTag = std.meta.activeTag;
const deinit_any = @import("plib").deinit_any;
const isArray = deinit_any.isArray;
const isTable = deinit_any.isTable;
const Toml = @import("root.zig").Toml;
const DateTime = @import("datetime.zig").DateTime;

pub fn build(self: anytype, allocator: std.mem.Allocator) Toml.Error!Toml {
  const Self = @TypeOf(self);
  return switch (@typeInfo(Self)) {
    .int       => try buildInt      (self           ),
    .bool      => try buildBool     (self           ),
    .float     => try buildFloat    (self           ),
    .array     => try buildFixed    (self, allocator),
    .vector    => try buildFixed    (self, allocator),
    .@"enum"   => try buildEnum     (self, allocator),
    .optional  => try buildOptional (self, allocator),
    .@"struct" => try buildStruct   (self, allocator),
    .@"union"  => try buildUnion    (self, allocator),
    .pointer   => try buildPointer  (self, allocator),
    else => @compileError("unsupported type: " ++ @typeName(Self)),
  };
}

inline fn buildInt(self: anytype) Toml.Error!Toml {
  return .{.integer = @intCast(self)};
}

inline fn buildBool(self: anytype) Toml.Error!Toml {
  return .{.boolean = self};
}

inline fn buildFloat(self: anytype) Toml.Error!Toml {
  return .{.float = @floatCast(self)};
}

fn buildFixed(self: anytype, allocator: std.mem.Allocator) Toml.Error!Toml {
  const array = switch (@typeInfo(@TypeOf(self))) {
    .array => self,
    .vector => |info| @as([info.len]info.child, self),
    else => unreachable,
  };
  return try buildSlice(array[0..], allocator);
}

inline fn buildEnum(self: anytype, allocator: std.mem.Allocator) Toml.Error!Toml {
  return if (comptime getCustomBuildFn(@TypeOf(self))) |build_fn| 
    try build_fn(self, allocator)
  else .{.string = try allocator.dupe(u8, @tagName(self))};
}

inline fn buildOptional(self: anytype, allocator: std.mem.Allocator) Toml.Error!Toml {
  return if (self) |item| try build(item, allocator) else error.TomlError;
}

fn buildStruct(self: anytype, allocator: std.mem.Allocator) Toml.Error!Toml {
  const Self = @TypeOf(self);
  if (comptime Self == DateTime) return .{.datetime = self};
  if (comptime isArray(Self)) return try buildSlice(self.items, allocator);
  if (comptime isTable(Self)) return try buildTable(self, allocator);
  if (comptime getCustomBuildFn(Self)) |build_fn| return try build_fn(self, allocator);

  const fields = @typeInfo(Self).@"struct".fields;

  var toml = Toml.init(.table);
  errdefer toml.deinit(allocator);
  try toml.table.ensureTotalCapacity(allocator, fields.len);

  inline for (fields) |field| {
    const name = try allocator.dupe(u8, field.name);
    errdefer allocator.free(name);
    toml.table.putAssumeCapacity(name, try build(@field(self, field.name), allocator));
  }

  return toml;
}

fn buildUnion(self: anytype, allocator: std.mem.Allocator) Toml.Error!Toml {
  const Self = @TypeOf(self);
  if (comptime Self == Toml) return self;
  if (comptime getCustomBuildFn(Self)) |build_fn| return try build_fn(self, allocator);
  return switch (asTag(self)) { inline else => |tag|
    try build(@field(self, @tagName(tag)), allocator)
  };
}

fn buildPointer(self: anytype, allocator: std.mem.Allocator) Toml.Error!Toml {
  const Self = @TypeOf(self);
  const info = @typeInfo(Self).pointer;
  return switch (info.size) {
    .One => try build(self.*, allocator),
    .Slice => if (info.child == u8) .{.string = try allocator.dupe(u8, self)}
              else try buildSlice(self, allocator),
    else => @compileError("unsupported type: " ++ @typeName(Self)),
  };
}

fn buildSlice(self: anytype, allocator: std.mem.Allocator) Toml.Error!Toml {
  var toml = Toml.init(.array);
  errdefer toml.deinit(allocator);
  try toml.array.ensureTotalCapacityPrecise(allocator, self.len);
  for (self) |item| toml.array.appendAssumeCapacity(try build(item, allocator));
  return toml;
}

fn buildTable(self: anytype, allocator: std.mem.Allocator) Toml.Error!Toml {
  var toml = Toml.init(.table);
  try toml.table.ensureTotalCapacity(allocator, self.count());
  var iter = self.iterator();
  while (iter.next()) |entry| {
    const name = try allocator.dupe(u8, entry.key_ptr.*);
    errdefer allocator.free(name);
    toml.table.putAssumeCapacity(name, try build(entry.value_ptr.*, allocator));
  }
  return toml;
}

fn BuildFn(comptime T: type) type {
  return fn (T, std.mem.Allocator) Toml.Error!Toml;
}

fn getCustomBuildFn(comptime T: type) ?BuildFn(T) {
  if (!@hasDecl(T, "toToml")) return null;
  const build_fn = T.fromToml;
  if (@TypeOf(build_fn) != BuildFn(T)) @compileError(
    "unsupported toToml type: " ++ @typeName(T.fromToml) ++
    ", should be: " ++ @typeName(BuildFn(T)));
  return build_fn;
}