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

    pub fn get(self: @This(), i: usize) Node(Tag) {
      return self.sub.items[i];
    }

    pub fn format(
      self: @This(),
      comptime fmt: []const u8,
      options: std.fmt.FormatOptions,
      writer: anytype,
    ) !void {
      if (options.width != null) {
        try writer.writeByteNTimes(' ', options.width.?);
      }
      try writer.print("[{s}]", .{@tagName(self.tag)});
      if (self.sub.items.len == 0) {
        try std.json.encodeJsonString(self.raw, .{}, writer);
      }
      try writer.writeAll("\n");
      if (self.sub.items.len != 0) {
        var next_options = options;
        next_options.width = (next_options.width orelse 0) + 2;
        for (self.sub.items) |item| {
          try item.format(fmt, next_options, writer);
        }
      }
    }
  };
}

pub const ParseError = error {
  UnknownParseError,
} || std.mem.Allocator.Error;

fn Output(comptime Builder: type) type {
  const output_info = @typeInfo(@typeInfo(@TypeOf(Builder.build)).Fn.return_type.?).ErrorUnion;
  comptime var BuildError = output_info.error_set;
  comptime var OutputType = output_info.payload;
  return (ParseError||BuildError)!OutputType;
}

pub fn createParser(comptime Syntax: type, comptime Builder: type) fn([]const u8, std.mem.Allocator) Output(Builder) {
  const Tag = Syntax.Tag;
  
  const rules: []const Rule = Syntax.rules;
  
  const root = Builder.root;

  comptime var flag = [_]bool{true} ** std.meta.fields(Tag).len;
  for (Builder.ignore) |tag| { flag[@intFromEnum(tag)] = false; }
  
  const Clojure = struct {
    fn parse(
      text: []const u8,
      allocator: std.mem.Allocator,
    ) Output(Builder) {
      var node = Node(Tag){
        .tag = root,
        .raw = text[0..0],
        .sub = std.ArrayList(Node(Tag)).init(allocator),
      };
      defer node.deinit();
      try parseRule(text, &node, rules[@intFromEnum(root)]);
      return try Builder.build(allocator, node);
    }

    fn parseRule(
      text: []const u8,
      node: *Node(Tag),
      rule: Rule,
    ) ParseError!void {
      switch (rule) {
        .alt => |alt| {
          const len = node.raw.len;
          for (alt) |sub| {
            if (parseRule(text, node, sub)){
              return;
            } else |_| {
              node.raw.len = len;
              continue;
            }
          }
          return error.UnknownParseError;
        },
        .con => |con| {
          for (con) |sub| {
            try parseRule(text, node, sub);
          }
        },
        .rep => |rep| {
          var count: usize = 0;
          while (rep.max == null or count < rep.max.?) {
            parseRule(text, node, rep.sub.*) catch break;
            count += 1;
          }
          if (count < rep.min) return error.UnknownParseError; 
        },
        .str => |str| {
          if (std.mem.startsWith(u8, text[node.raw.len..], str)) {
            node.raw.len += str.len;
          } else {
            return error.UnknownParseError;
          }
        },
        .val => |val| {
          if (text.len <= node.raw.len) return error.UnknownParseError;
          const next = text[node.raw.len];
          if (val.min <= next and next <= val.max) {
            node.raw.len += 1;
          } else {
            return error.UnknownParseError;
          }
        },
        .jmp => |jmp| {
          if (flag[jmp]) {
            var next = Node(Tag){
              .tag = @enumFromInt(jmp),
              .raw = text[node.raw.len..node.raw.len],
              .sub = std.ArrayList(Node(Tag)).init(node.sub.allocator),
            };
            errdefer next.deinit();
            try parseRule(text[node.raw.len..], &next, rules[jmp]);
            try node.sub.append(next);
            node.raw.len += next.raw.len;
          } else {
            try parseRule(text, node, rules[jmp]);
          }
        },
      }
    }
  };

  return Clojure.parse;
}