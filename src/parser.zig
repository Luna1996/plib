const std = @import("std");
const Rule = @import("rule.zig").Rule;
const Node = @import("node.zig").Node;

pub fn gen_parser(comptime abnf: type, comptime keep: []const abnf.Tag) Parser(abnf.Tag) {
  const Tag: type = abnf.Tag;
  const rules: []const Rule = abnf.rules;
  const bitset = bitset: {
    comptime var bitset = std.bit_set.StaticBitSet(std.meta.fields(Tag).len).initEmpty();
    inline for (keep) |tag| bitset.set(@intFromEnum(tag));
    break :bitset bitset;
  };

  const ParseContext = struct {
    const Self = @This();

    node: *Node(Tag),
    init_pos: usize = 0,
    keep_pos: usize = 0,
    
    fn reset(self: *Self, old_ctx: *const Self, old_len: usize) void {
      self.* = old_ctx.*;
      self.node.reset(old_len);
    }

    fn appendStr(self: *Self, input: []const u8) std.mem.Allocator.Error!void {
      switch (self.node.val) {
        .str => unreachable,
        .sub => |*sub| if (self.keep_pos < self.init_pos) {
          try sub.append(Node(Tag).initStr(input[self.keep_pos..self.init_pos]));
          self.keep_pos = self.init_pos;
        },
      }
    }

    fn shrinkTrivial(self: Self) void {
      switch (self.node.val) {
        .str => unreachable,
        .sub => |sub| if (sub.items.len == 1 and sub.items[0].tag == null) {
          const str = sub.items[0].val.str;
          sub.deinit();
          self.node.val = .{.str = str};
        },
      }
    }
  };

  return struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    input: []const u8,

    pub fn parse(allocator: std.mem.Allocator, input: []const u8) ParserError!Node(Tag) {
      var self = Self {.allocator = allocator, .input = input};
      var root = Node(Tag).initSub(allocator, keep[0]);
      errdefer root.deinit();
      var ctx = ParseContext { .node = &root };
      try self.parseRule(rules[@intFromEnum(keep[0])], &ctx);
      if (ctx.init_pos != self.input.len) return error.UnconsumedInput;
      try ctx.appendStr(self.input);
      ctx.shrinkTrivial();
      return root;
    }

    fn parseRule(self: *Self, rule: Rule, ctx: *ParseContext) ParserError!void {
      const old_ctx = ctx.*;
      const old_len = ctx.node.val.sub.items.len;
      errdefer ctx.reset(&old_ctx, old_len);
      switch (rule) {
        .alt => |alt| try self.parseRuleAlt(alt, ctx),
        .con => |con| try self.parseRuleCon(con, ctx),
        .rep => |rep| try self.parseRuleRep(rep, ctx),
        .str => |str| try self.parseRuleStr(str, ctx),
        .val => |val| try self.parseRuleVal(val, ctx),
        .jmp => |jmp| try self.parseRuleJmp(jmp, ctx),
      }
    }

    fn parseRuleAlt(self: *Self, alt: Rule.Alt, ctx: *ParseContext) ParserError!void {
      for (alt) |rule| {
        if (self.parseRule(rule, ctx)) return else |_| continue;
      }
      return error.NoneAltOptionMatch;
    }

    fn parseRuleCon(self: *Self, con: Rule.Con, ctx: *ParseContext) ParserError!void {
      for (con) |rule| {
        try self.parseRule(rule, ctx);
      }
    }

    fn parseRuleRep(self: *Self, rep: Rule.Rep, ctx: *ParseContext) ParserError!void {
      var cnt: usize = 0;
      while (true) {
        // reach the max count of repeat
        if (rep.max) |max| if (cnt > max) break;
        self.parseRule(rep.sub.*, ctx) catch break;
        cnt += 1;
      }
      if (cnt < rep.min) return error.LessThanMinimalRepeatCount;
    }

    fn parseRuleStr(self: *Self, str: Rule.Str, ctx: *ParseContext) ParserError!void {
      if (ctx.init_pos >= self.input.len) return error.EndOfInput;
      if (!std.mem.startsWith(u8, self.input[ctx.init_pos..], str)) return error.StrNotMatch;
      ctx.init_pos += str.len;
    }

    fn parseRuleVal(self: *Self, val: Rule.Val, ctx: *ParseContext) ParserError!void {
      if (ctx.init_pos >= self.input.len) return error.EndOfInput;
      const len = std.unicode.utf8ByteSequenceLength(self.input[ctx.init_pos]) catch return error.Utf8Error;
      const code = std.unicode.utf8Decode(self.input[ctx.init_pos..ctx.init_pos + len]) catch return error.Utf8Error;
      if (code < val.min or val.max < code) return error.ValOutOfScope;
      ctx.init_pos += len;
    }

    fn parseRuleJmp(self: *Self, jmp: Rule.Jmp, ctx: *ParseContext) ParserError!void {
      if (bitset.isSet(jmp)) {
        try ctx.appendStr(self.input);
        const old_node = ctx.node;
        var node = Node(Tag).initSub(self.allocator, @enumFromInt(jmp));
        errdefer node.deinit();
        ctx.node = &node;
        try self.parseRule(rules[jmp], ctx);
        try ctx.appendStr(self.input);
        ctx.shrinkTrivial();
        try old_node.val.sub.append(node);
        ctx.node = old_node;
      } else {
        try self.parseRule(rules[jmp], ctx);
      }
    }
  }.parse;
}

fn Parser(comptime Tag: type) type {
  return fn (std.mem.Allocator, []const u8) ParserError!Node(Tag);
}

const ParserError = error {
  UnconsumedInput, NoneAltOptionMatch, LessThanMinimalRepeatCount, ValOutOfScope, EndOfInput, StrNotMatch, Utf8Error,
} || std.mem.Allocator.Error;