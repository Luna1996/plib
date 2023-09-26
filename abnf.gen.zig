pub const Tag = enum {
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
pub const rules = &.{
  .{.rep=.{.min=1,.sub=&.{.alt=&.{.{.jmp=1},.{.con=&.{.{.rep=.{.sub=&.{.jmp=5}}},.{.jmp=6},}},}}}},
  .{.con=&.{.{.jmp=2},.{.rep=.{.sub=&.{.jmp=5}}},.{.jmp=3},.{.rep=.{.sub=&.{.jmp=5}}},.{.jmp=4},.{.jmp=6},}},
  .{.con=&.{.{.jmp=21},.{.rep=.{.sub=&.{.alt=&.{.{.jmp=21},.{.jmp=27},.{.str="-"},}}}},}},
  .{.alt=&.{.{.str="="},.{.str="=/"},}},
  .{.con=&.{.{.jmp=8},.{.rep=.{.sub=&.{.jmp=5}}},}},
  .{.alt=&.{.{.jmp=36},.{.con=&.{.{.jmp=6},.{.jmp=36},}},}},
  .{.alt=&.{.{.jmp=7},.{.jmp=25},}},
  .{.con=&.{.{.str=";"},.{.rep=.{.sub=&.{.alt=&.{.{.jmp=36},.{.jmp=35},}}}},.{.jmp=25},}},
  .{.con=&.{.{.jmp=9},.{.rep=.{.sub=&.{.con=&.{.{.rep=.{.sub=&.{.jmp=5}}},.{.str="/"},.{.rep=.{.sub=&.{.jmp=5}}},.{.jmp=9},}}}},}},
  .{.con=&.{.{.jmp=10},.{.rep=.{.sub=&.{.con=&.{.{.rep=.{.min=1,.sub=&.{.jmp=5}}},.{.jmp=10},}}}},}},
  .{.con=&.{.{.rep=.{.min=1,.sub=&.{.jmp=11}}},.{.jmp=12},}},
  .{.alt=&.{.{.con=&.{.{.rep=.{.sub=&.{.jmp=27}}},.{.str="*"},.{.rep=.{.sub=&.{.jmp=27}}},}},.{.rep=.{.min=1,.sub=&.{.jmp=27}}},}},
  .{.alt=&.{.{.jmp=2},.{.jmp=13},.{.jmp=14},.{.jmp=15},.{.jmp=16},.{.jmp=20},}},
  .{.con=&.{.{.str="("},.{.rep=.{.sub=&.{.jmp=5}}},.{.jmp=8},.{.rep=.{.sub=&.{.jmp=5}}},.{.str=")"},}},
  .{.con=&.{.{.str="["},.{.rep=.{.sub=&.{.jmp=5}}},.{.jmp=8},.{.rep=.{.sub=&.{.jmp=5}}},.{.str="]"},}},
  .{.con=&.{.{.jmp=28},.{.rep=.{.sub=&.{.alt=&.{.{.val=.{.min=32,.max=33}},.{.val=.{.min=35,.max=126}},}}}},.{.jmp=28},}},
  .{.con=&.{.{.str="%"},.{.alt=&.{.{.jmp=17},.{.jmp=18},.{.jmp=19},}},}},
  .{.con=&.{.{.str="b"},.{.rep=.{.min=1,.sub=&.{.jmp=22}}},.{.rep=.{.min=1,.sub=&.{.alt=&.{.{.rep=.{.min=1,.sub=&.{.con=&.{.{.str="."},.{.rep=.{.min=1,.sub=&.{.jmp=22}}},}}}},.{.con=&.{.{.str="-"},.{.rep=.{.min=1,.sub=&.{.jmp=22}}},}},}}}},}},
  .{.con=&.{.{.str="d"},.{.rep=.{.min=1,.sub=&.{.jmp=27}}},.{.rep=.{.min=1,.sub=&.{.alt=&.{.{.rep=.{.min=1,.sub=&.{.con=&.{.{.str="."},.{.rep=.{.min=1,.sub=&.{.jmp=27}}},}}}},.{.con=&.{.{.str="-"},.{.rep=.{.min=1,.sub=&.{.jmp=27}}},}},}}}},}},
  .{.con=&.{.{.str="x"},.{.rep=.{.min=1,.sub=&.{.jmp=29}}},.{.rep=.{.min=1,.sub=&.{.alt=&.{.{.rep=.{.min=1,.sub=&.{.con=&.{.{.str="."},.{.rep=.{.min=1,.sub=&.{.jmp=29}}},}}}},.{.con=&.{.{.str="-"},.{.rep=.{.min=1,.sub=&.{.jmp=29}}},}},}}}},}},
  .{.con=&.{.{.str="<"},.{.rep=.{.sub=&.{.alt=&.{.{.val=.{.min=32,.max=61}},.{.val=.{.min=63,.max=126}},}}}},.{.str=">"},}},
  .{.alt=&.{.{.val=.{.min=65,.max=90}},.{.val=.{.min=97,.max=122}},}},
  .{.alt=&.{.{.str="0"},.{.str="1"},}},
  .{.val=.{.min=1,.max=127}},
  .{.str="\\r"},
  .{.con=&.{.{.jmp=24},.{.jmp=31},}},
  .{.alt=&.{.{.val=.{.min=0,.max=31}},.{.str=""},}},
  .{.val=.{.min=48,.max=57}},
  .{.str="\\\""},
  .{.alt=&.{.{.jmp=27},.{.str="A"},.{.str="B"},.{.str="C"},.{.str="D"},.{.str="E"},.{.str="F"},}},
  .{.str="\\t"},
  .{.str="\\n"},
  .{.rep=.{.sub=&.{.alt=&.{.{.jmp=36},.{.con=&.{.{.jmp=25},.{.jmp=36},}},}}}},
  .{.val=.{.min=0,.max=255}},
  .{.str=" "},
  .{.val=.{.min=33,.max=126}},
  .{.alt=&.{.{.jmp=34},.{.jmp=30},}},
};