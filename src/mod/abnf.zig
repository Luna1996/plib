const std = @import("std");
const abnf = @import("gen.abnf").abnf;
const plib = @import("plib");
const Parser = plib.Parser(abnf);
const Tag = Parser.Tag;
const Node = Parser.Node;

pub const ABNF = struct {
  const Self = @This();

  const Conf = struct {
    allocator: std.mem.Allocator,
    file_path: ?[]const u8 = null,
    input: []const u8,
  };

  allocator: std.mem.Allocator,
  names: std.StringArrayHashMap(usize),
  rules: std.ArrayList(Rule),

  pub fn build(conf: Conf) !Self {
    var root = try parse(conf);
    defer root.deinit();

    const allocator = conf.allocator;
    var self = Self {
      .allocator = allocator,
      .names = std.StringArrayHashMap(usize).init(allocator),
      .rules = std.ArrayList(Rule).init(allocator),
    };

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
    errdefer result.root.deinit();

    if (result.fail) |fail| {
      std.debug.print("{}", .{fail});
      return error.ParseError;
    } else {
      return result.root;
    }
  }

  pub fn deinit(self: *Self) void {
    for (self.names.keys()) |name| self.allocator.free(name);
    self.names.deinit();
    for (self.rules.items) |rule| rule.deinit(self.allocator);
    self.rules.deinit();
  }

  fn buildABNF(self: *Self, root: *Node) !void {
    var id: usize = 0;
    while (id < root.subLen()) {
      const item = root.get(id);
      const name = item.getStr(0);
      if (self.names.get(name)) |old_id| {
        const prev = root.get(old_id);
        const cont = root.del(id);
        defer cont.deinit();
        try prev.get(1).appendSub(cont.get(1));
      } else {
        const name_dup = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_dup);
        try self.names.put(name_dup, id);
        id += 1;
      }
    }

    std.debug.print("{}", .{root});

    for (root.val.sub.items) |item| {
      const rule = try self.buildRule(item);
      errdefer rule.deinit(self.allocator);
      try self.rules.append(rule);
    }
  }

  fn buildRule(self: *Self, node: Node) !Rule {
    _ = self;
    _ = node;
    return .{.jmp = 0};
  }
};

pub const Rule = union(enum) {
  const Self = @This();
  pub const Alt = std.ArrayList(Rule);
  pub const Con = std.ArrayList(Rule);
  pub const Rep = struct {
    min: u8 = 0,
    max: ?u8 = null,
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

  pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
    switch (self) {
      .alt, .con => |lst| {
        for (lst.items) |sub| sub.deinit(allocator);
        lst.deinit();
      },
      .rep => |rep| {
        rep.sub.deinit(allocator);
        allocator.destroy(rep.sub);
      },
      else => {},
    }
  }
};