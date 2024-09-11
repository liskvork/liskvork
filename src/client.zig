const std = @import("std");

const net = @import("network");
const logz = @import("logz");

const Message = @import("message.zig").Message;

pub const Client = struct {
    const Self = @This();

    sock: net.Socket,
    msg: std.ArrayList(Message),
    internal_rbuffer: std.ArrayList(u8),
    internal_wbuffer: std.ArrayList(u8),
    stopping: bool = false,

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

    pub fn deinit(self: *const Self) void {
        self.msg.deinit();
        self.internal_rbuffer.deinit();
        self.internal_wbuffer.deinit();
        self.sock.close();
    }
};
