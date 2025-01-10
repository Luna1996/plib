const std = @import("std");
const Rule = @import("rule.zig").Rule;
const Node = @import("node.zig").Node;

pub const Parser = struct {
  const Self = @This();

  allocator: std.mem.Allocator,
  rules: []const Rule,
  input: []const u8,
  root: usize = 0,
  keep: []const usize,

  pub fn parse(self: *Self) ParseError!Node {
    var root = Node { .tag = self.config.root, .val = undefined };
    const len = try self.parseRule(&.{
      .rule = self.rules[self.config.root], 
      .node = &root, 
      .init_pos = 0,
      .keep_pos = 0,
    });
    if (len != self.input.len) {
      root.deinit();
      return .UnconsumedInput;
    }
    return root;
  }

  inline fn parseRule(self: *Self, ctx: *const ParseContext) ParseError!usize {
    return switch (ctx.rule) {
      .alt => try self.parseRuleAlt(ctx),
      .con => try self.parseRuleCon(ctx),
      .rep => try self.parseRuleRep(ctx),
      .str => try self.parseRuleStr(ctx),
      .val => try self.parseRuleVal(ctx),
      .jmp => try self.parseRuleJmp(ctx),
    };
  }

  fn parseRuleAlt(self: *Self, ctx: *const ParseContext) ParseError!usize {
    var ctx_mut = ctx.*;
    for (ctx.rule.alt) |rule| {
      ctx_mut.rule = rule;
      return self.parseRule(&ctx_mut) catch continue;
    }
  }

  fn parseRuleCon(self: *Self, ctx: *const ParseContext) ParseError!usize {
    var len = 0;
    var ctx_mut = ctx.*;
    for (ctx.rule.con) |rule| {
      ctx_mut.rule = rule;
      const sub_len = try self.parseRule(&ctx_mut);
      ctx_mut.init_pos += sub_len;
      len += sub_len;
    }
    return len;
  }

  fn parseRuleRep(self: *Self, ctx: *const ParseContext) ParseError!usize {
    var len = 0;
    var cnt = 0;
    var ctx_mut = ctx.*;
    ctx_mut.rule = ctx.rule.rep.sub;
    while (cnt <= ctx.rule.rep.max) {
    }
  }

  fn parseRuleStr(self: *Self, ctx: *const ParseContext) ParseError!usize {}

  fn parseRuleVal(self: *Self, ctx: *const ParseContext) ParseError!usize {}

  fn parseRuleJmp(self: *Self, ctx: *const ParseContext) ParseError!usize {}
};

const ParseContext = struct {
  rule: *const Rule,
  node: *Node,
  init_pos: usize,
  keep_pos: usize,
};

const ParseError = error {
  UnconsumedInput,
};