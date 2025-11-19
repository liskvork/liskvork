const std = @import("std");
const config = @import("config.zig");
const client = @import("client.zig");
const utils = @import("utils.zig");

const Self = @This();

file: std.fs.File = undefined,

pub const Error = error{
    FileNotOpen,
};

fn dump_header(self: *Self, conf: *const config.Config, p1: client.Client, p2: client.Client) !void {
    const header = try std.fmt.allocPrint(
        utils.allocator,
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
    defer utils.allocator.free(header);

    try self.file.writeAll(header);
}

pub fn init(dir: std.fs.Dir, path: []const u8, conf: *const config.Config, p1: client.Client, p2: client.Client) !*Self {
    const file = try dir.createFile(path, .{});
    const p = try utils.allocator.create(Self);
    p.* = .{
        .file = file,
    };
    try p.dump_header(conf, p1, p2);
    return p;
}

// TODO: Rewrite all those allocs to be within a static buffer
// there is absolutely no need for dynamic allocation here
fn write_line(self: *Self, ts: i64, id: u2, msg: []const u8) !void {
    const line = try std.fmt.allocPrint(utils.allocator, "{d}:{d}:{s}\n", .{ ts, id, msg });
    defer utils.allocator.free(line);
    try self.file.writeAll(line);
}

pub fn write_move(self: *Self, ts: i64, id: u2, x: usize, y: usize, time_taken: i64) !void {
    const msg = try std.fmt.allocPrint(utils.allocator, "{d} {d} {d}", .{ x, y, time_taken });
    defer utils.allocator.free(msg);
    try self.write_line(ts, id, msg);
}

pub fn write_event(self: *Self, ts: i64, id: u2, event: []const u8) !void {
    try self.write_line(ts, id, event);
}

pub fn deinit(self: *Self) void {
    self.file.close();
    utils.allocator.destroy(self);
}
