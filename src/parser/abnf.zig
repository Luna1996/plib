// https://www.rfc-editor.org/rfc/rfc5234

const std = @import("std");

pub fn Element(comptime Tag: type) type {
  return union(enum) {
    alternative: []const Element(Tag),
    concatenation: []const Element(Tag),
    repetition: struct {
      min: ?usize = null,
      max: ?usize = null,
      sub: Element(Tag),
    },
    string: []const u8,
    value_range: struct {
      min: u8,
      max: u8
    },
    rule: Tag,
  };
}

pub fn Rule(comptime Tag: type) type {
  return struct {
    tag: Tag,
    flat: bool = false,
    elem: Element(Tag),
  };
}

pub fn RuleSet(comptime Tag: type) type {
  return struct {
    rules: []const Rule(Tag),
  };
}
