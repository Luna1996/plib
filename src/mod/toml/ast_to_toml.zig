const Self = @This();

const std = @import("std");
const Toml = @import("root.zig").Toml;
const esc = @import("escape.zig");
const Tag = Toml.Tag;
const Ast = Toml.Ast;
const AstTag = Toml.Parser.Tag;
const DateTime = Toml.DateTime;

const Path = Toml.Path;
const PathContext = Toml.PathContext;

const asTag = std.meta.activeTag;

const BuildError = error {TomlError, DateTimeError} 
  || std.mem.Allocator.Error
  || std.fmt.ParseIntError
  || std.fmt.ParseFloatError
  || error { Utf8CannotEncodeSurrogateHalf, CodepointTooLarge };

const ExplicitLvl = enum(u2) {implicit, explicit, closed};
const ExplicitMap = std.HashMapUnmanaged(Path, ExplicitLvl, PathContext, std.hash_map.default_max_load_percentage);

const ErrorInfo = struct {
  file: ?[]const u8,
  text: []const u8,
};

allocator: std.mem.Allocator,
root: *Toml,

current_path: Path = Path.empty,
current_table: *Toml,

explicit: ExplicitMap = ExplicitMap.empty,

error_info: ?ErrorInfo,

pub fn build(allocator: std.mem.Allocator, ast: *const Ast, error_info: ?ErrorInfo) !Toml {
  var root = Toml.init(.table);
  var self = Self {
    .allocator = allocator,
    .root = &root,
    .current_table = &root,
    .error_info = error_info,
  };
  defer self.deinit();
  errdefer root.deinit(allocator);

  if (asTag(ast.val) == .str) return root;

  var iter = ast.iterator();
  while (iter.next()) |exp_ast| {
    if (asTag(exp_ast.val) == .str) continue;
    var exp_iter = exp_ast.iterator();
    if (exp_iter.next()) |sub_ast| switch (sub_ast.tag.?) {
      .keyval => try self.buildKeyVal(self.current_table, sub_ast),
      else    => try self.changeCurrentTable(sub_ast),
    };
  }

  return root;
}

fn deinit(self: *Self) void {
  var keys = self.explicit.keyIterator();
  while (keys.next()) |key| key.deinit(self.allocator);
  self.explicit.deinit(self.allocator);
  self.current_path.deinit(self.allocator);
}

fn changeCurrentTable(self: *Self, ast: *const Ast) !void {
  var iter = ast.iterator();
  self.current_path.items.len = 0;
  self.current_table = try self.resolveMul(self.root, iter.next().?, ast.tag.?);
}

fn resolveMul(self: *Self, root: *Toml, ast: *const Ast, ast_tag: AstTag) !*Toml {
  var iter = ast.iterator();
  var current_table = root;
  var cur_ast = iter.next();
  while (cur_ast) |key| {
    const nxt_ast = iter.next();
    current_table = try self.resolveOne(current_table, key.val.str, ast_tag, nxt_ast == null);
    cur_ast = nxt_ast;
  }
  return current_table;
}

fn resolveOne(self: *Self, root: *Toml, key_esc: []const u8, ast_tag: AstTag, is_last: bool) !*Toml {
  errdefer |e| if (e == error.TomlError) if (self.error_info) |info| {
    std.debug.print("{}", .{@import("plib").fmtFail("toml structure error", .{
      .file = info.file,
      .text = info.text,
      .span = key_esc,
    })});
  };

  var want_tag: Tag = tag: {
    if (!is_last) break :tag .table;
    break :tag switch (ast_tag) {
      .keyval      => .float,
      .std_table   => .table,
      .array_table => .array,
      else         => unreachable,
    };
  };

  var key, var need_free = try esc.unescape(self.allocator, key_esc);
  defer if (need_free) self.allocator.free(key);
  
  var tag: Tag = undefined;
  var new = new: {
    const res = try root.table.getOrPut(self.allocator, key);
    if (res.found_existing) {
      if (need_free) {
        self.allocator.free(key);
        key = res.key_ptr.*;
      }
      tag = asTag(res.value_ptr.*);
    } else {
      if (!need_free){
        key = try self.allocator.dupe(u8, key);
        res.key_ptr.* = key;
      }
      res.value_ptr.* = Toml.init(want_tag);
      tag = want_tag;
    }
    need_free = false;
    break :new res.value_ptr;
  };

  try self.current_path.append(self.allocator, .{.str = key});

  if (tag == .array and !is_last and want_tag == .table) {
    try self.canExtend(ast_tag, false);
    const num = new.array.items.len - 1;
    new = &new.array.items[num];
    tag = asTag(new.*);
    try self.current_path.append(self.allocator, .{.num = num});
  }

  if (tag == .array and is_last and want_tag == .array) {
    const num = new.array.items.len;
    want_tag = .table;
    try self.canExtend(ast_tag, true);
    new = try new.array.addOne(self.allocator);
    new.* = Toml.init(want_tag);
    tag = want_tag;
    try self.current_path.append(self.allocator, .{.num = num});
  }

  try self.canExtend(ast_tag, is_last);

  if (calcExplicitLvl(ast_tag, is_last)) |lvl| {
    const res = try self.explicit.getOrPut(self.allocator, self.current_path);
    if (!res.found_existing) {
      errdefer _ = self.explicit.remove(self.current_path);
      res.key_ptr.* = try self.current_path.clone(self.allocator);
    }
    res.value_ptr.* = lvl;
  }

  return if (tag == want_tag) new else error.TomlError;
}

fn buildKeyVal(self: *Self, root: *Toml, ast: *const Ast) !void {
  var iter = ast.iterator();
  const key = iter.next().?;
  const val = iter.next().?;
  const path_len = self.current_path.items.len;
  const item = try self.resolveMul(root, key, ast.tag.?);
  try self.buildVal(item, val);
  self.current_path.items.len = path_len;
}

fn buildVal(self: *Self, root: *Toml, ast: *const Ast) BuildError!void {
  switch (ast.tag.?) {
    .string       => try self.buildString  (root, ast.val.str),
    .integer      => try      buildInteger (root, ast.val.str),
    .float        => try      buildFloat   (root, ast.val.str),
    .boolean      =>          buildBoolean (root, ast.val.str),
    .date_time    => try      buildDateTime(root, ast.val.str),
    .array        => try self.buildArray   (root, ast),
    .inline_table => try self.buildTable   (root, ast),
    else          =>     unreachable,
  }
}

fn buildString(self: *Self, root: *Toml, raw: []const u8) !void {
  const str, const need_free = try esc.unescape(self.allocator, raw);
  root.* = .{.string = if (need_free) str else try self.allocator.dupe(u8, str)};
}

fn buildInteger(root: *Toml, str: []const u8) !void {
  root.* = .{.integer = try std.fmt.parseInt(i64, str, 0)};
}

fn buildFloat(root: *Toml, str: []const u8) !void {
  root.* = .{.float = try std.fmt.parseFloat(f64, str)};
}

fn buildBoolean(root: *Toml, str: []const u8) void {
  root.* = .{.boolean = std.mem.eql(u8, str, "true")};
}

fn buildDateTime(root: *Toml, str: []const u8) !void {
  root.* = .{.datetime = try DateTime.fromRFC3339(str)};
}

fn buildArray(self: *Self, root: *Toml, ast: *const Ast) !void {
  root.* = Toml.init(.array);
  if (std.meta.activeTag(ast.val) == .str) return;
  var iter = ast.iterator();
  const path_len = self.current_path.items.len;
  try self.current_path.append(self.allocator, .{.num = 0});
  while (iter.next()) |sub_ast| {
    const item = try root.array.addOne(self.allocator);
    item.* = Toml.init(.integer);
    try self.buildVal(item, sub_ast);
    self.current_path.items[path_len].num += 1;
  }
  self.current_path.items.len = path_len;
}

fn buildTable(self: *Self, root: *Toml, ast: *const Ast) !void {
  root.* = Toml.init(.table);
  if (std.meta.activeTag(ast.val) == .str) return;
  var iter = ast.iterator();
  while (iter.next()) |sub_ast|
    try self.buildKeyVal(root, sub_ast);
}

fn calcExplicitLvl(ast_tag: AstTag, is_last: bool) ?ExplicitLvl {
  return if (is_last) (if (ast_tag == .keyval) .closed else .explicit)
         else         (if (ast_tag == .keyval) .implicit else null);
}

fn canExtend(self: *Self, ast_tag: AstTag, is_last: bool) !void {
  if (switch (self.explicit.get(self.current_path) orelse return) {
    .closed => true,
    .explicit => is_last or ast_tag == .keyval,
    .implicit => is_last and ast_tag != .keyval,
  }) return error.TomlError;
}