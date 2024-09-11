const std = @import("std");
const builtin = @import("builtin");

const build_config = @import("build_config");

pub const semver = std.SemanticVersion.parse(build_config.version) catch @compileError("Given version is not valid semver");

pub const is_debug_build = builtin.mode == std.builtin.OptimizeMode.Debug;
