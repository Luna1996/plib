pub const Rule = union(enum) {
  alt: []const Rule,
  con: []const Rule,
  rep: struct {
    min: u8 = 0,
    max: ?u8 = null,
    sub: *const Rule,
  },
  str: []const u8,
  val: struct {
    min: u21,
    max: u21,
  },
  jmp: usize,
};