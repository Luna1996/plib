pub const Rule = union(enum) {
  alt: Alt,
  con: Con,
  rep: Rep,
  str: Str,
  val: Val,
  jmp: Jmp,

  pub const Alt = []const Rule;
  pub const Con = []const Rule;
  pub const Rep = struct {
    min: u8 = 0,
    max: ?u8 = null,
    sub: Rule,
  };
  pub const Str = []const u8;
  pub const Val = struct {
    min: u21,
    max: u21,
  };
  pub const Jmp = usize;
};