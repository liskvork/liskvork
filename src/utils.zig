const std = @import("std");
const builtin = @import("builtin");

const build_config = @import("build_config");

pub const semver = std.SemanticVersion.parse(build_config.version) catch @compileError("Given version is not valid semver");

pub const is_debug_build = builtin.mode == std.builtin.OptimizeMode.Debug;

pub const SliceError = error{
    SliceTooSmall,
    NonWhitespaceInTrim,
};

pub fn skip_n_whitespace(slice: []const u8, n: usize) ![]const u8 {
    if (slice.len < n)
        return SliceError.SliceTooSmall;
    for (0..n, slice[0..n]) |_, a| {
        if (!std.ascii.isWhitespace(a))
            return SliceError.NonWhitespaceInTrim;
    }
    return slice[n..];
}
