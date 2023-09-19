// https://www.rfc-editor.org/rfc/rfc5234

const std = @import("std");

pub const RuleSet = struct {
  allocator: std.mem.Allocator,
  names: std.ArrayList([]u8),
  rules: std.ArrayList(Rule),

  pub fn parse(allocator: std.mem.Allocator, abnf: []const u8) !RuleSet {
    var rule_set = RuleSet {
      .allocator = allocator,
      .names = std.ArrayList([]u8).init(allocator),
      .rules = std.ArrayList(Rule).init(allocator),
    };
    _ = rule_set;
    _ = abnf;
  }
};

pub const Rule = union(enum) {
  alternative: std.ArrayList(Rule),
  concatenation: std.ArrayList(Rule),
  repetition: struct {
    min: usize,
    max: usize,
    subrule: usize,
  },
  value_range: struct {
    min: u8,
    max: u8
  },
  string: []u8,
};