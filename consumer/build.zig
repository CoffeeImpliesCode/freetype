// SPDX-License-Identifier: MIT
//
//! Build graph for the standalone FreeType consumer.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const linkage = b.option(
        std.lang.LinkMode,
        "linkage",
        "Library linkage forwarded to the FreeType dependency",
    ) orelse .static;
    const runtime_loaded = b.option(
        bool,
        "runtime",
        "Load an explicit FreeType provider at run time instead of linking",
    ) orelse false;

    const dep = b.dependency("freetype", .{
        .target = target,
        .optimize = optimize,
        .linkage = linkage,
        .runtime = runtime_loaded,
    });

    // The dependency supplies libc through its public module.
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("freetype", dep.module("freetype"));

    const exe = b.addExecutable(.{
        .name = "freetype-consumer",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    run_exe.has_side_effects = true;
    run_exe.addPassthruArgs();
    const run_step = b.step("run", "Build and run the consumer program");
    run_step.dependOn(&run_exe.step);
}
