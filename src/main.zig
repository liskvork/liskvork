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

    defer {
        // Don't panic in release builds, that should only be needed in debug
        if (!build_config.use_system_allocator) {
            if (utils.gpa.deinit() != .ok and utils.is_debug_build)
                @panic("memory leaked");
        }
    }

    try logz.setup(utils.allocator, .{
        .level = .Warn,
        .output = .stdout,
        .encoding = .logfmt,
    });
    defer logz.deinit();

    const conf = try config.parse("config.ini");
    defer config.deinit_config(config.Config, &conf);

    try logz.setup(utils.allocator, .{
        .level = conf.log_level,
        .output = .stdout,
        .encoding = .logfmt,
    });

    logz.info().ctx("Launching liskvork").stringSafe("version", build_config.version).log();

    try server.launch_server(&conf);

    const close_time = std.time.milliTimestamp();
    const uptime = try zul.DateTime.fromUnix(close_time - start_time, .milliseconds);
    // TODO: Show days of uptime too (Not sure this is needed though)
    logz.info().ctx("Closing liskvork").fmt("uptime", "{}", .{uptime.time()}).log();
}

test {
    std.testing.refAllDecls(@This());
}
