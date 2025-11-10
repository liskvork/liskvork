const std = @import("std");
const builtin = @import("builtin");

const logz = @import("logz");
const zul = @import("zul");

const build_config = @import("build_config");

const config = @import("config.zig");
const server = @import("server.zig");
const utils = @import("utils.zig");

// Handles Program Arguments and returns true if execution should be stopped.
// TODO: make a proper argument handler in the future
pub fn handle_arguments() !bool {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--init-config")) {
            try config.create_default("config.ini");
            return true;
        }
    }
    return false;
}

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

    if (try handle_arguments())
        return;

    const conf = config.parse("config.ini") catch |err| {
        switch (err) {
            error.FileNotFound => {
                logz.err()
                    .ctx("Configuration file not found. Make sure that you run liskvork with the --init-config flag first.")
                    .string("filepath", "config.ini")
                    .log();
                return;
            },
            else => return err,
        }
    };
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
    logz.info().ctx("Closing liskvork").fmt("uptime", "{f}", .{uptime.time()}).log();
}

comptime {
    if (builtin.is_test) {
        std.testing.refAllDeclsRecursive(@This());
    }
}
