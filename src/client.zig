const std = @import("std");

const net = @import("network");
const logz = @import("logz");

const Message = @import("message.zig").Message;
const server = @import("server.zig");
const utils = @import("utils.zig");

const ClientState = enum {
    WaitingForHandshake,
    WaitingForRole,
    SWaitingForStart,
    PWaitingForStart,
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

const GamePosition = @Vector(2, u32);

pub const Client = struct {
    const Self = @This();

    sock: net.Socket,
    msg: std.ArrayList(Message),
    internal_rbuffer: std.ArrayList(u8),
    internal_wbuffer: std.ArrayList(u8),
    stopping: bool = false,
    state: ClientState = ClientState.WaitingForHandshake,
    ctype: ?ClientType = null,

    pub fn init(allocator: std.mem.Allocator, sock: net.Socket) Client {
        return .{
            .sock = sock,
            .msg = std.ArrayList(Message).init(allocator),
            .internal_rbuffer = std.ArrayList(u8).init(allocator),
            .internal_wbuffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn create_messages(self: *Self, allocator: std.mem.Allocator) !void {
        while (std.mem.indexOfPos(
            u8,
            self.internal_rbuffer.items,
            0,
            "\n",
        )) |i| {
            const msg_slice = self.internal_rbuffer.items[0..i];
            try self.msg.append(try Message.init(msg_slice, allocator));
            logz.debug().ctx("New command").string("data", msg_slice).log();
            const src = self.internal_rbuffer.items[i + 1 ..];
            const dest = self.internal_rbuffer.items;
            std.mem.copyForwards(u8, dest, src);
            self.internal_rbuffer.shrinkRetainingCapacity(src.len);
        }
    }

    fn send_message(self: *Self, msg: []const u8) !void {
        logz.debug().ctx("Sending message").string("data", msg).log();
        try self.internal_wbuffer.appendSlice(msg);
    }

    fn send_handshake(self: *Self, ctx: *const server.Context) !void {
        try self.send_message(ctx.cache.handshake);
    }

    fn send_ok(self: *Self) !void {
        try self.send_message("OK\n");
    }

    fn send_about(self: *Self) !void {
        try self.send_message("ABOUT\n");
    }

    fn send_info_no_check(self: *Self, T: type, name: []const u8, val: T, allocator: std.mem.Allocator) !void {
        switch (T) {
            u64 => {
                const to_send = try std.fmt.allocPrint(allocator, "INFO {s} {}\n", .{ name, val });
                defer allocator.free(to_send);
                try self.send_message(to_send);
            },
            else => @compileError("Missing serializer for send_info_no_check for type " ++ @typeName(T)),
        }
    }

    fn send_info(self: *Self, info: ServerInfo, allocator: std.mem.Allocator) !void {
        // TODO: Check if there is a better way to do this, cause this looks ugly af
        switch (info) {
            .timeout_turn => |v| try self.send_info_no_check(@TypeOf(v), "timeout_turn", v, allocator),
            .timeout_match => |v| try self.send_info_no_check(@TypeOf(v), "timeout_match", v, allocator),
            .max_memory => |v| try self.send_info_no_check(@TypeOf(v), "max_memory", v, allocator),
            .time_left => |v| try self.send_info_no_check(@TypeOf(v), "time_left", v, allocator),
        }
    }

    fn send_all_infos(self: *Self, ctx: *const server.Context, allocator: std.mem.Allocator) !void {
        try self.send_info(.{ .timeout_turn = ctx.conf.game_timeout_turn }, allocator);
        try self.send_info(.{ .timeout_match = ctx.conf.game_timeout_match }, allocator);
        try self.send_info(.{ .max_memory = ctx.conf.game_max_memory }, allocator);
        // TODO: Put the actual value
        try self.send_info(.{ .time_left = 0 }, allocator);
    }

    fn send_ko(self: *Self, msg: ?[]const u8, allocator: std.mem.Allocator) !void {
        if (msg) |m| {
            const to_send = try std.fmt.allocPrint(allocator, "KO {s}\n", .{m});
            defer allocator.free(to_send);
            try self.send_message(to_send);
            return;
        }
        try self.send_message("KO\n");
    }

    fn send_begin(self: *Self) !void {
        try self.send_message("BEGIN\n");
    }

    fn send_turn(self: *Self, pos: GamePosition, allocator: std.mem.Allocator) !void {
        const to_send = try std.fmt.allocPrint(allocator, "TURN {},{}\n", .{ pos[0], pos[1] });
        defer allocator.free(to_send);
        try self.send_message(to_send);
    }

    fn send_start(self: *Self, ctx: *const server.Context, allocator: std.mem.Allocator) !void {
        const to_send = try std.fmt.allocPrint(allocator, "START {}\n", .{ctx.conf.game_board_size});
        defer allocator.free(to_send);
        try self.send_message(to_send);
    }

    fn handle_plogic(self: *Self, ctx: *server.Context, msg: *Message, allocator: std.mem.Allocator) !void {
        _ = msg;
        // TODO: Remove this later, it's only there for debug
        try self.send_all_infos(ctx, allocator);
    }

    fn handle_slogic(self: *Self, ctx: *server.Context, msg: *Message, allocator: std.mem.Allocator) !void {
        _ = self;
        _ = ctx;
        _ = msg;
        _ = allocator;
    }

    pub fn handle_logic(self: *Self, ctx: *server.Context, allocator: std.mem.Allocator) !void {
        switch (self.state) {
            .WaitingForHandshake => {
                try self.send_handshake(ctx);
                self.state = ClientState.WaitingForRole;
                return;
            },
            else => {},
        }
        for (self.msg.items) |*msg| {
            defer msg.deinit();
            logz.debug().ctx("Handling message").string("data", msg.data).int("timestamp", msg.timestamp).log();
            if (utils.is_debug_build and std.mem.eql(u8, msg.data, "STOP")) {
                ctx.running = false;
            }

            switch (self.state) {
                .WaitingForHandshake => unreachable,
                .WaitingForRole => {
                    if (std.mem.eql(u8, msg.data, "PLAYER")) {
                        if (ctx.nb_players >= 2) {
                            try self.send_ko("Too many players connected", allocator);
                            logz.debug().ctx("Refused new player, because there are too many players already").log();
                            continue;
                        }
                        self.ctype = ClientType.Player;
                        self.state = ClientState.PWaitingForStart;
                        ctx.nb_players += 1;
                        try self.send_ok();
                    } else if (std.mem.eql(u8, msg.data, "SPECTATOR")) {
                        if (ctx.conf.other_spectator_slots != 0 and ctx.nb_spectators >= ctx.conf.other_spectator_slots) {
                            try self.send_ko("Too many spectators connected, try later", allocator);
                            logz.debug().ctx("Refused new spectator, because there are too many spectators already").log();
                            continue;
                        }
                        self.ctype = ClientType.Spectator;
                        self.state = ClientState.SWaitingForStart;
                        ctx.nb_spectators += 1;
                        try self.send_ok();
                    } else {
                        try self.send_ko("Unknown role, try again", allocator);
                    }
                },
                else => {
                    switch (self.ctype.?) {
                        .Player => try self.handle_plogic(ctx, msg, allocator),
                        .Spectator => try self.handle_slogic(ctx, msg, allocator),
                    }
                },
            }
        }
        self.msg.clearRetainingCapacity();
    }

    pub fn handle_net_event(self: *Self, set: *const net.SocketSet, allocator: std.mem.Allocator) !void {
        if (set.isFaulted(self.sock)) {
            self.stopping = true;
            return;
        }
        if (set.isReadyRead(self.sock)) {
            var tmp_rbuf: [4096]u8 = undefined;
            const nb_bytes = try self.sock.receive(&tmp_rbuf);
            if (nb_bytes == 0) {
                self.stopping = true;
                return;
            }
            try self.internal_rbuffer.appendSlice(tmp_rbuf[0..nb_bytes]);
            try self.create_messages(allocator);
        }
        if (set.isReadyWrite(self.sock)) {
            const nb_bytes = try self.sock.send(self.internal_wbuffer.items);
            if (nb_bytes == self.internal_wbuffer.items.len) {
                self.internal_wbuffer.clearRetainingCapacity();
            } else {
                const src = self.internal_wbuffer.items[nb_bytes..];
                const dest = self.internal_wbuffer.items;
                std.mem.copyForwards(u8, dest, src);
                self.internal_wbuffer.shrinkRetainingCapacity(src.len);
            }
        }
    }

    pub fn wants_to_write(self: *const Self) bool {
        return self.internal_wbuffer.items.len > 0;
    }

    pub fn wants_to_read(self: *const Self) bool {
        return self.stopping == false;
    }

    pub fn deinit(self: *const Self, ctx: *server.Context) void {
        self.msg.deinit();
        self.internal_rbuffer.deinit();
        self.internal_wbuffer.deinit();
        self.sock.close();
        if (self.ctype) |t| {
            switch (t) {
                .Player => ctx.nb_players -= 1,
                .Spectator => ctx.nb_spectators -= 1,
            }
        }
    }
};
