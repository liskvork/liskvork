const builtin = @import("builtin");

const std = @import("std");

const net = @import("network");

const config = @import("config.zig");

pub const Message = struct {
    const Self = @This();

    // Raw message as received from a client
    data: []const u8,
    // Time in microseconds when the message has been received
    timestamp: i64,
    // Allocator used to keep a copy of the original message
    allocator: std.mem.Allocator,

    pub fn init(data: []const u8, allocator: std.mem.Allocator) !Message {
        return .{
            .data = try allocator.dupe(u8, data),
            .timestamp = std.time.microTimestamp(),
        };
    }

    pub fn deinit(self: *const Self) void {
        self.allocator.free(self.data);
    }
};

pub const Client = struct {
    const Self = @This();

    sock: net.Socket,
    msg: std.ArrayList(Message),
    internal_rbuffer: std.ArrayList(u8),
    internal_wbuffer: std.ArrayList(u8),
    stopping: bool = false,

    fn init(allocator: std.mem.Allocator, sock: net.Socket) Client {
        return .{
            .sock = sock,
            .msg = std.ArrayList(Message).init(allocator),
            .internal_rbuffer = std.ArrayList(u8).init(allocator),
            .internal_wbuffer = std.ArrayList(u8).init(allocator),
        };
    }

    fn handle_event(self: *Self, set: *const net.SocketSet) !void {
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
            try self.internal_wbuffer.appendSlice(tmp_rbuf[0..nb_bytes]);
        }
        if (set.isReadyWrite(self.sock)) {
            const nb_bytes = try self.sock.send(self.internal_wbuffer.items);
            if (nb_bytes == self.internal_wbuffer.items.len) {
                self.internal_wbuffer.clearRetainingCapacity();
            } else {
                const src = self.internal_wbuffer.items[nb_bytes..];
                const dest = self.internal_wbuffer.items;
                std.mem.copyForwards(u8, dest, src);
            }
        }
    }

    fn wants_to_write(self: *const Self) bool {
        return self.internal_wbuffer.items.len > 0;
    }

    fn wants_to_read(self: *const Self) bool {
        return self.stopping == false;
    }

    fn deinit(self: *const Self) void {
        self.msg.deinit();
        self.internal_rbuffer.deinit();
        self.internal_wbuffer.deinit();
        self.sock.close();
    }
};

pub const Context = struct {
    const Self = @This();

    srv_sock: net.Socket,
    clients: std.ArrayList(Client),
    conf: *const config.config,

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

    while (true) {
        try setup_socket_set(&ctx, &set);
        const evt_return = try net.waitForSocketEvent(&set, null);
        const has_timeout_been_reached = evt_return == 0;
        _ = has_timeout_been_reached;
        for (ctx.clients.items) |*cli|
            try cli.handle_event(&set);
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
        break;
    }
}

test {
    std.testing.refAllDecls(@This());
}
