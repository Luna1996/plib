const std = @import("std");
const plib = @import("plib");
const Parser = plib.Parser(@import("gen").abnf);
const Tag = Parser.Tag;
const Node = Parser.Node;

test "toml" {
  const file_path = "C:/code/toml-test/valid/spec-example-1-compact.toml";
  const allocator = std.testing.allocator;
  const file_text = try std.fs.cwd().readFileAlloc(allocator, file_path, std.math.maxInt(usize));
  defer allocator.free(file_text);
  const result = try Parser.parse(.{
    .allocator = allocator,
    .file_path = file_path,
    .input = file_text,
    .keeps = &.{
      .toml, .expression,
    },
  });
  defer result.root.deinit();
  std.debug.print("\n{}", .{result.root});
  if (result.fail) |fail| std.debug.print("{}", .{fail});
}