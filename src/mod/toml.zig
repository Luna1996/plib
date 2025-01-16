const std = @import("std");
const plib = @import("plib");
const Parser = plib.Parser(@import("gen").abnf);
const Tag = Parser.Tag;
const Node = Parser.Node;

const allocator = std.testing.allocator;

var ok: usize = 0;
var no: usize = 0;

test "toml" {
  std.debug.print("\n", .{});
  var dir = try std.fs.cwd().openDir("../../toml-test/valid", .{.iterate = true});
  defer dir.close();
  try testDir(dir);
  std.debug.print("[{d}/{d}/{d}]", .{ no, ok, ok + no });
}

fn testDir(dir: std.fs.Dir) !void {
  var iter = dir.iterate();
  while (try iter.next()) |item| switch (item.kind) {
    .directory => {
      var sub = try dir.openDir(item.name, .{.iterate = true});
      defer sub.close();
      try testDir(sub);
    },
    .file => {
      if (!std.mem.endsWith(u8, item.name, ".toml")) continue;
      const file_text = try dir.readFileAlloc(allocator, item.name, std.math.maxInt(usize));
      defer allocator.free(file_text);
      const real_path = try dir.realpathAlloc(allocator, item.name);
      defer allocator.free(real_path);
      const result = try Parser.parse(.{
        .allocator = allocator,
        .file_path = real_path,
        .input = file_text,
        .keeps = &.{
          .toml, .expression, .key, .val, .table, .comment,
        },
      });
      defer result.root.deinit();
      if (result.fail) |fail| {
        no += 1;
        std.debug.print("{}", .{fail});
      } else {
        ok += 1;
      }
    },
    else => {},
  };
}