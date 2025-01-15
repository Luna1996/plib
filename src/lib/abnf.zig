const std = @import("std");

pub const Rule = union(enum) {
  pub const Alt = []const Rule;
  pub const Con = []const Rule;
  pub const Rep = struct {
    min: u8 = 0,
    max: ?u8 = null,
    sub: *const Rule,
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
};

pub const ABNF = struct {
  names: []const [:0]const u8,
  rules: []const Rule,
};