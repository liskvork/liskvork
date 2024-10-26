const std = @import("std");

const targets = [_]std.Target.Query{
    .{
        .cpu_arch = .x86_64,
        .os_tag = .linux,
    },
    .{
        .cpu_arch = .aarch64,
        .os_tag = .linux,
    },
    .{
        .cpu_arch = .x86_64,
        .os_tag = .macos,
    },
    .{
        .cpu_arch = .aarch64,
        .os_tag = .macos,
    },
    .{
        .cpu_arch = .x86_64,
        .os_tag = .windows,
    },
    .{
        .cpu_arch = .aarch64,
        .os_tag = .windows,
    },
};

const default_version_string = "0.0.0-dev";

const default_bin_name = "liskvork";

const build_options = struct {
    version: []const u8,
    build_all: bool,
    bin_name: []const u8,
    use_system_allocator: bool,
};

fn add_options_to_bin(b: *std.Build, bin: *std.Build.Step.Compile, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, opt: build_options) void {
    const ini_pkg = b.dependency("ini", .{ .target = target, .optimize = optimize });
    const logz_pkg = b.dependency("logz", .{ .target = target, .optimize = optimize });
    const zul_pkg = b.dependency("zul", .{ .target = target, .optimize = optimize });
    const httpz_pkg = b.dependency("httpz", .{ .target = target, .optimize = optimize });

    const options = b.addOptions();
    options.addOption([]const u8, "version", opt.version);
    options.addOption([]const u8, "bin_name", opt.bin_name);
    options.addOption(bool, "use_system_allocator", opt.use_system_allocator);

    bin.root_module.addOptions("build_config", options);
    bin.root_module.addImport("ini", ini_pkg.module("ini"));
    bin.root_module.addImport("logz", logz_pkg.module("logz"));
    bin.root_module.addImport("zul", zul_pkg.module("zul"));
    bin.root_module.addImport("httpz", httpz_pkg.module("httpz"));

    if (opt.use_system_allocator)
        bin.linkLibC();
}

fn configure_tests(b: *std.Build, opt: build_options, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    add_options_to_bin(b, unit_tests, target, optimize, opt);
    return unit_tests;
}

fn create_binary_name(opt: build_options, target: std.Build.ResolvedTarget, allocator: std.mem.Allocator) ![]const u8 {
    return try std.fmt.allocPrint(
        allocator,
        "{s}-{s}-{s}",
        .{
            opt.bin_name,
            opt.version,
            try target.result.linuxTriple(allocator),
        },
    );
}

fn configure_binary(b: *std.Build, opt: build_options, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, allocator: std.mem.Allocator, simple_bin_name: bool) !*std.Build.Step.Compile {
    const final_bin_name = if (simple_bin_name) opt.bin_name else try create_binary_name(
        opt,
        target,
        allocator,
    );
    const bin = b.addExecutable(.{
        .name = final_bin_name,
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/main.zig"),
    });
    add_options_to_bin(b, bin, target, optimize, opt);
    b.installArtifact(bin);
    return bin;
}

fn set_build_options(b: *std.Build) build_options {
    return .{
        .version = b.option(
            []const u8,
            "version",
            "application version string",
        ) orelse default_version_string,
        .build_all = b.option(
            bool,
            "build_all",
            "build on all platforms possible",
        ) orelse false,
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
    };
}

pub fn build(b: *std.Build) !void {
    const native_target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const opt = set_build_options(b);

    if (opt.build_all) {
        for (targets) |target|
            _ = try configure_binary(
                b,
                opt,
                std.Build.resolveTargetQuery(b, target),
                optimize,
                allocator,
                false,
            );
    } else {
        const liskvork = try configure_binary(
            b,
            opt,
            native_target,
            optimize,
            allocator,
            true,
        );

        const run_liskvork = b.addRunArtifact(liskvork);

        const run_step = b.step("run", "Run liskvork");
        run_step.dependOn(&run_liskvork.step);
    }

    const test_step = b.step("test", "Run unit tests");

    const unit_tests = configure_tests(b, opt, native_target, optimize);

    const run_unit_tests = b.addRunArtifact(unit_tests);
    // Uncomment ONLY if needed
    // run_unit_tests.has_side_effects = true;
    test_step.dependOn(&run_unit_tests.step);
}
