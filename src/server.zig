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

fn dump_after_move(board_file: std.fs.File, ctx: *const Context, pos: game.Position, num_move: u16, num_player: u2) !void {
    const start = try std.fmt.allocPrint(
        utils.allocator,
        "Move {}:\nPlayer{}: {},{}\n",
        .{
            num_move,
            num_player,
            pos[0],
            pos[1],
        },
    );
    defer utils.allocator.free(start);

    try board_file.writeAll(start);
    try ctx.board.dump(board_file);
    try board_file.writeAll("\n\n");
}

pub fn launch_server(conf: *const config.Config) !void {
    var ctx = try Context.init(conf);
    defer ctx.deinit();

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
    try player2.start_process(&ctx);

    var num_move: u16 = 1;
    var pos1 = try player1.begin(&ctx);
    _ = try ctx.board.place(pos1, .Player1); // Is never a winning move
    try dump_after_move(board_log_file, &ctx, pos1, num_move, 1);
    while (true) {
        const pos2 = try player2.turn(&ctx, pos1);
        const pos2_win = try ctx.board.place(pos2, .Player2);
        num_move += 1;
        try dump_after_move(board_log_file, &ctx, pos2, num_move, 2);
        if (pos2_win) {
            logz.info().ctx("Player 2 wins!").log();
            break;
        }

        pos1 = try player1.turn(&ctx, pos2);
        const pos1_win = try ctx.board.place(pos1, .Player1);
        num_move += 1;
        try dump_after_move(board_log_file, &ctx, pos1, num_move, 1);
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
