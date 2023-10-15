//! https://www.rfc-editor.org/rfc/rfc5234#section-4

const std = @import("std");
const stdx = @import("../stdx.zig");
const parser = @import("../parser.zig");
const Syntax = @import("abnf.abnf.zig");

const Tag = Syntax.Tag;

const Node = parser.Node;

const Rule = union(enum) {
  alt: std.ArrayList(*Rule),
  con: std.ArrayList(*Rule),
  rep: struct {
    min: usize = 0,
    max: ?usize = null,
    sub: *Rule,
  },
  str: []u8,
  val: struct {
    min: u21,
    max: u21
  },
  jmp: usize,

  fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
    switch (self.*) {
      .alt, .con => |lst| {
        for (lst.items) |sub| { sub.deinit(allocator); }
        lst.deinit();
      },
      .rep => |rep| {
        rep.sub.deinit(allocator);
      },
      .str => |str| {
        allocator.free(str);
      },
      else => {},
    }
    allocator.destroy(self);
  }

  pub fn format(
    self: @This(),
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
  ) !void {
    try writer.print(".{{.{s}=", .{@tagName(self)});
    switch (self) {
      .alt, .con => |arr| {
        try writer.writeAll("&.{");
        for (arr.items) |sub| {
          try sub.*.format(fmt, options, writer);
          try writer.writeAll(",");
        }
        try writer.writeAll("}");
      },
      .rep => |rep| {
        try writer.writeAll(".{");
        if (rep.min != 0) {
          try writer.print(".min={d},", .{rep.min});
        }
        if (rep.max) |max| {
          try writer.print(".max={d},", .{max});
        }
        try writer.writeAll(".sub=&");
        try rep.sub.*.format(fmt, options, writer);
        try writer.writeAll("}");
      },
      .str => |str| {
        try stdx.printEscapedStringWithQuotes(str, writer);
      },
      .val => |val| {
        try writer.print(".{{.min={d},.max={d}}}", .{val.min, val.max});
      },
      .jmp => |jmp| {
        try writer.print("{d}", .{jmp});
      },
    }
    try writer.writeAll("}");
  }

  fn append(self: *@This(), rule: *Rule) !void {
    switch (self.*) {
      .alt, .con => |*lst| {
        if (std.meta.activeTag(self.*) == std.meta.activeTag(rule.*)) {
          const arr = switch (rule.*) {
            .alt, .con => |*arr| arr,
            else => unreachable,  
          };
          try lst.appendSlice(arr.items);
          arr.deinit();
          lst.allocator.destroy(rule);
        } else {
          try lst.append(rule);
        }
      },
      else => unreachable,
    }
  }
};

const RuleSet = struct {
  names: std.ArrayList([]u8),
  rules: std.ArrayList(*Rule),

  fn init(allocator: std.mem.Allocator) !RuleSet {
    return .{
      .names = std.ArrayList([]u8).init(allocator),
      .rules = std.ArrayList(*Rule).init(allocator),
    };
  }

  pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
    for (self.names.items) |name| { allocator.free(name); }
    self.names.deinit();
    for (self.rules.items) |*rule| { rule.*.deinit(allocator); }
    self.rules.deinit();
  }

  pub fn format(
    self: @This(),
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
  ) !void {
    _ = options;
    const pretty = comptime std.mem.eql(u8, "p", fmt);
    try writer.writeAll(
      if (pretty) "pub const Tag = enum {\n"
      else "pub const Tag=enum{"
    );

    for (self.names.items) |name| {
      try writer.print(
        if (pretty) "  {s},\n"
        else "{s},"
        , .{name}
      );
    }
    
    try writer.writeAll(
      if (pretty) "};\n\npub const rules = &.{\n"
      else "};pub const rules=&.{"
    );

    for (self.rules.items) |rule| {
      try writer.print(
        if (pretty) "  {p},\n"
        else "{},"
        , .{rule.*}
      );
    }
    try writer.writeAll("};");
  }
};

fn buildRule(
  allocator: std.mem.Allocator,
  name_map: std.StringHashMap(usize),
  text: []const u8,
  node: *Node(Tag),
  rule: *Rule,
) !void {
  const len = node.sub.items.len;
  switch (node.tag) {
    .alternation, .concatenation => {
      if (len == 1) {
        try buildRule(allocator, name_map, text, node.get(0), rule);
      } else {
        rule.* = switch (node.tag) {
          .alternation => .{.alt = std.ArrayList(*Rule).init(allocator)},
          .concatenation => .{.con = std.ArrayList(*Rule).init(allocator)},
          else => unreachable,
        };
        for (node.sub.items) |sub_node| {
          var sub_rule = try allocator.create(Rule);
          try buildRule(allocator, name_map, text, sub_node, sub_rule);
          try rule.append(sub_rule);
        }
      }
    },
    .repetition => {
      if (node.get(0).tag == .repeat) {
        rule.* = .{.rep = undefined};
        const rept = node.get(0).raw(text);
        if (std.mem.indexOfScalar(u8, rept, '*')) |star| {
          if (star != 0) {
            rule.rep.min = try std.fmt.parseUnsigned(usize, rept[0..star], 10);
          }
          if (star != rept.len - 1) {
            rule.rep.max = try std.fmt.parseUnsigned(usize, rept[star + 1..], 10);
          }
        } else {
          const n = try std.fmt.parseUnsigned(usize, rept, 10);
          rule.rep.min = n;
          rule.rep.max = n;
        }
        const next = try allocator.create(Rule);
        try buildRule(allocator, name_map, text, node.get(1), next);
        rule.rep.sub = next;
      } else {
        try buildRule(allocator, name_map, text, node.get(0), rule);
      }
    },
    .option => {
      const next = try allocator.create(Rule);
      try buildRule(allocator, name_map, text, node.get(0), next);
      rule.* = .{.rep = .{.max = 1, .sub = next}};
    },
    .char_val => {
      rule.* = .{.str = try allocator.dupe(u8, node.raw(text)[1..node.len-1])};
    },
    .bin_val, .dec_val, .hex_val => {
      const base: u8 = switch (node.tag) {
        .bin_val => 2,
        .dec_val => 10,
        .hex_val => 16,
        else => unreachable,
      };
      const raw = node.raw(text)[2..];
      if (std.mem.indexOfScalar(u8, raw, '-')) |hyphen| {
        rule.* = .{.val = .{
          .min = try std.fmt.parseUnsigned(u21, raw[0..hyphen], base),
          .max = try std.fmt.parseUnsigned(u21, raw[hyphen + 1..], base),
        }};
      } else {
        var buffer = std.ArrayList(u8).init(allocator);
        errdefer buffer.deinit();
        var iter = std.mem.tokenizeScalar(u8, raw, '.');
        var cp_buffer: [4]u8 = undefined;
        while (iter.next()) |token| {
          const cp = try std.fmt.parseUnsigned(u21, token, base);
          const cp_len = try std.unicode.utf8Encode(cp, &cp_buffer);
          try buffer.appendSlice(cp_buffer[0..cp_len]);
        }
        buffer.shrinkAndFree(buffer.items.len);
        rule.* = .{.str = buffer.items};
      }
    },
    .rulename => {
      rule.* = .{.jmp = name_map.get(node.raw(text)).?};
    },
    .prose_val => {
      rule.* = .{.jmp = name_map.get(node.raw(text)[1..node.len-1]).?};
    },
    else => unreachable,
  }
}

pub const Builder = struct {
  pub const root: Tag = .rulelist;
  pub const ignore: []const Tag = &.{
    .comment, .group,
    .empty_line, .empty,
    .alpha, .wsp, .crlf,
    .bit, .dec, .hex,
  };

  pub fn build(
    allocator: std.mem.Allocator,
    text: []const u8,
    node: *Node(Tag),
  ) !RuleSet {
    var rule_set = try RuleSet.init(allocator);
    
    var name_map = std.StringHashMap(usize).init(allocator);
    defer name_map.deinit();
    var node_map = std.ArrayList(*Node(Tag)).init(allocator);
    defer node_map.deinit();

    for (node.sub.items) |item| {
      const rulename = item.get(0).raw(text);
      if (name_map.get(rulename)) |i| {
        var last = node_map.items[i];
        var more = &item.get(2).sub;
        try last.sub.appendSlice(more.items);
        more.clearAndFree();
      } else {
        try name_map.putNoClobber(rulename, name_map.count());
        var dupe = try allocator.dupe(u8, rulename);
        std.mem.replaceScalar(u8, dupe, '-', '_');
        try rule_set.names.append(dupe);
        try node_map.append(item.get(2));
      }
    }
    
    for (node_map.items) |item| {
      const rule = try allocator.create(Rule);
      try buildRule(allocator, name_map, text, item, rule);
      try rule_set.rules.append(rule);
    }

    return rule_set;
  }
};

pub const parse = parser.createParser(Syntax, Builder);