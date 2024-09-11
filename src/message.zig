const std = @import("std");

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
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *const Self) void {
        self.allocator.free(self.data);
    }
};
