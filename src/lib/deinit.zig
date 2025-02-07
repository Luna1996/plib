const std = @import("std");

pub fn deinit(self: anytype, allocator: std.mem.Allocator) void {
  const Self: type = @TypeOf(self);
  switch (@typeInfo(Self)) {
    .pointer   => |info| switch (info.size) {
      .One => {
        deinit(self.*, allocator);
        allocator.destroy(self);
      },
      .Slice => {
        if (comptime !isFlat(info.child))
          for (self) |item| deinit(item, allocator);
        allocator.free(self);
      },
      else => {},
    },
    .optional  => if (self) |item| deinit(item, allocator),
    .array     => |info| if (comptime !isFlat(info.child)) for (self) |item| deinit(item, allocator),
    .vector    => |info| if (comptime !isFlat(info.child)) for (0..info.len) |i| deinit(self[i], allocator),
    .@"struct" => |info| if (comptime hasDeinit(Self)) {
      customDeinit(Self, self, allocator);
    } else {
      inline for (info.fields) |field| deinit(@field(self, field.name), allocator);
    },
    .@"union"  => |info| if (comptime hasDeinit(Self)) {
      customDeinit(Self, self, allocator);
    } else {
      if (info.tag_type == null) return;
      switch (std.meta.activeTag(self)) {
        inline else => |tag| deinit(@field(self, @tagName(tag)), allocator),
      }
    },
    else => {},
  }
}

fn hasDeinit(comptime Self: type) bool {
  if (!@hasDecl(Self, "deinit")) return false;
  return switch (@TypeOf(Self.deinit)) {
    fn(Self)void, fn(*Self, std.mem.Allocator)void => true,
    else => false,
  };
}

fn customDeinit(comptime Self: type, self: Self, allocator: std.mem.Allocator) void {
  switch (@TypeOf(Self.deinit)) {
    fn(Self)void => self.deinit(),
    fn(*Self, std.mem.Allocator)void => {
      var mut_self = self;
      mut_self.deinit(allocator);
    },
    else => unreachable,
  }
}

fn isFlat(comptime T: type) bool {
  return switch (@typeInfo(T)) {
    .optional, .pointer, .array, .vector, .@"struct", .@"union" => false,
    else => true,
  };
}

test "plib.deinit" {
  std.debug.print("\n", .{});
  const allocator = std.testing.allocator;
  const A = std.ArrayList(u8);
  var a = try A.initCapacity(allocator, 10);
  a.appendAssumeCapacity(0);
  defer deinit(a, allocator);
}