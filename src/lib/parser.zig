const std = @import("std");
const ABNF = @import("abnf.zig").ABNF;
const Rule = @import("abnf.zig").Rule;

pub fn Parser(comptime abnf: ABNF) type {
  return struct {
    const Self = @This();
    
    pub const Tag = block: {
      var fields: [abnf.names.len]std.builtin.Type.EnumField = undefined;
      for (&fields, abnf.names, 0..) |*field, name, i| field.* = .{ .name = name, .value = i };
      break :block @as(type, @Type(.{.@"enum" = .{
        .tag_type = std.math.Log2Int(std.meta.Int(.unsigned, abnf.names.len)),
        .decls = &.{},
        .fields = &fields,
        .is_exhaustive = true,
      }}));
    };
    
    pub const Node = @import("node.zig").Node(Tag);

    const AllocError = std.mem.Allocator.Error;
    const ParseError = error { ParseError } || AllocError;

    const Fail = struct {
      pos: usize,
      wht: union(enum) {
        val: Rule.Val,
        str: Rule.Str,
      },
    };

    const FailWithContext = struct {
      path: ?[]const u8,
      text: []const u8,
      fail: Fail,

      pub fn format(
        self: @This(), 
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
      ) !void {
        const loc = std.zig.findLineColumn(self.text, self.fail.pos);
        try writer.print("{s}:{d}:{d}: expect ", .{
          if (self.path) |path| path else "????",
          loc.line + 1, loc.column + 1,
        });
        switch (self.fail.wht) {
          .val => |val| {
            var out: [4]u8 = undefined;
            try writer.print("\'{}\'", .{std.zig.fmtEscapes(out[0..try std.unicode.utf8Encode(val.min, &out)])});
            try writer.print("-\'{}\'", .{std.zig.fmtEscapes(out[0..try std.unicode.utf8Encode(val.max, &out)])});
          },
          .str => |str| try writer.print("\"{}\"", .{std.zig.fmtEscapes(str)}),
        }
        try writer.print(" at\n{s}\n", .{loc.source_line});
        try writer.writeByteNTimes(' ', loc.column);
        try writer.writeAll("^\n");
      }
    };

    const Result = struct {
      root: Node,
      fail: ?FailWithContext,
    };

    const rules = abnf.rules;

    allocator: std.mem.Allocator,
    keeps: std.enums.EnumSet(Tag),
    input: []const u8,

    cur_node: *Node,
    init_pos: usize = 0,
    keep_pos: usize = 0,

    keep_null: bool,

    last_fail: ?Fail = null,

    pub fn parse(conf: struct {
      allocator: std.mem.Allocator,
      input: []const u8,
      keeps: []const Tag,
      file_path: ?[]const u8 = null,
      root_rule: Tag = @enumFromInt(0),
      keep_null: bool = false,
    }) AllocError!Result {
      var root = Node.initSub(conf.allocator, conf.root_rule);
      errdefer root.deinit();
      var self = Self {
        .allocator = conf.allocator,
        .keeps = std.enums.EnumSet(Tag).initEmpty(),
        .input = conf.input,
        .cur_node = &root,
        .keep_null = conf.keep_null,
      };
      for (conf.keeps) |tag| self.keeps.setPresent(tag, true);
      self.parseRule(rules[@intFromEnum(conf.root_rule)]) catch |e|
        if (e != error.ParseError) return AllocError.OutOfMemory;
      try self.appendStr(true);
      if (self.init_pos == self.input.len) self.last_fail = null;
      return .{
        .root = root,
        .fail = if (self.last_fail) |fail| .{
          .path = conf.file_path,
          .text = conf.input,
          .fail = fail,    
        } else null,
      };
    }

    fn parseRule(self: *Self, rule: Rule) ParseError!void {
      const old_node = self.cur_node;
      const old_len = self.cur_node.val.sub.items.len;
      const old_init_pos = self.init_pos;
      const old_keep_pos = self.keep_pos;
      errdefer {
        self.cur_node = old_node;
        self.cur_node.reset(old_len);
        self.init_pos = old_init_pos;
        self.keep_pos = old_keep_pos;
      }
      switch (rule) {
        .alt => |alt| try self.parseRuleAlt(alt),
        .con => |con| try self.parseRuleCon(con),
        .rep => |rep| try self.parseRuleRep(rep),
        .str => |str| try self.parseRuleStr(str),
        .val => |val| try self.parseRuleVal(val),
        .jmp => |jmp| try self.parseRuleJmp(jmp),
      }
    }

    fn parseRuleAlt(self: *Self, alt: Rule.Alt) ParseError!void {
      for (alt) |rule| if (self.parseRule(rule)) return else |_| continue;
      return error.ParseError;
    }

    fn parseRuleCon(self: *Self, con: Rule.Con) ParseError!void {
      for (con) |rule| try self.parseRule(rule);
    }

    fn parseRuleRep(self: *Self, rep: Rule.Rep) ParseError!void {
      var cnt: usize = 0;
      while (true) {
        if (0 > rep.max and cnt > rep.max) break;
        self.parseRule(rep.sub.*) catch break;
        cnt += 1;
      }
      if (cnt < rep.min) return error.ParseError;
    }

    fn parseRuleStr(self: *Self, str: Rule.Str) ParseError!void {
      if (self.init_pos >= self.input.len or !std.mem.startsWith(u8, self.input[self.init_pos..], str)) {
        try self.postError(.{.pos = self.init_pos, .wht = .{.str = str}});
      }
      self.init_pos += str.len;
    }

    fn parseRuleVal(self: *Self, val: Rule.Val) ParseError!void {
      if (fail: {
        if (self.init_pos >= self.input.len) break :fail true;
        const len = std.unicode.utf8ByteSequenceLength(self.input[self.init_pos]) catch break :fail true;
        const code = std.unicode.utf8Decode(self.input[self.init_pos..self.init_pos + len]) catch break :fail true;
        if (code < val.min or val.max < code) break :fail true;
        self.init_pos += len;
        break :fail false;
      }) {
        try self.postError(.{.pos = self.init_pos, .wht = .{.val = val}});
      }
    }

    fn parseRuleJmp(self: *Self, jmp: Rule.Jmp) ParseError!void {
      if (self.keeps.contains(@enumFromInt(jmp))) {
        try self.appendStr(false);
        const old_node = self.cur_node;
        var node = Node.initSub(self.allocator, @enumFromInt(jmp));
        errdefer node.deinit();
        self.cur_node = &node;
        try self.parseRule(rules[jmp]);
        try self.appendStr(true);
        try old_node.val.sub.append(node);
        self.cur_node = old_node;
      } else {
        try self.parseRule(rules[jmp]);
      }
    }

    fn postError(self: *Self, fail: Fail) !void {
      if (self.last_fail == null or self.last_fail.?.pos <= fail.pos) {
        self.last_fail = fail;
      }
      return error.ParseError;
    }

    fn appendStr(self: *Self, is_end: bool) !void {
      switch (self.cur_node.val) {
        .str => unreachable,
        .sub => |*sub| if (self.keep_pos < self.init_pos) {
          const str = self.input[self.keep_pos..self.init_pos];
          if (is_end and sub.items.len == 0) {
            sub.deinit();
            self.cur_node.val = .{.str = str};
          } else if (self.keep_null) {
            try sub.append(Node.initStr(str));
          }
          self.keep_pos = self.init_pos;
        },
      }
    }
  };
}