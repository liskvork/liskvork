const std = @import("std");

const utils = @import("utils.zig");
const client = @import("client.zig");
const game = @import("game.zig");

pub const ClientCommandLogType = enum {
    Info,
    Debug,
    Error,
    Unknown,
};

pub const ClientCommandLog = struct {
    const Self = @This();

    msg_type: ClientCommandLogType,
    data: []const u8,
    allocator: std.mem.Allocator,

    fn init(log_type: ClientCommandLogType, data: []const u8, allocator: std.mem.Allocator) !ClientCommandLog {
        return .{
            .msg_type = log_type,
            .data = try allocator.dupe(u8, data),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: Self) void {
        self.allocator.free(self.data);
    }
};

pub const ClientResponseAbout = struct {
    const Self = @This();

    name: []const u8,
    version: ?[]const u8,
    author: ?[]const u8,
    country: ?[]const u8,
    www: ?[]const u8,
    allocator: std.mem.Allocator,

    fn init(opt: *const ClientResponseAboutOpt, allocator: std.mem.Allocator) Self {
        std.debug.assert(opt.name != null);
        return .{
            .name = opt.name.?,
            .version = opt.version,
            .author = opt.author,
            .country = opt.country,
            .www = opt.www,
            .allocator = allocator,
        };
    }

    pub fn dupe(self: *const Self, allocator: std.mem.Allocator) !Self {
        return .{
            .name = try allocator.dupe(u8, self.name),
            .version = if (self.version) |v| try allocator.dupe(u8, v) else null,
            .author = if (self.author) |v| try allocator.dupe(u8, v) else null,
            .country = if (self.country) |v| try allocator.dupe(u8, v) else null,
            .www = if (self.www) |v| try allocator.dupe(u8, v) else null,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *const Self) void {
        self.allocator.free(self.name);
        if (self.version) |v| self.allocator.free(v);
        if (self.author) |v| self.allocator.free(v);
        if (self.country) |v| self.allocator.free(v);
        if (self.www) |v| self.allocator.free(v);
    }
};

// The only different is the name being optional, to ease the parsing process
const ClientResponseAboutOpt = struct {
    const Self = @This();

    name: ?[]const u8 = null,
    version: ?[]const u8 = null,
    author: ?[]const u8 = null,
    country: ?[]const u8 = null,
    www: ?[]const u8 = null,

    pub fn cleanup(self: *const Self, allocator: std.mem.Allocator) void {
        if (self.name) |v| allocator.free(v);
        if (self.version) |v| allocator.free(v);
        if (self.author) |v| allocator.free(v);
        if (self.country) |v| allocator.free(v);
        if (self.www) |v| allocator.free(v);
    }
};

const ClientResponseKO = struct {
    const Self = @This();

    data: ?[]const u8,
    allocator: std.mem.Allocator,

    fn init(data: ?[]const u8, allocator: std.mem.Allocator) !Self {
        return .{
            .data = if (data) |d| try allocator.dupe(u8, d) else null,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: Self) void {
        if (self.data) |d|
            self.allocator.free(d);
    }
};

pub const ClientCommand = union(enum) {
    const Self = @This();

    CommandLog: ClientCommandLog,
    ResponseOK: void,
    ResponseKO: ClientResponseKO,
    ResponsePosition: game.Position,
    ResponseAbout: ClientResponseAbout,

    pub fn deinit(self: Self) void {
        switch (self) {
            .CommandLog => |v| v.deinit(),
            .ResponseKO => |v| v.deinit(),
            .ResponseAbout => |v| v.deinit(),
            else => {},
        }
    }
};

const log_starters = [_][]const u8{
    "INFO",
    "DEBUG",
    "ERROR",
    "UNKNOWN",
};

fn parse_log(msg: []const u8, idx: usize, allocator: std.mem.Allocator) !?ClientCommand {
    const starter = log_starters[idx];
    const ws_data = utils.skip_n_whitespace(msg[starter.len..], 1) catch {
        return null;
    };

    const data = std.mem.trim(u8, ws_data, &std.ascii.whitespace);

    if (data.len == 0)
        return null;
    return .{
        .CommandLog = try ClientCommandLog.init(
            @enumFromInt(idx),
            data,
            allocator,
        ),
    };
}

fn parse_ok(msg: []const u8) ?ClientCommand {
    const rest = msg[2..]; // Skip the start
    if (!utils.is_all_whitespace(rest))
        return null;
    return .ResponseOK;
}

fn parse_ko(msg: []const u8, allocator: std.mem.Allocator) !?ClientCommand {
    const rest = msg[2..];

    // Check if there is a message with the KO
    if (utils.is_all_whitespace(rest))
        return .{
            .ResponseKO = try ClientResponseKO.init(null, allocator),
        };

    const ws_data = utils.skip_n_whitespace(rest, 1) catch {
        return null;
    };

    const data = std.mem.trim(u8, ws_data, &std.ascii.whitespace);
    return .{
        .ResponseKO = try ClientResponseKO.init(data, allocator),
    };
}

// That is so ugly but I don't really have another idea right now
// TODO: Make so it isn't complete garbage
fn about_cleanup(out: *ClientResponseAboutOpt, allocator: std.mem.Allocator) ?ClientCommand {
    out.cleanup(allocator);
    return null;
}

fn map_kv_to_opt_about(k: []const u8, v: []const u8, out: *ClientResponseAboutOpt, allocator: std.mem.Allocator) !bool {
    inline for (std.meta.fields(ClientResponseAboutOpt)) |f| {
        if (std.mem.eql(u8, f.name, k)) {
            @field(out, f.name) = if (v.len > 0) try allocator.dupe(u8, v) else null;
            return true;
        }
    }
    return false;
}

// TODO: Same here this is ultra ugly
//
// Parses something like the following (taken directly from the documentation)
// name="SmortBrain",version="1.0",author="emneo",country="FR",www="emneo.dev"
fn parse_about_response(msg: []const u8, allocator: std.mem.Allocator) !?ClientCommand {
    var tmp = ClientResponseAboutOpt{};
    var rest = std.mem.trim(u8, msg, &std.ascii.whitespace);
    while (rest.len > 0) {
        const equal_idx = std.mem.indexOf(u8, rest, "=") orelse return about_cleanup(&tmp, allocator);
        const k = std.mem.trim(u8, rest[0..equal_idx], &std.ascii.whitespace);
        rest = rest[equal_idx + 1 ..];
        const start_quote = std.mem.indexOf(u8, rest, "\"") orelse return about_cleanup(&tmp, allocator);
        rest = rest[start_quote + 1 ..];
        const end_quote = std.mem.indexOf(u8, rest, "\"") orelse return about_cleanup(&tmp, allocator);
        const v = rest[0..end_quote];
        rest = std.mem.trim(u8, rest[end_quote + 1 ..], &std.ascii.whitespace);
        if (!try map_kv_to_opt_about(k, v, &tmp, allocator))
            return about_cleanup(&tmp, allocator);
        if (rest.len == 0)
            continue;
        const next_comma = std.mem.indexOf(u8, rest, ",") orelse return about_cleanup(&tmp, allocator);
        rest = std.mem.trim(u8, rest[next_comma + 1 ..], &std.ascii.whitespace);
    }
    if (tmp.name == null)
        return about_cleanup(&tmp, allocator);
    return .{
        .ResponseAbout = ClientResponseAbout.init(&tmp, allocator),
    };
}

fn parse_turn(msg: []const u8) ?ClientCommand {
    const num_commas = std.mem.count(u8, msg, ",");
    if (num_commas != 1)
        return null;
    const comma_idx = std.mem.indexOf(u8, msg, ",");
    // The comma is at the end of the message, can't parse
    if (comma_idx.? + 1 == msg.len)
        return null;
    const first_num_slice = std.mem.trim(u8, msg[0..comma_idx.?], &std.ascii.whitespace);
    const second_num_slice = std.mem.trim(u8, msg[comma_idx.? + 1 ..], &std.ascii.whitespace);
    const first_num = std.fmt.parseInt(u32, first_num_slice, 10) catch return null;
    const second_num = std.fmt.parseInt(u32, second_num_slice, 10) catch return null;
    return ClientCommand{
        .ResponsePosition = .{ first_num, second_num },
    };
}

pub fn parse(msg: []const u8, allocator: std.mem.Allocator) !?ClientCommand {
    for (log_starters, 0..) |s, i| {
        if (std.mem.startsWith(u8, msg, s))
            return try parse_log(msg, i, allocator);
    }
    if (std.mem.startsWith(u8, msg, "OK"))
        return parse_ok(msg);
    if (std.mem.startsWith(u8, msg, "KO"))
        return try parse_ko(msg, allocator);
    const tmp = try parse_about_response(msg, allocator);
    if (tmp != null)
        return tmp;
    return parse_turn(msg);
}

// -------------------------
// --------- TESTS ---------
// -------------------------

test "about name version www with extra character" {
    const t = std.testing;
    const alloc = t.allocator;

    const cmd = try parse(
        "name   =\"    funny    \",\t\t      \t version\t =  \"1\t. 0\",www =       \"em\tneo.dev\" :3",
        alloc,
    );
    try t.expect(cmd == null);
}

test "about name version www" {
    const t = std.testing;
    const alloc = t.allocator;

    const cmd = try parse(
        "name   =\"    funny    \",\t\t      \t version\t =  \"1\t. 0\",www =       \"em\tneo.dev\"",
        alloc,
    );
    try t.expect(cmd != null);
    defer cmd.?.deinit();

    try t.expectEqualDeep(cmd, ClientCommand{
        .ResponseAbout = .{
            .name = "    funny    ",
            .country = null,
            .www = "em\tneo.dev",
            .author = null,
            .version = "1\t. 0",
            .allocator = alloc,
        },
    });
}

test "turn 0,0" {
    const t = std.testing;
    const alloc = t.allocator;

    const cmd = try parse("0,0", alloc);
    try t.expect(cmd != null);

    try t.expectEqualDeep(cmd, ClientCommand{
        .ResponsePosition = .{ 0, 0 },
    });
}

test "turn 13,42" {
    const t = std.testing;
    const alloc = t.allocator;

    const cmd = try parse("13  \t ,  \t \t42", alloc);
    try t.expect(cmd != null);

    try t.expectEqualDeep(cmd, ClientCommand{
        .ResponsePosition = .{ 13, 42 },
    });
}

test "turn 0,0,0 fail" {
    const t = std.testing;
    const alloc = t.allocator;

    const cmd = try parse("0,0,0", alloc);
    try t.expect(cmd == null);
}

test "about version www" {
    const t = std.testing;
    const alloc = t.allocator;

    const cmd = try parse("version=\"1.0\",www=\"emneo.dev\"", alloc);
    try t.expect(cmd == null);
}

test "about just name" {
    const t = std.testing;
    const alloc = t.allocator;

    const cmd = try parse("name=\"funny\"", alloc);
    try t.expect(cmd != null);
    defer cmd.?.deinit();

    try t.expectEqualDeep(cmd, ClientCommand{
        .ResponseAbout = .{
            .name = "funny",
            .country = null,
            .www = null,
            .author = null,
            .version = null,
            .allocator = alloc,
        },
    });
}

test "ko parsing" {
    const t = std.testing;
    const alloc = t.allocator;

    const cmd = try parse("KO", alloc);

    try t.expectEqualDeep(cmd, ClientCommand{
        .ResponseKO = .{
            .data = null,
            .allocator = alloc,
        },
    });
}

test "ko parsing with whitespace" {
    const t = std.testing;
    const alloc = t.allocator;

    const cmd = try parse("KO   \t\t    \t     ", alloc);

    try t.expectEqualDeep(cmd, ClientCommand{
        .ResponseKO = .{
            .data = null,
            .allocator = alloc,
        },
    });
}

test "ko parsing with data" {
    const t = std.testing;
    const alloc = t.allocator;

    const cmd = try parse("KO YEAH THERE ARE SOME THINGS HERE", alloc);
    try t.expect(cmd != null);
    defer cmd.?.deinit();

    try t.expectEqualDeep(cmd, ClientCommand{
        .ResponseKO = .{
            .data = "YEAH THERE ARE SOME THINGS HERE",
            .allocator = alloc,
        },
    });
}

test "bad ko parsing" {
    const t = std.testing;
    const alloc = t.allocator;

    const cmd = try parse("KOYEAH THERE ARE SOME THINGS HERE", alloc);

    try t.expectEqual(cmd, null);
}

test "ok parsing" {
    const t = std.testing;
    const alloc = t.allocator;

    const cmd = try parse("OK", alloc);

    try t.expectEqualDeep(cmd, .ResponseOK);
}

test "ok parsing with whitespace" {
    const t = std.testing;
    const alloc = t.allocator;

    const cmd = try parse("OK   \t\t    \t     ", alloc);

    try t.expectEqualDeep(cmd, .ResponseOK);
}

test "bad ok parsing" {
    const t = std.testing;
    const alloc = t.allocator;

    const cmd = try parse("OK YEAH THERE ARE SOME THINGS HERE", alloc);

    try t.expectEqual(cmd, null);
}

test "bad ok parsing 2" {
    const t = std.testing;
    const alloc = t.allocator;

    const cmd = try parse("OKYEAH THERE ARE SOME THINGS HERE", alloc);

    try t.expectEqual(cmd, null);
}

test "debug log parsing" {
    const t = std.testing;
    const alloc = t.allocator;

    const cmd = try parse("DEBUG issou that works", alloc);
    try t.expect(cmd != null);

    defer cmd.?.deinit();

    try t.expectEqualDeep(cmd, ClientCommand{
        .CommandLog = .{
            .msg_type = ClientCommandLogType.Debug,
            .data = "issou that works",
            .allocator = alloc,
        },
    });
}

test "info log parsing with whitespace" {
    const t = std.testing;
    const alloc = t.allocator;

    const cmd = try parse("INFO \t  \t      issou that works", alloc);
    try t.expect(cmd != null);

    defer cmd.?.deinit();

    try t.expectEqualDeep(cmd, ClientCommand{
        .CommandLog = .{
            .msg_type = ClientCommandLogType.Info,
            .data = "issou that works",
            .allocator = alloc,
        },
    });
}

test "error log parsing no msg" {
    const t = std.testing;
    const alloc = t.allocator;

    const cmd = try parse("ERROR", alloc);
    try t.expect(cmd == null);
}

test "error log parsing with garbage" {
    const t = std.testing;
    const alloc = t.allocator;

    const cmd = try parse("ERRORILOVEFOODABITTOOMUCH", alloc);
    try t.expect(cmd == null);
}

test "unknown log parsing one whitespace" {
    const t = std.testing;
    const alloc = t.allocator;

    const cmd = try parse("UNKNOWN ", alloc);
    try t.expect(cmd == null);
}

test "debug log parsing multiple whitespace" {
    const t = std.testing;
    const alloc = t.allocator;

    const cmd = try parse("DEBUG     \t    \t        ", alloc);
    try t.expect(cmd == null);
}

test "error log parsing with whitespace" {
    const t = std.testing;
    const alloc = t.allocator;

    const cmd = try parse("ERROR\t  \t      issou that works", alloc);
    try t.expect(cmd != null);

    defer cmd.?.deinit();

    try t.expectEqualDeep(cmd, ClientCommand{
        .CommandLog = .{
            .msg_type = ClientCommandLogType.Error,
            .data = "issou that works",
            .allocator = alloc,
        },
    });
}

test {
    std.testing.refAllDecls(@This());
}
