const std = @import("std");

const zeit = @import("zeit");

const plib = @import("plib");
const Parser = plib.Parser(@import("gen").abnf);
const Tag = Parser.Tag;
const Node = Parser.Node;
const Array = std.ArrayList;
const Table = std.StringHashMap;

const unescape = @import("toml/string.zig").unescape;

pub const Toml = struct {
  allocator: std.mem.Allocator,
  root: Value,

  const Self = @This();

  pub const Value = union(enum) {
    string: []const u8,
    boolean: bool,
    array: Array(Value),
    table: Table(Value),
    nanosec: zeit.Nanoseconds,
    float: f64,
    integer: i64,
  };

  pub const ValueType = std.meta.Tag(Value);

  const Conf = struct {
    allocator: std.mem.Allocator,
    file_path: ?[]const u8 = null,
    input: []const u8,
  };

  const BuildError = error {TomlError} || std.mem.Allocator.Error;

  pub fn build(conf: Conf) !Self {
    const root = try parse(conf);
    defer root.deinit();

    var self = Self {
      .allocator = conf.allocator,
      .root = Table(Value).init(conf.allocator),
    };
    errdefer self.deinit();

    return self;
  }

  pub fn parse(conf: Conf) !Node {
    var result = try Parser.parse(.{
      .allocator = conf.allocator,
      .input = conf.input,
      .keeps = &.{
        .toml, .key, .std_table, .array_table,
        .unquoted_key, .basic_string, .literal_string,
        .ml_basic_string, .ml_literal_string,
        .boolean, .array, .inline_table, .float, .integer,
        .offset_date_time, .local_date_time, .local_date, .local_time,
      },
      .file_path = conf.file_path,
    });
    errdefer result.root.deinit();

    if (result.fail) |fail| {
      std.debug.print("{}", .{fail});
      return error.ParseError;
    } else {
      return result.root;
    }
  }

  pub fn deinit(self: Self) void {
    self.deinitValue(self.root);
  }

  pub fn initValue(self: Self, wht: ValueType) Value {
    return switch (wht) {
      .string => .{.string = undefined},
      .boolean => .{.boolean = undefined},
      .array => .{.array = Array(Value).init(self.allocator)},
      .table => .{.table = Table(Value).init(self.allocator)},
      .nanosec => .{.nanosec = undefined},
      .float => .{.float = undefined},
      .integer => .{.integer = undefined},
    };
  }

  pub fn deinitValue(self: Self, value: Value) void {
    switch (value) {
      .array => |array| {
        for (array.items) |item| self.deinitValue(item);
        array.deinit();
      },
      .table => |table| {
        var iter = table.iterator();
        while (iter.next()) |item| {
          self.allocator.free(item.key_ptr.*);
          self.deinitValue(item.value_ptr.*);
        }
        table.deinit();
      },
      .string => |string| {
        self.allocator.free(string);
      },
      else => {},
    }
  }

  fn buildToml(self: Self, root: Node) !void {
    const items = root.val.sub.items;
    const ctx = &self.root;
    var i: usize = 0;
    while (i < items.len) {
      const item = items[i];
      switch (item.tag.?) {
        .key => {
          i += 1;
          const next = items[i];
          var new = ctx.*;
          if (try self.resolveMulByNode(&new, item, nodeTagToValueType(next.tag.?))) {
            return error.TomlError;
          }
          try self.buildValue(&new, next);
        },
        .std_table => if (try self.resolveMulByNode(ctx, item.get(0).*, .table)) {
          return error.TomlError;
        },
        .array_table => {
          _ = try self.resolveMulByNode(ctx, item.get(0).*, .array);
          const new = self.initValue(.array);
          try ctx.array.append(new);
          ctx.* = new;
        },
        else => unreachable,
      }
      i += 1;
    }
  }

  const build_value_fns = std.enums.EnumArray(std.meta.Tag(Value), *const fn(Self, *Value, Node) BuildError!void).init(.{
    .string = buildString,
    .boolean = buildBoolean,
    .array = buildArray,
    .table = buildTable,
    .nanosec = buildNanosec,
    .float = buildFloat,
    .integer = buildInteger,
  });

  fn buildValue(self: Self, ctx: *Value, node: Node) !void {
    try build_value_fns.get(std.meta.activeTag(ctx.*))(self, ctx, node);
  }

  fn buildString(self: Self, ctx: *Value, node: Node) !void {
  }

  fn buildBoolean(self: Self, ctx: *Value, node: Node) !void {}

  fn buildArray(self: Self, ctx: *Value, node: Node) !void {}

  fn buildTable(self: Self, ctx: *Value, node: Node) !void {}

  fn buildNanosec(self: Self, ctx: *Value, node: Node) !void {}

  fn buildFloat(self: Self, ctx: *Value, node: Node) !void {}

  fn buildInteger(self: Self, ctx: *Value, node: Node) !void {}

  fn resolveMulByNode(self: Self, ctx: *Value, key: Node, wht: ValueType) !bool {
    const sub_len = key.subLen();
    for (key.val.sub.items[0..sub_len - 1]) |sub|
      _ = try self.resolveOneByNode(ctx, sub, .table);
    return try self.resolveOneByNode(ctx, key.val.sub.items[sub_len - 1], wht);
  }

  fn resolveOneByNode(self: Self, ctx: *Value, key: Node, wht: ValueType) !bool {
    const str = switch (key.tag.?) {
      .unquoted_key => key.val.str,
      .basic_string => try unescape(self.allocator, key.val.str[1..key.val.str.len - 1]),
      .literal_string => key.val.str[1..key.val.str.len - 1],
      else => unreachable,
    };
   
    if (ctx.table.get(str)) |sub| {
      if (key.tag.? == .basic_string)
        self.allocator.free(str);
      if (std.meta.activeTag(sub) != wht)
        return error.TomlError;
      ctx.* = sub;
      return true;
    }

    const sub_key = switch (key.tab.?) {
      .basic_string => str,
      .unquoted_key, .literal_string => try self.allocator.dupe(u8, str),
      else => unreachable,
    };
    errdefer self.allocator.free(sub_key);

    const sub = self.initValue(wht);
    try ctx.table.put(sub_key, sub);
    ctx.* = sub;

    return false;
  }

  fn nodeTagToValueType(tag: Tag) ValueType {
    return switch (tag) {
      .basic_string,
      .literal_string,
      .ml_basic_string,
      .ml_literal_string => .string,
      .boolean           => .boolean,
      .array             => .array,
      .inline_table      => .table,
      .float             => .float,
      .integer           => .integer,
      .offset_date_time,
      .local_date_time,
      .local_date,
      .local_time        => .nanosec,
      else               => unreachable,
    };
  }
};

test "toml" {
  std.debug.print("\n", .{});
  const allocator = std.testing.allocator;
  const dir = std.fs.cwd();
  const name = "../../toml-test/valid/spec-example-1.toml";
  const file_text = try dir.readFileAlloc(allocator, name, std.math.maxInt(usize));
  defer allocator.free(file_text);
  const real_path = try dir.realpathAlloc(allocator, name);
  defer allocator.free(real_path);
  const root = try Toml.parse(.{
    .allocator = allocator,
    .file_path = real_path,
    .input = file_text,
  });
  defer root.deinit();
  std.debug.print("{}", .{root});
}

// fn testDir(dir: std.fs.Dir) !void {
//   var iter = dir.iterate();
//   while (try iter.next()) |item| switch (item.kind) {
//     .directory => {
//       var sub = try dir.openDir(item.name, .{.iterate = true});
//       defer sub.close();
//       try testDir(sub);
//     },
//     .file => {
//       if (!std.mem.endsWith(u8, item.name, ".toml")) continue;
//       try testFile(dir, item.name);
//     },
//     else => {},
//   };
// }

// fn testFile(dir: std.fs.Dir, name: []const u8) !void {
//   const result = try Parser.parse(.{
//     .allocator = allocator,
//     .file_path = real_path,
//     .input = file_text,
//     .keeps = &.{
//     },
//   });
//   defer result.root.deinit();
//   if (result.fail) |fail| {
//     no += 1;
//     std.debug.print("{}", .{fail});
//   } else {
//     ok += 1;
//   }
// }