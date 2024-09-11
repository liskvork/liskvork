const std = @import("std");
const builtin = @import("builtin");

const logz = @import("logz");
const zul = @import("zul");

const build_config = @import("build_config");

const config = @import("config.zig");
const server = @import("server.zig");
const utils = @import("utils.zig");

pub fn main() !void {
    const start_time = std.time.milliTimestamp();

    var gpa = std.heap.GeneralPurposeAllocator(.{
        .safety = utils.is_debug_build,
    }){};
    defer {
        // Don't panic in release builds, that should only be needed in debug
        if (gpa.deinit() != .ok and utils.is_debug_build)
            @panic("memory leaked");
    }
    const allocator = gpa.allocator();

    try logz.setup(allocator, .{
        .level = .Error,
        .output = .stdout,
        .encoding = .logfmt,
    });

    const conf = try config.parse("config.ini", allocator);
    defer config.deinit_config(config.config, &conf, allocator);

    try logz.setup(allocator, .{
        .level = conf.log_level,
        .output = .stdout,
        .encoding = .logfmt,
    });
    defer logz.deinit();

    logz.info().ctx("Launching liskvork").stringSafe("version", build_config.version).log();

    try server.launch_server(&conf, allocator);

    const close_time = std.time.milliTimestamp();
    const uptime = try zul.DateTime.fromUnix(close_time - start_time, .milliseconds);
    // TODO: Show days of uptime too (Not sure this is needed though)
    logz.info().ctx("Closing liskvork").fmt("uptime", "{}", .{uptime.time()}).log();
}

test {
    std.testing.refAllDecls(@This());
}
