const std = @import("std");
const plib = @import("plib");
const Parser = plib.Parser(@import("gen").abnf);
const Tag = Parser.Tag;
const Node = Parser.Node;
const Array = std.ArrayList;
const Table = std.StringHashMap;

pub const Toml = struct {
  pub const Value = union(enum) {
    string: []const u8,
    boolean: bool,
    array: Array(Value),
    table: Table(Value),
    date_time: usize,
    float: f64,
    integer: i64,
  };

  allocator: std.mem.Allocator,
  root: Value,

  const Self = @This();

  const Conf = struct {
    allocator: std.mem.Allocator,
    file_path: ?[]const u8 = null,
    input: []const u8,
  };

  pub fn build(conf: Conf) !Self {
    const root = try parse(conf);
    defer root.deinit();

    const self = Self {
      .allocator = conf.allocator,
      .root = Table(Value).init(conf.allocator),
    };
    errdefer self.deinit();
  }

  pub fn parse(conf: Conf) !Node {
    var result = try Parser.parse(.{
      .allocator = conf.allocator,
      .input = conf.input,
      .keeps = &.{
        .toml, .key, .std_table, .array_table,
        .string, .boolean, .array, .inline_table, .date_time, .float, .integer,
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

  fn deinitValue(self: Self, value: Value) void {
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
      else => {},
    }
  }

  // fn buildToml(self: Self, root: Node) !void {}
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