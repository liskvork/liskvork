const std = @import("std");
const config = @import("config");

const semver = std.SemanticVersion.parse(config.version) catch @compileError("Given version is not valid semver");

pub fn main() !void {
    std.debug.print("Given version: {any}\n", .{semver});
}
