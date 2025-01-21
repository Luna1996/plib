const std = @import("std");
const plib = @import("plib");
const Parser = plib.Parser(@import("gen").abnf);
const Tag = Parser.Tag;
const Node = Parser.Node;

pub const ABNF = struct {
  const Self = @This();

  const Error = std.mem.Allocator.Error;

  const Conf = struct {
    allocator: std.mem.Allocator,
    file_path: ?[]const u8 = null,
    input: []const u8,
  };

  allocator: std.mem.Allocator,
  names: std.StringArrayHashMapUnmanaged(usize),
  rules: std.ArrayListUnmanaged(Rule),

  pub fn build(conf: Conf) !Self {
    var root = try parse(conf);
    defer root.deinit(conf.allocator);

    const allocator = conf.allocator;
    var self = Self {
      .allocator = allocator,
      .names = std.StringArrayHashMapUnmanaged(usize).empty,
      .rules = std.ArrayListUnmanaged(Rule).empty,
    };

    errdefer self.deinit();
    try self.buildABNF(&root);

    return self;
  }

  pub fn parse(conf: Conf) !Node {
    var result = try Parser.parse(.{
      .allocator = conf.allocator,
      .input = conf.input,
      .keeps = &.{
        .rulelist, .rule, .rulename,
        .alternation, .concatenation, .repetition, .option,
        .repeat, .char_val, .bin_val, .dec_val, .hex_val,
      },
      .file_path = conf.file_path,
    });
    errdefer result.root.deinit(conf.allocator);

    if (result.fail) |fail| {
      std.debug.print("{}", .{fail});
      return error.ParseError;
    } else {
      return result.root;
    }
  }

  pub fn deinit(self: *Self) void {
    for (self.names.keys()) |name| self.allocator.free(name);
    self.names.deinit(self.allocator);
    for (self.rules.items) |*rule| rule.deinit(self.allocator);
    self.rules.deinit(self.allocator);
  }

  fn buildABNF(self: *Self, root: *Node) !void {
    var id: usize = 0;
    while (id < root.subLen()) {
      const item = root.get(id);
      const name = item.getStr(0);
      if (self.names.get(name)) |old_id| {
        const prev = root.get(old_id);
        var cont = root.del(id);
        defer cont.deinit(self.allocator);
        try prev.get(1).appendSub(self.allocator, cont.get(1));
      } else {
        const name_dup = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_dup);
        try self.names.put(self.allocator, name_dup, id);
        id += 1;
      }
    }

    try self.rules.ensureTotalCapacityPrecise(self.allocator, id);
    for (root.val.sub.items) |*item|
      self.rules.appendAssumeCapacity(try self.buildAlt(item.get(1)));
  }

  fn buildAlt(self: Self, node: *Node) Error!Rule {
    const sub_len = node.subLen();
    if (sub_len == 1) return try self.buildCon(node.get(0));
    var res = Rule {.alt = try std.ArrayListUnmanaged(Rule).initCapacity(self.allocator, sub_len)};
    errdefer res.deinit(self.allocator);
    for (node.val.sub.items) |*item|
      res.alt.appendAssumeCapacity(try self.buildCon(item));
    return res;
  }

  fn buildCon(self: Self, node: *Node) Error!Rule {
    const sub_len = node.subLen();
    if (sub_len == 1) return try self.buildRep(node.get(0));
    var res = Rule {.con = try std.ArrayListUnmanaged(Rule).initCapacity(self.allocator, sub_len)};
    errdefer res.deinit(self.allocator);
    for (node.val.sub.items) |*item|
      res.con.appendAssumeCapacity(try self.buildRep(item));
    return res;
  }

  fn buildRep(self: Self, node: *Node) Error!Rule {
    const last = node.get(node.subLen() - 1);
    var item = switch (last.tag.?) {
      .option      => try self.buildOpt(last),
      .rulename    =>     self.buildJmp(last),
      .alternation => try self.buildAlt(last),
      .char_val    => try self.buildStr(last),
      .bin_val,
      .dec_val,
      .hex_val     => try self.buildNum(last),
      else         =>     unreachable,
    };
    errdefer item.deinit(self.allocator);

    if (node.subLen() == 2) {
      var rule = Rule {.rep = .{.sub = try self.allocator.create(Rule)}};
      rule.rep.sub.* = item;
      const str = node.getStr(0);
      if (std.mem.indexOfScalar(u8, str, '*')) |sep| {
        if (sep > 0)
          rule.rep.min = std.fmt.parseUnsigned(u8, str[0..sep]   , 10) catch unreachable;
        if (sep < str.len - 1)
          rule.rep.max = std.fmt.parseUnsigned(u8, str[sep + 1..], 10) catch unreachable;
      } else {
        const num =      std.fmt.parseUnsigned(u8, str           , 10) catch unreachable;
        rule.rep.min = num;
        rule.rep.max = num;
      }
      return rule;
    } else {
      return item;
    }
  }

  fn buildOpt(self: Self, node: *Node) Error!Rule {
    const rule = Rule{.rep = .{
      .max = 1,
      .sub = try self.allocator.create(Rule),
    }};
    errdefer self.allocator.destroy(rule.rep.sub);
    rule.rep.sub.* = try self.buildAlt(node.get(0));
    return rule;
  }

  fn buildJmp(self: Self, node: *Node) Rule {
    return .{.jmp = self.names.get(node.val.str).?};
  }

  fn buildStr(self: Self, node: *Node) Error!Rule {
    const str = node.val.str;
    return .{.str = try self.allocator.dupe(u8, str[1..str.len - 1])};
  }

  fn buildNum(self: Self, node: *Node) Error!Rule {
    const str = node.val.str[2..];
    const base: u8 = switch (node.tag.?) {
      .bin_val => 2,
      .dec_val => 10,
      .hex_val => 16,
      else => unreachable,
    };
    if (std.mem.indexOfScalar(u8, str, '-')) |i| {
      return .{.val = .{
        .min = std.fmt.parseUnsigned(u21, str[0..i   ], base) catch unreachable,
        .max = std.fmt.parseUnsigned(u21, str[i + 1..], base) catch unreachable,
      }};
    } else {
      var out = std.ArrayList(u8).init(self.allocator);
      errdefer out.deinit();
      var buf: [4]u8 = undefined;
      var iter = std.mem.splitScalar(u8, str, '.');
      while (iter.next()) |one| {
        const val = std.fmt.parseUnsigned(u21, one, base) catch unreachable;
        try out.appendSlice(buf[0..std.unicode.utf8Encode(val, &buf) catch unreachable]);
      }
      return .{.str = try out.toOwnedSlice()};
    }
  }

  pub fn format(
    self: Self, 
    comptime _: []const u8,
    _: std.fmt.FormatOptions,
    writer: anytype,
  ) !void {
    try writer.writeAll("pub const abnf = @import(\"plib\").ABNF {\n  .names = &.{\n");
    for (self.names.keys()) |name| {
      const tag = try self.allocator.dupe(u8, name);
      defer self.allocator.free(tag);
      std.mem.replaceScalar(u8, tag, '-', '_');
      try writer.print("    \"{s}\",\n", .{tag});
    }
    try writer.writeAll("  },\n  .rules = &.{\n");
    for (self.rules.items) |rule|
      try writer.print("    {},\n", .{rule});
    try writer.writeAll("  }\n};");
  }
};

pub const Rule = union(enum) {
  const Self = @This();
  pub const Alt = std.ArrayListUnmanaged(Rule);
  pub const Con = std.ArrayListUnmanaged(Rule);
  pub const Rep = struct {
    min: u8 = 0,
    max: u8 = 0,
    sub: *Rule,
  };
  pub const Str = []const u8;
  pub const Val = struct {
    min: u21,
    max: u21,
  };
  pub const Jmp = usize;

  alt: Alt,
  con: Con,
  rep: Rep,
  str: Str,
  val: Val,
  jmp: Jmp,

  pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    switch (self.*) {
      .alt, .con => |*lst| {
        for (lst.items) |*sub| sub.deinit(allocator);
        lst.deinit(allocator);
      },
      .rep => |rep| {
        rep.sub.deinit(allocator);
        allocator.destroy(rep.sub);
      },
      .str => |str| allocator.free(str),
      else => {},
    }
  }

  pub fn format(
    self: Self, 
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
  ) !void {
    try writer.print(".{{.{s}=", .{@tagName(self)});
    switch (self) {
      .alt, .con => |lst| {
        try writer.writeAll("&.{");
        const max = lst.items.len - 1;
        for (lst.items, 0..) |rule, i| {
          try rule.format(fmt, options, writer);
          if (i != max) try writer.writeByte(',');
        }
        try writer.writeByte('}');
      },
      .rep => |rep| {
        try writer.writeAll(".{");
        if (rep.min != 0) try writer.print(".min={d},", .{rep.min});
        if (rep.max != 0) try writer.print(".max={d},", .{rep.max});
        try writer.writeAll(".sub=&");
        try rep.sub.format(fmt, options, writer);
        try writer.writeAll("}");
      },
      .str => |str| try writer.print("\"{}\"", .{std.zig.fmtEscapes(str)}),
      .val => |val| try writer.print(".{{.min={d},.max={d}}}", .{val.min, val.max}),
      .jmp => |jmp| try writer.print("{d}", .{jmp}),
    }
    try writer.writeByte('}');
  }
};