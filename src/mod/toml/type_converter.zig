const Self = @This();

const std = @import("std");

const esc = @import("escape.zig");
const Toml = @import("root.zig").Toml;
const DateTime = @import("datetime.zig").DateTime;

pub const Error = error { TomlError } || std.mem.Allocator.Error;

pub const Conf = struct {
  allocator: std.mem.Allocator,
  log_error: bool = false,
};

pub fn BuildFn(comptime T: type) type {
  return fn (Conf, Toml) Error!T;
}

// pub fn build(comptime T: type, conf: Conf, toml: Toml) Error!T {
//   return try getBuildFn(T)(conf, toml);
// }

// fn getBuildFn(comptime T: type) BuildFn(T) {
//   if (T == Toml) return buildToml;
//   switch (@typeInfo(T)) {
//     .int => {},
//     .float => {},
//     .pointer => {},
//     .array => {},
//     .@"struct" => {},
//     .optional => {},
//     .@"enum" => {},
//     .@"union" => {},
//   }
// }

// fn buildToml(_: Conf, toml: Toml) Error!Toml {
//   return toml;
// }