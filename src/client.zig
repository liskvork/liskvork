const std = @import("std");
const builtin = @import("builtin");

const logz = @import("logz");

const build_config = @import("build_config");

const server = @import("server.zig");
const utils = @import("utils.zig");
const protocol = @import("gomoku_protocol");
const game = @import("gomoku_game");
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
    infos: std.ArrayList(protocol.ClientInfo) = undefined,
    filepath: []const u8,
    match_time_remaining: u64,
    turn_time: u64,
    proc: std.process.Child = undefined,
    read_buf: [2048]u8 = undefined,
    write_buf: [2048]u8 = undefined,
    stdout_reader: std.Io.File.Reader = undefined,
    reader: *std.Io.Reader = undefined,
    stdin_writer: std.Io.File.Writer = undefined,
    writer: *std.Io.Writer = undefined,
    p_num: u2,
    initialized: bool = false,
    name: []const u8 = undefined,

    pub fn init(filepath: []const u8, conf: *const config.Config, p_num: u2) !Client {
        return .{
            .filepath = try utils.allocator.dupe(u8, filepath),
            .match_time_remaining = if (p_num == 1) conf.player1_timeout_match else conf.player2_timeout_match,
            .turn_time = if (p_num == 1) conf.player1_timeout_turn else conf.player2_timeout_turn,
            .p_num = p_num,
        };
    }

    fn set_memory_limit(self: *Self, limit: u64) !void {
        const bytes_per_kilobyte = 1024;
        var rl: std.os.linux.rlimit = .{
            .cur = limit,
            .max = limit,
        };
        logz.debug().ctx("Enforcing memory limit...").int("limit (KB)", limit / bytes_per_kilobyte).log();
        if (self.proc.id == null) {
            logz.fatal().ctx("Process not accessible for enforcement. Did the brain stop?").log();
            return error.BadInitialization;
        }
        // Not sure we want to use .DATA here, but it will do for now
        const result = std.os.linux.prlimit(self.proc.id.?, .DATA, &rl, null);
        if (result != 0) {
            const error_string = @tagName(std.c.errno(result));
            logz.fatal().ctx("Memory enforcement on subprocess failed to set").stringSafe("errno", error_string).log();
            return error.BadInitialization;
        }
        logz.debug().ctx("Memory limit enforced").log();
    }

    pub fn start_process(self: *Self, ctx: *const server.Context) !void {
        const s = std.Io.Dir.cwd().statFile(utils.io, self.filepath, .{}) catch |e| {
            switch (e) {
                std.Io.File.OpenError.FileNotFound => {
                    logz.fatal().ctx("Could not find brain executable").string("filepath", self.filepath).log();
                },
                else => {
                    logz.fatal().ctx("Unknown error while trying to get info on brain executable").string("filepath", self.filepath).string("error name", @errorName(e)).log();
                },
            }
            return error.BadInitialization;
        };
        if (builtin.os.tag != .windows and s.permissions.toMode() & 0o111 == 0) {
            logz.fatal().ctx("The brain executable is not executable!").string("filepath", self.filepath).log();
            return error.BadInitialization;
        }

        logz.debug().ctx("Spawning process").string("filepath", self.filepath).log();
        self.proc = try std.process.spawn(utils.io, .{
            .argv = &.{self.filepath},
            .stdout = .pipe,
            .stdin = .pipe,
            .stderr = .inherit,
        });

        self.stdout_reader = self.proc.stdout.?.reader(utils.io, &self.read_buf);
        self.reader = &self.stdout_reader.interface;
        self.stdin_writer = self.proc.stdin.?.writer(utils.io, &self.write_buf);
        self.writer = &self.stdin_writer.interface;

        // Enforce the memory limit if it's turned on *and* we are on Linux
        if (ctx.conf.game_enforce_max_memory and ctx.conf.game_max_memory > 0 and builtin.os.tag == .linux)
            try self.set_memory_limit(ctx.conf.game_max_memory);

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
        defer about_resp.?.deinit(utils.allocator);
        switch (about_resp.?) {
            .ResponseAbout => |e| self.infos = e,
            else => {
                logz.fatal().ctx("Did not get proper ABOUT answer from AI!").log();
                return error.BadInitialization;
            },
        }

        try self.send_start(ctx);
        const start_resp = self.get_command_with_timeout(5 * std.time.ms_per_s) catch |e| {
            if (e == error.TimeoutError)
                logz.fatal().ctx("AI did not answer to START command in time!").log();
            return e;
        };
        if (start_resp == null) {
            logz.fatal().ctx("Did not get proper START answer from AI!").log();
            return error.BadInitialization;
        }
        defer start_resp.?.deinit(utils.allocator);
        switch (start_resp.?) {
            .ResponseOK => {},
            else => {
                logz.fatal().ctx("Did not get proper START answer from AI!").log();
                return error.BadInitialization;
            },
        }

        try self.send_all_infos(ctx);

        var l = logz.info().ctx("Finished initialization");
        defer l.log();
        var found_name: bool = false;
        for (self.infos.items) |i| {
            if (std.mem.eql(u8, i.k, "name")) {
                self.name = i.v;
                found_name = true;
            }
            l = l.string(i.k, i.v);
        }
        if (!found_name) {
            self.name = if (self.p_num == 1) "no_name_p1" else "no_name_p2";
            logz.debug().ctx("Brain did not provide a name").stringSafe("default", self.name).log();
            l = l.string("name", self.name);
        }
        self.initialized = true;
    }

    fn send_message(self: *Self, msg: []const u8) !void {
        return self.send_format_message("{s}", .{msg});
    }

    fn get_command_with_timeout(self: *Self, timeout: i32) !?protocol.ClientCommand {
        const line = try self.get_line_with_timeout(timeout);
        logz.debug().ctx("Received message").string("data", std.mem.trim(u8, line, &std.ascii.whitespace)).int("player", self.p_num).log();
        return protocol.parse(line, utils.allocator) catch |e| {
            logz.err().ctx("Could not parse command").string("data", line).err(e).log();
            return null;
        };
    }

    fn get_line_with_timeout(self: *Self, timeout: i32) ![]const u8 {
        const line = try utils.readline_with_timeout(self.reader, timeout);
        return line[0 .. line.len - 1];
    }

    fn send_format_message(self: *Self, comptime fmt: []const u8, args: anytype) !void {
        logz.debug().ctx("Sending message").fmt("data", fmt, args).int("player", self.p_num).log();
        try self.writer.print(fmt ++ "\r\n", args);
        try self.writer.flush();
    }

    fn send_about(self: *Self) !void {
        try self.send_message("ABOUT");
    }

    fn send_ok(self: *Self) !void {
        try self.send_message("OK");
    }

    fn send_info_no_check(self: *Self, T: type, name: []const u8, val: T) !void {
        switch (T) {
            u64 => try self.send_format_message("INFO {s} {}", .{ name, val }),
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
            => |v| if (v != 0) try self.send_info_no_check(
                @TypeOf(v),
                @tagName(info),
                v,
            ),
        }
    }

    fn send_all_infos(self: *Self, ctx: *const server.Context) !void {
        try self.send_info(.{ .timeout_turn = self.turn_time });
        try self.send_info(.{ .timeout_match = self.match_time_remaining });
        try self.send_info(.{ .max_memory = ctx.conf.game_max_memory });
    }

    fn send_ko(self: *Self, msg: ?[]const u8) !void {
        if (msg) |m| {
            try self.send_format_message("KO {s}", .{m});
        } else try self.send_message("KO");
    }

    fn send_begin(self: *Self) !void {
        try self.send_message("BEGIN");
    }

    fn send_turn(self: *Self, pos: game.Position) !void {
        try self.send_format_message("TURN {},{}", .{ pos[0], pos[1] });
    }

    fn send_start(self: *Self, ctx: *const server.Context) !void {
        try self.send_format_message("START {}", .{ctx.conf.game_board_size});
    }

    fn send_end(self: *Self) !void {
        try self.send_message("END");
    }

    fn handle_log(self: *Self, l: *const protocol.ClientCommandLog) void {
        switch (l.msg_type) {
            .Info => logz.info().ctx("info from client").int("player", self.p_num).string("msg", l.data).log(),
            .Error => logz.info().ctx("error from client").int("player", self.p_num).string("msg", l.data).log(),
            .Debug => logz.info().ctx("debug from client").int("player", self.p_num).string("msg", l.data).log(),
            .Unknown => logz.warn().ctx("unknown from client").int("player", self.p_num).string("msg", l.data).log(),
        }
    }

    fn get_pos(self: *Self) !game.Position {
        const start_time = utils.micro_timestamp();
        while (true) {
            const current_time = utils.micro_timestamp();
            const remaining_time_turn: i32 = @max(0, @as(i32, @intCast(self.turn_time)) - @as(i32, @intCast(@divTrunc(current_time - start_time, 1000))));
            const remaining_time_match: i32 = @max(0, @as(i32, @intCast(self.match_time_remaining)) - @as(i32, @intCast(@divTrunc(current_time - start_time, 1000))));
            const remaining_time = @min(remaining_time_match, remaining_time_turn);

            const cmd = try self.get_command_with_timeout(if (self.turn_time != 0) remaining_time else -1);
            if (cmd == null)
                return error.BadCommand;
            defer cmd.?.deinit(utils.allocator);
            switch (cmd.?) {
                .CommandLog => |l| {
                    self.handle_log(&l);
                    continue;
                },
                .ResponsePosition => |p| {
                    const end_time = utils.micro_timestamp();
                    self.match_time_remaining -= @max(0, @divTrunc(end_time - start_time, 1000));
                    return p;
                },
                else => |c| {
                    logz.err().ctx("Did not get a position or a log from brain").string("actual", @typeName(@TypeOf(c))).log();
                    return error.BadCommand;
                },
            }
        }
    }

    pub fn begin(self: *Self) !game.Position {
        try self.send_begin();
        return try self.get_pos();
    }

    pub fn turn(self: *Self, pos: game.Position) !game.Position {
        try self.send_turn(pos);
        return try self.get_pos();
    }

    fn stop_child_inner(self: *Self, grace_time: u64) !void {
        // FIXME: I honestly don't like the naming of this function
        if (grace_time != 0) {
            try self.send_end();
            try std.Io.sleep(utils.io, .fromMilliseconds(@intCast(grace_time)), .awake);
        }
        self.proc.kill(utils.io); // This won't kill the process if it is already gone
    }

    pub fn stop_child(self: *Self, grace_time: u64) void {
        self.stop_child_inner(grace_time) catch |e| {
            logz.err().ctx("Could not end brain properly").int("player", self.p_num).err(e).log();
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.initialized) {
            for (self.infos.items) |i|
                i.deinit(utils.allocator);
            self.infos.deinit(utils.allocator);
        }
        utils.allocator.free(self.filepath);
    }
};
