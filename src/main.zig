const std = @import("std");
const builtin = @import("builtin");
const logz = @import("logz");

const build_config = @import("build_config");

const config = @import("config.zig");

const semver = std.SemanticVersion.parse(build_config.version) catch @compileError("Given version is not valid semver");

const is_debug_build = builtin.mode == std.builtin.OptimizeMode.Debug;

pub fn main() !void {
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
    _ = conf;
}

test {
    std.testing.refAllDecls(@This());
}
