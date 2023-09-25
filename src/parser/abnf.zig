const std = @import("std");

pub const Rule = union(enum) {
  alt: []const Rule,
  con: []const Rule,
  rep: struct {
    min: usize = 0,
    max: ?usize = null,
    sub: *const Rule,
  },
  str: []const u8,
  val: struct {
    min: u8,
    max: u8
  },
  jmp: usize,
};

pub fn Node(comptime Tag: type) type {
  return struct {
    tag: Tag,
    raw: []const u8,
    sub: std.ArrayList(Node(Tag)),

    pub fn deinit(self: @This()) void {
      for (self.sub.items) |item| { item.deinit(); }
      self.sub.deinit();
    }
  };
}

pub fn Parser(comptime Gen: type) type {
  const Tag = Gen.Tag;
  const rules: []const Rule = Gen.rules;
  return struct {
    pub fn parse(
      text: []const u8,
      allocator: std.mem.Allocator,
      root: Tag,
      flat: []const Tag,
    ) !Node(Tag) {
      var node = Node(Tag){
        .tag = root,
        .raw = undefined,
        .sub = std.ArrayList(Node(Tag)).init(allocator),
      };
      errdefer node.deinit();
      var flag = [_]bool{true} ** std.meta.fields(Tag).len;
      for (flat) |tag| { flag[@intFromEnum(tag)] = false; }
      try parseRule(text, node, rules[@intFromEnum(root)], &flag);
      return node;
    }

    fn parseRule(
      text: []const u8,
      node: *Node(Tag),
      rule: Rule,
      flag: []const bool,
    ) !void {
      var i = 0;
      switch (rule) {
        .alt => |_| {},
        .con => |_| {},
        .rep => |_| {},
        .str => |_| {},
        .val => |_| {},
        .jmp => |jmp| {
          if (flag[jmp]) {
            var next = Node(Tag){
              .tag = @enumFromInt(jmp),
              .raw = undefined,
              .sub = std.ArrayList(Node(Tag)).init(node.sub.allocator),
            };
            errdefer next.deinit();
            try parseRule(text[i..], next, rules[jmp], flag);
            
          } else {
          }
        },
      }
      node.raw = text[0..i];
    }
  };
}

test Rule {
  const r: []const Rule = @import("abnf.tmp.zig").rule_set;
  std.debug.print("\n{any}\n", .{r});
}