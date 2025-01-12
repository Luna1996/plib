const std = @import("std");
const Rule = @import("rule.zig").Rule;
const Node = @import("node.zig").Node;

pub const Parser = struct {
  const Self = @This();

  allocator: std.mem.Allocator,
  rules: []const Rule,
  input: []const u8,
  root: usize = 0,
  keep: std.bit_set.DynamicBitSet,

  pub fn parse(self: *Self) ParseError!Node {
    var root = Node.initStr(self.allocator, self.root);
    errdefer root.deinit();
    var ctx = ParseContext { .node = &root };
    try self.parseRule(self.rules[self.root], &ctx);
    if (ctx.init_pos != self.input.len) return .UnconsumedInput;
    try ctx.appendStr(self.input);
    ctx.shrinkTrivial();
    return root;
  }

  fn parseRule(self: *Self, rule: Rule, ctx: *ParseContext) ParseError!void {
    const old_ctx = ctx.*;
    const old_len = ctx.node.val.sub.items.len;
    errdefer ctx.reset(old_ctx, old_len);
    switch (rule) {
      .alt => |alt| try self.parseRuleAlt(alt, ctx),
      .con => |con| try self.parseRuleCon(con, ctx),
      .rep => |rep| try self.parseRuleRep(rep, ctx),
      .str => |str| try self.parseRuleStr(str, ctx),
      .val => |val| try self.parseRuleVal(val, ctx),
      .jmp => |jmp| try self.parseRuleJmp(jmp, ctx),
    }
    ctx.shrinkTrivial();
  }

  fn parseRuleAlt(self: *Self, alt: Rule.Alt, ctx: *ParseContext) ParseError!void {
    for (alt) |rule| {
      if (self.parseRule(rule, ctx)) return else |_| continue;
    }
    return error.NoneAltOptionMatch;
  }

  fn parseRuleCon(self: *Self, con: Rule.Con, ctx: *ParseContext) ParseError!void {
    for (con) |rule| {
      try self.parseRule(rule, ctx);
    }
  }

  fn parseRuleRep(self: *Self, rep: Rule.Rep, ctx: *ParseContext) ParseError!void {
    var cnt: usize = 0;
    while (true) {
      // reach the max count of repeat
      if (rep.max) |max| if (cnt > max) break;
      self.parseRule(rep.sub, ctx) catch break;
      cnt += 1;
    }
    if (cnt < rep.min) return .LessThanMinimalRepeatCount;
  }

  fn parseRuleStr(self: *Self, str: Rule.Str, ctx: *ParseContext) ParseError!void {
    if (ctx.init_pos >= self.input.len) return error.EndOfInput;
    if (!std.mem.startsWith(u8, self.input[ctx.init_pos], str)) return error.StrNotMatch;
    ctx.init_pos += str.len;
  }

  fn parseRuleVal(self: *Self, val: Rule.Val, ctx: *ParseContext) ParseError!void {
    if (ctx.init_pos >= self.input.len) return error.EndOfInput;
    const len = try std.unicode.utf8ByteSequenceLength(self.input[ctx.init_pos]);
    const code = try std.unicode.utf8Decode(self.input[ctx.init_pos..ctx.init_pos + len]);
    if (code < val.min or val.max < code) return error.ValOutOfScope;
    ctx.init_pos += len;
  }

  fn parseRuleJmp(self: *Self, jmp: Rule.Jmp, ctx: *ParseContext) ParseError!void {
    if (self.keep.isSet(jmp)) {
      const old_ctx = ctx.*;
      var node = Node.init(self.allocator, jmp);
      errdefer node.deinit();
      ctx.node = &node;
      ctx.keep_pos = ctx.init_pos;
      try self.parseRule(self.rules[jmp], ctx);
      try old_ctx.appendStr(self.input);
      try old_ctx.node.val.sub.append(node);
      ctx.node = old_ctx.node;
      try ctx.appendStr(self.input);
      ctx.keep_pos = ctx.init_pos;
    } else {
      try self.parseRule(self.rules[jmp], ctx);
    }
  }

};

const ParseContext = struct {
  const Self = @This();

  node: *Node,
  init_pos: usize = 0,
  keep_pos: usize = 0,
  
  fn reset(self: *Self, old_ctx: *const Self, old_len: usize) void {
    self.* = old_ctx.*;
    switch (self.node.val) {
      .str => unreachable,
      .sub => |sub| if (sub.items.len > old_len) {
        for (old_len..sub.items.len) |i|
          sub.items[i].deinit();
        sub.shrinkAndFree(old_len);
      },
    }
  }

  fn appendStr(self: Self, input: []const u8) std.mem.Allocator.Error!void {
    switch (self.node.val) {
      .str => unreachable,
      .sub => |sub| if (self.keep_pos < self.init_pos) {
        try sub.append(Node.initStr(input[self.keep_pos..self.init_pos]));
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

const ParseError = error {
  UnconsumedInput, NoneAltOptionMatch, LessThanMinimalRepeatCount, ValOutOfScope, EndOfInput, StrNotMatch,
  Utf8InvalidStartByte
} || std.unicode.Utf8DecodeError || std.mem.Allocator.Error;