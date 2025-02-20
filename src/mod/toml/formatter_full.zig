const Self = @This();

const std = @import("std");
const Toml = @import("root.zig").Toml;
const Ast = Toml.Ast;

ast: Ast