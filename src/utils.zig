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
pub fn read_with_timeout(f: std.Io.File, output: []u8, timeout: i32) !usize {
    const SelectResult = union(enum) { timeout: anyerror!void, rd: anyerror!usize };
    var buf: [1]SelectResult = undefined;

    var select: std.Io.Select(SelectResult) = .init(io, &buf);
    defer select.cancelDiscard();

    const output_buf = &[_][]u8{output};

    try select.concurrent(.timeout, std.Io.sleep, .{ io, .fromMilliseconds(timeout), .awake });
    try select.concurrent(.rd, std.Io.File.readStreaming, .{ f, io, output_buf });

    return switch (try select.await()) {
        .timeout => error.RequestTimeout,
        .rd => |res| res,
    };
}
