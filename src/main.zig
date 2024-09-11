const std = @import("std");
const builtin = @import("builtin");

const logz = @import("logz");
const zul = @import("zul");

const build_config = @import("build_config");

const config = @import("config.zig");
const server = @import("server.zig");

pub const semver = std.SemanticVersion.parse(build_config.version) catch @compileError("Given version is not valid semver");

pub const is_debug_build = builtin.mode == std.builtin.OptimizeMode.Debug;

pub fn main() !void {
    const start_time = std.time.milliTimestamp();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        // Don't panic in release builds, that should only be needed in debug
        if (gpa.deinit() != .ok and is_debug_build)
            @panic("memory leaked");
    }
    const allocator = gpa.allocator();

    try logz.setup(allocator, .{
        .level = if (is_debug_build) .Debug else .Info,
        .output = .stdout,
        .encoding = .logfmt,
    });
    defer logz.deinit();

    logz.info().ctx("Launching liskvork").stringSafe("version", build_config.version).log();

    const conf = try config.parse("config.ini", allocator);
    try server.launch_server(&conf, allocator);
    config.deinit_config(config.config, &conf, allocator);

    const close_time = std.time.milliTimestamp();
    const uptime = try zul.DateTime.fromUnix(close_time - start_time, .milliseconds);
    // TODO: Show days of uptime too (Not sure this is needed though)
    logz.info().ctx("Closing liskvork").fmt("uptime", "{}", .{uptime.time()}).log();
}

test {
    std.testing.refAllDecls(@This());
}
