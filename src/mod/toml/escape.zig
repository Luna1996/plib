const std = @import("std");
const Ast = @import("root.zig").Toml.Ast;

pub fn unescape(allocator: std.mem.Allocator, ast: *const Ast) !std.meta.Tuple(&.{[]const u8, bool}) {
  if (ast.tag.? == .unquoted_key) return .{ast.val.str, false};
  var help = Unescaper.init(allocator, ast);
  try help.work();
  return if (help.new) |new| .{new, true} else .{help.old, false};
}

const Unescaper = struct {
  allocator: std.mem.Allocator,
  is_mul: bool = undefined,
  is_lit: bool = undefined,
  old: []const u8 = undefined,
  new: ?[]u8 = null,
  old_pos: usize = 0,
  new_pos: usize = 0,

  const Self = @This();

  inline fn init(allocator: std.mem.Allocator, ast: *const Ast) Self {
    var self = Self {.allocator = allocator};
    self.is_mul, self.is_lit = switch (ast.tag.?) {
      .basic_string      => .{false, false},
      .ml_basic_string   => .{true , false},
      .literal_string    => .{false, true },
      .ml_literal_string => .{true , true },
      else => unreachable,
    };

    const str = ast.val.str;
    const len = str.len;
    self.old =
           if (!self.is_mul)   str[1..len-1]
      else if (str[3] == '\n') str[4..len-3]
      else                     str[3..len-3];
    return self;
  }

  inline fn work(self: *Self) !void {
    if (self.is_lit) return;
    errdefer if (self.new) |new| self.allocator.free(new);
    while (self.old_pos < self.old.len) try self.step();
    if (self.new) |new| self.new = try self.allocator.realloc(new, self.new_pos);
  }

  inline fn step(self: *Self) !void {
    const ne_len = skipNE(self.old[self.old_pos..]);
    if (self.new == null)
      self.new = try self.allocator.alloc(u8, self.old.len);
    const new = self.new.?;

    if (ne_len > 0) {
      @memcpy(new[self.new_pos..][0..ne_len], self.old[self.old_pos..][0..ne_len]);
      self.old_pos += ne_len;
      self.new_pos += ne_len;
    }

    if (self.old_pos == self.old.len) return;
    const c = self.old[self.old_pos + 1];
    self.old_pos += 2;

    var uni_len: usize = 0;
    
    switch (c) {
      0x22 => new[self.new_pos] = 0x22,
      0x5C => new[self.new_pos] = 0x5C,
      0x62 => new[self.new_pos] = 0x08,
      0x66 => new[self.new_pos] = 0x0C,
      0x6E => new[self.new_pos] = 0x0A,
      0x72 => new[self.new_pos] = 0x0D,
      0x74 => new[self.new_pos] = 0x09,
      0x75 => uni_len = 4,
      0x55 => uni_len = 8,
      else => {
        self.old_pos += skipWS(self.old[self.old_pos..]);
        return;
      },
    }

    if (uni_len == 0) {
      self.new_pos += 1;
      return;
    }

    const unicode = try std.fmt.parseUnsigned(u21, self.old[self.old_pos..][0..uni_len], 16);
    self.old_pos += uni_len;
    self.new_pos += try std.unicode.utf8Encode(unicode, new[self.new_pos..][0..4]);
  }

  inline fn skipWS(s: []const u8) usize {
    for (s, 0..) |c, i| switch (c) {
      0x20, 0x0A, 0x0D, 0x09 => continue,
      else => return i,
    };
    return s.len;
  }

  inline fn skipNE(s: []const u8) usize {
    for (s, 0..) |c, i| if (c == 0x5C) {return i;};
    return s.len;
  }
};

pub fn needEscape(str: []const u8) bool {
  const view = std.unicode.Utf8View.initUnchecked(str);
  var iter = view.iterator();
  while (iter.nextCodepoint()) |code| if (needEscapeCode(code)) {
    return true;
  };
  return false;
}

pub fn needEscapeCode(code: u21) bool {
  return switch (code) {
    'A'...'Z', 'a'...'z', '0'...'9', '-', '_',
    => false,
    else
    => true,
  };
}

pub fn escape(str: []const u8) std.fmt.Formatter(escapeString) {
  return .{.data = str};
}

fn escapeString(
  self: []const u8,
  comptime _: []const u8,
  _: std.fmt.FormatOptions,
  writer: anytype,
) !void {
  const v = std.unicode.Utf8View.initUnchecked(self);
  var i = v.iterator();
  while (i.nextCodepointSlice()) |s| {
    const c = std.unicode.utf8Decode(s) catch unreachable;
    if (needEscapeCode(c)) {
      switch (c) {
        ' ', '!', '#'...'&', '('...'~' => {
          try writer.writeByte(@intCast(c));
          continue;
        },
        else => {},
      }
      try writer.writeByte(0x5C);
      if (c <= 0xFF) {
        switch (c) {
          0x22 => try writer.writeByte(0x22),
          0x5C => try writer.writeByte(0x5C),
          0x08 => try writer.writeByte(0x62),
          0x1B => try writer.writeByte(0x65),
          0x0C => try writer.writeByte(0x66),
          0x0A => try writer.writeByte(0x6E),
          0x0D => try writer.writeByte(0x72),
          0x09 => try writer.writeByte(0x74),
          else => try writer.print("u{X:04}", .{c}),
        }
      } else if (c <= 0xFFFF) {
        try writer.print("u{X:04}", .{c});
      } else if (c <= 0xFFFFFFFF) {
        try writer.print("U{X:08}", .{c});
      }
    } else {
      try writer.writeAll(s);
    }
  }
}