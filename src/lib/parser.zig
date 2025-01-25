const std = @import("std");
const ABNF = @import("abnf.zig").ABNF;
const Rule = @import("abnf.zig").Rule;
const fmtFail = @import("fail.zig").fmtFail;

pub fn Parser(comptime abnf: ABNF) type {
  return struct {
    allocator: std.mem.Allocator,
    keeps: std.enums.EnumSet(Tag),
    input: []const u8,

    cur_ast: *Ast,
    init_pos: usize = 0,
    keep_pos: usize = 0,

    keep_null: bool,

    last_fail: ?Fail = null,

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
    
    pub const Ast = @import("ast.zig").Ast(Tag);

    const Error = error { ParseError } || std.mem.Allocator.Error;

    const Fail = struct {
      pos: usize,
      wht: union(enum) {
        val: Rule.Val,
        str: Rule.Str,
      },

      pub fn format(
        self: @This(), 
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
      ) !void {
        switch (self.wht) {
          .val => |val| {
            var out: [4]u8 = undefined;
            try writer.print("\'{}\'", .{std.zig.fmtEscapes(out[0..try std.unicode.utf8Encode(val.min, &out)])});
            try writer.print("-\'{}\'", .{std.zig.fmtEscapes(out[0..try std.unicode.utf8Encode(val.max, &out)])});
          },
          .str => |str| try writer.print("\"{}\"", .{std.zig.fmtEscapes(str)}),
        }
      }
    };

    const rules = abnf.rules;

    pub fn parse(conf: struct {
      allocator: std.mem.Allocator,
      input: []const u8,
      keeps: []const Tag,
      file_path: ?[]const u8 = null,
      root_rule: Tag = @enumFromInt(0),
      keep_null: bool = false,
      log_error: bool = true,
    }) Error!Ast {
      var root = Ast.initSub(conf.root_rule);
      errdefer root.deinit(conf.allocator);
      var self = Self {
        .allocator = conf.allocator,
        .keeps = std.enums.EnumSet(Tag).initEmpty(),
        .input = conf.input,
        .cur_ast = &root,
        .keep_null = conf.keep_null,
      };
      errdefer |e| if (e == error.ParseError and conf.log_error) if (self.last_fail) |fail| {
        std.debug.print("{}", .{fmtFail(fail, .{
          .file = conf.file_path,
          .text = conf.input,
          .pos = fail.pos,
        })});
      };
      for (conf.keeps) |tag| self.keeps.setPresent(tag, true);
      try self.parseRule(rules[@intFromEnum(conf.root_rule)]);
      try self.appendStr(conf.allocator, true);
      if (self.init_pos != self.input.len) return error.ParseError;
      return root;
    }

    fn parseRule(self: *Self, rule: Rule) Error!void {
      const old_ast = self.cur_ast;
      const old_len = self.cur_ast.val.sub.items.len;
      const old_init_pos = self.init_pos;
      const old_keep_pos = self.keep_pos;
      errdefer {
        self.cur_ast = old_ast;
        self.cur_ast.reset(self.allocator, old_len);
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

    fn parseRuleAlt(self: *Self, alt: Rule.Alt) Error!void {
      for (alt) |rule| if (self.parseRule(rule)) return else |_| continue;
      return error.ParseError;
    }

    fn parseRuleCon(self: *Self, con: Rule.Con) Error!void {
      for (con) |rule| try self.parseRule(rule);
    }

    fn parseRuleRep(self: *Self, rep: Rule.Rep) Error!void {
      var cnt: usize = 0;
      while (rep.max == 0 or cnt < rep.max) {
        self.parseRule(rep.sub.*) catch break;
        cnt += 1;
      }
      if (cnt < rep.min) return error.ParseError;
    }

    fn parseRuleStr(self: *Self, str: Rule.Str) Error!void {
      if (self.init_pos >= self.input.len or !std.mem.startsWith(u8, self.input[self.init_pos..], str)) {
        try self.postError(.{.pos = self.init_pos, .wht = .{.str = str}});
      }
      self.init_pos += str.len;
    }

    fn parseRuleVal(self: *Self, val: Rule.Val) Error!void {
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

    fn parseRuleJmp(self: *Self, jmp: Rule.Jmp) Error!void {
      if (self.keeps.contains(@enumFromInt(jmp))) {
        try self.appendStr(self.allocator, false);
        const old_ast = self.cur_ast;
        var ast = Ast.initSub(@enumFromInt(jmp));
        errdefer ast.deinit(self.allocator);
        self.cur_ast = &ast;
        try self.parseRule(rules[jmp]);
        try self.appendStr(self.allocator, true);
        try old_ast.val.sub.append(self.allocator, ast);
        self.cur_ast = old_ast;
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

    fn appendStr(self: *Self, allocator: std.mem.Allocator, is_end: bool) !void {
      switch (self.cur_ast.val) {
        .str => unreachable,
        .sub => |*sub| if (self.keep_pos < self.init_pos) {
          const str = self.input[self.keep_pos..self.init_pos];
          if (is_end and sub.items.len == 0) {
            sub.deinit(allocator);
            self.cur_ast.val = .{.str = str};
          } else if (self.keep_null) {
            try sub.append(allocator, Ast.initStr(str));
          }
          self.keep_pos = self.init_pos;
        },
      }
    }
  };
}