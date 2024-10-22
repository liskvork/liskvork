const std = @import("std");

const logz = @import("logz");

const build_config = @import("build_config");

const server = @import("server.zig");
const utils = @import("utils.zig");
const command = @import("command.zig");
const game = @import("game.zig");

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

    // TODO: Init properly with a pipe communication
    pub fn init(filepath: []const u8) !Client {
        _ = filepath;
    }

    fn send_message(self: *Self, msg: []const u8) !void {
        _ = self;
        logz.debug().ctx("Sending message").string("data", msg).log();
        // TODO: Send the messages to the brain

        // try self.internal_wbuffer.appendSlice(msg);
    }

    fn send_format_message(self: *Self, comptime fmt: []const u8, args: anytype, allocator: std.mem.Allocator) !void {
        const to_send = try std.fmt.allocPrint(allocator, fmt, args);
        defer allocator.free(to_send);
        try self.send_message(to_send);
    }

    fn send_handshake(self: *Self, ctx: *const server.Context) !void {
        try self.send_message(ctx.cache.handshake);
    }

    fn send_ok(self: *Self) !void {
        try self.send_message("OK\n");
    }

    fn send_info_no_check(self: *Self, T: type, name: []const u8, val: T, allocator: std.mem.Allocator) !void {
        switch (T) {
            u64 => try self.send_format_message("INFO {s} {}\n", .{ name, val }, allocator),
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

    fn send_all_infos(self: *Self, ctx: *const server.Context, allocator: std.mem.Allocator) !void {
        try self.send_info(.{ .timeout_turn = ctx.conf.game_timeout_turn }, allocator);
        try self.send_info(.{ .timeout_match = ctx.conf.game_timeout_match }, allocator);
        try self.send_info(.{ .max_memory = ctx.conf.game_max_memory }, allocator);
    }

    fn send_ko(self: *Self, msg: ?[]const u8, allocator: std.mem.Allocator) !void {
        if (msg) |m| {
            try self.send_format_message("KO {s}\n", .{m}, allocator);
        } else try self.send_message("KO\n");
    }

    fn send_begin(self: *Self) !void {
        try self.send_message("BEGIN\n");
    }

    fn send_turn(self: *Self, pos: game.Position, allocator: std.mem.Allocator) !void {
        try self.send_format_message("TURN {},{}\n", .{ pos[0], pos[1] }, allocator);
    }

    fn send_start(self: *Self, ctx: *const server.Context, allocator: std.mem.Allocator) !void {
        try self.send_format_message("START {}\n", .{ctx.conf.game_board_size}, allocator);
    }

    fn send_end_no_check(self: *Self, status: []const u8, msg: ?[]const u8, allocator: std.mem.Allocator) !void {
        try self.send_format_message("END {s} \"{s}\"\n", .{ status, msg orelse "" }, allocator);
    }

    fn send_end(self: *Self, status: EndStatus, msg: ?[]const u8, allocator: std.mem.Allocator) !void {
        try self.send_end_no_check(@tagName(status), msg, allocator);
    }

    pub fn start(self: *Self, ctx: *const server.Context, allocator: std.mem.Allocator) !void {
        try self.send_start(ctx, allocator);
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

    pub fn handle_logic(self: *Self, ctx: *server.Context) !void {
        _ = self;
        _ = ctx;
    }

    pub fn deinit(self: *const Self) void {
        if (self.infos) |i|
            i.deinit();
    }
};

test {
    std.testing.refAllDecls(@This());
}
