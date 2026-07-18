const std = @import("std");
const config = @import("config.zig");
const client = @import("client.zig");
const utils = @import("utils.zig");

const Self = @This();

file: std.Io.File = undefined,
write_buffer: [128]u8 = undefined,
file_writer: std.Io.File.Writer = undefined,
writer: *std.Io.Writer = undefined,

pub const Error = error{
    FileNotOpen,
};

fn dump_header(self: *Self, conf: *const config.Config, p1: client.Client, p2: client.Client) !void {
    try self.writer.print(
        "{d}\n{d} {d}\n{d} {d}\n{d} {d}\n{s}\n{s}\n---\n",
        .{
            conf.game_board_size,
            conf.player1_timeout_match,
            conf.player2_timeout_match,
            conf.player1_timeout_turn,
            conf.player2_timeout_turn,
            conf.game_max_memory,
            conf.game_max_memory,
            p1.name,
            p2.name,
        },
    );
    try self.writer.flush();
}

pub fn init(dir: std.Io.Dir, path: []const u8, conf: *const config.Config, p1: client.Client, p2: client.Client) !*Self {
    const file = try dir.createFile(utils.io, path, .{});
    const p = try utils.allocator.create(Self);
    p.* = .{
        .file = file,
    };
    p.file_writer = p.file.writer(utils.io, &p.write_buffer);
    p.writer = &p.file_writer.interface;
    try p.dump_header(conf, p1, p2);
    return p;
}

pub fn write_move(self: *Self, ts: i64, id: u2, x: usize, y: usize, time_taken: i64) !void {
    try self.writer.print("{d}:{d}:{d} {d} {d}\n", .{
        ts,
        id,
        x,
        y,
        time_taken,
    });
    try self.writer.flush();
}

pub fn write_event(self: *Self, ts: i64, id: u2, event: []const u8) !void {
    try self.writer.print("{d}:{d}:{s}\n", .{ ts, id, event });
    try self.writer.flush();
}

pub fn deinit(self: *Self) void {
    self.writer.flush() catch {};
    self.file.close(utils.io);
    utils.allocator.destroy(self);
}
