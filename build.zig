const std = @import("std");

const default_version_string = "0.6.0-dev";

const default_bin_name = "liskvork";

const target_archs = [_]std.Target.Cpu.Arch{
    .x86_64,
    .aarch64,
    .riscv64,
};

const target_oss = [_]std.Target.Os.Tag{
    .linux,
    .windows,
    .macos,
    .freebsd,
    .netbsd,
};

const build_options = struct {
    version: []const u8,
    bin_name: []const u8,
    use_system_allocator: bool,
    llvm: ?bool,
    build_all: bool,
};

fn add_options_to_bin(b: *std.Build, bin: *std.Build.Step.Compile, opt: build_options) void {
    const options = b.addOptions();
    options.addOption([]const u8, "version", opt.version);
    options.addOption([]const u8, "bin_name", opt.bin_name);
    options.addOption(bool, "use_system_allocator", opt.use_system_allocator);

    bin.root_module.addOptions("build_config", options);
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
        ),
        .build_all = b.option(
            bool,
            "build_all",
            "build on all platforms possible",
        ) orelse false,
    };
}

fn create_binary_name(opt: build_options, target: std.Build.ResolvedTarget, allocator: std.mem.Allocator) ![]const u8 {
    return try std.fmt.allocPrint(
        allocator,
        "{s}-{s}-{s}",
        .{
            opt.bin_name,
            try std.fmt.allocPrint(allocator, "{s}-{s}", .{
                @tagName(target.result.cpu.arch),
                @tagName(target.result.os.tag),
            }),
            opt.version,
        },
    );
}

fn supports(comptime os: std.Target.Os.Tag, arch: std.Target.Cpu.Arch) bool {
    return switch (arch) {
        .aarch64 => switch (os) {
            .windows, .linux, .freebsd, .macos, .netbsd => true,
            else => @panic("No idea if " ++ @tagName(os) ++ " supports " ++ @tagName(arch)),
        },
        .x86_64 => switch (os) {
            .windows, .linux, .freebsd, .macos, .netbsd => true,
            else => @panic("No idea if " ++ @tagName(os) ++ " supports " ++ @tagName(arch)),
        },
        .riscv64 => switch (os) {
            .linux, .freebsd => true,
            .windows, .macos, .netbsd => false,
            else => @panic("No idea if " ++ @tagName(os) ++ " supports " ++ @tagName(arch)),
        },
        else => @panic("No idea if " ++ @tagName(os) ++ " supports " ++ @tagName(arch)),
    };
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const opt = set_build_options(b);

    const pkg_args = .{ .target = target, .optimize = optimize };
    const ini_pkg = b.dependency("ini", pkg_args);
    const logz_pkg = b.dependency("logz", pkg_args);
    const zul_pkg = b.dependency("zul", pkg_args);
    const libgomoku_pkg = b.dependency("libgomoku", pkg_args);
    const zigclap_pkg = b.dependency("clap", pkg_args);

    if (opt.build_all) {
        // We want to build all targets, to check if all platforms build or to
        // release some binaries
        inline for (target_archs) |t_arch| {
            inline for (target_oss) |t_os| {
                if (comptime !supports(t_os, t_arch))
                    continue;
                const t: std.Target.Query = .{
                    .cpu_arch = t_arch,
                    .os_tag = t_os,
                };
                const resolved_target = std.Build.resolveTargetQuery(b, t);
                const liskvork_mod = b.createModule(.{
                    .optimize = optimize,
                    .target = resolved_target,
                    .root_source_file = b.path("src/main.zig"),
                    .link_libc = opt.use_system_allocator,
                    .imports = &.{
                        .{ .name = "ini", .module = ini_pkg.module("ini") },
                        .{ .name = "logz", .module = logz_pkg.module("logz") },
                        .{ .name = "zul", .module = zul_pkg.module("zul") },
                        .{ .name = "clap", .module = zigclap_pkg.module("clap") },
                        .{ .name = "gomoku_game", .module = libgomoku_pkg.module("gomoku_game") },
                        .{ .name = "gomoku_protocol", .module = libgomoku_pkg.module("gomoku_protocol") },
                    },
                });

                const liskvork_bin = b.addExecutable(.{
                    .root_module = liskvork_mod,
                    .use_llvm = opt.llvm,
                    .name = try create_binary_name(opt, resolved_target, b.allocator),
                });
                add_options_to_bin(b, liskvork_bin, opt);
                b.installArtifact(liskvork_bin);
            }
        }
        return;
    }

    // Not building for all targets, setup tests and run steps
    const liskvork_mod = b.createModule(.{
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path("src/main.zig"),
        .link_libc = opt.use_system_allocator,
        .imports = &.{
            .{ .name = "ini", .module = ini_pkg.module("ini") },
            .{ .name = "logz", .module = logz_pkg.module("logz") },
            .{ .name = "zul", .module = zul_pkg.module("zul") },
            .{ .name = "clap", .module = zigclap_pkg.module("clap") },
            .{ .name = "gomoku_game", .module = libgomoku_pkg.module("gomoku_game") },
            .{ .name = "gomoku_protocol", .module = libgomoku_pkg.module("gomoku_protocol") },
        },
    });

    const liskvork_bin = b.addExecutable(.{
        .root_module = liskvork_mod,
        .use_llvm = opt.llvm,
        .name = opt.bin_name,
    });
    add_options_to_bin(b, liskvork_bin, opt);
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
    add_options_to_bin(b, unit_tests, opt);

    const run_unit_tests = b.addRunArtifact(unit_tests);
    run_unit_tests.has_side_effects = true;
    test_step.dependOn(&run_unit_tests.step);
}
