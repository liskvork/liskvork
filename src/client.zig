const std = @import("std");

const logz = @import("logz");

const build_config = @import("build_config");

const server = @import("server.zig");
const utils = @import("utils.zig");
const command = @import("command.zig");
const game = @import("game.zig");
const config = @import("config.zig");

const ClientState = enum {
    WaitingForHandshake,
    WaitingForRole,
    SWaitingForStart,
    PWaitingForStart,
    PWaitingForStartAnswer,
    PWaitingForOtherPlayer,
    PWaitingForTurn,
};

const ClientType = enum {
    Player,
    Spectator,
};

const ServerInfo = union(enum) {
    timeout_turn: u64,
    timeout_match: u64,
    max_memory: u64,
    time_left: u64,
};

const EndStatus = enum {
    WIN,
    LOSE,
    TIE,
    ERROR,
};

pub const Client = struct {
    const Self = @This();

    stopping: bool = false,
    state: ClientState = ClientState.WaitingForHandshake,
    infos: ?command.ClientResponseAbout = null,
    filepath: []const u8,
    match_time_remaining: u64,
    turn_time: u64,
    proc: std.process.Child,
    read_buf: std.ArrayList(u8),

    pub fn init(filepath: []const u8, conf: *const config.Config) !Client {
        return .{
            .filepath = try utils.allocator.dupe(u8, filepath),
            .match_time_remaining = conf.game_timeout_match,
            .turn_time = conf.game_timeout_turn,
            .proc = std.process.Child.init(.{filepath}, utils.allocator),
            .read_buf = std.ArrayList(u8).init(utils.allocator),
        };
    }

    pub fn start_process(self: *Self, ctx: *const server.Context) !void {
        self.proc.stdout_behavior = .Pipe;
        self.proc.stdin_behavior = .Pipe;
        self.proc.stdout_behavior = .Ignore;

        logz.debug().ctx("Spawning process").string("filepath", self.filepath).log();
        try self.proc.spawn();
        // TODO: Get basic info from the process

        try self.send_about();
        // <- name...
        try self.send_start(ctx);
        // <- OK

        // ALL GOOD
    }

    fn send_message(self: *Self, msg: []const u8) !void {
        logz.debug().ctx("Sending message").string("data", msg).log();
        // Not sure if this can block at all, but it will for for now
        try self.proc.stdin.?.writeAll(msg);
    }

    fn get_command_with_timeout(self: *Self, timeout: i32) !?command.ClientCommand {
        return try command.parse(try self.get_line_with_timeout(timeout), utils.allocator);
    }

    // That needs hella testing lmao
    fn get_line_with_timeout(self: *Self, timeout: i32) !void {
        var left_timeout: i32 = timeout * std.time.us_per_ms;
        const start_time = std.time.microTimestamp();
        const tmp_rd_buf: [256]u8 = undefined;
        while (true) {
            const nb_read = try utils.read_with_timeout(self.proc.stdout, &tmp_rd_buf, left_timeout / std.time.us_per_ms);
            try self.read_buf.appendSlice(tmp_rd_buf[0..nb_read]);
            if (std.mem.indexOf(u8, self.read_buf.items, "\n")) |i| {
                const line = try utils.allocator.dupe(u8, self.read_buf.items[0 .. i + 1]);
                const rest = self.read_buf.items[i + 1 ..];
                std.mem.copyForwards(u8, self.read_buf.items, rest);
                self.read_buf.shrinkRetainingCapacity(rest.len);
                return line;
            }
            const current_time = std.time.microTimestamp();
            left_timeout = @max(0, timeout - (start_time - current_time));
        }
    }

    fn send_format_message(self: *Self, comptime fmt: []const u8, args: anytype) !void {
        const to_send = try std.fmt.allocPrint(utils.allocator, fmt, args);
        defer utils.allocator.free(to_send);
        try self.send_message(to_send);
    }

    fn send_about(self: *Self) !void {
        try self.send_message("ABOUT\r\n");
    }

    fn send_ok(self: *Self) !void {
        try self.send_message("OK\r\n");
    }

    fn send_info_no_check(self: *Self, T: type, name: []const u8, val: T, allocator: std.mem.Allocator) !void {
        switch (T) {
            u64 => try self.send_format_message("INFO {s} {}\r\n", .{ name, val }, allocator),
            else => @compileError("Missing serializer for send_info_no_check for type " ++ @typeName(T)),
        }
    }

    fn send_info(self: *Self, info: ServerInfo, allocator: std.mem.Allocator) !void {
        switch (info) {
            .timeout_turn,
            .timeout_match,
            .max_memory,
            .time_left,
            => |v| try self.send_info_no_check(
                @TypeOf(v),
                @tagName(info),
                v,
                allocator,
            ),
        }
    }

    fn send_all_infos(self: *Self, ctx: *const server.Context) !void {
        try self.send_info(.{ .timeout_turn = ctx.conf.game_timeout_turn });
        try self.send_info(.{ .timeout_match = ctx.conf.game_timeout_match });
        try self.send_info(.{ .max_memory = ctx.conf.game_max_memory });
    }

    fn send_ko(self: *Self, msg: ?[]const u8) !void {
        if (msg) |m| {
            try self.send_format_message("KO {s}\r\n", .{m});
        } else try self.send_message("KO\r\n");
    }

    fn send_begin(self: *Self) !void {
        try self.send_message("BEGIN\r\n");
    }

    fn send_turn(self: *Self, pos: game.Position) !void {
        try self.send_format_message("TURN {},{}\r\n", .{ pos[0], pos[1] });
    }

    fn send_start(self: *Self, ctx: *const server.Context) !void {
        try self.send_format_message("START {}\r\n", .{ctx.conf.game_board_size});
    }

    fn send_end_no_check(self: *Self, status: []const u8, msg: ?[]const u8) !void {
        try self.send_format_message("END {s} \"{s}\"\r\n", .{ status, msg orelse "" });
    }

    fn send_end(self: *Self, status: EndStatus, msg: ?[]const u8) !void {
        try self.send_end_no_check(@tagName(status), msg);
    }

    pub fn start(self: *Self, ctx: *const server.Context) !void {
        try self.send_start(ctx);
        self.state = ClientState.PWaitingForStartAnswer;
    }

    pub fn begin(self: *Self) !void {
        try self.send_begin();
        self.state = .PWaitingForTurn;
    }

    fn handle_log(self: *Self, l: *const command.ClientCommandLog) void {
        std.debug.assert(self.infos != null);
        switch (l.msg_type) {
            .Info => logz.info().ctx("info from client").string("name", self.infos.?.name).string("msg", l.data).log(),
            .Error => logz.info().ctx("error from client").string("name", self.infos.?.name).string("msg", l.data).log(),
            .Debug => logz.info().ctx("debug from client").string("name", self.infos.?.name).string("msg", l.data).log(),
            .Unknown => logz.warn().ctx("unknown from client").string("name", self.infos.?.name).string("msg", l.data).log(),
        }
    }

    pub fn stop_child(self: *const Self) !void {
        // -> END

        const seconds_to_wait_after_end = 1;
        std.time.sleep(seconds_to_wait_after_end * std.time.ns_per_s);
        _ = try self.proc.kill(); // This won't kill the process if it is already gone
    }

    pub fn deinit(self: *const Self) void {
        if (self.infos) |i|
            i.deinit();
        utils.allocator.free(self.filepath);
        self.read_buf.deinit();
    }
};

test {
    std.testing.refAllDecls(@This());
}
