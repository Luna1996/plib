const std = @import("std");
const Self = @import("root.zig").Toml;
const esc = @import("escape.zig");
const Tag = Self.Tag;
const Ast = Self.Ast;
const DateTime = Self.DateTime;

const BuildError = error {TomlError, DateTimeError} 
  || std.mem.Allocator.Error
  || std.fmt.ParseIntError
  || std.fmt.ParseFloatError
  || error { Utf8CannotEncodeSurrogateHalf, CodepointTooLarge };

const State = enum(u1) {explicit, implicit};
const Visits = std.AutoHashMapUnmanaged(*Self, State);

pub fn buildToml(allocator: std.mem.Allocator, ast: *const Ast) !Self {
  var root = Self.init(.table);
  errdefer root.deinit(allocator);

  var visits = Visits.empty;
  defer visits.deinit(allocator);

  if (std.meta.activeTag(ast.val) == .str) return root;

  var   i     = @as(usize, 0);
  const items = ast.val.sub.items;
  const len   = items.len;
  var   self  = &root;

  while (i < len) {
    const item = &items[i];
    switch (item.tag.?) {
      .key => { 
        try buildKeyVal(self, allocator, item, &items[i + 1], &visits);
        i += 2;
      },
      .std_table => {
        self = try resolveTable(&root, allocator, item, &visits);
        i += 1;
      },
      .array_table => {
        self = try resolveArray(&root, allocator, item, &visits);
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
  visits: *Visits,
) !void {
  const item = try resolveMulByAst(self, allocator, key, visits, .explicit, .integer);
  item.* = try buildVal(allocator, val, visits);
}

fn buildVal(
  allocator: std.mem.Allocator,
  ast: *const Ast,
  visits: *Visits,
) BuildError!Self {
  return switch (ast.tag.?) {
    .basic_string,
    .literal_string,
    .ml_basic_string,
    .ml_literal_string => try buildString  (allocator, ast),
    .integer           => try buildInteger (           ast),
    .float             => try buildFloat   (           ast),
    .boolean           =>     buildBoolean (           ast),
    .array             => try buildArray   (allocator, ast, visits),
    .inline_table      => try buildTable   (allocator, ast, visits),
    .offset_date_time,
    .local_date_time,
    .local_date,
    .local_time        =>     buildDateTime(           ast),
    else               =>     unreachable,
  };
}

fn buildString(allocator: std.mem.Allocator, ast: *const Ast) !Self {
  const str, const need_free = try esc.unescape(allocator, ast);
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

fn buildDateTime(ast: *const Ast) !Self {
  return .{.datetime = try DateTime.fromRFC3339(ast.val.str)};
}

fn buildArray(allocator: std.mem.Allocator, ast: *const Ast, visits: *Visits) !Self {
  var self = Self.init(.array);
  errdefer self.deinit(allocator);
  if (std.meta.activeTag(ast.val) == .str) return self;
  for (ast.val.sub.items) |*item| {
    var next = try buildVal(allocator, item, visits);
    errdefer next.deinit(allocator);
    try self.array.append(allocator, next);
  }
  return self;
}

fn buildTable(allocator: std.mem.Allocator, ast: *const Ast, visits: *Visits) !Self {
  var self = Self.init(.table);
  errdefer self.deinit(allocator);
  if (std.meta.activeTag(ast.val) == .str) return self;
  var i: usize = 0;
  const items = ast.val.sub.items;
  const len = items.len;
  while (i < len) : (i += 2)
    try buildKeyVal(&self, allocator, &items[i], &items[i + 1], visits);
  return self;
}

fn resolveTable(
  self: *Self,
  allocator: std.mem.Allocator,
  ast: *const Ast,
  visits: *Visits,
) !*Self {
  return try resolveMulByAst(self, allocator, ast.get(0), visits, .explicit, .table);
}

fn resolveArray(
  self: *Self,
  allocator: std.mem.Allocator,
  ast: *const Ast,
  visits: *Visits,
) !*Self {
  const next = try resolveMulByAst(self, allocator, ast.get(0), visits, .implicit, .array);
  const item = try next.array.addOne(allocator);
  item.* = Self.init(.table);
  return item;
}

fn resolveMulByAst(
  self: *Self,
  allocator: std.mem.Allocator,
  ast: *const Ast,
  visits: *Visits,
  comptime state: State,
  comptime expect: Tag,
) !*Self {
  const keys = ast.val.sub.items;
  const len = keys.len;
  var current_table = self;
  for (keys[0..len - 1]) |*key| {
    current_table = try resolveOneByAst(current_table, allocator, key, visits, .implicit, .table);
    _ = try visits.getOrPutValue(allocator, current_table, .implicit);
  }
  current_table = try resolveOneByAst(current_table, allocator, &keys[len - 1], visits, state, expect);
  try visits.put(allocator, current_table, state);
  return current_table;
}

fn resolveOneByAst(
  self: *Self,
  allocator: std.mem.Allocator,
  ast: *const Ast,
  visits: *Visits,
  comptime state: State,
  comptime expect: Tag,
) !*Self {
  var key, const need_free = try esc.unescape(allocator, ast);
  if (self.table.getPtr(key)) |val| {
    if (need_free) allocator.free(key);
    const is_close = visits.get(val) == .explicit;
    if (is_close and state == .explicit)
      return error.TomlError;
    const tag = std.meta.activeTag(val.*);
    if (tag == expect) return val;
    if (tag == .array and !is_close) {
      const new = &val.array.items[val.array.items.len - 1];
      if (std.meta.activeTag(new.*) == expect)
        return new;
    }
    return error.TomlError;
  }
  if (!need_free) key = try allocator.dupe(u8, key);
  errdefer allocator.free(key);
  const res = try self.table.getOrPut(allocator, key);
  res.value_ptr.* = Self.init(expect);
  return res.value_ptr;
}