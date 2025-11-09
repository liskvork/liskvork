const builtin = @import("builtin");

const std = @import("std");

const logz = @import("logz");

const build_config = @import("build_config");

const utils = @import("utils.zig");
const config = @import("config.zig");
const client = @import("client.zig");
const Client = client.Client;
const game = @import("gomoku_game");

const WriteError = @import("std").posix.WriteError;

pub const Context = struct {
    const Self = @This();

    conf: *const config.Config,
    running: bool = true,
    game_launched: bool = false,
    board: game.Game,

    pub fn init(conf: *const config.Config, allocator: std.mem.Allocator) !Context {
        return .{
            .conf = conf,
            .board = try game.Game.init(conf.game_board_size, allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.board.deinit();
    }
};

fn dump_after_move(board_file: std.fs.File, ctx: *const Context, pos: game.Position, num_move: u16, num_player: u2, time_taken: i64) !void {
    const start = try std.fmt.allocPrint(
        utils.allocator,
        "Move {}:\nPlayer{}: {},{}\nTime: {d:.3}ms\n",
        .{
            num_move,
            num_player,
            pos[0],
            pos[1],
            @as(f32, @floatFromInt(time_taken)) / @as(f32, @floatFromInt(std.time.us_per_ms)),
        },
    );
    defer utils.allocator.free(start);

    try board_file.writeAll(start);
    try ctx.board.dump(board_file, ctx.conf.log_board_color, pos);
    try board_file.writeAll("\n\n");
}

fn call_winning_player(num_player: u2) void {
    if (num_player == 1) {
        logz.info().ctx("Player1 wins!").log();
    } else logz.info().ctx("Player2 wins!").log();
}

fn handle_player_error(e: anyerror, num_player: u2) !void {
    const winning_player: u2 = if (num_player == 1) 2 else 1;
    switch (e) {
        utils.ReadWriteError.TimeoutError => {
            logz.err().ctx("Player could not answer in the given time").int("player", num_player).log();
        },
        game.Error.OutOfBound => {
            logz.err().ctx("Player gave a move that's out of bounds").int("player", num_player).log();
        },
        game.Error.AlreadyTaken => {
            logz.err().ctx("Player gave a position that's already in use").int("player", num_player).log();
        },
        WriteError.BrokenPipe => {
            logz.err().ctx("Player has a broken pipe! Did your AI crash/close?").int("player", num_player).log();
        },
        else => {
            logz.err().ctx("Unhandled error").int("player", num_player).stringSafe("errorName", @errorName(e)).log();
        },
    }
    call_winning_player(winning_player);
}

pub fn launch_server(conf: *const config.Config) !void {
    var ctx = try Context.init(conf, utils.allocator);
    defer ctx.deinit();

    var read_buffer: [1024]u8 = undefined;
    var stdin = std.fs.File.stdin().reader(&read_buffer);

    const board_log_file = try std.fs.cwd().createFile(
        conf.log_board_file,
        .{},
    );
    defer board_log_file.close();

    var player1 = try Client.init(conf.player1_path, conf, 1);
    defer player1.deinit();
    var player2 = try Client.init(conf.player2_path, conf, 2);
    defer player2.deinit();
    try player1.start_process(&ctx);
    defer player1.stop_child(conf.other_end_grace_time);
    try player2.start_process(&ctx);
    defer player2.stop_child(conf.other_end_grace_time);

    var num_move: u16 = 1;

    if (!ctx.conf.other_auto_start) {
        logz.warn().ctx("auto_start is turned off! Press enter to start...").log();
        var buf: [10]u8 = undefined; // 10 is a magic number, doesn't matter
        _ = try stdin.interface.adaptToOldInterface().readUntilDelimiterOrEof(&buf, '\n');
        logz.info().ctx("Starting...").log();
    }

    var start_time = std.time.microTimestamp();
    var pos1 = player1.begin() catch |e| return handle_player_error(e, 1);
    var end_time = std.time.microTimestamp();
    _ = ctx.board.place(pos1, .Player1) catch |e| return handle_player_error(e, 1); // Is never a winning move
    try dump_after_move(board_log_file, &ctx, pos1, num_move, 1, end_time - start_time);
    try while (true) {
        start_time = std.time.microTimestamp();
        const pos2 = player2.turn(pos1) catch |e| break handle_player_error(e, 2);
        end_time = std.time.microTimestamp();
        const pos2_win = ctx.board.place(pos2, .Player2) catch |e| break handle_player_error(e, 1);
        num_move += 1;
        try dump_after_move(board_log_file, &ctx, pos2, num_move, 2, end_time - start_time);
        if (pos2_win) {
            logz.info().ctx("Player 2 wins!").log();
            break;
        }
        if (num_move >= ctx.conf.game_board_size * ctx.conf.game_board_size) {
            logz.info().ctx("I don't know how you did it, but it's a tie! The board is full.").log();
            break;
        }

        start_time = std.time.microTimestamp();
        pos1 = player1.turn(pos2) catch |e| break handle_player_error(e, 1);
        end_time = std.time.microTimestamp();
        const pos1_win = ctx.board.place(pos1, .Player1) catch |e| break handle_player_error(e, 1);
        num_move += 1;
        try dump_after_move(board_log_file, &ctx, pos1, num_move, 1, end_time - start_time);
        if (pos1_win) {
            logz.info().ctx("Player 1 wins!").log();
            break;
        }
        if (num_move >= ctx.conf.game_board_size * ctx.conf.game_board_size) {
            logz.info().ctx("I don't know how you did it, but it's a tie! The board is full.").log();
            break;
        }
    };

    if (!ctx.conf.other_auto_close) {
        logz.warn().ctx("auto_close is turned off! Press enter to close...").log();
        var buf: [10]u8 = undefined; // 10 is a magic number, doesn't matter
        _ = try stdin.interface.adaptToOldInterface().readUntilDelimiterOrEof(&buf, '\n');
        logz.info().ctx("Closing...").log();
    }
}
