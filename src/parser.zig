const std = @import("std");
const stdx = @import("../stdx.zig");

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
    min: u8,
    max: u8
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
      var node = try allocator.create(usize);
      node.tag = tag;
      node.pos = pos;
      node.len = 0;
      node.sub = std.ArrayList(*Self).init(allocator);
      return node;
    }

    pub fn destroy(self: *const Self, allocator: std.mem.Allocator) void {
      for (self.sub.items) |sub| sub.destroy(allocator);
      self.sub.deinit();
      allocator.destroy(self);
    }

    pub fn get(self: *const Self, i: usize) *Self {
      return self.sub.items[i];
    }

    pub fn raw(self: *const Self, text: []const u8) []const u8 {
      return text[self.pos..self.pos + self.len];
    }

    fn restor(self: *Self, allocator: std.mem.Allocator,  i: usize, j: usize) void {
      self.len = i;
      for (self.sub.items[j..]) |sub| {
        sub.destroy(allocator);
      }
      self.sub.shrinkAndFree(j);
    }

    pub fn format(
      self: *const Self,
      comptime fmt: []const u8,
      options: std.fmt.FormatOptions,
      writer: anytype,
    ) !void {
      if (options.width != null) {
        try writer.writeByteNTimes(' ', options.width.?);
      }
      try writer.print("[{s}]", .{@tagName(self.tag)});
      if (self.sub.items.len == 0) {
        try stdx.printEscapedStringWithQuotes(self.raw, writer);
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

fn ParseError(comptime Tag: type) type {
  return struct {
    const Self = @This();
    const Record = struct{
      tag: Tag,
      rule: *const Rule,
    };
    const RecordList = std.ArrayList(Record);
    const RecordMap = std.HashMap(RecordList);

    text: []const u8,
    records: RecordMap,

    fn init(allocator: std.mem.Allocator) Self {
      return .{.records = RecordMap.init(allocator)};
    }

    fn deinit(self: *const Self) void {
      var iter = self.records.valueIterator();
      while (iter.next()) |item| {
        item.deinit();
      }
      self.records.deinit();
    }

    fn reset(self: *Self) void {
      var iter = self.records.valueIterator();
      while (iter.next()) |item| {
        item.deinit();
      }
      self.records.clearRetainingCapacity();
    }

    fn put(self: *Self, pos: usize, tag: Tag, rule: *const Rule) !void {
      var res = try self.records.getOrPut(pos);
      if (!res.found_existing) {
        res.value_ptr.* = RecordList.init(self.records.allocator);
      }
      try res.value_ptr.append(.{.tag = tag, .rule = rule});
    }

    pub fn format(
      self: *const Self,
      comptime fmt: []const u8,
      options: std.fmt.FormatOptions,
      writer: anytype,
    ) !void {
      _ = writer;
      _ = options;
      _ = fmt;
      var iter = self.records.keyIterator();
      _ = iter;
    }
  };
}

fn Output(comptime Builder: type) type {
  const output_info = @typeInfo(@typeInfo(@TypeOf(Builder.build)).Fn.return_type.?).ErrorUnion;
  comptime var BuildError = output_info.error_set;
  comptime var OutputType = output_info.payload;
  return (error.ParseError || std.mem.Allocator.Error || BuildError)!OutputType;
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
      const node = try Node(Tag).create(allocator, root, 0);
      errdefer node.deinit();

      var errs = ParseError.init(allocator);
      defer errs.deinit();

      try parseRule(allocator, node, &rules[@intFromEnum(root)], &errs);
      
      return try Builder.build(allocator, text, node);
    }

    fn parseRule(
      allocator: std.mem.Allocator,
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
            if (parseRule(allocator, tag, text, node, &sub, errs)){
              errs.reset();
              return;
            } else |_| {
              node.restor(i, j);
            }
          }
          return error.ParseError;
        },
        .con => |con| {
          for (con) |sub| {
            try parseRule(allocator, tag, text, node, &sub, errs);
          }
        },
        .rep => |rep| {
          var count: usize = 0;
          while ((rep.max == null or count < rep.max.?) and node.pos + node.len < text.len) {
            const i = node.len;
            const j = node.sub.items.len;
            if (parseRule(allocator, tag, text, node, rep.sub, errs)) {
              count += 1;
            } else |_| {
              node.restor(i, j);
              break;
            }
          }
          if (count < rep.min) {
            return error.ParseError;
          }
          errs.reset();
        },
        .str => |str| {
          if (std.mem.eql(u8, text[node.pos..node.pos + str.len], str)) {
            node.len += str.len;
          } else {
            try errs.put(node.pos, tag, rule);
            return error.ParseError;
          }
        },
        .val => |val| {
          if (text.len <= node.raw.len) return error.ParseError;
          const next = text[node.raw.len];
          if (val.min <= next and next <= val.max) {
            node.raw.len += 1;
          } else {
            try errs.put(node.pos, tag, rule);
            return error.ParseError;
          }
        },
        .jmp => |jmp| {
          if (flag[jmp]) {
            const new_tag: Tag = @enumFromInt(jmp);
            var new_node = try Node(Tag).create(allocator, tag, node.pos + node.len);
            errdefer new_node.deinit();
            try parseRule(allocator, new_tag, text, new_node, &rules[jmp], errs);
            try node.sub.append(new_node);
            node.len += new_node.len;
          } else {
            try parseRule(allocator, tag, text, node, rules[jmp], errs);
          }
        },
      }
    }
  };

  return Clojure.parse;
}