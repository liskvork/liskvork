const builtin = @import("builtin");

const std = @import("std");

const logz = @import("logz");

const build_config = @import("build_config");

const utils = @import("utils.zig");
const config = @import("config.zig");
const client = @import("client.zig");
const Client = client.Client;
const game = @import("game.zig");

pub const Context = struct {
    const Self = @This();

    conf: *const config.Config,
    running: bool = true,
    game_launched: bool = false,
    board: game.Game,

    pub fn init(conf: *const config.Config) !Context {
        return .{
            .conf = conf,
            .board = try game.Game.init(conf.game_board_size),
        };
    }

    pub fn deinit(self: *Self) void {
        self.board.deinit();
    }
};

pub fn launch_server(conf: *const config.Config) !void {
    var ctx = try Context.init(conf);
    defer ctx.deinit();

    var player1 = try Client.init(conf.game_player1, conf);
    defer player1.deinit();
    var player2 = try Client.init(conf.game_player2, conf);
    defer player2.deinit();
    try player1.start_process(&ctx);
    try player2.start_process(&ctx);

    var pos1 = try player1.begin(&ctx);
    _ = try ctx.board.place(pos1, .Player1); // Is never a winning move
    while (true) {
        const pos2 = try player2.turn(&ctx, pos1);
        const pos2_win = try ctx.board.place(pos2, .Player2);
        if (pos2_win) {
            logz.info().ctx("Player 2 wins!").log();
            break;
        }

        pos1 = try player1.turn(&ctx, pos2);
        const pos1_win = try ctx.board.place(pos1, .Player1);
        if (pos1_win) {
            logz.info().ctx("Player 1 wins!").log();
            break;
        }
    }

    try player1.stop_child();
    try player2.stop_child();
}

test {
    std.testing.refAllDecls(@This());
}
