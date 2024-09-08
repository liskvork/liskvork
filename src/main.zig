const std = @import("std");
const build_config = @import("build_config");
const config = @import("config.zig");

const semver = std.SemanticVersion.parse(build_config.version) catch @compileError("Given version is not valid semver");

pub fn main() !void {
    std.debug.print("Launching liskvork version {any}\n", .{semver});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() != .ok) @panic("memory leaked");
    const allocator = gpa.allocator();

    const conf = try config.parse("config.ini", allocator);
    std.debug.print("Got conf: {any}\n", .{conf});
}

test {
    std.testing.refAllDecls(@This());
}
