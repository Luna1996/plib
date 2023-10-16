const std = @import("std");
const stdx = @import("stdx.zig");

const Rule = union(enum) {
  alt: []const Rule,
  con: []const Rule,
  rep: struct {
    min: usize = 0,
    max: ?usize = null,
    sub: *const Rule,
  },
  str: []const u8,
  val: struct {
    min: u21,
    max: u21,
  },
  jmp: usize,
};

pub fn Node(comptime Tag: type) type {
  return struct {
    const Self = @This();

    tag: Tag,
    pos: usize, len: usize,
    sub: std.ArrayList(*Self),

    fn create(allocator: std.mem.Allocator, tag: Tag, pos: usize) !*Self {
      var node = try allocator.create(Self);
      node.tag = tag;
      node.pos = pos;
      node.len = 0;
      node.sub = std.ArrayList(*Self).init(allocator);
      return node;
    }

    pub fn destroy(self: *const Self) void {
      const allocator = self.sub.allocator;
      for (self.sub.items) |sub| sub.destroy();
      self.sub.deinit();
      allocator.destroy(self);
    }

    pub fn get(self: *const Self, i: usize) *Self {
      return self.sub.items[i];
    }

    pub fn raw(self: *const Self, text: []const u8) []const u8 {
      return text[self.pos..self.pos + self.len];
    }

    fn restor(self: *Self, i: usize, j: usize) void {
      self.len = i;
      for (self.sub.items[j..]) |sub| {
        sub.destroy();
      }
      self.sub.items.len = j;
    }

    pub fn print(
      self: *const Self,
      text: []const u8,
      indent: usize,
      writer: anytype,
    ) !void {
      try writer.writeByteNTimes(' ', indent);
      try writer.writeAll("[");
      try writer.writeAll(@tagName(self.tag));
      try writer.writeAll("]");
      if (self.sub.items.len == 0) {
        try stdx.printEscapedStringWithQuotes(self.raw(text), writer);
      }
      try writer.writeAll("\n");
      if (self.sub.items.len != 0) {
        for (self.sub.items) |item| {
          try item.print(text, indent + 2, writer);
        }
      }
    }
  };
}

pub const ParseError = struct {
  const Self = @This();
  const Record = struct{
    tag: []const u8,
    rule: Rule,
  };

  pos: usize,
  records: std.ArrayList(Rule),

  fn init(allocator: std.mem.Allocator) Self {
    return .{.pos = 0, .records = std.ArrayList(Record).init(allocator)};
  }

  fn deinit(self: *Self) void {
    self.records.deinit();
  }

  fn put(self: *Self, pos: usize, tag: []const u8, rule: Rule) !void {
    if (pos < self.pos) return;
    if (pos > self.pos) {
      try self.records.resize(0);
      self.pos = pos;
    }
    try self.records.append(.{.tag = tag, .rule = rule});
  }

  fn print(
    self: *const Self,
    input: Input,
    writer: anytype,
  ) !void {
    if (self.records.items.len == 0) return;
    const path = input.path orelse "(unknown)";
    var line = std.mem.count(u8, input.text[0..self.pos], "\n") + 1;
    var line_start = if (std.mem.lastIndexOfScalar(u8, input.text[0..self.pos], '\n')) |start| start + 1 else 0;
    var line_end = std.mem.indexOfScalarPos(u8, input.text, self.pos, '\n') orelse input.text.len;
    try writer.print("Encounter ParseError!\n{s}:{d}:{d}\n{s}\n", .{
      path, line, self.pos - line_start + 1,
      input.text[line_start..line_end],
    });
    try writer.writeByteNTimes(' ', self.pos - line_start);
    try writer.writeAll("^\n");
    for (self.records.items) |item| {
      try writer.print("  <{s}> expecting ", .{item.tag});
      switch (item.rule) {
        .str => |str| {
          try stdx.printEscapedStringWithQuotes(str, writer);
        },
        .val => |val| {
          try writer.print("0x{X}-{X}", .{val.min, val.max});
        },
        else => unreachable,
      }
      try writer.writeAll(";\n");
    }
  }
};

pub const Input = struct {
  path: ?[]const u8,
  text: []const u8,
};

fn Output(comptime Builder: type) type {
  const output_info = @typeInfo(@typeInfo(@TypeOf(Builder.build)).Fn.return_type.?).ErrorUnion;
  comptime var BuildError = output_info.error_set;
  comptime var OutputType = output_info.payload;
  return (error {ParseError} || std.mem.Allocator.Error || BuildError)!OutputType;
}

pub fn createParser(comptime Syntax: type, comptime Builder: type) fn(std.mem.Allocator, Input, ?std.fs.File) Output(Builder) {
  const Tag = Syntax.Tag;
  
  const rules: []const Rule = Syntax.rules;
  
  const root: Tag = if (@hasDecl(Builder, "root")) Builder.root else @enumFromInt(0);

  comptime var flag = [_]bool{true} ** std.meta.fields(Tag).len;
  if (@hasDecl(Builder, "ignore")) {
    for (Builder.ignore) |tag| {
      flag[@intFromEnum(tag)] = false;
    }
  }

  const Clojure = struct {
    fn parse(
      allocator: std.mem.Allocator,
      input: Input,
      output: ?std.fs.File,
    ) Output(Builder) {
      const node = try Node(Tag).create(allocator, root, 0);
      defer node.destroy();

      var errs = ParseError.init(allocator);
      defer errs.deinit();

      parseRule(root, input.text, node, &rules[@intFromEnum(root)], &errs) catch |err| {
        if (err == error.ParseError) {
          errs.print(input, std.io.getStdOut().writer()) catch {};
        }
        return err;
      };
      if (node.len != input.text.len) {
        errs.print(input, std.io.getStdOut().writer()) catch {};
        return error.ParseError;
      }

      if (output) |file| {
        node.print(input.text, 0, file.writer()) catch {};
      }
      
      return try Builder.build(allocator, input.text, node);
    }

    fn parseRule(
      tag: Tag,
      text: []const u8,
      node: *Node(Tag),
      rule: *const Rule,
      errs: *ParseError,
    ) !void {
      switch (rule.*) {
        .alt => |alt| {
          const i = node.len;
          const j = node.sub.items.len;
          for (alt) |sub| {
            if (parseRule(tag, text, node, &sub, errs)) {
              return;
            } else |_| {
              node.restor(i, j);
            }
          }
          return error.ParseError;
        },
        .con => |con| {
          for (con) |sub| {
            try parseRule(tag, text, node, &sub, errs);
          }
        },
        .rep => |rep| {
          var count: usize = 0;
          while ((rep.max == null or count < rep.max.?) and node.pos + node.len < text.len) {
            const i = node.len;
            const j = node.sub.items.len;
            if (parseRule(tag, text, node, rep.sub, errs)) {
              count += 1;
            } else |_| {
              node.restor(i, j);
              break;
            }
          }
          if (count < rep.min) {
            return error.ParseError;
          }
        },
        .str => |str| {
          const pos = node.pos + node.len;
          if (std.mem.startsWith(u8, text[pos..], str)) {
            node.len += str.len;
          } else {
            try errs.put(pos, @tagName(tag), rule.*);
            return error.ParseError;
          }
        },
        .val => |val| {
          const pos = node.pos + node.len;
          if (text.len <= pos) {
            try errs.put(pos, @tagName(tag), rule.*);
            return error.ParseError;
          }
          var iter = std.unicode.Utf8Iterator{.bytes = text[pos..], .i = 0};
          const next_char = iter.nextCodepoint() orelse {
            try errs.put(pos, @tagName(tag), rule.*);
            return error.ParseError;
          };
          if (val.min <= next_char and next_char <= val.max) {
            node.len += iter.i;
          } else {
            try errs.put(pos, @tagName(tag), rule.*);
            return error.ParseError;
          }
        },
        .jmp => |jmp| {
          if (flag[jmp]) {
            const new_tag = @as(Tag, @enumFromInt(jmp));
            var new_node = try Node(Tag).create(node.sub.allocator, new_tag, node.pos + node.len);
            errdefer new_node.destroy();
            try parseRule(new_tag, text, new_node, &rules[jmp], errs);
            try node.sub.append(new_node);
            node.len += new_node.len;
          } else {
            try parseRule(tag, text, node, &rules[jmp], errs);
          }
        },
      }
    }
  };

  return Clojure.parse;
}