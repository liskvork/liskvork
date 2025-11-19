const std = @import("std");
const clap = @import("clap");
const utils = @import("utils.zig");

const help =
    \\-h, --help                Display this help message.
    \\--init-config             Initialize config or reset to default (config.ini).
    \\-c, --config <PATH>       Set the config path
    \\--player1 <PATH>          Override the path to the player1 brain.
    \\--player2 <PATH>          Override the path to the player2 brain.
    \\-o, --output <OUT>        Set board output (defaults to config).
    \\-s, --size <SIZE>         Set board size.
    \\-m, --memory <MEM>        Set the maximum memory available for brains.
    \\-r, --replay-file <PATH>  Override the path to the replay output.
    \\--no-replay               Disable replay file output.
;
const params = clap.parseParamsComptime(help);

pub const Args = struct {
    // Config Overrides
    player1_path: ?[]const u8,
    player2_path: ?[]const u8,
    log_board_file: ?[]const u8,
    log_replay_file: ?[]const u8,
    game_board_size: ?u32,
    game_max_memory: ?u64,

    // Other flags
    help_flag: bool,
    init_config: bool,
    config_path: []const u8,
    no_replay: bool,
};

pub fn handle() !Args {
    const parsers = comptime .{
        .PATH = clap.parsers.string,
        .OUT = clap.parsers.string,
        .SIZE = clap.parsers.int(u32, 10),
        .MEM = clap.parsers.int(u64, 10),
    };

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, parsers, .{ .diagnostic = &diag, .allocator = utils.allocator, .assignment_separators = "=" }) catch |err| {
        try diag.reportToFile(.stderr(), err);
        return err;
    };
    defer res.deinit();

    return Args{
        .help_flag = res.args.help != 0,
        .init_config = res.args.@"init-config" != 0,
        .config_path = res.args.config orelse "config.ini",

        .player1_path = res.args.player1,
        .player2_path = res.args.player2,
        .log_board_file = res.args.output,
        .log_replay_file = res.args.@"replay-file",
        .no_replay = res.args.@"no-replay" != 0,
        .game_board_size = res.args.size,
        .game_max_memory = res.args.memory,
    };
}

pub fn print_help() !void {
    const args = try std.process.argsAlloc(utils.allocator);
    defer std.process.argsFree(utils.allocator, args);

    std.debug.print("USAGE: {s} ", .{args[0]});
    try clap.usageToFile(.stderr(), clap.Help, &params);
    std.debug.print("\n", .{});
    try clap.helpToFile(.stderr(), clap.Help, &params, .{});
}
