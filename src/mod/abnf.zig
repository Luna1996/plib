const std = @import("std");
const abnf = @import("gen.abnf").abnf;
const plib = @import("plib");
const Rule = plib.Rule;
const Parser = plib.Parser(abnf);
const Tag = Parser.Tag;
const Node = Parser.Node;

pub const ABNF = struct {
  const Self = @This();

  names: []const [:0]const u8,
  rules: []const Rule,

  pub fn parse(conf: struct {
    allocator: std.mem.Allocator,
    file_path: ?[]const u8 = null,
    input: []const u8,
  }) !ABNF {
    var result = try Parser.parse(.{
      .allocator = conf.allocator,
      .input = conf.input,
      .keeps = &.{
        .rulelist, .rule, .rulename, .defined_as,
        .alternation, .concatenation, .repetition, .option,
        .repeat, .char_val, .bin_val, .dec_val, .hex_val,
      },
      .file_path = conf.file_path,
    });
    defer result.root.deinit();
    if (result.fail) |fail| {
      std.debug.print("{}", .{fail});
    } else {
      std.debug.print("{}", .{result.root});
    }
    return undefined;
  }


};

const ParseContex = struct {
  allocator: std.mem.Allocator,
  names_map: std.StringHashMapUnmanaged(usize),
};

pub fn main() !void {}