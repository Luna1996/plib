const std = @import("std");
const Self = @import("root.zig").Toml;
const esc = @import("escape.zig");
const Tag = Self.Tag;
const Ast = Self.Ast;
const Instant = Self.Instant;

const BuildError = error {TomlError} 
  || std.mem.Allocator.Error
  || std.fmt.ParseIntError
  || std.fmt.ParseFloatError
  || error { Utf8CannotEncodeSurrogateHalf, CodepointTooLarge }
  || error { InvalidISO8601, UnhandledFormat };

pub fn buildToml(allocator: std.mem.Allocator, ast: *const Ast) !Self {
  var root = Self.init(.table);
  errdefer root.deinit(allocator);


  var   i     = @as(usize, 0);
  const items = ast.val.sub.items;
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
  key: *const Ast,
  val: *const Ast,
) !void {
  const item, const found_existing =
    try resolveMulByAst(self, allocator, key, .integer);
  if (found_existing) return error.TomlError;
  item.* = try buildVal(allocator, val);
}

fn buildVal(allocator: std.mem.Allocator, ast: *const Ast) BuildError!Self {
  return switch (ast.tag.?) {
    .basic_string,
    .literal_string,
    .ml_basic_string,
    .ml_literal_string => try buildString  (allocator, ast),
    .integer           => try buildInteger (           ast),
    .float             => try buildFloat   (           ast),
    .boolean           =>     buildBoolean (           ast),
    .array             => try buildArray   (allocator, ast),
    .table             => try buildTable   (allocator, ast),
    else               =>     buildInstant (           ast),
  };
}

fn buildString(allocator: std.mem.Allocator, ast: *const Ast) !Self {
  const str, const need_free = try dupeString(allocator, ast);
  return .{.string = if (need_free) str else try allocator.dupe(u8, str)};
}

fn buildInteger(ast: *const Ast) !Self {
  return .{.integer = try std.fmt.parseInt(i64, ast.val.str, 0)};
}

fn buildFloat(ast: *const Ast) !Self {
  return .{.float = try std.fmt.parseFloat(f64, ast.val.str)};
}

fn buildBoolean(ast: *const Ast) Self {
  return .{.boolean = std.mem.eql(u8, ast.val.str, "true")};
}

fn buildInstant(ast: *const Ast) !Self {
  return .{.instant = try Instant.fromAst(ast)};
}

fn buildArray(allocator: std.mem.Allocator, ast: *const Ast) !Self {
  var self = Self.init(.array);
  errdefer self.deinit(allocator);
  for (ast.val.sub.items) |*item| {
    var next = try buildVal(allocator, item);
    errdefer next.deinit(allocator);
    try self.array.append(allocator, next);
  }
  return self;
}

fn buildTable(allocator: std.mem.Allocator, ast: *const Ast) !Self {
  var self = Self.init(.table);
  errdefer self.deinit(allocator);
  var i: usize = 0;
  const items = ast.val.sub.items;
  const len = items.len;
  while (i < len) : (i += 2)
    try buildKeyVal(&self, allocator, &items[i], &items[i + 1]);
  return self;
}

fn resolveTable(
  self: *Self,
  allocator: std.mem.Allocator,
  ast: *const Ast
) !*Self {
  const next, const found_existing =
    try resolveMulByAst(self, allocator, ast.get(0), .table);
  return if (found_existing) error.TomlError else next;
}

fn resolveArray(
  self: *Self,
  allocator: std.mem.Allocator,
  ast: *const Ast
) !*Self {
  const next: *Self, _ = try resolveMulByAst(self, allocator, ast.get(0), .array);
  const item = try next.array.addOne(allocator);
  item.* = Self.init(.table);
  return item;
}

const ResolveResult: type = std.meta.Tuple(&.{*Self, bool});

fn resolveMulByAst(
  self: *Self,
  allocator: std.mem.Allocator,
  ast: *const Ast,
  comptime expect: Tag,
) !ResolveResult {
  const keys = ast.val.sub.items;
  const len = keys.len;
  var current_table = self;
  for (keys[0..len - 1]) |*key|
    current_table, _ = try resolveOneByAst(current_table, allocator, key, .table);
  return try resolveOneByAst(current_table, allocator, &keys[len - 1], expect);
}

fn resolveOneByAst(
  self: *Self,
  allocator: std.mem.Allocator,
  ast: *const Ast,
  comptime expect: Tag,
) !ResolveResult {
  var key, const need_free = try dupeString(allocator, ast);
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
  ast: *const Ast,
) !std.meta.Tuple(&.{[]const u8, bool}) {
  const str = ast.val.str;
  const len = str.len;
  return switch (ast.tag.?) {
    .basic_string      => .{ try esc.unescape(allocator, str[1..len - 1]), true  },
    .ml_basic_string   => .{ try esc.unescape(allocator, str[3..len - 3]), true  },
    .literal_string    => .{                             str[1..len - 1] , false },
    .ml_literal_string => .{                             str[3..len - 3] , false },
    .unquoted_key      => .{                             str             , false },
    else => unreachable,
  };
}