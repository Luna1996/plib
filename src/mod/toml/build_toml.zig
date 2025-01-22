const std = @import("std");
const Self = @import("../toml.zig").Toml;
const esc = @import("escape.zig");
const Tag = Self.Tag;
const Node = Self.Node;
const Instant = Self.Instant;

const BuildError = error {TomlError} 
  || std.mem.Allocator.Error
  || std.fmt.ParseIntError
  || std.fmt.ParseFloatError
  || error { Utf8CannotEncodeSurrogateHalf, CodepointTooLarge }
  || error { InvalidISO8601, UnhandledFormat };

pub fn buildToml(allocator: std.mem.Allocator, node: *const Node) !Self {
  var root = Self.init(.table);
  errdefer root.deinit(allocator);


  var   i     = @as(usize, 0);
  const items = node.val.sub.items;
  const len   = items.len;
  var   self  = &root;

  while (i < len) {
    const item = &items[i];
    switch (item.tag.?) {
      .key => { 
        try buildKeyVal(self, allocator, item, &items[i + 1]);
        i += 2;
      },
      .std_table => {
        self = try resolveTable(&root, allocator, item);
        i += 1;
      },
      .array_table => {
        self = try resolveArray(&root, allocator, item);
        i += 1;
      },
      else => unreachable,
    }
  }

  return root;
}

fn buildKeyVal(
  self: *Self,
  allocator: std.mem.Allocator,
  key: *const Node,
  val: *const Node,
) !void {
  const item, const found_existing =
    try resolveMulByNode(self, allocator, key, .integer);
  if (found_existing) return error.TomlError;
  item.* = try buildVal(allocator, val);
}

fn buildVal(allocator: std.mem.Allocator, node: *const Node) BuildError!Self {
  return switch (node.tag.?) {
    .basic_string,
    .literal_string,
    .ml_basic_string,
    .ml_literal_string => try buildString  (allocator, node),
    .integer           => try buildInteger (           node),
    .float             => try buildFloat   (           node),
    .boolean           =>     buildBoolean (           node),
    .array             => try buildArray   (allocator, node),
    .table             => try buildTable   (allocator, node),
    else               =>     buildInstant (           node),
  };
}

fn buildString(allocator: std.mem.Allocator, node: *const Node) !Self {
  const str, const need_free = try dupeString(allocator, node);
  return .{.string = if (need_free) str else try allocator.dupe(u8, str)};
}

fn buildInteger(node: *const Node) !Self {
  return .{.integer = try std.fmt.parseInt(i64, node.val.str, 0)};
}

fn buildFloat(node: *const Node) !Self {
  return .{.float = try std.fmt.parseFloat(f64, node.val.str)};
}

fn buildBoolean(node: *const Node) Self {
  return .{.boolean = std.mem.eql(u8, node.val.str, "true")};
}

fn buildInstant(node: *const Node) !Self {
  return .{.instant = try Instant.fromNode(node)};
}

fn buildArray(allocator: std.mem.Allocator, node: *const Node) !Self {
  var self = Self.init(.array);
  errdefer self.deinit(allocator);
  for (node.val.sub.items) |*item| {
    var next = try buildVal(allocator, item);
    errdefer next.deinit(allocator);
    try self.array.append(allocator, next);
  }
  return self;
}

fn buildTable(allocator: std.mem.Allocator, node: *const Node) !Self {
  var self = Self.init(.table);
  errdefer self.deinit(allocator);
  var i: usize = 0;
  const items = node.val.sub.items;
  const len = items.len;
  while (i < len) : (i += 2)
    try buildKeyVal(&self, allocator, &items[i], &items[i + 1]);
  return self;
}

fn resolveTable(
  self: *Self,
  allocator: std.mem.Allocator,
  node: *const Node
) !*Self {
  const next, const found_existing =
    try resolveMulByNode(self, allocator, node.get(0), .table);
  return if (found_existing) error.TomlError else next;
}

fn resolveArray(
  self: *Self,
  allocator: std.mem.Allocator,
  node: *const Node
) !*Self {
  const next: *Self, _ = try resolveMulByNode(self, allocator, node.get(0), .array);
  const item = try next.array.addOne(allocator);
  item.* = Self.init(.table);
  return item;
}

const ResolveResult: type = std.meta.Tuple(&.{*Self, bool});

fn resolveMulByNode(
  self: *Self,
  allocator: std.mem.Allocator,
  node: *const Node,
  comptime expect: Tag,
) !ResolveResult {
  const keys = node.val.sub.items;
  const len = keys.len;
  var current_table = self;
  for (keys[0..len - 1]) |*key|
    current_table, _ = try resolveOneByNode(current_table, allocator, key, .table);
  return try resolveOneByNode(current_table, allocator, &keys[len - 1], expect);
}

fn resolveOneByNode(
  self: *Self,
  allocator: std.mem.Allocator,
  node: *const Node,
  comptime expect: Tag,
) !ResolveResult {
  var key, const need_free = try dupeString(allocator, node);
  if (self.table.getPtr(key)) |old| {
    if (need_free) allocator.free(key);
    if (std.meta.activeTag(old.*) != expect) return error.TomlError;
    return .{old, true};
  }
  if (!need_free) key = try allocator.dupe(u8, key);
  errdefer allocator.free(key);
  const res = try self.table.getOrPut(allocator, key);
  res.value_ptr.* = Self.init(expect);
  return .{ res.value_ptr, res.found_existing };
}

fn dupeString(
  allocator: std.mem.Allocator,
  node: *const Node,
) !std.meta.Tuple(&.{[]const u8, bool}) {
  const str = node.val.str;
  const len = str.len;
  return switch (node.tag.?) {
    .basic_string      => .{ try esc.unescape(allocator, str[1..len - 1]), true  },
    .ml_basic_string   => .{ try esc.unescape(allocator, str[3..len - 3]), true  },
    .literal_string    => .{                             str[1..len - 1] , false },
    .ml_literal_string => .{                             str[3..len - 3] , false },
    .unquoted_key      => .{                             str             , false },
    else => unreachable,
  };
}