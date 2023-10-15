const std = @import("std");

const StringList = std.ArrayList([]const u8);

const ArgParseError = error {
  IllFormed,
  UnknownArgName,
  ValParseError,
  RedundantArg,
  MissingRequiredArg,
  UnusedUnnamedArg,
};

pub fn Args(comptime T: type, comptime conf: Conf(T)) type {
  return struct {
    arena: std.heap.ArenaAllocator,
    args: T,

    pub fn init(allocator: std.mem.Allocator) !@This() {
      var a1 = std.heap.ArenaAllocator.init(allocator);
      defer a1.deinit();
      var a2 = std.heap.ArenaAllocator.init(allocator);
      errdefer a2.deinit();
      
      const raw_args = (try std.process.argsAlloc(a2.allocator()))[1..];

      if (raw_args.len == 1 and (std.mem.eql(u8, raw_args[0], "--help") or std.mem.eql(u8, raw_args[0], "-h"))) {
        printHelp();
        std.process.exit(0);
      }

      var named = std.StringHashMap(StringList).init(a1.allocator());
      var unnamed = StringList.init(a1.allocator());
      for (raw_args) |raw_arg| {
        if (raw_arg.len == 0) continue;
        switch(raw_arg[0]) {
          '-' => {
            const sep = std.mem.indexOfScalar(u8, raw_arg, '=') orelse raw_arg.len;
            if (raw_arg[sep - 1] == '-' or sep == raw_arg.len - 1) {
              std.debug.print("\"{s}\" is ill formed.\n", .{raw_arg});
              printHelp();
              return ArgParseError.IllFormed;
            }
            const res = try named.getOrPut(try getFieldName(raw_arg[0..sep]));
            if (!res.found_existing) {
              res.value_ptr.* = StringList.init(a1.allocator());
            }
            if (sep < raw_arg.len - 1) {
              const d: u1 = switch (raw_arg[sep + 1]) {'"', '\'' => 1, else => 0};
              try res.value_ptr.append(raw_arg[sep + 1 + d..raw_arg.len - d]);
            }
          },
          else => try unnamed.append(raw_arg),
        }
      }

      var args: T = undefined;

      comptime var hasUnnamed = false;

      inline for (std.meta.fields(T)) |field| {
        const field_type = comptime field.type;
        const field_name = comptime field.name;
        const has_default = comptime field.default_value != null;
        const is_optional = comptime std.meta.trait.is(.Optional)(field_type);
        const is_required = comptime !has_default and !is_optional;
        
        if (has_default) {
          @field(args, field_name) = field.default_value;
        } else if (is_optional) {
          @field(args, field_name) = null;
        }

        const info: Info = @field(conf, field_name);

        if (info.is_unnamed) {
          if (hasUnnamed) {
            @compileError("Conf can only have at most one is_unnamed set.\n");
          }
          hasUnnamed = true;
          if (unnamed.items.len == 0 and is_required) {
            std.debug.print("Missing required unnamed arg of type <{s}>.\n", .{@typeName(field_type)});
            printHelp();
            return ArgParseError.MissingRequiredArg;
          }
          @field(args, field_name) = try parseAll(field_type, unnamed.items, a2.allocator());
        } else if (named.get(field_name)) |strs| {
          @field(args, field_name) = try parseAll(field_type, strs.items, a2.allocator());
        } else if (is_required) {
          std.debug.print("Missing required arg \"{s}\" of type <{s}>.\n", .{@typeName(field_type)});
          printHelp();
          return ArgParseError.MissingRequiredArg;
        }
      }

      if (!hasUnnamed and unnamed.items.len != 0) {
        std.debug.print("Unnamed arg \"{s}\" is unused.\n", .{unnamed.items[0]});
        printHelp();
        return ArgParseError.UnusedUnnamedArg;
      }

      return .{.arena = a2, .args = args};
    }

    pub fn deinit(self: @This()) void {
      self.arena.deinit();
    }

    fn parseAll(comptime V: type, strs: []const []const u8, allocator: std.mem.Allocator) !V {
      switch (@typeInfo(V)) {
        .Pointer => |info| if (V != []const u8) {
          if (info.size != .Slice || !info.is_const || info.is_volatile || (info.sentinel != null)) {
            @compileError("Unsupported arg type: <" ++ @typeName(V) ++ ">.\n");
          }
          var vals = try allocator.alloc(info.child, strs.len);
          for (vals, strs) |*val, str| {
            val.* = try parseOne(info.child, str);
          }
          return vals;
        },
        .Bool => if (strs.len == 0) {
          return true;
        },
        else => {},
      }
      if (strs.len == 0) {
        printHelp();
        return ArgParseError.IllFormed;
      } else if (strs.len > 1) {
        printHelp();
        return ArgParseError.RedundantArg;
      }
      return try parseOne(V, strs[0]);
    }

    fn parseOne(comptime V: type, str: []const u8) !V {
      if (V == []const u8) return str;
      errdefer {
        std.debug.print("Expect a <{s}> value, but got \"{s}\".\n", .{@typeName(V), str});
        printHelp();
      }
      return switch (@typeInfo(V)) {
        .Bool =>
          if (std.mem.eql(u8, str, "true")) true 
          else if (std.mem.eql(u8, str, "false")) false
          else ArgParseError.ValParseError,
        .Int =>
          std.fmt.parseInt(V, str, 0)
          catch ArgParseError.ValParseError,
        .Float =>
          std.fmt.parseFloat(V, str)
          catch ArgParseError.ValParseError,
        .Enum =>
          std.meta.stringToEnum(str)
          orelse ArgParseError.ValParseError,
        .Optional => |info|
          if (std.mem.eql(u8, str, "null")) null
          else try parseOne(info.child, str),
        else => @compileError("Unsupported arg type: <" ++ @typeName(V) ++ ">.\n"),
      };
    }

    fn getFieldName(str: []const u8) ![]const u8 {
      inline for (comptime std.meta.fieldNames(T)) |field_name| {
        const info: Info = @field(conf, field_name);
        if (info.is_unnamed) continue;
        if (str[1] != '-') {
          if (info.alias) |alias| {
            if (std.mem.eql(u8, alias, str[1..])) {
              return field_name;
            }
          }
        } else if (std.mem.eql(u8, info.label orelse field_name, str[2..])) {
          return field_name;
        }
      }
      std.debug.print("Unknown arg name: \"{s}\"\n", .{if (str[1] == '-') str[2..] else str[1..]});
      printHelp();
      return ArgParseError.UnknownArgName;
    }

    fn printHelp() void {
      std.debug.print("Usage: (required args maked with star)\n  --help, -h, show this help.\n", .{});
      inline for (std.meta.fields(T)) |field| {
        const field_type = comptime field.type;
        const field_name = comptime field.name;
        const has_default = comptime field.default_value != null;
        const is_optional = comptime std.meta.trait.is(.Optional)(field_type);
        const is_required = comptime !has_default and !is_optional;
        
        const info: Info = @field(conf, field_name);
        std.debug.print("{c} --{s}, ", .{ if (is_required) '*' else ' ', info.label orelse field_name});
        if (info.alias) |alias| {
          std.debug.print("-{s}, ", .{alias});
        }
        std.debug.print("[{s}], {s}.\n", .{ @typeName(field_type), info.desc});
      }
    }
  };
}

fn Conf(comptime T: type) type {
  comptime if (std.meta.activeTag(@typeInfo(T)) != .Struct) {
    @compileError("Args only be struct type but got <" ++ @typeName(T) ++ ">.\n");
  };
  const field_names = std.meta.fieldNames(T);
  comptime var fields: [field_names.len]std.builtin.Type.StructField = undefined;
  for (&fields, field_names) |*field, name| {
    field.* = .{
      .name = name,
      .type = Info,
      .default_value = null, 
      .is_comptime = false,
      .alignment = 0,
    };
  }
  return @Type(.{.Struct = .{
    .layout = .Auto,
    .fields = &fields,
    .decls = &.{},
    .is_tuple = false,
  }});
}

const Info = struct {
  label: ?[]const u8 = null,
  alias: ?[]const u8 = null,
  desc: []const u8,
  is_unnamed: bool = false,
};

test {
  std.debug.print("\n", .{});
  const args = try Args(
    struct {
      input: []const u8,
      output: ?[]const u8,
      output_ast: ?[]const u8,
    },
    .{
      .input = .{.is_unnamed = true, .desc = "the path of input abnf file"},
      .output = .{.alias = "o", .desc = "the path for output zig file"},
      .output_ast = .{.alias = "a", .desc = "dump ast tree to the file if set"},
    },
  ).init(std.testing.allocator);
  _ = args;
}