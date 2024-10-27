const builtin = @import("builtin");

const std = @import("std");

const logz = @import("logz");

const build_config = @import("build_config");

const utils = @import("utils.zig");
const config = @import("config.zig");
const client = @import("client.zig");
const Client = client.Client;
const game = @import("game.zig");
const Web = @import("web.zig");

pub const Context = struct {
    const Self = @This();

    conf: *const config.Config,
    running: bool = true,
    game_launched: bool = false,
    board: game.Game,
    web_srv: Web.Server,

    pub fn init(conf: *const config.Config) !Context {
        return .{
            .conf = conf,
            .board = try game.Game.init(conf.game_board_size),
            .web_srv = if (conf.web_enable) try Web.Server.init(conf) else undefined,
        };
    }

    pub fn deinit(self: *Self) void {
        self.board.deinit();
        if (self.conf.web_enable)
            self.web_srv.deinit();
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
        else => return e,
    }
    call_winning_player(winning_player);
}

pub fn launch_server(conf: *const config.Config) !void {
    var ctx = try Context.init(conf);
    defer ctx.deinit();

    const stdin = std.io.getStdIn().reader();

    if (conf.web_enable)
        try ctx.web_srv.launch_in_background();

    const board_log_file = try std.fs.cwd().createFile(
        conf.log_board_file,
        .{},
    );
    defer board_log_file.close();

    var player1 = try Client.init(conf.game_player1, conf);
    defer player1.deinit();
    var player2 = try Client.init(conf.game_player2, conf);
    defer player2.deinit();
    try player1.start_process(&ctx);
    defer player1.stop_child() catch @panic("How?");
    try player2.start_process(&ctx);
    defer player2.stop_child() catch @panic("How?");

    var num_move: u16 = 1;

    if (!ctx.conf.other_auto_start) {
        logz.warn().ctx("auto_start is turned off! Press enter to start...").log();
        var buf: [10]u8 = undefined; // 10 is a magic number, doesn't matter
        _ = try stdin.readUntilDelimiterOrEof(&buf, '\n');
        logz.info().ctx("Starting...").log();
    }

    var start_time = std.time.microTimestamp();
    var pos1 = player1.begin(&ctx) catch |e| return handle_player_error(e, 1);
    var end_time = std.time.microTimestamp();
    _ = ctx.board.place(pos1, .Player1) catch |e| return handle_player_error(e, 1); // Is never a winning move
    if (conf.web_enable) try ctx.web_srv.push_move(pos1, .Player1);
    try dump_after_move(board_log_file, &ctx, pos1, num_move, 1, end_time - start_time);
    try while (true) {
        start_time = std.time.microTimestamp();
        const pos2 = player2.turn(&ctx, pos1) catch |e| break handle_player_error(e, 1);
        end_time = std.time.microTimestamp();
        const pos2_win = ctx.board.place(pos2, .Player2) catch |e| break handle_player_error(e, 1);
        if (conf.web_enable) try ctx.web_srv.push_move(pos2, .Player2);
        num_move += 1;
        try dump_after_move(board_log_file, &ctx, pos2, num_move, 2, end_time - start_time);
        if (pos2_win) {
            logz.info().ctx("Player 2 wins!").log();
            break;
        }
        if (num_move >= 200) {
            logz.info().ctx("I don't know how you did it, but it's a tie! The board is full.").log();
            break;
        }

        start_time = std.time.microTimestamp();
        pos1 = player1.turn(&ctx, pos2) catch |e| break handle_player_error(e, 1);
        end_time = std.time.microTimestamp();
        const pos1_win = ctx.board.place(pos1, .Player1) catch |e| break handle_player_error(e, 1);
        if (conf.web_enable) try ctx.web_srv.push_move(pos1, .Player1);
        num_move += 1;
        try dump_after_move(board_log_file, &ctx, pos1, num_move, 1, end_time - start_time);
        if (pos1_win) {
            logz.info().ctx("Player 1 wins!").log();
            break;
        }
    };

    if (!ctx.conf.other_auto_close) {
        logz.warn().ctx("auto_close is turned off! Press enter to close...").log();
        var buf: [10]u8 = undefined; // 10 is a magic number, doesn't matter
        _ = try stdin.readUntilDelimiterOrEof(&buf, '\n');
        logz.info().ctx("Closing...").log();
    }
}

test {
    std.testing.refAllDecls(@This());
}
