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
  // 00 - rulelist
  .{.rep=.{.min=1,.sub=&.{.alt=&.{.{.jmp=1},.{.con=&.{.{.rep=.{.sub=&.{.jmp=5}}},.{.jmp=6}}}}}}},
  // 01 - rule
  .{.con=&.{.{.jmp=2},.{.rep=.{.sub=&.{.jmp=5}}},.{.jmp=3},.{.rep=.{.sub=&.{.jmp=5}}},.{.jmp=4},.{.jmp=6}}},
  // 02 - rulename
  .{.con=&.{.{.jmp=21},.{.rep=.{.sub=&.{.alt=&.{.{.jmp=21},.{.jmp=27},.{.str="-"}}}}}}},
  // 03 - defined_as
  .{.alt=&.{.{.str="="},.{.str="=/"}}},
  // 04 - elements
  .{.con=&.{.{.jmp=8},.{.rep=.{.sub=&.{.jmp=5}}}}},
  // 05 - c_wsp
  .{.alt=&.{.{.jmp=36},.{.con=&.{.{.jmp=6},.{.jmp=36}}}}},
  // 06 - c_nl
  .{.alt=&.{.{.jmp=7},.{.jmp=25}}},
  // 07 - comment
  .{.con=&.{.{.str=";"},.{.rep=.{.sub=&.{.alt=&.{.{.jmp=36},.{.jmp=35}}}}},.{.jmp=25}}},
  // 08 - alternation
  .{.con=&.{.{.jmp=9},.{.rep=.{.sub=&.{.con=&.{.{.rep=.{.sub=&.{.jmp=5}}},.{.str="/"},.{.rep=.{.sub=&.{.jmp=5}}},.{.jmp=9}}}}}}},
  // 09 - concatenation
  .{.con=&.{.{.jmp=10},.{.rep=.{.sub=&.{.con=&.{.{.rep=.{.min=1,.sub=&.{.jmp=5}}},.{.jmp=10}}}}}}},
  // 10 - repetition
  .{.con=&.{.{.rep=.{.max=1,.sub=&.{.jmp=11}}},.{.jmp=12}}},
  // 11 - repeat
  .{.alt=&.{.{.con=&.{.{.rep=.{.sub=&.{.jmp=27}}},.{.str="*"},.{.rep=.{.sub=&.{.jmp=27}}}}},.{.rep=.{.min=1,.sub=&.{.jmp=27}}}}},
  // 12 - element
  .{.alt=&.{.{.jmp=2},.{.jmp=13},.{.jmp=14},.{.jmp=15},.{.jmp=16},.{.jmp=20}}},
  // 13 - group
  .{.con=&.{.{.str="("},.{.rep=.{.sub=&.{.jmp=5}}},.{.rep=.{.sub=&.{.jmp=8}}},.{.rep=.{.sub=&.{.jmp=5}}},.{.str=")"}}},
  // 14 - option
  .{.con=&.{.{.str="["},.{.rep=.{.sub=&.{.jmp=5}}},.{.rep=.{.sub=&.{.jmp=8}}},.{.rep=.{.sub=&.{.jmp=5}}},.{.str="]"}}},
  // 15 - char_val
  .{.con=&.{.{.jmp=28},.{.rep=.{.sub=&.{.alt=&.{.{.val=.{.min=32,.max=33}},.{.val=.{.min=35,.max=126}}}}}},.{.jmp=28}}},
  // 16 - num_val
  .{.con=&.{.{.str="%"},.{.alt=&.{.{.jmp=17},.{.jmp=18},.{.jmp=19}}}}},
  // 17 - bin_val
  .{.con=&.{.{.str="b"},.{.rep=.{.min=1,.sub=&.{.jmp=22}}},.{.rep=.{.max=1,.sub=&.{.alt=&.{.{.rep=.{.min=1,.sub=&.{.con=&.{.{.str="."},.{.rep=.{.min=1,.sub=&.{.jmp=22}}}}}}},.{.con=&.{.{.str="-"},.{.rep=.{.min=1,.sub=&.{.jmp=22}}}}}}}}}}},
  // 18 - dec_val
  .{.con=&.{.{.str="d"},.{.rep=.{.min=1,.sub=&.{.jmp=27}}},.{.rep=.{.max=1,.sub=&.{.alt=&.{.{.rep=.{.min=1,.sub=&.{.con=&.{.{.str="."},.{.rep=.{.min=1,.sub=&.{.jmp=27}}}}}}},.{.con=&.{.{.str="-"},.{.rep=.{.min=1,.sub=&.{.jmp=27}}}}}}}}}}},
  // 19 - hex_val
  .{.con=&.{.{.str="x"},.{.rep=.{.min=1,.sub=&.{.jmp=29}}},.{.rep=.{.max=1,.sub=&.{.alt=&.{.{.rep=.{.min=1,.sub=&.{.con=&.{.{.str="."},.{.rep=.{.min=1,.sub=&.{.jmp=29}}}}}}},.{.con=&.{.{.str="-"},.{.rep=.{.min=1,.sub=&.{.jmp=29}}}}}}}}}}},
  // 20 - prose_val
  .{.con=&.{.{.str="<"},.{.rep=.{.sub=&.{.alt=&.{.{.val=.{.min=32,.max=61}},.{.val=.{.min=63,.max=126}}}}}},.{.str=">"}}},
  // 21 - ALPHA
  .{.alt=&.{.{.val=.{.min=65,.max=90}},.{.val=.{.min=97,.max=122}}}},
  // 22 - BIT
  .{.alt=&.{.{.str="0"},.{.str="1"}}},
  // 23 - CHAR
  .{.val=.{.min=1,.max=127}},
  // 24 - CR
  .{.str="\x0D"},
  // 25 - CRLF
  .{.con=&.{.{.jmp=24},.{.jmp=31}}},
  // 26 - CTL
  .{.alt=&.{.{.val=.{.min=0,.max=31}},.{.str="\x7F"}}},
  // 27 - DIGIT
  .{.val=.{.min=48,.max=57}},
  // 28 - DQUOTE
  .{.str="\x22"},
  // 29 - HEXDIG
  .{.alt=&.{.{.jmp=27},.{.str="A"},.{.str="B"},.{.str="C"},.{.str="D"},.{.str="E"},.{.str="F"}}},
  // 30 - HTAB
  .{.str="\x09"},
  // 31 - LF
  .{.str="\x0A"},
  // 32 - LWSP
  .{.rep=.{.sub=&.{.alt=&.{.{.jmp=36},.{.con=&.{.{.jmp=25},.{.jmp=36}}}}}}},
  // 33 - OCTET
  .{.val=.{.min=0,.max=255}},
  // 34 - SP
  .{.str="\x20"},
  // 35 - VCHAR
  .{.val=.{.min=33,.max=126}},
  // 36 - WSP
  .{.alt=&.{.{.jmp=34},.{.jmp=30}}}
};