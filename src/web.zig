const std = @import("std");

const httpz = @import("httpz");
const websocket = httpz.websocket;
const logz = @import("logz");

const utils = @import("utils.zig");
const config = @import("config.zig");
const game = @import("game.zig");

// Shared between requests
var conf: *const config.Config = undefined;
var moves_mtx: std.Thread.Mutex = .{};
var moves = std.ArrayList(Move).init(utils.allocator);
var moves_str_cache = std.ArrayList(u8).init(utils.allocator);
// \Shared between requests

fn handle_not_found(_: *httpz.Request, res: *httpz.Response) !void {
    res.status = 404;
    res.body = "Not Found";
}

fn handle_errors(req: *httpz.Request, res: *httpz.Response, err: anyerror) void {
    res.status = 500;
    res.body = "Internal Server Error";
    logz.warn().ctx("httpz: unhandled exception").string("request", req.url.raw).fmt("err", "{}", .{err}).log();
}

const root_file = @embedFile("html/index.html");

fn handle_root(_: *httpz.Request, res: *httpz.Response) !void {
    res.status = 200;
    res.body = root_file;
}

fn handle_moves(req: *httpz.Request, res: *httpz.Response) !void {
    res.status = 200;
    moves_mtx.lock();
    defer moves_mtx.unlock();
    res.body = try req.arena.dupe(u8, moves_str_cache.items);
}

const WsContext = struct {};

const WsHandler = struct {
    const Self = @This();

    ctx: WsContext,
    conn: *websocket.Conn,
    pub fn init(conn: *websocket.Conn, ctx: WsContext) !Self {
        return .{
            .ctx = ctx,
            .conn = conn,
        };
    }

    pub fn handle(self: *WsHandler, _: websocket.Message) !void {
        moves_mtx.lock();
        defer moves_mtx.unlock();
        try self.conn.write(moves_str_cache.items);
    }

    pub fn close(_: *WsHandler) void {}
};

fn ws(req: *httpz.Request, res: *httpz.Response) !void {
    if (try httpz.upgradeWebsocket(WsHandler, req, res, WsContext{}) == false) {
        // this was not a valid websocket handshake request
        // you should probably return with an error
        res.status = 400;
        res.body = "invalid websocket handshake";
        return;
    }
    // when upgradeWebsocket succeeds, you can no longer use `res`
}

pub const Move = struct {
    const Self = @This();

    pos: game.Position,
    t: game.MoveType,

    pub fn format(self: Self, buf: []u8) usize {
        const a = std.fmt.formatIntBuf(buf, self.pos[0], 10, .lower, .{});
        buf[a] = ',';
        const b = std.fmt.formatIntBuf(buf[a + 1 ..], self.pos[1], 10, .lower, .{});
        buf[a + b + 1] = ',';
        buf[a + b + 2] = if (self.t == .Player1) '1' else '2';
        buf[a + b + 3] = '\n';
        return a + b + 4;
    }
};

pub const Server = struct {
    const Self = @This();

    srv: httpz.ServerCtx(void, void),
    thr: std.Thread = undefined,

    pub fn init(cf: *const config.Config) !Self {
        var srv = try httpz.Server().init(
            utils.allocator,
            .{
                .port = cf.web_port,
                .address = cf.web_address,
            },
        );
        srv.notFound(handle_not_found);
        srv.errorHandler(handle_errors);

        const router = srv.router();
        router.get("/", handle_root);
        router.get("/moves", handle_moves);
        router.get("/ws", ws);

        conf = cf;

        return .{
            .srv = srv,
        };
    }

    pub fn launch_in_background(self: *Self) !void {
        logz.info().ctx("Launching spectator web server").fmt(
            "address",
            "http://{s}:{}",
            .{
                conf.web_address,
                conf.web_port,
            },
        ).log();
        self.thr = try std.Thread.spawn(
            .{},
            launch,
            .{self},
        );
    }

    fn update_move_cache_unsafe(self: *Self) !void {
        _ = self;
        moves_str_cache.clearRetainingCapacity();
        var buf: [64]u8 = undefined;
        for (moves.items) |m| {
            const n = m.format(&buf);
            try moves_str_cache.appendSlice(buf[0..n]);
        }
        if (moves_str_cache.items.len == 0)
            try moves_str_cache.appendSlice("EMPTY\n");
    }

    fn update_move_cache(self: *Self) !void {
        moves_mtx.lock();
        defer moves_mtx.unlock();

        return self.update_move_cache_unsafe();
    }

    fn launch(self: *Self) !void {
        moves_mtx.lock();
        try self.update_move_cache_unsafe();
        moves_mtx.unlock();
        return self.srv.listen();
    }

    pub fn deinit(self: *Self) void {
        self.srv.stop();
        self.thr.join();
        self.srv.deinit();
        moves.deinit();
        moves_str_cache.deinit();
    }

    pub fn push_move(self: *Self, pos: game.Position, t: game.MoveType) !void {
        moves_mtx.lock();
        defer moves_mtx.unlock();

        try moves.append(.{
            .pos = pos,
            .t = t,
        });
        try self.update_move_cache_unsafe();
    }
};
