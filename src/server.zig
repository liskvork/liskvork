const builtin = @import("builtin");

const std = @import("std");

const logz = @import("logz");
const net = @import("network");

const build_config = @import("build_config");

const utils = @import("utils.zig");
const config = @import("config.zig");
const Client = @import("client.zig").Client;

pub const Context = struct {
    const Self = @This();

    srv_sock: net.Socket,
    clients: std.ArrayList(Client),
    conf: *const config.config,
    running: bool = true,

    pub fn init(allocator: std.mem.Allocator, conf: *const config.config, is_ipv6: bool) !Context {
        return .{
            .clients = std.ArrayList(Client).init(allocator),
            .conf = conf,
            .srv_sock = try net.Socket.create(
                if (is_ipv6) net.AddressFamily.ipv6 else net.AddressFamily.ipv4,
                net.Protocol.tcp,
            ),
        };
    }

    pub fn deinit(self: *const Self) void {
        for (self.clients.items) |c| {
            c.deinit();
        }
        self.clients.deinit();
    }
};

fn setup_socket_set(ctx: *const Context, set: *net.SocketSet) !void {
    set.clear();
    try set.add(ctx.srv_sock, .{ .read = true, .write = false });
    for (ctx.clients.items) |*cli|
        try set.add(cli.sock, .{
            .read = cli.wants_to_read(),
            .write = cli.wants_to_write(),
        });
}

fn handle_commands(ctx: *Context) !void {
    for (ctx.clients.items) |*cli| {
        for (cli.msg.items) |msg| {
            defer msg.deinit();
            logz.debug().ctx("Handling message").string("data", msg.data).int("timestamp", msg.timestamp).log();
            if (utils.is_debug_build and std.mem.eql(u8, msg.data, "STOP")) {
                ctx.running = false;
            }
        }
        cli.msg.clearRetainingCapacity();
    }
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

    while (ctx.running) {
        try setup_socket_set(&ctx, &set);
        const evt_return = try net.waitForSocketEvent(&set, null);
        const has_timeout_been_reached = evt_return == 0;
        _ = has_timeout_been_reached;
        for (ctx.clients.items) |*cli|
            try cli.handle_net_event(&set, allocator);
        if (set.isReadyRead(ctx.srv_sock)) {
            // Accept new connection
            const new_sock = try ctx.srv_sock.accept();
            try ctx.clients.append(Client.init(allocator, new_sock));
        }
        // Cleanup stopping clients
        var i: u32 = 0;
        while (i < ctx.clients.items.len) {
            if (ctx.clients.items[i].stopping) {
                ctx.clients.swapRemove(i).deinit();
                continue;
            }
            i += 1;
        }
        try handle_commands(&ctx);
    }
}

test {
    std.testing.refAllDecls(@This());
}
