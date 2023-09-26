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

  pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
    switch (self) {
      .alt, .con => |lst| {
        for (lst) |sub| { sub.deinit(allocator); }
        allocator.free(lst);
      },
      .rep => |rep| {
        rep.sub.deinit(allocator);
        allocator.destroy(rep.sub);
      },
      .str => |str| {
        allocator.free(str);
      },
      else => {},
    }
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
        for (arr) |sub| {
          try format(sub, fmt, options, writer);
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
        try format(rep.sub.*, fmt, options, writer);
        try writer.writeAll("}");
      },
      .str => |str| {
        try std.json.encodeJsonString(str, .{}, writer);
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
      return try Builder.build(node, allocator);
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