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

  pub const Error = error { TomlError } || std.mem.Allocator.Error;
  
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
    const IP = []const u8;
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
  defer Toml.deinitAny(spec, allocator);
  var toml = try Toml.fromAny(spec, allocator);
  defer toml.deinit(allocator);
}

test "toml.size" {
  std.debug.assert(@sizeOf(Toml) == 32);
}