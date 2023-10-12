const std = @import("std");

pub fn initArgs(allocator: std.mem.Allocator, comptime Args: type, comptime conf: anytype) !Args {
  _ = conf;

  comptime var short_map = std.ComptimeStringMap([]const u8);
  _ = short_map;

  const raw_args = try std.process.argsAlloc(allocator);
  defer std.process.argsFree(raw_args);
  var named_raw_args = std.StringHashMap([]const u8).init(allocator);
  defer named_raw_args.deinit();
  var unnamed_raw_args = std.ArrayList([]const u8).init(allocator);
  defer unnamed_raw_args.deinit();
  for (raw_args) |raw_arg| {
    _ = raw_arg;
  }
}

pub fn freeArgs(allocator: std.mem.Allocator, args: anytype) void {
  _ = args;
  _ = allocator;
}

const ConfField = struct {
  alias: ?[]const u8 = null,
  desc: ?[]const u8 = null
};

fn Conf(comptime conf: anytype) type {
  comptime var alias_len = 0;
  comptime var desc_len = 0;
  
  inline for (std.meta.fieldNames(@TypeOf(conf))) |field_name| {
    const field: ConfField = @field(conf, field_name);
    if (field.alias != null) alias_len += 1;
    if (field.desc != null) desc_len += 1;
  }

  const KV = struct {[]const u8, []const u8};
  return struct {
    alias: [alias_len]KV,
    desc: [desc_len]KV,
  };
}

fn parseConf(comptime conf: anytype) Conf(conf) {
  comptime var res: Conf(conf) = undefined;
  comptime var alias_len = 0;
  comptime var desc_len = 0;
  
  inline for (std.meta.fieldNames(@TypeOf(conf))) |field_name| {
    const field: ConfField = @field(conf, field_name);
    if (field.alias) |alias| {
      res.alias[alias_len] = .{field_name, alias};
      alias_len += 1;
    }
    if (field.desc) |desc| {
      res.desc[desc_len] = .{field_name, desc};
      desc_len += 1;
    }
  }

  return res;
}