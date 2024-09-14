const std = @import("std");

const utils = @import("utils.zig");
const client = @import("client.zig");

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
    name: []const u8,
    version: ?[]const u8,
    author: ?[]const u8,
    country: ?[]const u8,
    www: ?[]const u8,
};

// The only different is the name being optional, to ease the parsing process
const ClientResponseAboutOpt = struct {
    name: ?[]const u8 = null,
    version: ?[]const u8 = null,
    author: ?[]const u8 = null,
    country: ?[]const u8 = null,
    www: ?[]const u8 = null,
};

pub const ClientCommand = union(enum) {
    const Self = @This();

    CommandLog: ClientCommandLog,
    ResponseOK: void,
    ResponseKO: ?[]const u8,
    ResponsePosition: client.GamePosition,

    pub fn deinit(self: Self) void {
        switch (self) {
            .CommandLog => |v| v.deinit(),
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

pub fn parse(msg: []const u8, allocator: std.mem.Allocator) !?ClientCommand {
    for (log_starters, 0..) |s, i| {
        if (std.mem.startsWith(u8, msg, s))
            return parse_log(msg, i, allocator);
    }
    if (std.mem.startsWith(u8, msg, "OK"))
        return parse_ok(msg);
    return null;
}

// -------------------------
// --------- TESTS ---------
// -------------------------

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
