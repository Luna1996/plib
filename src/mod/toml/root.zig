const std = @import("std");

pub const Toml = union(enum) {
  string  : []const u8,
  integer : i64,
  float   : f64,
  boolean : bool,
  datetime: DateTime,
  array   : Array,
  table   : Table,

  const Self = @This();
  
  pub const Parser = @import("plib").Parser(@import("gen").abnf);
  pub const Ast = Parser.Ast;

  pub const Tag = @as(type, std.meta.Tag(Self));

  pub const DateTime = @import("datetime.zig").DateTime;
  pub const Array = std.ArrayListUnmanaged(Self);
  pub const Table = std.StringHashMapUnmanaged(Self);
  
  pub usingnamespace @import("core.zig");
  pub usingnamespace @import("formatter_flat.zig");
  pub usingnamespace @import("formatter_json.zig");
  pub usingnamespace @import("json_to_toml.zig");
};

test "toml" {
  std.debug.print("\n", .{});
  const allocator = std.testing.allocator;
  const file_text =
    \\#Useless spaces eliminated.
    \\title="TOML Example"
    \\[owner]
    \\name="Lance Uppercut"
    \\dob=1979-05-27T07:32:00-08:00#First class dates
    \\[database]
    \\server="192.168.1.1"
    \\ports=[8001,8001,8002]
    \\connection_max=5000
    \\enabled=true
    \\[servers]
    \\[servers.alpha]
    \\ip="10.0.0.1"
    \\dc="eqdc10"
    \\[servers.beta]
    \\ip="10.0.0.2"
    \\dc="eqdc10"
    \\[clients]
    \\data=[["gamma","delta"],[1,2]]
    \\hosts=[
    \\"alpha",
    \\"omega"
    \\]
  ;
  const spec = try Toml.parse(struct {
    const IP = struct {
      ip: [4]u8,

      pub fn fromToml(_: Toml.Conf, toml: Toml) @import("toml_to_any.zig").Error!IP {
        std.debug.print("yeah!{f}\n", .{toml});
        return .{.ip = .{1, 2, 3, 4}};
      }
    };
    const Client = union(enum) {
      str: [2][]const u8,
      int: @Vector(2, u32),
    };
    title: []const u8,
    owner: struct {
      name: []const u8,
      dob: Toml.DateTime,
    },
    database: struct {
      server: IP,
      ports: []const u32,
      connection_max: u32,
      enabled: bool,
    },
    servers: std.StringHashMapUnmanaged(struct {
      ip: IP,
      dc: []const u8,
    }),
    clients: struct {
      data: std.ArrayList(Client),
      hosts: Client,
    },
  }, .{
    .allocator = allocator,
    .input = file_text,
  });
  defer @import("plib").deinit(spec, allocator);
  var iter = spec.servers.iterator();
  while (iter.next()) |entry| {
    @import("plib").deinit(entry.key_ptr.*, allocator);
    @import("plib").deinit(entry.value_ptr.*, allocator);
  }
  for (spec.clients.data.items) |item|
    @import("plib").deinit(item, allocator);
  std.debug.print("{}", .{spec});
}