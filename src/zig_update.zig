const std = @import("std");
const builtin = @import("builtin");

const meta = @import("meta.zig");

const allocator = std.heap.page_allocator;

pub fn main() !void {
  const version_page = try get_version_page();
  defer allocator.free(version_page);
  const tarball_path = try get_tarball_path(version_page);
  const tarball_file = try download_tarball(tarball_path);
  defer tarball_file.close();
}

fn get_version_page() ![]u8 {
  const version_page_uri = "https://ziglang.org/download/index.json";

  std.log.info("json: {s}", .{version_page_uri});

  var http_client = std.http.Client{.allocator = allocator};
  defer http_client.deinit();
  var request = try http_client.request(
    .GET, 
    try std.Uri.parse(version_page_uri), 
    .{.allocator = allocator}, 
    .{});
  defer request.deinit();
  try request.start();
  try request.wait();
  return try request.reader().readAllAlloc(allocator, std.math.maxInt(u64));
}

fn get_tarball_path(version_page: []const u8) ![]const u8 {
  const version_name = @tagName(builtin.cpu.arch) ++ "-" ++ @tagName(builtin.os.tag);
  std.log.info("version: {s}", .{version_name});
  const version_type = meta.makeStruct(.{
    .{"master", meta.makeStruct(.{ 
      .{version_name, meta.makeStruct(.{
        .{"tarball", []const u8},
      })},
    })},
  });

  var version_json = try std.json.parseFromSlice(
    version_type, 
    allocator, 
    version_page, 
    .{.ignore_unknown_fields = true});
  defer version_json.deinit();
  const tarball_path = @field(version_json.value.master, version_name).tarball;
  std.log.info("tarball: {s}", .{tarball_path});
  return tarball_path;
}

fn download_tarball(tarball_path: []const u8) !std.fs.File {
  var http_client = std.http.Client{.allocator = allocator};
  defer http_client.deinit();
  
  var request = try http_client.request(
    .GET, 
    try std.Uri.parse(tarball_path), 
    .{.allocator = allocator}, 
    .{});
  defer request.deinit();
  
  try request.start();
  try request.wait();
  
  const tarball_byte = try request.reader().readAllAlloc(allocator, std.math.maxInt(u64));
  defer allocator.free(tarball_byte);

  const tarball_name = tarball_path[std.mem.lastIndexOfScalar(u8, tarball_path, '/').? + 1..];
  const tarball_file = try std.fs.cwd().createFile(tarball_name, .{});
  errdefer {
    tarball_file.close();
    std.fs.deleteFileAbsolute(tarball_name) catch unreachable;
  }
  try tarball_file.writeAll(tarball_byte);
  return tarball_file;
}