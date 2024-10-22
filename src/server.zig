const builtin = @import("builtin");

const std = @import("std");

const logz = @import("logz");

const build_config = @import("build_config");

const utils = @import("utils.zig");
const config = @import("config.zig");
const client = @import("client.zig");
const Client = client.Client;
const game = @import("game.zig");

const Cache = struct {
    const Self = @This();

    handshake: []const u8,
    players: [2]?*Client = .{ null, null },

    fn init(conf: *const config.Config) !Cache {
        const hs = try std.fmt.allocPrint(
            utils.allocator,
            "HELLO {s} {s} \"{s}\"\n",
            .{ build_config.bin_name, build_config.version, conf.other_motd },
        );
        return .{
            .handshake = hs,
        };
    }

    fn deinit(self: *const Self) void {
        utils.allocator.free(self.handshake);
    }
};

pub const Context = struct {
    const Self = @This();

    conf: *const config.Config,
    running: bool = true,
    cache: Cache,
    game_launched: bool = false,
    board: game.Game,

    pub fn init(conf: *const config.Config) !Context {
        return .{
            .conf = conf,
            .cache = try Cache.init(conf),
            .board = try game.Game.init(conf.game_board_size),
        };
    }

    pub fn deinit(self: *Self) void {
        self.cache.deinit();
        self.board.deinit();
    }
};

pub fn launch_server(conf: *const config.Config) !void {
    var ctx = try Context.init(conf);
    defer ctx.deinit();

    while (ctx.running) {
        break;
    }
}

test {
    std.testing.refAllDecls(@This());
}
