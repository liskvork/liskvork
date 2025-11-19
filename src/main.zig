const std = @import("std");
const builtin = @import("builtin");

const logz = @import("logz");
const zul = @import("zul");
const clap = @import("clap");

const build_config = @import("build_config");

const config = @import("config.zig");
const server = @import("server.zig");
const utils = @import("utils.zig");
const args = @import("args.zig");

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

    const args_data = try args.handle();

    if (args_data.help_flag) {
        return try args.print_help();
    }

    if (args_data.init_config) {
        return try config.create_default("config.ini");
    }

    var conf = config.parse(args_data.config_path) catch |err| {
        switch (err) {
            error.FileNotFound => {
                logz.err()
                    .ctx("Configuration file not found. Make sure that you run liskvork with the --init-config flag first.")
                    .string("filepath", args_data.config_path)
                    .log();
                return;
            },
            else => return err,
        }
    };
    defer config.deinit_config(config.Config, &conf);
    conf.override(args_data);
    if (args_data.no_replay)
        conf.log_replay_file_enabled = false;

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
