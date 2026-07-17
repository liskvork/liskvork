const std = @import("std");
const builtin = @import("builtin");

const build_config = @import("build_config");

pub const semver = std.SemanticVersion.parse(build_config.version) catch @compileError("Given version is not valid semver");

pub const is_debug_build = builtin.mode == std.builtin.OptimizeMode.Debug;

pub var gpa = if (build_config.use_system_allocator) {} else std.heap.DebugAllocator(.{
    .safety = is_debug_build,
    .verbose_log = false, // abandon hope all ye who enter here
}){};

pub const allocator = if (build_config.use_system_allocator) std.heap.c_allocator else gpa.allocator();

pub var io: std.Io = undefined;

pub var process_args: std.process.Args = undefined;

pub fn init_process(init: std.process.Init) void {
    io = init.io;
    process_args = init.minimal.args;
}

pub fn milli_timestamp() i64 {
    return std.Io.Clock.now(.real, io).toMilliseconds();
}

pub fn micro_timestamp() i64 {
    return std.Io.Clock.now(.real, io).toMicroseconds();
}

pub const ReadWriteError = error{
    TimeoutError,
    ConnectionError,
};

// timeout in ms
// TODO: Handle timeouts on windows
pub fn read_with_timeout(f: std.Io.File, output: []u8, timeout: i32) !usize {
    if (builtin.os.tag == .windows) {
        // Windows is broken currently, will fix later ✨
        return 0;
    }
    if (builtin.os.tag != .windows) {
        var fds: [1]std.posix.pollfd = .{
            .{
                .fd = f.handle,
                .events = std.posix.POLL.IN | std.posix.POLL.HUP,
                .revents = 0,
            },
        };
        const poll_ret = try std.posix.poll(&fds, timeout);
        if (poll_ret == 0)
            return ReadWriteError.TimeoutError;
        std.debug.assert(poll_ret == 1);
        if (fds[0].revents & std.posix.POLL.HUP != 0)
            return ReadWriteError.ConnectionError;
    }
    return std.posix.read(f.handle, output);
}
