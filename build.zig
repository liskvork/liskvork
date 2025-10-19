const std = @import("std");

const default_version_string = "0.6.0-dev";

const default_bin_name = "liskvork";

const build_options = struct {
    version: []const u8,
    bin_name: []const u8,
    use_system_allocator: bool,
    llvm: bool,
};

fn add_options_to_bin(b: *std.Build, bin: *std.Build.Step.Compile, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, opt: build_options) void {
    const ini_pkg = b.dependency("ini", .{ .target = target, .optimize = optimize });
    const logz_pkg = b.dependency("logz", .{ .target = target, .optimize = optimize });
    const zul_pkg = b.dependency("zul", .{ .target = target, .optimize = optimize });
    const libgomoku_pkg = b.dependency("libgomoku", .{ .target = target, .optimize = optimize, .llvm = opt.llvm });

    const options = b.addOptions();
    options.addOption([]const u8, "version", opt.version);
    options.addOption([]const u8, "bin_name", opt.bin_name);
    options.addOption(bool, "use_system_allocator", opt.use_system_allocator);

    bin.root_module.addOptions("build_config", options);
    bin.root_module.addImport("ini", ini_pkg.module("ini"));
    bin.root_module.addImport("logz", logz_pkg.module("logz"));
    bin.root_module.addImport("zul", zul_pkg.module("zul"));
    bin.root_module.addImport("gomoku_game", libgomoku_pkg.module("gomoku_game"));
    bin.root_module.addImport("gomoku_protocol", libgomoku_pkg.module("gomoku_protocol"));
}

fn set_build_options(b: *std.Build) build_options {
    return .{
        .version = b.option(
            []const u8,
            "version",
            "application version string",
        ) orelse default_version_string,
        .bin_name = b.option(
            []const u8,
            "bin_name",
            "base bin name",
        ) orelse "liskvork",
        .use_system_allocator = b.option(
            bool,
            "use_system_allocator",
            "use the system allocator (libc)",
        ) orelse false,
        .llvm = b.option(
            bool,
            "llvm",
            "Use LLVM backend",
        ) orelse true,
    };
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const opt = set_build_options(b);

    const liskvork_mod = b.createModule(.{
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path("src/main.zig"),
        .link_libc = opt.use_system_allocator,
    });

    const liskvork_bin = b.addExecutable(.{
        .root_module = liskvork_mod,
        .use_llvm = opt.llvm,
        .name = opt.bin_name,
    });
    add_options_to_bin(b, liskvork_bin, target, optimize, opt);
    b.installArtifact(liskvork_bin);

    const run_cmd = b.addRunArtifact(liskvork_bin);

    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run liskvork");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run unit tests");

    const unit_tests = b.addTest(.{
        .root_module = liskvork_mod,
        .use_llvm = opt.llvm,
        .test_runner = .{
            .path = b.path("test_runner.zig"),
            .mode = .simple,
        },
    });
    add_options_to_bin(b, unit_tests, target, optimize, opt);

    const run_unit_tests = b.addRunArtifact(unit_tests);
    run_unit_tests.has_side_effects = true;
    test_step.dependOn(&run_unit_tests.step);
}
