//! ZIP File Format Specification 6.3.10
//! https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT

const std = @import("std");

const Signature = struct {
  const LocalFileHeader = 0x04034b50;
  const CentralFileHeader = 0x02014b50;
};

/// - `file_path` path to input file.
/// - `output_path` path to output directory.
pub fn unzip(allocator: std.mem.Allocator ,file_path: []const u8, output_path: []const u8) !void {
  var output_buffer: [4096]u8 = undefined;
  const output_dir = try std.fs.cwd().makeOpenPath(output_path, .{});
  const input_file = try std.fs.cwd().openFile(file_path, .{});
  defer input_file.close();
  const reader = input_file.reader();
  while (true) {
    const signature = try reader.readIntLittle(u32);
    switch (signature) {
      Signature.LocalFileHeader => {
        try input_file.seekBy(2);
        const general_purpose_bit_flag = try reader.readIntLittle(u16);
        std.debug.assert((general_purpose_bit_flag & 0b1000 == 0));
        const compression_method = try reader.readIntLittle(u16);
        try input_file.seekBy(8);
        const compressed_size = try reader.readIntLittle(u32);
        try input_file.seekBy(4);
        const file_name_length = try reader.readIntLittle(u16);
        const extra_field_length = try reader.readIntLittle(u16);
        var file_name = output_buffer[0..file_name_length];
        _ = try reader.readAll(file_name);
        std.debug.print("{s}\n", .{file_name});
        try input_file.seekBy(extra_field_length);
        if (file_name[file_name.len - 1] == '/') { continue; }
        if (std.fs.path.dirname(file_name)) |dir_name| {
          try output_dir.makePath(dir_name);
        }
        const output_file = try output_dir.createFile(file_name, .{});
        defer output_file.close();
        const a = try input_file.getPos();
        switch (compression_method) {
          0 => {
            try output_file.writeFileAll(input_file, .{ .in_offset = try input_file.getPos(), .in_len = compressed_size });
            try input_file.seekBy(compressed_size);
          },
          8 => {
            var limited_reader = std.io.limitedReader(reader, compressed_size);
            var decompressor = try std.compress.deflate.decompressor(allocator, limited_reader.reader(), null);
            defer decompressor.deinit();
            const decompressor_reader = decompressor.reader();
            while (true) {
              const readed_length = try decompressor_reader.readAll(&output_buffer);
              try output_file.writeAll(output_buffer[0..readed_length]);
              if (readed_length < output_buffer.len) break;
            }
          },
          else => {
            std.debug.print("Unknown compression method {d} at {X:0>8}\n", .{compression_method, try input_file.getPos()});
            return error.UnknownCompressionMethod;
          }
        }
        const b = try input_file.getPos();
        std.debug.assert(b - a == compressed_size);
      },
      Signature.CentralFileHeader => return,
      else => {
        std.debug.print("Unknown signature 0x{x:0>8} at {X:0>8}\n", .{signature, try input_file.getPos()});
        return error.UnknownSignature;
      },
    }
  }
}

test unzip {
  std.debug.print("\n", .{});
  try unzip(std.testing.allocator, "zig-windows-x86_64-0.12.0-dev.177+3b2b9fcbc.zip", "");
}