const std = @import("std");
const builtin = @import("builtin");

const logz = @import("logz");

const build_config = @import("build_config");

const server = @import("server.zig");
const utils = @import("utils.zig");
const command = @import("command.zig");
const game = @import("game.zig");
const config = @import("config.zig");

const Allocator = std.mem.Allocator;

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

const ClientError = error{
    BadInitialization,
    BadCommand,
};

pub const Client = struct {
    const Self = @This();

    stopping: bool = false,
    infos: ?command.ClientResponseAbout = null,
    filepath: []const u8,
    match_time_remaining: u64,
    turn_time: u64,
    proc: std.process.Child = undefined,
    read_buf: std.ArrayList(u8),

    pub fn init(filepath: []const u8, conf: *const config.Config) !Client {
        return .{
            .filepath = try utils.allocator.dupe(u8, filepath),
            .match_time_remaining = conf.game_timeout_match,
            .turn_time = conf.game_timeout_turn,
            .read_buf = std.ArrayList(u8).init(utils.allocator),
        };
    }

    pub fn start_process(self: *Self, ctx: *const server.Context) !void {
        const s = std.fs.cwd().statFile(self.filepath) catch |e| {
            switch (e) {
                std.fs.File.OpenError.FileNotFound => {
                    logz.fatal().ctx("Could not find brain executable").string("filepath", self.filepath).log();
                },
                else => {
                    logz.fatal().ctx("Unknown error while trying to get info on brain executable").string("filepath", self.filepath).string("error name", @errorName(e)).log();
                },
            }
            return error.BadInitialization;
        };
        if (builtin.os.tag != .windows and s.mode & 0o111 == 0) {
            logz.fatal().ctx("The brain executable is not executable!").string("filepath", self.filepath).log();
            return error.BadInitialization;
        }

        self.proc = std.process.Child.init(&.{self.filepath}, utils.allocator);
        self.proc.stdout_behavior = .Pipe;
        self.proc.stdin_behavior = .Pipe;
        self.proc.stderr_behavior = .Ignore;

        logz.debug().ctx("Spawning process").string("filepath", self.filepath).log();
        try self.proc.spawn();

        try self.send_about();
        const about_resp = self.get_command_with_timeout(5 * std.time.ms_per_s) catch |e| {
            if (e == error.TimeoutError)
                logz.fatal().ctx("AI did not answer to ABOUT command in time!").log();
            return e;
        };
        if (about_resp == null) {
            logz.fatal().ctx("Did not get proper ABOUT answer from AI!").log();
            return error.BadInitialization;
        }
        defer about_resp.?.deinit();
        switch (about_resp.?) {
            .ResponseAbout => |e| self.infos = try e.dupe(utils.allocator),
            else => {
                logz.fatal().ctx("Did not get proper ABOUT answer from AI!").log();
                return error.BadInitialization;
            },
        }

        try self.send_start(ctx);
        const start_resp = self.get_command_with_timeout(5 * std.time.ms_per_s) catch |e| {
            if (e == error.TimeoutError)
                logz.fatal().ctx("AI did not answer to ABOUT command in time!").log();
            return e;
        };
        if (start_resp == null) {
            logz.fatal().ctx("Did not get proper START answer from AI!").log();
            return error.BadInitialization;
        }
        defer start_resp.?.deinit();
        switch (start_resp.?) {
            .ResponseOK => {},
            else => {
                logz.fatal().ctx("Did not get proper START answer from AI!").log();
                return error.BadInitialization;
            },
        }

        try self.send_all_infos(ctx);

        var l = logz.info().ctx("Finished initialization").string("name", self.infos.?.name);
        defer l.log();
        if (self.infos.?.author) |i| l = l.string("author", i);
        if (self.infos.?.version) |i| l = l.string("version", i);
        if (self.infos.?.country) |i| l = l.string("country", i);
        if (self.infos.?.www) |i| l = l.string("www", i);
    }

    fn send_message(self: *Self, msg: []const u8) !void {
        logz.debug().ctx("Sending message").string("data", std.mem.trim(u8, msg, &std.ascii.whitespace)).log();
        // Not sure if this can block at all, but it will for for now
        try self.proc.stdin.?.writeAll(msg);
    }

    fn get_command_with_timeout(self: *Self, timeout: i32) !?command.ClientCommand {
        const line = try self.get_line_with_timeout(timeout);
        defer utils.allocator.free(line);
        const cmd = try command.parse(line, utils.allocator);
        if (cmd == null)
            logz.err().ctx("Could not parse command").string("data", line).log();
        return cmd;
    }

    // That needs hella testing lmao
    fn get_line_with_timeout(self: *Self, timeout: i32) ![]const u8 {
        var left_timeout: i32 = timeout * std.time.us_per_ms;
        const start_time = std.time.microTimestamp();
        var tmp_rd_buf: [256]u8 = undefined;
        while (true) {
            if (std.mem.indexOf(u8, self.read_buf.items, "\n")) |i| {
                const line = try utils.allocator.dupe(u8, self.read_buf.items[0 .. i + 1]);
                const rest = self.read_buf.items[i + 1 ..];
                std.mem.copyForwards(u8, self.read_buf.items, rest);
                self.read_buf.shrinkRetainingCapacity(rest.len);
                return line;
            }
            const nb_read = try utils.read_with_timeout(self.proc.stdout.?, &tmp_rd_buf, if (timeout != -1) @divTrunc(left_timeout, std.time.us_per_ms) else -1);
            try self.read_buf.appendSlice(tmp_rd_buf[0..nb_read]);
            const current_time = std.time.microTimestamp();
            left_timeout = @intCast(@max(0, timeout - (start_time - current_time)));
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

    fn send_info_no_check(self: *Self, T: type, name: []const u8, val: T) !void {
        switch (T) {
            u64 => try self.send_format_message("INFO {s} {}\r\n", .{ name, val }),
            else => @compileError("Missing serializer for send_info_no_check for type " ++ @typeName(T)),
        }
    }

    // TODO: Refactor this shit
    fn send_info(self: *Self, info: ServerInfo) !void {
        switch (info) {
            .max_memory,
            .time_left,
            .timeout_turn,
            .timeout_match,
            => |v| try self.send_info_no_check(
                @TypeOf(v),
                @tagName(info),
                if (v == 0) 99999999 else v,
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

    fn send_end(self: *Self) !void {
        try self.send_message("END\r\n");
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

    fn get_pos(self: *Self, ctx: *const server.Context) !game.Position {
        const start_time = std.time.microTimestamp();
        while (true) {
            const current_time = std.time.microTimestamp();
            const remaining_time: i32 = @max(0, @as(i32, @intCast(ctx.conf.game_timeout_turn)) - @as(i32, @intCast(@divTrunc(current_time - start_time, 1000))));

            const cmd = try self.get_command_with_timeout(if (ctx.conf.game_timeout_turn != 0) remaining_time else -1);
            if (cmd == null)
                return error.BadCommand;
            defer cmd.?.deinit();
            switch (cmd.?) {
                .CommandLog => |l| {
                    self.handle_log(&l);
                    continue;
                },
                .ResponsePosition => |p| return p,
                else => |c| {
                    logz.err().ctx("Did not get a position or a log from brain").string("actual", @typeName(@TypeOf(c))).log();
                    return error.BadCommand;
                },
            }
        }
    }

    pub fn begin(self: *Self, ctx: *const server.Context) !game.Position {
        try self.send_begin();
        return try self.get_pos(ctx);
    }

    pub fn turn(self: *Self, ctx: *const server.Context, pos: game.Position) !game.Position {
        try self.send_turn(pos);
        return try self.get_pos(ctx);
    }

    pub fn stop_child(self: *Self) !void {
        self.send_end() catch {}; // Evil af, but aight

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
