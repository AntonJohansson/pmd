const std = @import("std");
const client = @import("client.zig");

pub fn bind(i: i32) void {
    std.log.info("wow {}", .{i});
}

pub fn connect(ip: []const u8, port: u16) void {
    client.connect(ip, port);
}
