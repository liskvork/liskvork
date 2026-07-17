const std = @import("std");

const game = @import("gomoku_game");

const Error = error{
    SliceTooSmall,
    NonWhitespaceInTrim,
    UnknownCommand,
    BadCommand,
    EndOfStream,
    NotEnoughWhitespace,
};

fn all_respect(T: type, slice: []const T, predicate: fn (val: T) bool) bool {
    for (slice) |i| {
        if (!predicate(i))
            return false;
    }
    return true;
}

inline fn is_all_whitespace(slice: []const u8) bool {
    return all_respect(u8, slice, std.ascii.isWhitespace);
}

fn toss_n_whitespace(slice: []const u8, n: usize) ![]const u8 {
    if (slice.len < n)
        return Error.SliceTooSmall;
    if (!is_all_whitespace(slice[0..n]))
        return Error.NonWhitespaceInTrim;
    return slice[n..];
}

fn toss_whitespace(r: *std.Io.Reader) !void {
    while (true) {
        const b = r.peekByte() catch |e|
            return switch (e) {
                error.EndOfStream => {},
                else => e,
            };
        if (!std.ascii.isWhitespace(b))
            return;
        r.toss(1);
    }
}

fn toss_n_whitespace_min(r: *std.Io.Reader, n: usize) !void {
    for (0..n) |i| {
        _ = i;
        const b = try r.takeByte();
        if (!std.ascii.isWhitespace(b))
            return Error.NotEnoughWhitespace;
    }
    try toss_whitespace(r);
    _ = try r.peekByte();
}

pub const ClientInfo = struct {
    const Self = @This();

    k: []const u8,
    v: []const u8,

    pub fn init(allocator: std.mem.Allocator, k: []const u8, v: []const u8) !Self {
        return .{
            .k = try allocator.dupe(u8, k),
            .v = try allocator.dupe(u8, v),
        };
    }

    pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
        allocator.free(self.k);
        allocator.free(self.v);
    }
};

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

    fn init(log_type: ClientCommandLogType, data: []const u8) !ClientCommandLog {
        return .{
            .msg_type = log_type,
            .data = data,
        };
    }

    pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
    }
};

const ClientResponseKO = struct {
    const Self = @This();

    data: ?[]const u8,

    fn init(data: ?[]const u8) Self {
        return .{
            .data = data,
        };
    }

    const empty: Self = .{
        .data = null,
    };

    pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
        if (self.data) |d|
            allocator.free(d);
    }
};

pub const ClientCommand = union(enum) {
    const Self = @This();

    CommandLog: ClientCommandLog,
    ResponseOK: void,
    ResponseKO: ClientResponseKO,
    ResponsePosition: game.Position,
    ResponseSuggest: game.Position,
    ResponseAbout: std.ArrayList(ClientInfo),

    pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
        switch (self) {
            .CommandLog => |v| v.deinit(allocator),
            .ResponseKO => |v| v.deinit(allocator),
            else => {},
        }
    }
};

const log_starters = [_][]const u8{
    "MESSAGE",
    "DEBUG",
    "ERROR",
    "UNKNOWN",
};

fn parse_log(r: *std.Io.Reader, idx: usize, allocator: std.mem.Allocator) !ClientCommand {
    r.toss(log_starters[idx].len);
    if (!std.ascii.isWhitespace(try r.peekByte()))
        return Error.UnknownCommand;

    try toss_n_whitespace_min(r, 1);

    return .{
        .CommandLog = try ClientCommandLog.init(
            @enumFromInt(idx),
            try r.allocRemaining(allocator, .unlimited),
        ),
    };
}

fn parse_ok(r: *std.Io.Reader) !ClientCommand {
    r.toss("OK".len);

    try toss_whitespace(r);

    _ = r.peekByte() catch |e| {
        return switch (e) {
            error.EndOfStream => .ResponseOK,
            else => e,
        };
    };

    return Error.BadCommand;
}

fn parse_ko(r: *std.Io.Reader, allocator: std.mem.Allocator) !ClientCommand {
    r.toss("KO".len);

    if (r.peekByte() == error.EndOfStream)
        return .{ .ResponseKO = .empty };

    toss_n_whitespace_min(r, 1) catch |e| {
        return switch (e) {
            error.EndOfStream => .{ .ResponseKO = .empty },
            else => e,
        };
    };

    return .{
        .ResponseKO = ClientResponseKO.init(
            std.mem.trim(u8, try r.allocRemaining(allocator, .unlimited), &std.ascii.whitespace),
        ),
    };
}

// That is so ugly but I don't really have another idea right now
// TODO: Make so it isn't complete garbage
fn about_cleanup(out: *std.ArrayList(ClientInfo), allocator: std.mem.Allocator) ?ClientCommand {
    for (out.items) |i|
        i.deinit(allocator);
    out.deinit(allocator);
    return null;
}

// TODO: Same here this is ultra ugly
//
// Parses something like the following (taken directly from the documentation)
// name="SmortBrain",version="1.0",author="emneo",country="FR",www="emneo.dev"
fn parse_about_response(msg: []const u8, allocator: std.mem.Allocator) !?ClientCommand {
    var result = std.ArrayList(ClientInfo).empty;
    var rest = std.mem.trim(u8, msg, &std.ascii.whitespace);
    while (rest.len > 0) {
        const equal_idx = std.mem.indexOf(u8, rest, "=") orelse return about_cleanup(&result, allocator);
        const k = std.mem.trim(u8, rest[0..equal_idx], &std.ascii.whitespace);
        rest = rest[equal_idx + 1 ..];
        const start_quote = std.mem.indexOf(u8, rest, "\"") orelse return about_cleanup(&result, allocator);
        rest = rest[start_quote + 1 ..];
        const end_quote = std.mem.indexOf(u8, rest, "\"") orelse return about_cleanup(&result, allocator);
        const v = rest[0..end_quote];
        rest = std.mem.trim(u8, rest[end_quote + 1 ..], &std.ascii.whitespace);
        try result.append(allocator, try ClientInfo.init(allocator, k, v));
        if (rest.len == 0)
            continue;
        const next_comma = std.mem.indexOf(u8, rest, ",") orelse return about_cleanup(&result, allocator);
        rest = std.mem.trim(u8, rest[next_comma + 1 ..], &std.ascii.whitespace);
    }
    if (result.items.len == 0)
        return about_cleanup(&result, allocator);
    return .{
        .ResponseAbout = result,
    };
}

const MAX_USIZE_STR_SIZE = blk: {
    const max_usize = std.math.maxInt(usize);
    const max_usize_str = std.fmt.comptimePrint("{}", .{max_usize});
    break :blk max_usize_str.len;
};

fn parse_position(r: *std.Io.Reader) !game.Position {
    var x_buf: [MAX_USIZE_STR_SIZE]u8 = undefined;
    var y_buf: [MAX_USIZE_STR_SIZE]u8 = undefined;
    var x_writer: std.Io.Writer = .fixed(&x_buf);
    var y_writer: std.Io.Writer = .fixed(&y_buf);

    const x_len = try r.streamDelimiter(&x_writer, ',');
    if (x_len == 0) return Error.BadCommand;

    r.toss(1); // Toss the delimiter

    const y_len = try r.streamRemaining(&y_writer);
    if (y_len == 0) return Error.BadCommand;

    const x = try std.fmt.parseUnsigned(usize, x_buf[0..x_len], 10);
    const y = try std.fmt.parseUnsigned(usize, y_buf[0..y_len], 10);
    return .{ x, y };
}

fn parse_turn(r: *std.Io.Reader) !ClientCommand {
    return ClientCommand{
        .ResponsePosition = try parse_position(r),
    };
}

fn parse_suggest(r: *std.Io.Reader) !ClientCommand {
    r.toss("SUGGEST".len);

    try toss_n_whitespace_min(r, 1);

    return .{
        .ResponseSuggest = try parse_position(r),
    };
}

pub fn parse(msg: []const u8, allocator: std.mem.Allocator) !ClientCommand {
    var r = std.Io.Reader.fixed(msg);
    for (log_starters, 0..) |s, i| {
        if (std.mem.startsWith(u8, msg, s))
            return try parse_log(&r, i, allocator);
    }
    if (std.mem.startsWith(u8, msg, "OK"))
        return try parse_ok(&r);
    if (std.mem.startsWith(u8, msg, "KO"))
        return try parse_ko(&r, allocator);
    if (std.mem.startsWith(u8, msg, "SUGGEST"))
        return try parse_suggest(&r);
    const tmp = try parse_about_response(msg, allocator);
    if (tmp != null)
        return tmp.?;
    return try parse_turn(&r);
}

// -------------------------
// --------- TESTS ---------
// -------------------------

test "about name version www with extra character" {
    const t = std.testing;
    const alloc = t.allocator;

    // TODO: Actually fix that once about parsing is better

    const cmd = parse(
        "name   =\"    funny    \",\t\t      \t version\t =  \"1\t. 0\",www =       \"em\tneo.dev\" :3",
        alloc,
    ) catch return;
    _ = cmd;
    try t.expect(false);
}

test "about name version www" {
    const t = std.testing;
    const alloc = t.allocator;

    var cmd = try parse(
        "name   =\"    funny    \",\t\t      \t version\t =  \"1\t. 0\",www =       \"em\tneo.dev\"",
        alloc,
    );
    try t.expect(cmd == .ResponseAbout);
    defer {
        for (cmd.ResponseAbout.items) |i|
            i.deinit(alloc);
        cmd.ResponseAbout.deinit(alloc);
    }

    const expected = [_]ClientInfo{
        .{ .k = "name", .v = "    funny    " },
        .{ .k = "version", .v = "1\t. 0" },
        .{ .k = "www", .v = "em\tneo.dev" },
    };
    try t.expectEqualDeep(cmd.ResponseAbout.items, &expected);
}

test "turn 0,0" {
    const t = std.testing;
    const alloc = t.allocator;

    const cmd = try parse("0,0", alloc);

    try t.expectEqualDeep(cmd, ClientCommand{
        .ResponsePosition = .{ 0, 0 },
    });
}

test "turn 13,42" {
    const t = std.testing;
    const alloc = t.allocator;

    const cmd = try parse("13,42", alloc);

    try t.expectEqualDeep(cmd, ClientCommand{
        .ResponsePosition = .{ 13, 42 },
    });
}

test "suggest simple 0,0" {
    const t = std.testing;

    const data = "SUGGEST 0,0";
    var r: std.Io.Reader = .fixed(data);

    const pos = try parse_suggest(&r);
    try t.expectEqualDeep(
        ClientCommand{
            .ResponseSuggest = .{ 0, 0 },
        },
        pos,
    );
}

test "suggest 0,0" {
    const t = std.testing;
    const alloc = t.allocator;

    const pos = try parse("SUGGEST 0,0", alloc);
    try t.expectEqualDeep(
        ClientCommand{
            .ResponseSuggest = .{ 0, 0 },
        },
        pos,
    );
}

test "suggest simple 42,13" {
    const t = std.testing;

    const data = "SUGGEST 42,13";
    var r: std.Io.Reader = .fixed(data);

    const pos = try parse_suggest(&r);
    try t.expectEqualDeep(
        ClientCommand{
            .ResponseSuggest = .{ 42, 13 },
        },
        pos,
    );
}

test "suggest 42,13" {
    const t = std.testing;
    const alloc = t.allocator;

    const pos = try parse("SUGGEST 42,13", alloc);
    try t.expectEqualDeep(
        ClientCommand{
            .ResponseSuggest = .{ 42, 13 },
        },
        pos,
    );
}

test "suggest simple overflow" {
    const t = std.testing;

    const data = "SUGGEST 42123456789123456789123456789,13";
    var r: std.Io.Reader = .fixed(data);

    const pos = parse_suggest(&r);
    try t.expectError(std.Io.Writer.Error.WriteFailed, pos);
}

test "suggest overflow" {
    const t = std.testing;
    const alloc = t.allocator;

    const data = "SUGGEST 42123456789123456789123456789,13";

    const pos = parse(data, alloc);
    try t.expectError(std.Io.Writer.Error.WriteFailed, pos);
}

test "turn 0,0,0 fail" {
    const t = std.testing;
    const alloc = t.allocator;

    const cmd = parse("0,0,0", alloc);
    try t.expectError(std.fmt.ParseIntError.InvalidCharacter, cmd);
}

test "about version www" {
    const t = std.testing;
    const alloc = t.allocator;

    var cmd = try parse("version=\"1.0\",www=\"emneo.dev\"", alloc);
    try t.expect(cmd == .ResponseAbout);
    defer {
        for (cmd.ResponseAbout.items) |i|
            i.deinit(alloc);
        cmd.ResponseAbout.deinit(alloc);
    }

    const expected = [_]ClientInfo{
        .{ .k = "version", .v = "1.0" },
        .{ .k = "www", .v = "emneo.dev" },
    };

    try t.expectEqualDeep(cmd.ResponseAbout.items, &expected);
}

test "about just name" {
    const t = std.testing;
    const alloc = t.allocator;

    var cmd = try parse("name=\"funny\"", alloc);
    defer {
        for (cmd.ResponseAbout.items) |i|
            i.deinit(alloc);
        cmd.ResponseAbout.deinit(alloc);
    }

    var expected = std.ArrayList(ClientInfo).empty;
    defer expected.deinit(alloc);
    try expected.appendSlice(alloc, &.{.{ .k = "name", .v = "funny" }});

    try t.expectEqualDeep(cmd, ClientCommand{
        .ResponseAbout = expected,
    });
}

test "ko parsing" {
    const t = std.testing;
    const alloc = t.allocator;

    const cmd = try parse("KO", alloc);

    try t.expectEqualDeep(cmd, ClientCommand{
        .ResponseKO = .{
            .data = null,
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
        },
    });
}

test "ko parsing with data" {
    const t = std.testing;
    const alloc = t.allocator;

    const cmd = try parse("KO YEAH THERE ARE SOME THINGS HERE", alloc);
    defer cmd.deinit(alloc);

    try t.expectEqualDeep(cmd, ClientCommand{
        .ResponseKO = .{
            .data = "YEAH THERE ARE SOME THINGS HERE",
        },
    });
}

test "bad ko parsing" {
    const t = std.testing;
    const alloc = t.allocator;

    const cmd = parse("KOYEAH THERE ARE SOME THINGS HERE", alloc);
    try t.expectError(Error.NotEnoughWhitespace, cmd);
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

    const cmd = parse("OK YEAH THERE ARE SOME THINGS HERE", alloc);
    try t.expectError(Error.BadCommand, cmd);
}

test "bad ok parsing 2" {
    const t = std.testing;
    const alloc = t.allocator;

    const cmd = parse("OKYEAH THERE ARE SOME THINGS HERE", alloc);
    try t.expectError(Error.BadCommand, cmd);
}

test "debug log parsing" {
    const t = std.testing;
    const alloc = t.allocator;

    const cmd = try parse("DEBUG issou that works", alloc);

    defer cmd.deinit(alloc);

    try t.expectEqualDeep(cmd, ClientCommand{
        .CommandLog = .{
            .msg_type = ClientCommandLogType.Debug,
            .data = "issou that works",
        },
    });
}

test "info log parsing with whitespace" {
    const t = std.testing;
    const alloc = t.allocator;

    const cmd = try parse("MESSAGE \t  \t      issou that works", alloc);

    defer cmd.deinit(alloc);

    try t.expectEqualDeep(cmd, ClientCommand{
        .CommandLog = .{
            .msg_type = ClientCommandLogType.Info,
            .data = "issou that works",
        },
    });
}

test "error log parsing no msg" {
    const t = std.testing;
    const alloc = t.allocator;

    const cmd = parse("ERROR", alloc);
    try t.expectError(error.EndOfStream, cmd);
}

test "error log parsing with garbage" {
    const t = std.testing;
    const alloc = t.allocator;

    const cmd = parse("ERRORILOVEFOODABITTOOMUCH", alloc);
    try t.expectError(Error.UnknownCommand, cmd);
}

test "unknown log parsing one whitespace" {
    const t = std.testing;
    const alloc = t.allocator;

    const cmd = parse("UNKNOWN ", alloc);
    try t.expectError(error.EndOfStream, cmd);
}

test "debug log parsing multiple whitespace" {
    const t = std.testing;
    const alloc = t.allocator;

    const cmd = parse("DEBUG     \t    \t        ", alloc);
    try t.expectError(error.EndOfStream, cmd);
}

test "error log parsing with whitespace" {
    const t = std.testing;
    const alloc = t.allocator;

    const cmd = try parse("ERROR\t  \t      issou that works", alloc);

    defer cmd.deinit(alloc);

    try t.expectEqualDeep(cmd, ClientCommand{
        .CommandLog = .{
            .msg_type = ClientCommandLogType.Error,
            .data = "issou that works",
        },
    });
}
