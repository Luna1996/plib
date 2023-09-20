const std = @import("std");

pub fn Rule(comptime Tag: type) type {
  return union(enum) {
    alternation: []const Rule(Tag),
    concatenation: []const Rule(Tag),
    repetition: struct {
      min: ?usize = null,
      max: ?usize = null,
      sub: Rule(Tag),
    },
    string: []const u8,
    value_range: struct {
      min: u8,
      max: u8
    },
    rule: Tag,
  };
}

pub fn RuleSet(comptime T: type) type {
  const field_names = std.meta.fieldNames(T);
  comptime var fields: [field_names.len]std.builtin.Type.StructField = undefined;
  for (field_names, 0..) |field_name, i| {
    fields[i] = .{
      .name = field_name,
      .type = Rule(T),
      .default_value = null,
      .is_comptime = false,
      .alignment = @alignOf(Rule(T)),
    };
  }
  return struct {
    pub const Tag = T;

    rules: @Type(.{
      .layout = .Auto,
      .fields = &fields,
      .decls = &.{},
      .is_tuple = false,
    }),

    pub fn get(self: @This(), tag: T) Rule(T) {
      return @field(self.rules, @tagName(tag));
    }
  };
}

pub fn toRuleSet(comptime rule_set: anytype) RuleSet(std.meta.FieldEnum(@TypeOf(rule_set))) {

}

const ABNFTag = enum {
  rulelist,
  rule,
  rulename,
  defined_as,
  elements,
  c_wsp,
  c_nl,
  comment,
  alternation,
  concatenation,
  repetition,
  repeat,
  element,
  group,
  option,
  char_val,
  num_val,
  bin_val,
  dec_val,
  hex_val,
  prose_val,
  ALPHA,
  BIT,
  CHAR,
  CR,
  CRLF,
  CTL,
  DIGIT,
  DQUOTE,
  HEXDIG,
  HTAB,
  LF,
  LWSP,
  OCTET,
  SP,
  VCHAR,
  WSP,
};

/// https://www.rfc-editor.org/rfc/rfc5234#section-4
const abnf_rule = RuleSet(ABNFTag){.rules = .{
  .rulelist = .{.repetition = .{.min = 1, .sub = .{.alternation = &[_]Rule(ABNFTag){.{.rule = .rule}, .{.concatenation = &[_]Rule(ABNFTag){.{.repetition = .{.sub = .{.rule = .c_wsp}}}, .{.rule = .c_nl}}}}}}},
  .rule = .{.concatenation = &[_]Rule(ABNFTag){.{.rule = .rulename}, .{.rule = .defined_as}, .{.rule = .elements}, .{.rule = .c_nl}}},
  // .rulename = .{.concatenation = &[_]Rule(ABNFTag)},
},};