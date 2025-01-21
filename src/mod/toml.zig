const std = @import("std");

const zeit = @import("zeit");

const plib = @import("plib");
const Parser = plib.Parser(@import("gen").abnf);
const Node = Parser.Node;

pub const Toml = union(enum) {
  string : []const u8,
  integer: i64,
  float  : f64,
  boolean: bool,
  time   : Time,
  array  : Array,
  table  : Table,

  const Self = @This();
  
  const Tag = std.meta.Tag(Self);

  pub const Time = struct {
    timestamp: i64 = 0,
    offset:    i64 = 0,

    pub fn fromZeit(time: zeit.Time) Time {
      const days = zeit.daysFromCivil(.{
        .year  = time.year ,
        .month = time.month,
        .day   = time.day  ,
      });
      return .{
        .timestamp =
          @as(i64,      days       ) * std.time.us_per_day +
          @as(i64, time.hour       ) * std.time.us_per_hour +
          @as(i64, time.minute     ) * std.time.us_per_min +
          @as(i64, time.second     ) * std.time.us_per_s +
          @as(i64, time.millisecond) * std.time.us_per_ms +
          @as(i64, time.microsecond) * std.time.us_per_us +
          @as(i64, time.nanosecond ),

        .offset = @as(i64, time.offset) * std.time.ns_per_day,
      };
    }
  };
  
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
  }

  pub fn init(comptime tag: Tag) Self {
    return switch (tag) {
      .string  => .{ .string  = ""          },
      .integer => .{ .integer = 0           },
      .float   => .{ .float   = 0           },
      .boolean => .{ .boolean = false       },
      .time    => .{ .time    = .{}         },
      .array   => .{ .array   = Array.empty },
      .table   => .{ .table   = Table.empty },
    };
  }

  pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    switch (self.*) {
      .string  => |string| allocator.free(string),
      .array   => |*array| deinitArray(array, allocator),
      .table   => |*table| deinitTable(table, allocator),
      else     =>          unreachable,
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

  fn buildToml(allocator: std.mem.Allocator, node: Node) !Self {
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

  fn buildVal(allocator: std.mem.Allocator, node: *const Node) !Self {
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
      else               =>     buildTime    (           node),
    };
  }

  fn buildString(allocator: std.mem.Allocator, node: *const Node) !Self {
    const str, const need_free = try dupeString(allocator, node);
    return .{.string = if (need_free) str else try allocator.dupe(str) };
  }

  fn buildInteger(node: *const Node) !Self {
    return .{.integer = try std.fmt.parseInt(i64, node.val.str, 0)};
  }
  
  fn buildFloat(node: *const Node) !Self {
    return .{.float = try std.fmt.parseFloat(f64, node.val.str, 0)};
  }
  
  fn buildBoolean(node: *const Node) Self {
    return .{.boolean = std.mem.eql(u8, node.val.str, "true") };
  }
  
  fn buildTime(node: *const Node) !Self {
    _ = node;
  }
  
  fn buildArray(allocator: std.mem.Allocator, node: *const Node) !Self {
    _ = allocator;
    _ = node;
  }
  
  fn buildTable(allocator: std.mem.Allocator, node: *const Node) !Self {
    _ = allocator;
    _ = node;
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
    if (len == 0) return self;
    var current_table = self;
    for (keys[0..len - 1]) |*key|
      current_table, _ = try current_table.resolveOneByNode(allocator, key, .table);
    return try current_table.resolveOneByNode(allocator, keys[len - 1], expect);
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
    if (!need_free) key = try allocator.dupe(key);
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
      .basic_string      => .{ try unescape(allocator, str[1..len - 1]), true  },
      .ml_basic_string   => .{ try unescape(allocator, str[3..len - 3]), true  },
      .literal_string    => .{                         str[1..len - 1] , false },
      .ml_literal_string => .{                         str[3..len - 3] , false },
      else => unreachable,
    };
  }

  fn unescape(allocator: std.mem.Allocator, str: []const u8) ![]u8 {
    var res = try allocator.alloc(u8, str.len);
    errdefer allocator.free(res);
    var i: usize = 0;
    var j: usize = 0;
    while (i < str.len) {
      const c1 = str[i];
      if (c1 != '\\') 
                { res[j] = c1  ; i += 1; j += 1; continue; }
      const c2 = str[i + 1]; switch (c2) {
        0x22 => { res[j] = 0x22; i += 2; j += 1; },
        0x5C => { res[j] = 0x5C; i += 2; j += 1; },
        0x62 => { res[j] = 0x08; i += 2; j += 1; },
        0x65 => { res[j] = 0x1B; i += 2; j += 1; },
        0x66 => { res[j] = 0x0C; i += 2; j += 1; },
        0x6E => { res[j] = 0x0A; i += 2; j += 1; },
        0x72 => { res[j] = 0x0D; i += 2; j += 1; },
        0x74 => { res[j] = 0x09; i += 2; j += 1; },
        else => {
          const n = switch (c2) { 0x78 => 2, 0x75 => 4, 0x55 => 8 };
          const u = try std.fmt.parseUnsigned(u21, str[i + 2..][0..n], 16);
          i += 2 + n;
          j += try std.unicode.utf8Encode(u, res[j..][0..4]);
        }
      }
    }
    return try allocator.realloc(res, j);
  }
};

test "toml" {
  std.debug.print("\n", .{});
  std.debug.print("{d}\n", .{@sizeOf(Toml)});
  const allocator = std.testing.allocator;
  const dir = std.fs.cwd();
  const name = "../../toml-test/valid/spec-example-1.toml";
  const file_text = try dir.readFileAlloc(allocator, name, std.math.maxInt(usize));
  defer allocator.free(file_text);
  const real_path = try dir.realpathAlloc(allocator, name);
  defer allocator.free(real_path);
  var root = try Toml.parse(.{
    .allocator = allocator,
    .file_path = real_path,
    .input = file_text,
  });
  defer root.deinit(allocator);
  std.debug.print("{}", .{root});
}