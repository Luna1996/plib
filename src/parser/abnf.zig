//! https://www.rfc-editor.org/rfc/rfc5234#section-4

const std = @import("std");
const ast = @import("ast.zig");
const Syntax = @import("abnf.tmp.zig");

const Tag = Syntax.Tag;

pub const Rule = ast.Rule;
const Node = ast.Node;

const RuleSet = struct {
  names: std.ArrayList([]u8),
  rules: std.ArrayList(Rule),

  fn init(allocator: std.mem.Allocator) !RuleSet {
    return .{
      .names = std.ArrayList([]u8).init(allocator),
      .rules = std.ArrayList(Rule).init(allocator),
    };
  }

  fn deinit(self: @This(), allocator: std.mem.Allocator) void {
    for (self.names.items) |name| { allocator.free(name); }
    self.names.deinit();
    for (self.rules.items) |rule| { rule.deinit(allocator); }
    self.rules.deinit();
  }

  fn find(self: @This(), name: []const u8) ?usize {
    for (self.names.items, 0..) |item, i| {
      if (std.mem.eql(u8, name, item)) {
        return i;
      }
    }
    return null;
  }

  pub fn format(
    self: @This(),
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
  ) !void {
    _ = fmt;
    _ = options;
    try writer.writeAll("pub const Tag =enum{");
    for (self.names) |name| {
      try writer.print(".{s},", .{name});
    }
    try writer.writeAll("};");

    try writer.writeAll("pub const rules=&.{");
    for (self.rules) |rule| {
      try writer.print("{},", .{rule});
    }
    try writer.writeAll("}");
  }
};

const Builder = struct {
  pub const root: Tag = .rulelist;
  pub const ignore: []const Tag = &.{
    .c_wsp, .c_nl, .comment,
    .ALPHA, .BIT, .CHAR, .CR,
    .CRLF, .CTL, .DIGIT, .DQUOTE,
    .HEXDIG, .HTAB, .LF, .LWSP,
    .OCTET, .SP, .VCHAR, .WSP
  };

  pub fn build(node: Node(Tag), allocator: std.mem.Allocator) !RuleSet {
    var rule_set = try RuleSet.init(allocator, node.sub.items.len);
    for (node.sub.items) |item| {
      const rulename = item.sub.items[0].raw;
      const tagid = if (item.sub.items[1].raw.len == 1) {
        try rule_set.names.append(try allocator.dupe(u8, rulename));
        rule_set.names.items.len - 1;
      } else {
        rule_set.find(rulename).?;
      };
      _ = tagid;
    }
    return rule_set;
  }
};

pub const parser = ast.createParser(Syntax, Builder);

test {
  std.debug.print("\n", .{});
  try parser(@embedFile("abnf.txt"), std.testing.allocator);
}