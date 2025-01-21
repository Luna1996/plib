const std = @import("std");

pub const zeit = @import("zeit");

const plib = @import("plib");
const Parser = plib.Parser(@import("gen").abnf);
const Node = Parser.Node;

pub const Instant = @import("toml/time.zig");
const esc = @import("toml/escape.zig");

pub const Toml = union(enum) {
  string : []const u8,
  integer: i64,
  float  : f64,
  boolean: bool,
  instant: Instant,
  array  : Array,
  table  : Table,

  const Self = @This();
  
  const Tag = @as(type, std.meta.Tag(Self));

  const Array = std.ArrayListUnmanaged(Self);
  const Table = std.StringHashMapUnmanaged(Self);
  
  const Conf = struct {
    allocator: std.mem.Allocator,
    file_path: ?[]const u8 = null,
    input: []const u8,
    edit_inplace: bool = false,
  };

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
    errdefer result.root.deinit(conf.allocator);

    if (result.fail) |fail| {
      std.debug.print("{}", .{fail});
      return error.ParseError;
    } else {
      return result.root;
    }
  }

  pub fn build(conf: Conf) !Self {
    var root = try parse(conf);
    defer root.deinit(conf.allocator);
    return try buildToml(conf.allocator, &root);
  }

  pub fn init(comptime tag: Tag) Self {
    return switch (tag) {
      .string  => .{ .string  = ""          },
      .integer => .{ .integer = 0           },
      .float   => .{ .float   = 0           },
      .boolean => .{ .boolean = false       },
      .instant => .{ .instant = .{}         },
      .array   => .{ .array   = Array.empty },
      .table   => .{ .table   = Table.empty },
    };
  }

  pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    switch (self.*) {
      .string  => |string| allocator.free(string),
      .array   => |*array| deinitArray(array, allocator),
      .table   => |*table| deinitTable(table, allocator),
      else     => {},
    }
  }

  fn deinitArray(array: *Array, allocator: std.mem.Allocator) void {
    for (array.items) |*item|
      item.deinit(allocator);
    array.deinit(allocator);
  }

  fn deinitTable(table: *Table, allocator: std.mem.Allocator) void {
    var iterator = table.iterator();
    while (iterator.next()) |entry| {
      allocator.free(entry.key_ptr.*);
      entry.value_ptr.deinit(allocator);
    }
    table.deinit(allocator);
  }

  const BuildError = error {TomlError} 
    || std.mem.Allocator.Error
    || std.fmt.ParseIntError
    || std.fmt.ParseFloatError
    || error { Utf8CannotEncodeSurrogateHalf, CodepointTooLarge }
    || error { InvalidISO8601, UnhandledFormat };

  fn buildToml(allocator: std.mem.Allocator, node: *const Node) !Self {
    var root = init(.table);
    errdefer root.deinit(allocator);


    var   i     = @as(usize, 0);
    const items = node.val.sub.items;
    const len   = items.len;
    var   self  = &root;

    while (i < len) {
      const item = &items[i];
      switch (item.tag.?) {
        .key => { 
          try self.buildKeyVal(allocator, item, &items[i + 1]);
          i += 2;
        },
        .std_table => {
          self = try self.resolveTable(allocator, item);
          i += 1;
        },
        .array_table => {
          self = try self.resolveArray(allocator, item);
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
      try self.resolveMulByNode(allocator, key, .integer);
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
    return .{.string = if (need_free) str else try allocator.dupe(u8, str) };
  }

  fn buildInteger(node: *const Node) !Self {
    return .{.integer = try std.fmt.parseInt(i64, node.val.str, 0)};
  }
  
  fn buildFloat(node: *const Node) !Self {
    return .{.float = try std.fmt.parseFloat(f64, node.val.str)};
  }
  
  fn buildBoolean(node: *const Node) Self {
    return .{.boolean = std.mem.eql(u8, node.val.str, "true") };
  }
  
  fn buildInstant(node: *const Node) !Self {
    return .{.instant =
      if (node.tag.? == .local_time)
        try Instant.fromLocalTime (node.val.str)
      else
        try Instant.fromRFC3339   (node.val.str)
    };
  }
  
  fn buildArray(allocator: std.mem.Allocator, node: *const Node) !Self {
    var self = init(.array);
    errdefer self.deinit(allocator);
    for (node.val.sub.items) |*item| {
      var next = try buildVal(allocator, item);
      errdefer next.deinit(allocator);
      try self.array.append(allocator, next);
    }
    return self;
  }
  
  fn buildTable(allocator: std.mem.Allocator, node: *const Node) !Self {
    var self = init(.table);
    errdefer self.deinit(allocator);
    var i: usize = 0;
    const items = node.val.sub.items;
    const len = items.len;
    while (i < len) : (i += 2)
      try self.buildKeyVal(allocator, &items[i], &items[i + 1]);
    return self;
  }

  fn resolveTable(
    self: *Self,
    allocator: std.mem.Allocator,
    node: *const Node
  ) !*Self {
    const next, const found_existing =
      try self.resolveMulByNode(allocator, node.get(0), .table);
    return if (found_existing) error.TomlError else next;
  }

  fn resolveArray(
    self: *Self,
    allocator: std.mem.Allocator,
    node: *const Node
  ) !*Self {
    const next: *Self, _ = try self.resolveMulByNode(allocator, node.get(0), .array);
    const item = try next.array.addOne(allocator);
    item.* = init(.table);
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
      current_table, _ = try current_table.resolveOneByNode(allocator, key, .table);
    return try current_table.resolveOneByNode(allocator, &keys[len - 1], expect);
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
    res.value_ptr.* = init(expect);
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

  pub fn format(
    self: Self,
    comptime fmt: []const u8,
    _: std.fmt.FormatOptions,
    writer: anytype,
  ) !void {
    if (std.mem.eql(u8, fmt, "f")) {
      try self.formatFlat(writer);
    } else {
      var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
      defer _ = gpa.deinit();
      defer _ = gpa.detectLeaks();
      const allocator = gpa.allocator();
      var path = std.ArrayListUnmanaged([]const u8).empty;
      defer path.deinit(allocator);
      self.formatToml(allocator, path, writer);
    }
  }

  fn formatToml(
    self: Self,
    allocator: std.mem.Allocator,
    path: std.ArrayListUnmanaged([]const u8),
    writer: anytype,
  ) !void {
    var not_flat = std.ArrayListUnmanaged(Table.Entry).empty;
    defer not_flat.deinit(allocator);
    var iter = self.table.iterator();
    while (iter.next()) |entry| if (entry.value_ptr.isFlat()) {
      // try writer.print("{s}");
    } else {
      try not_flat.append(entry);
    };
  }

  fn formatFlat(self: Self, writer: anytype) !void {
    switch (self) {
      .string => |string| try writer.print("\"{}\"", .{ esc.escape(string) }),
      // TODO
    }
  }

  fn isFlat(self: Self) bool {
    return switch (self) {
      .string, .integer, .float, .boolean, .instant,
        => true,
      .array => |array| array: {
        for (array.items) |item|
          if (item.isFlat()) break :array true else continue;
        break :array false;
      },
      .table,
        => false,
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
  var toml = try Toml.build(.{
    .allocator = allocator,
    .file_path = real_path,
    .input = file_text,
  });
  defer toml.deinit(allocator);
  // std.debug.print("{}", .{root});
}