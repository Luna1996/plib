const std = @import("std");

pub fn unescape(allocator: std.mem.Allocator, str: []const u8) ![]u8 {
  var res = try allocator.alloc(u8, str.len);
  errdefer allocator.free(res);
  var i: usize = 0;
  var j: usize = 0;
  while (i < str.len) {
    const c1 = str[i];
    if (c1 != '\\') 
              { res[j] = c1  ; i += 1; j += 1; continue; }
    const c2 = str[i + 1]; switch (c2) {
      0x22 => { res[j] = 0x22; i += 2; j += 1; },
      0x5C => { res[j] = 0x5C; i += 2; j += 1; },
      0x62 => { res[j] = 0x08; i += 2; j += 1; },
      0x65 => { res[j] = 0x1B; i += 2; j += 1; },
      0x66 => { res[j] = 0x0C; i += 2; j += 1; },
      0x6E => { res[j] = 0x0A; i += 2; j += 1; },
      0x72 => { res[j] = 0x0D; i += 2; j += 1; },
      0x74 => { res[j] = 0x09; i += 2; j += 1; },
      else => {
        const n: usize = switch (c2) { 0x78 => 2, 0x75 => 4, 0x55 => 8, else => unreachable };
        const u = try std.fmt.parseUnsigned(u21, str[i + 2..][0..n], 16);
        i += 2 + n;
        j += try std.unicode.utf8Encode(u, res[j..][0..4]);
      }
    }
  }
  return try allocator.realloc(res, j);
}

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
    0xB2, 0xB3, 0xB9, 0xBC, 0xBD,
    0xBE, 0xC0...0xD6, 0xD8...0xF6,
    0x00F8...0x037D, 0x037F...0x1FFF,
    0x200C,  0x200D, 0x203F...0x2040,
    0x2070...0x218F, 0x2460...0x24FF,
    0x2C00...0x2FEF, 0x3001...0xD7FF,
    0xF900...0xFDCF, 0xFDF0...0xFFFD,
    0x10000...0xEFFFF,
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
      try writer.writeByte(0x5C);
      switch (c) {
        0x22 => try writer.writeByte(0x22),
        0x5C => try writer.writeByte(0x5C),
        0x08 => try writer.writeByte(0x62),
        0x1B => try writer.writeByte(0x65),
        0x0C => try writer.writeByte(0x66),
        0x0A => try writer.writeByte(0x6E),
        0x0D => try writer.writeByte(0x72),
        0x09 => try writer.writeByte(0x74),
        else => {},
      }
      if (c <= 0xFF) {
        try writer.print("x{X:02}", .{c});
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