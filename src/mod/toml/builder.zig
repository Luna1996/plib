const Self = @This();

const std = @import("std");
const Toml = @import("root.zig").Toml;
const esc = @import("escape.zig");
const Tag = Toml.Tag;
const Ast = Toml.Ast;
const AstTag = Toml.Parser.Tag;
const DateTime = Toml.DateTime;

const asTag = std.meta.activeTag;

const BuildError = error {TomlError, DateTimeError} 
  || std.mem.Allocator.Error
  || std.fmt.ParseIntError
  || std.fmt.ParseFloatError
  || error { Utf8CannotEncodeSurrogateHalf, CodepointTooLarge };

/// 0 - open\
/// 1 - implicit\
/// 2 - explicit\
/// 3 - closed
const ExplicitMap = std.AutoHashMapUnmanaged(*Toml, u2);

const ErrorInfo = struct {
  file: ?[]const u8,
  text: []const u8,
};

allocator: std.mem.Allocator,
root: *Toml,
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
  errdefer self.root.deinit(allocator);

  if (asTag(ast.val) == .str) return root;

  for (ast.val.sub.items) |*sub_ast| switch (sub_ast.tag.?) {
    .keyval => try self.buildKeyVal(self.current_table, sub_ast),
    else    => try self.changeCurrentTable(sub_ast),
  };

  return root;
}

fn deinit(self: *Self) void {
  self.explicit.deinit(self.allocator);
}

fn changeCurrentTable(self: *Self, ast: *const Ast) !void {
  self.current_table = try self.resolveMul(self.root, ast);
}

fn resolveMul(self: *Self, root: *Toml, ast: *const Ast) !*Toml {
  const keys = ast.get(0).val.sub.items;
  const ast_tag = ast.tag.?;
  var current_table = root;
  for (keys, 1..) |*key, i|
    current_table = try self.resolveOne(current_table, key.val.str, ast_tag, i == keys.len);
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
  errdefer if (need_free) self.allocator.free(key);
  
  var tag: Tag = undefined;
  var new = new: {
    const res = try root.table.getOrPut(self.allocator, key);
    if (res.found_existing) {
      if (need_free) {
        self.allocator.free(key);
        need_free = false;
      }
      tag = asTag(res.value_ptr.*);
    } else {
      if (!need_free){
        key = try self.allocator.dupe(u8, key);
        need_free = true;
        res.key_ptr.* = key;
      }
      res.value_ptr.* = Toml.init(want_tag);
      tag = want_tag;
    }
    break :new res.value_ptr;
  };


  if (!is_last and want_tag == .table and tag == .array) {
    try self.canExtend(new, ast_tag, false);
    new = &new.array.items[new.array.items.len - 1];
    tag = asTag(new.*);
  }

  if (is_last and want_tag == .array and tag == .array) {
    want_tag = .table;
    try self.canExtend(new, ast_tag, true);
    new = try new.array.addOne(self.allocator);
    new.* = Toml.init(want_tag);
    tag = want_tag;
  }

  try self.canExtend(new, ast_tag, is_last);

  if (calcExplicitLvl(ast_tag, is_last)) |lvl|
    try self.explicit.put(self.allocator, new, lvl);

  return if (tag == want_tag) new else error.TomlError;
}

fn buildKeyVal(self: *Self, root: *Toml, ast: *const Ast) !void {
  const val = ast.get(1);
  const item = try self.resolveMul(root, ast);
  item.* = try self.buildVal(val);
}

fn buildVal(self: *Self, ast: *const Ast) BuildError!Toml {
  return switch (ast.tag.?) {
    .string       => try self.buildString  (ast.val.str),
    .integer      => try      buildInteger (ast.val.str),
    .float        => try      buildFloat   (ast.val.str),
    .boolean      =>          buildBoolean (ast.val.str),
    .date_time    =>          buildDateTime(ast.val.str),
    .array        => try self.buildArray   (ast),
    .inline_table => try self.buildTable   (ast),
    else          =>     unreachable,
  };
}

fn buildString(self: *Self, raw: []const u8) !Toml {
  const str, const need_free = try esc.unescape(self.allocator, raw);
  return .{.string = if (need_free) str else try self.allocator.dupe(u8, str)};
}

fn buildInteger(str: []const u8) !Toml {
  return .{.integer = try std.fmt.parseInt(i64, str, 0)};
}

fn buildFloat(str: []const u8) !Toml {
  return .{.float = try std.fmt.parseFloat(f64, str)};
}

fn buildBoolean(str: []const u8) Toml {
  return .{.boolean = std.mem.eql(u8, str, "true")};
}

fn buildDateTime(str: []const u8) !Toml {
  return .{.datetime = try DateTime.fromRFC3339(str)};
}

fn buildArray(self: *Self, ast: *const Ast) !Toml {
  var item = Toml.init(.array);
  errdefer item.deinit(self.allocator);
  if (std.meta.activeTag(ast.val) == .str) return item;
  for (ast.val.sub.items) |*sub_ast| {
    var next = try self.buildVal(sub_ast);
    errdefer next.deinit(self.allocator);
    try item.array.append(self.allocator, next);
  }
  return item;
}

fn buildTable(self: *Self, ast: *const Ast) !Toml {
  var item = Toml.init(.table);
  errdefer item.deinit(self.allocator);
  if (std.meta.activeTag(ast.val) == .str) return item;
  for (ast.val.sub.items) |*sub_ast|
    try self.buildKeyVal(&item, sub_ast);
  return item;
}

fn calcExplicitLvl(ast_tag: AstTag, is_last: bool) ?u2 {
  return if (is_last) (if (ast_tag == .keyval) 3 else 2)
         else         (if (ast_tag == .keyval) 1 else null);
}

fn canExtend(self: *Self, toml: *Toml, ast_tag: AstTag, is_last: bool) !void {
  if (switch (self.explicit.get(toml) orelse return) {
    3 => true,
    2 => is_last or ast_tag == .keyval,
    1 => is_last and ast_tag != .keyval,
    0 => unreachable,
  }) return error.TomlError;
}