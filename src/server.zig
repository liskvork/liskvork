const builtin = @import("builtin");

const std = @import("std");

const logz = @import("logz");
const net = @import("network");

const build_config = @import("build_config");

const utils = @import("utils.zig");
const config = @import("config.zig");
const client = @import("client.zig");
const Client = client.Client;

const Cache = struct {
    const Self = @This();

    handshake: []const u8,
    players: [2]?*Client = .{ null, null },

    allocator: std.mem.Allocator,
    fn init(conf: *const config.config, allocator: std.mem.Allocator) !Cache {
        const hs = try std.fmt.allocPrint(
            allocator,
            "HELLO {s} {s} \"{s}\"\n",
            .{ build_config.bin_name, build_config.version, conf.other_motd },
        );
        return .{
            .handshake = hs,
            .allocator = allocator,
        };
    }

    fn deinit(self: *const Self) void {
        self.allocator.free(self.handshake);
    }
};

pub const Context = struct {
    const Self = @This();

    srv_sock: net.Socket,
    clients: std.ArrayList(*Client),
    conf: *const config.config,
    running: bool = true,
    cache: Cache,
    nb_players: u8 = 0,
    nb_spectators: u8 = 0,
    game_launched: bool = false,
    players_accepted: bool = false,

    pub fn init(allocator: std.mem.Allocator, conf: *const config.config, is_ipv6: bool) !Context {
        return .{
            .clients = std.ArrayList(*Client).init(allocator),
            .conf = conf,
            .srv_sock = try net.Socket.create(
                if (is_ipv6) net.AddressFamily.ipv6 else net.AddressFamily.ipv4,
                net.Protocol.tcp,
            ),
            .cache = try Cache.init(conf, allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.clients.items) |c| {
            c.deinit(self);
        }
        self.clients.deinit();
        self.cache.deinit();
    }
};

fn setup_socket_set(ctx: *const Context, set: *net.SocketSet) !void {
    set.clear();
    try set.add(ctx.srv_sock, .{ .read = true, .write = false });
    for (ctx.clients.items) |cli|
        try set.add(cli.sock, .{
            .read = cli.wants_to_read(),
            .write = cli.wants_to_write(),
        });
}

fn handle_commands(ctx: *Context, allocator: std.mem.Allocator) !void {
    for (ctx.clients.items) |cli|
        try cli.handle_logic(ctx, allocator);
}

pub fn launch_server(conf: *const config.config, allocator: std.mem.Allocator) !void {
    const is_ipv6: bool = switch (conf.network_ip) {
        .ipv4 => false,
        .ipv6 => true,
    };
    var ctx = try Context.init(allocator, conf, is_ipv6);
    defer ctx.deinit();

    try ctx.srv_sock.enablePortReuse(true);
    try ctx.srv_sock.bind(.{
        .address = conf.network_ip,
        .port = conf.network_port,
    });
    try ctx.srv_sock.listen();
    var set = try net.SocketSet.init(allocator);
    defer set.deinit();

    main: while (ctx.running) {
        try setup_socket_set(&ctx, &set);
        const evt_return = try net.waitForSocketEvent(&set, null);
        const has_timeout_been_reached = evt_return == 0;
        _ = has_timeout_been_reached;
        for (ctx.clients.items) |cli|
            try cli.handle_net_event(&set, allocator);
        if (set.isReadyRead(ctx.srv_sock)) {
            // Accept new connection
            const new_sock = try ctx.srv_sock.accept();
            try ctx.clients.append(try Client.init(allocator, new_sock));
        }
        // Cleanup stopping clients
        var i: u32 = 0;
        while (i < ctx.clients.items.len) {
            if (ctx.clients.items[i].stopping) {
                ctx.clients.swapRemove(i).deinit(&ctx);
                continue;
            }
            i += 1;
        }
        try handle_commands(&ctx, allocator);
        if (ctx.game_launched and !ctx.players_accepted) {
            for (ctx.cache.players) |p| {
                std.debug.assert(p != null);
                if (p.?.state == .PWaitingForStartAnswer)
                    continue :main;
            }
            ctx.players_accepted = true;
            try ctx.cache.players[0].?.begin();
        }
        if (!ctx.game_launched and ctx.nb_players == 2) {
            var p_idx: usize = 0;
            for (ctx.clients.items) |c| {
                if (c.ctype == .Player) {
                    ctx.cache.players[p_idx] = c;
                    c.player_cache_idx = p_idx;
                    p_idx += 1;
                }
            }
            std.debug.assert(p_idx == 2);
            ctx.game_launched = true;
            try ctx.cache.players[0].?.start(&ctx, allocator);
            try ctx.cache.players[1].?.start(&ctx, allocator);
        }
    }
}

test {
    std.testing.refAllDecls(@This());
}
