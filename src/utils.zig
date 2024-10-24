const std = @import("std");
const builtin = @import("builtin");

const build_config = @import("build_config");

pub const semver = std.SemanticVersion.parse(build_config.version) catch @compileError("Given version is not valid semver");

pub const is_debug_build = builtin.mode == std.builtin.OptimizeMode.Debug;

pub var gpa = std.heap.GeneralPurposeAllocator(.{
    .safety = is_debug_build,
    .verbose_log = false, // abandon hope all ye who enter here
}){};

pub const allocator = gpa.allocator();

pub const SliceError = error{
    SliceTooSmall,
    NonWhitespaceInTrim,
};

pub fn all_respect(T: type, slice: []const T, predicate: fn (val: T) bool) bool {
    for (slice) |i| {
        if (!predicate(i))
            return false;
    }
    return true;
}

pub inline fn is_all_whitespace(slice: []const u8) bool {
    return all_respect(u8, slice, std.ascii.isWhitespace);
}

pub fn skip_n_whitespace(slice: []const u8, n: usize) ![]const u8 {
    if (slice.len < n)
        return SliceError.SliceTooSmall;
    if (!is_all_whitespace(slice[0..n]))
        return SliceError.NonWhitespaceInTrim;
    return slice[n..];
}

pub const ReadWriteError = error{
    TimeoutError,
};

// timeout in ms
// TODO: Handle timeouts on windows
pub fn read_with_timeout(f: std.fs.File, output: []u8, timeout: i32) !usize {
    if (builtin.os.tag != .windows) {
        var fds: [1]std.posix.pollfd = .{
            .{
                .fd = f.handle,
                .events = std.posix.POLL.IN,
                .revents = 0,
            },
        };
        const poll_ret = try std.posix.poll(&fds, timeout);
        if (poll_ret == 0)
            return ReadWriteError.TimeoutError;
        if (poll_ret == -1)
            unreachable; // Not so sure about that :|
        std.debug.assert(poll_ret == 1);
    }
    return std.posix.read(f.handle, output);
}
