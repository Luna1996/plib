const std = @import("std");

pub fn deinitAny(self: anytype, allocator: std.mem.Allocator) void {
  const T: type = @TypeOf(self);
  switch (@typeInfo(T)) {
    .pointer   => |info| switch (info.size) {
      .one => {
        deinitAny(self.*, allocator);
        allocator.destroy(self);
      },
      .slice => {
        if (comptime needDeinit(info.child))
          for (self) |item| deinitAny(item, allocator);
        allocator.free(self);
      },
      else => {},
    },
    .optional  => if (self) |item| deinitAny(item, allocator),
    .array     => |info| if (comptime needDeinit(info.child)) for (self) |item| deinitAny(item, allocator),
    .vector    => |info| if (comptime needDeinit(info.child)) for (0..info.len) |i| deinitAny(self[i], allocator),
    .@"struct" => |info| if (comptime isArray(T)) {
      deinitArray(self, allocator);
    } else if (comptime isTable(T)) {
      deinitTable(self, allocator);
    } else if (comptime hasDeinit(T)) {
      customDeinit(self, allocator);
    } else {
      inline for (info.fields) |field| deinitAny(@field(self, field.name), allocator);
    },
    .@"union"  => |info| if (comptime hasDeinit(T)) {
      customDeinit(self, allocator);
    } else {
      if (info.tag_type == null) return;
      switch (std.meta.activeTag(self)) {
        inline else => |tag| deinitAny(@field(self, @tagName(tag)), allocator),
      }
    },
    else => {},
  }
}

fn needDeinit(comptime T: type) bool {
  return switch (@typeInfo(T)) {
    .optional, .pointer, .array, .vector, .@"struct", .@"union" => true,
    else => false,
  };
}

fn hasDeinit(comptime T: type) bool {
  if (!@hasDecl(T, "deinit")) return false;
  return switch (@TypeOf(T.deinit)) {
    fn(T)void, fn(*T, std.mem.Allocator)void => true,
    else => false,
  };
}

pub fn isArray(comptime T: type) bool {
  if (!@hasDecl(T, "Slice")) return false;
  return switch (@typeInfo(T.Slice)) {
    .pointer => |info|
      T == std.ArrayListAligned(info.child, info.alignment) or
      T == std.ArrayListAlignedUnmanaged(info.child, info.alignment),
    else => false,
  };
}

pub fn isTable(comptime T: type) bool {
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


fn deinitArray(self: anytype, allocator: std.mem.Allocator) void {
  const V = std.meta.Child(@TypeOf(self).Slice);
  if (needDeinit(V)) for (self.items) |item| deinitAny(item, allocator);
  customDeinit(self, allocator);
}

fn deinitTable(self: anytype, allocator: std.mem.Allocator) void {
  const KV = @TypeOf(self).KV;
  const K = std.meta.FieldType(KV, .key);
  const V = std.meta.FieldType(KV, .value);
  var iter = self.iterator();
  while (iter.next()) |entry| {
    if (comptime needDeinit(K)) deinitAny(entry.key_ptr.*, allocator);
    if (comptime needDeinit(V)) deinitAny(entry.value_ptr.*, allocator);
  }
  customDeinit(self, allocator);
}

fn customDeinit(self: anytype, allocator: std.mem.Allocator) void {
  const T = @TypeOf(self);
  switch (@TypeOf(T.deinit)) {
    fn(T)void => self.deinit(),
    fn(*T, std.mem.Allocator)void => {
      var mut_self = self;
      mut_self.deinit(allocator);
    },
    else => unreachable,
  }
}