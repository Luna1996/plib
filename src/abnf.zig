// https://www.rfc-editor.org/rfc/rfc5234

const std = @import("std");

const RuleSet = struct {
  allocator: std.mem.Allocator,
  names: std.ArrayList([]u8),
  rules: std.ArrayList(Rule),
};

const Rule = union(enum) {
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