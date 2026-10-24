// SPDX-License-Identifier: MIT
// See FORK-LICENSE.md for what that identifier covers.

const std = @import("std");
const manifest = @import("build.zig.zon");
const graph = @import("runtime/graph.zig");

/// Package version; compared against the vendored headers.
const manifest_version = std.SemanticVersion.parse(manifest.version) catch
    @panic("build.zig.zon .version is not a semantic version");

/// Name shared by the dependency, module, and native artifact.
const lib_name = "freetype";
const facade_source = "zig/root.zig";
const translate_header = "zig/translate.h";
const test_source = "tests.zig";
const example_source = "smoke.zig";

const source_dir = "src";
const include_dir = "include";

/// Release read from `include/freetype/freetype.h:5170-5172`.
const upstream_version: std.SemanticVersion = .{ .major = 2, .minor = 14, .patch = 3 };

/// Derived from libtool's `version_info='26:6:20'` (`builds/unix/configure.raw:20`).
/// The SONAME is current minus age; the filename carries the full version.
const abi_version: std.SemanticVersion = .{ .major = 6, .minor = 26, .patch = 20 };

const base_sources = [_][]const u8{
    "src/base/ftbase.c",
    "src/base/ftinit.c",
};

/// Compile modules registered by `ftmodule.h`, not every entry in `modules.cfg`.
/// `ftcache_module_class` is not registered there, so `src/cache/` is not compiled.
const module_sources = [_][]const u8{
    "src/truetype/truetype.c",
    "src/type1/type1.c",
    "src/cff/cff.c",
    "src/cid/type1cid.c",
    "src/pfr/pfr.c",
    "src/type42/type42.c",
    "src/winfonts/winfnt.c",
    "src/pcf/pcf.c",
    "src/bdf/bdf.c",
    "src/sfnt/sfnt.c",
    "src/autofit/autofit.c",
    "src/pshinter/pshinter.c",
    "src/smooth/smooth.c",
    "src/raster/raster.c",
    "src/svg/svg.c",
    "src/sdf/sdf.c",
    "src/psaux/psaux.c",
    "src/psnames/psnames.c",
    "src/gzip/ftgzip.c",
    "src/lzw/ftlzw.c",
};

const base_extensions = [_][]const u8{
    "src/base/ftbbox.c",
    "src/base/ftbdf.c",
    "src/base/ftbitmap.c",
    "src/base/ftcid.c",
    "src/base/ftfstype.c",
    "src/base/ftgasp.c",
    "src/base/ftglyph.c",
    "src/base/ftgxval.c",
    "src/base/ftmm.c",
    "src/base/ftotval.c",
    "src/base/ftpatent.c",
    "src/base/ftpfr.c",
    "src/base/ftstroke.c",
    "src/base/ftsynth.c",
    "src/base/fttype1.c",
    "src/base/ftwinfnt.c",
};

/// FreeType's separate debug unit (`meson.build:247-252`).
const debug_source = "src/base/ftdebug.c";

/// Public headers and their configuration dependencies (`meson.build:139-195`).
const public_headers = [_][]const u8{
    "include/ft2build.h",
    "include/freetype/config/ftconfig.h",
    "include/freetype/config/ftheader.h",
    "include/freetype/config/ftoption.h",
    "include/freetype/config/ftstdlib.h",
    "include/freetype/config/integer-types.h",
    "include/freetype/config/mac-support.h",
    "include/freetype/config/public-macros.h",
    "include/freetype/freetype.h",
    "include/freetype/ftadvanc.h",
    "include/freetype/ftbbox.h",
    "include/freetype/ftbdf.h",
    "include/freetype/ftbitmap.h",
    "include/freetype/ftbzip2.h",
    "include/freetype/ftcache.h",
    "include/freetype/ftchapters.h",
    "include/freetype/ftcid.h",
    "include/freetype/ftcolor.h",
    "include/freetype/ftdriver.h",
    "include/freetype/fterrdef.h",
    "include/freetype/fterrors.h",
    "include/freetype/ftfntfmt.h",
    "include/freetype/ftgasp.h",
    "include/freetype/ftglyph.h",
    "include/freetype/ftgxval.h",
    "include/freetype/ftgzip.h",
    "include/freetype/ftimage.h",
    "include/freetype/ftincrem.h",
    "include/freetype/ftlcdfil.h",
    "include/freetype/ftlist.h",
    "include/freetype/ftlogging.h",
    "include/freetype/ftlzw.h",
    "include/freetype/ftmac.h",
    "include/freetype/ftmm.h",
    "include/freetype/ftmodapi.h",
    "include/freetype/ftmoderr.h",
    "include/freetype/ftotval.h",
    "include/freetype/ftoutln.h",
    "include/freetype/ftparams.h",
    "include/freetype/ftpfr.h",
    "include/freetype/ftrender.h",
    "include/freetype/ftsizes.h",
    "include/freetype/ftsnames.h",
    "include/freetype/ftstroke.h",
    "include/freetype/ftsynth.h",
    "include/freetype/ftsystem.h",
    "include/freetype/fttrigon.h",
    "include/freetype/fttypes.h",
    "include/freetype/ftwinfnt.h",
    "include/freetype/otsvg.h",
    "include/freetype/t1tables.h",
    "include/freetype/ttnameid.h",
    "include/freetype/tttables.h",
    "include/freetype/tttags.h",
};

/// Match upstream's `include/freetype2/` install path (`meson.build:477-478`).
const install_include_subdir = "freetype2";

/// License records installed under `share/licenses/freetype/`.
const licence_records = [_][]const u8{
    "LICENSE.TXT",
    "docs/FTL.TXT",
    "docs/GPLv2.TXT",
    "src/bdf/README",
    "src/pcf/README",
    "src/gzip/zlib.h",
    "tests/fixtures/COPYING",
    "README",
    "NOTICE.md",
    "FORK-LICENSE.md",
    "UPSTREAM.md",
    "UPSTREAM.sha256",
    "FORK-NOTES.md",
    "CHANGELOG.md",
    "README.md",
};

/// Leave the C dialect to the compiler, as upstream's Unix build does.
const c_flags = [_][]const u8{};

const Library = enum {
    bundled,
    system,
};

const check_targets = [_]std.Target.Query{
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .macos, .abi = .none },
    .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
    .{ .cpu_arch = .riscv64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .wasm32, .os_tag = .wasi },
};

/// WASI's `include/freetype/config/ftstdlib.h:166` includes `<setjmp.h>`.
/// wasi-libc requires `__wasm_exception_handling__` (`libc/include/wasm-wasi-musl/setjmp.h:13`).
/// Static linked checks retain WASI despite this toolchain boundary.
const refused_check_targets = [_]std.Target.Query{};

const Graph = struct {
    c_lib: ?*std.Build.Step.Compile,
    module: *std.Build.Module,
    platform: Platform,
};

const Platform = struct {
    system_source: []const u8,
    macros: []const [2][]const u8,
    separate_m: bool,
    /// Whether shared mode needs Windows import/export decoration.
    dll: bool,

    fn forTarget(target: std.Build.ResolvedTarget) Platform {
        return switch (target.result.os.tag) {
            .windows => .{
                .system_source = "builds/windows/ftsystem.c",
                .macros = &.{},
                .separate_m = false,
                .dll = true,
            },
            // The mmap implementation needs these headers (`meson.build:225-244`).
            .linux,
            .macos,
            .ios,
            .tvos,
            .watchos,
            .visionos,
            .freebsd,
            .netbsd,
            .openbsd,
            .dragonfly,
            .illumos,
            => .{
                .system_source = "builds/unix/ftsystem.c",
                // Define headers expected by `builds/unix/ftsystem.c:29-64`.
                .macros = &.{
                    .{ "HAVE_UNISTD_H", "1" },
                    .{ "HAVE_FCNTL_H", "1" },
                },
                .separate_m = true,
                .dll = false,
            },
            else => .{
                .system_source = "src/base/ftsystem.c",
                .macros = &.{},
                .separate_m = true,
                .dll = false,
            },
        };
    }

    fn kind(platform: Platform) []const u8 {
        if (std.mem.endsWith(u8, platform.system_source, "builds/unix/ftsystem.c")) {
            return "upstream's mmap ftsystem.c";
        }
        if (std.mem.endsWith(u8, platform.system_source, "builds/windows/ftsystem.c")) {
            return "upstream's Windows ftsystem.c";
        }
        return "upstream's stdio ftsystem.c";
    }
};

fn artifactName(b: *std.Build, target: std.Build.ResolvedTarget, public: bool) []const u8 {
    if (public) return lib_name;
    const triple = target.result.zigTriple(b.allocator) catch @panic("unspellable target");
    return b.fmt("{s}-{s}", .{ lib_name, triple });
}

/// Aro omits Clang's RISC-V float-ABI macro; pass it so translation matches the C build.
/// glibc's `jmp_buf` depends on that ABI and rejects single-float (`bits/setjmp.h:32-36`).
fn translateCRiscvFloatAbi(target: std.Build.ResolvedTarget) ?[2][]const u8 {
    switch (target.result.cpu.arch) {
        .riscv32, .riscv32be, .riscv64, .riscv64be => {},
        else => return null,
    }
    const abi: []const u8 = if (std.Target.riscv.featureSetHas(target.result.cpu.features, .d))
        "__riscv_float_abi_double"
    else if (std.Target.riscv.featureSetHas(target.result.cpu.features, .f))
        "__riscv_float_abi_single"
    else
        "__riscv_float_abi_soft";
    return .{ abi, "1" };
}

fn addGraph(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
    library: Library,
    linkage: std.lang.LinkMode,
    runtime_loaded: bool,
    public: bool,
) Graph {
    const platform = Platform.forTarget(target);

    const c_lib: ?*std.Build.Step.Compile = if (library == .bundled)
        add_c_library(b, target, optimize, linkage, platform, artifactName(b, target, public))
    else
        null;

    const no_macros: []const [2][]const u8 = &.{};
    const translate_macros = if (library == .bundled) platform.macros else no_macros;
    const translate_include: ?std.Build.LazyPath =
        if (library == .bundled) b.path(include_dir) else null;

    const translate = b.addTranslateC(.{
        .root_source_file = b.path(translate_header),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    // Translated headers include `ft2build.h` by bare name.
    if (translate_include) |dir| translate.addIncludePath(dir);
    for (translate_macros) |macro| translate.defineCMacro(macro[0], macro[1]);
    // Match C visibility: `FT2_BUILD_LIBRARY` controls `FT_LOCAL` (`compiler-macros.h`).
    translate.defineCMacro("FT2_BUILD_LIBRARY", "1");
    if (translateCRiscvFloatAbi(target)) |macro| translate.defineCMacro(macro[0], macro[1]);
    if (library == .system) {
        // Zig 0.17's TranslateC does not inherit the maker's search prefixes.
        b.graph.poisonCache();
        for (b.graph.search_prefixes.items) |prefix| {
            translate.addSystemIncludePath(.{ .cwd_relative = b.pathJoin(&.{ prefix, "include", install_include_subdir }) });
            translate.addSystemIncludePath(.{ .cwd_relative = b.pathJoin(&.{ prefix, "include" }) });
            translate.addCFlags(&.{ "-L", b.pathJoin(&.{ prefix, "lib" }) });
        }
        translate.linkSystemLibrary(lib_name, .{ .preferred_link_mode = linkage });
    }

    const module = if (public)
        b.addModule(lib_name, .{
            .root_source_file = b.path(facade_source),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        })
    else
        b.createModule(.{
            .root_source_file = b.path(facade_source),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });

    if (runtime_loaded) {
        // Do not link the archive in runtime mode; that would bypass the generated dispatch.
        module.addImport("c", graph.createModule(b, translate, target, optimize));
    } else {
        module.addImport("c", translate.createModule());
        module.addImport("rt", graph.createCoreModule(b, target, optimize));
        if (c_lib) |lib| module.linkLibrary(lib);
        if (library == .system and linkage == .static and platform.separate_m)
            module.linkSystemLibrary("m", .{});
    }
    if (library == .bundled) module.addIncludePath(b.path(include_dir));

    return .{ .c_lib = c_lib, .module = module, .platform = platform };
}

fn add_c_library(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
    requested: std.lang.LinkMode,
    platform: Platform,
    name: []const u8,
) *std.Build.Step.Compile {
    const linkage = deliveredLinkage(target, requested);
    const c_lib = b.addLibrary(.{
        .name = name,
        .linkage = linkage,
        .version = if (linkage == .dynamic) abi_version else null,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            // Shared objects require position-independent code.
            .pic = if (linkage == .dynamic) true else null,
        }),
    });
    const c_mod = c_lib.root_module;

    c_mod.addIncludePath(b.path(include_dir));
    // Keep C and translated header macros aligned.
    for (platform.macros) |macro| c_mod.addCMacro(macro[0], macro[1]);
    c_mod.addCMacro("FT2_BUILD_LIBRARY", "1");

    for (base_sources) |source| {
        c_mod.addCSourceFile(.{ .file = b.path(source), .flags = &c_flags });
    }
    for (module_sources) |source| {
        c_mod.addCSourceFile(.{ .file = b.path(source), .flags = &c_flags });
    }
    for (base_extensions) |source| {
        c_mod.addCSourceFile(.{ .file = b.path(source), .flags = &c_flags });
    }
    c_mod.addCSourceFile(.{
        .file = b.path(platform.system_source),
        .flags = &c_flags,
    });
    c_mod.addCSourceFile(.{ .file = b.path(debug_source), .flags = &c_flags });

    if (platform.separate_m) c_mod.linkSystemLibrary("m", .{});

    if (linkage == .dynamic) setVersionScript(b, c_lib, target);

    for (public_headers) |header| {
        const dest = std.fs.path.join(b.allocator, &.{ install_include_subdir, header["include/".len..] }) catch
            @panic("OOM naming a public header");
        c_lib.installHeader(b.path(header), dest);
    }

    return c_lib;
}

/// Restrict ELF exports to the header API; other formats use linker defaults.
/// Avoid a second maintained list of `FT_*` symbols.
fn setVersionScript(b: *std.Build, c_lib: *std.Build.Step.Compile, target: std.Build.ResolvedTarget) void {
    if (target.result.ofmt != .elf) return;
    const files = b.addWriteFiles();
    c_lib.setVersionScript(files.add("freetype.map",
        \\FREETYPE_2 {
        \\  global:
        \\    FT_*;
        \\  local:
        \\    *;
        \\};
        \\
    ));
}

fn targetHasDynamicLinker(target: std.Build.ResolvedTarget) bool {
    return target.result.os.tag == .windows or std.Target.DynamicLinker.kind(target.result.os.tag) != .none;
}

/// Reject dynamic mode without a dynamic linker; do not substitute static.
fn deliveredLinkage(target: std.Build.ResolvedTarget, requested: std.lang.LinkMode) std.lang.LinkMode {
    if (requested == .dynamic and !targetHasDynamicLinker(target)) {
        std.debug.panic(
            "freetype: -Dlinkage=dynamic was asked for {s}, which has no " ++
                "dynamic linker. Name a target with one, or build the static " ++
                "archive that is this package's default.",
            .{@tagName(target.result.os.tag)},
        );
    }
    return requested;
}

/// Compile one target's surface without running it.
fn add_target_check(
    b: *std.Build,
    cross_target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
    library: Library,
    linkage: std.lang.LinkMode,
    runtime_loaded: bool,
    step: *std.Build.Step,
) void {
    const triple = cross_target.result.zigTriple(b.allocator) catch @panic("unspellable target");
    const cross = addGraph(b, cross_target, optimize, library, linkage, runtime_loaded, false);

    const test_mod = b.createModule(.{
        .root_source_file = b.path(test_source),
        .target = cross_target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_mod.addImport(lib_name, cross.module);
    step.dependOn(&b.addTest(.{
        .name = b.fmt("freetype-tests-{s}", .{triple}),
        .root_module = test_mod,
    }).step);

    const example_mod = b.createModule(.{
        .root_source_file = b.path(example_source),
        .target = cross_target,
        .optimize = optimize,
        .link_libc = true,
    });
    example_mod.addImport(lib_name, cross.module);
    step.dependOn(&b.addExecutable(.{
        .name = b.fmt("freetype-smoke-{s}", .{triple}),
        .root_module = example_mod,
    }).step);
}

/// Generate the relocatable `freetype2.pc` file.
fn add_pkg_config(b: *std.Build, platform: Platform, linkage: std.lang.LinkMode) void {
    const files = b.addWriteFiles();
    const install_pc = b.addInstallFileWithDir(
        files.add("freetype2.pc", b.fmt(
            \\# freetype2.pc for the FreeType {f} SDK.
            \\#
            \\# FreeType's release tarball ships no pkg-config file; `freetype2.pc`
            \\# is generated by its install step. Every field below is this fork's,
            \\# and build.zig's add_pkg_config names the upstream line each one comes
            \\# from. `prefix` is pcfiledir-relative so the installed file is correct
            \\# wherever --prefix put it.
            \\#
            \\# The include root is `freetype2`, not `freetype`, because that is where
            \\# upstream installs these headers: `include/freetype/freetype.h:76-81`
            \\# writes the recipe as `#include <ft2build.h>` then
            \\# `#include <freetype/freetype.h>`, and both resolve under
            \\# `$(includedir)/freetype2`.
            \\prefix=${{pcfiledir}}/../..
            \\exec_prefix=${{prefix}}
            \\libdir=${{prefix}}/lib
            \\includedir=${{prefix}}/include
            \\
            \\Name: freetype2
            \\Description: A free, high-quality, and portable TrueType font engine
            \\Version: {f}
            \\
            \\Requires:
            \\Libs: -L"${{libdir}}" -lfreetype
            \\Libs.private: -lm
            \\Cflags: -I"${{includedir}}/{s}"{s}
            \\
        , .{
            upstream_version,
            upstream_version,
            install_include_subdir,
            if (linkage == .dynamic and platform.dll) " -DFT2_BUILD_LIBRARY" else "",
        })),
        .prefix,
        "lib/pkgconfig/freetype2.pc",
    );
    b.getInstallStep().dependOn(&install_pc.step);
}

/// Install license and provenance records under `share/licenses/freetype/`.
fn install_licence_records(b: *std.Build) void {
    for (licence_records) |record| {
        const install_record = b.addInstallFileWithDir(
            b.path(record),
            .prefix,
            b.fmt("share/licenses/freetype/{s}", .{std.fs.path.basename(record)}),
        );
        b.getInstallStep().dependOn(&install_record.step);
    }
}

/// Keep accepted and refused compile-check target sets disjoint and complete.
fn checkMatrixPartition(_: *std.Build) void {
    if (refused_check_targets.len != 0) {
        @panic("build.zig: refused_check_targets is not empty and this build has no refusal to record; see the module doc");
    }
}

fn runConsumer(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
    library: Library,
    linkage: std.lang.LinkMode,
    runtime_loaded: bool,
) *std.Build.Step.Run {
    const triple = target.query.zigTriple(b.allocator) catch @panic("OOM");
    defer b.allocator.free(triple);
    const cpu = target.query.serializeCpuAlloc(b.allocator) catch @panic("OOM");
    defer b.allocator.free(cpu);

    const run = b.addSystemCommand(&.{ b.graph.zig_exe, "build" });
    run.setName("consumer package");
    // Keep relative cache and Zig library environment paths anchored to the caller's cwd.
    run.addArg("--build-file");
    run.addFileArg2(b.path("consumer/build.zig"), .{ .make_absolute = true });
    for ([_][]const u8{ "ZIG_GLOBAL_CACHE_DIR", "ZIG_LIB_DIR" }) |key| {
        if (b.graph.environ_map.get(key)) |value| run.setEnvironmentVariable(key, value);
    }
    run.addArg(if (target.query.isNative()) "run" else "install");
    run.addArg(b.fmt("-Dtarget={s}", .{triple}));
    run.addArg(b.fmt("-Dcpu={s}", .{cpu}));
    run.addArg(b.fmt("-Doptimize={s}", .{@tagName(optimize)}));
    run.addArg(b.fmt("-Dlinkage={s}", .{@tagName(linkage)}));
    run.addArg(b.fmt("-Druntime={}", .{runtime_loaded}));
    run.addArg(if (library == .system) "-fsys=freetype" else "-fno-sys=freetype");
    if (library == .system) {
        b.graph.poisonCache();
        for (b.graph.search_prefixes.items) |prefix| {
            run.addArgs(&.{ "--search-prefix", prefix });
        }
    }
    run.addThirdPartyEnabledArgDarling(.{ .enabled = "-fdarling" });
    run.addThirdPartyEnabledArgQemu(.{ .enabled = "-fqemu" });
    run.addThirdPartyEnabledArgRosetta(.{ .enabled = "-frosetta" });
    run.addThirdPartyEnabledArgWasmtime(.{ .enabled = "-fwasmtime" });
    run.addThirdPartyEnabledArgWine(.{ .enabled = "-fwine" });
    run.addArgs(&.{ "-j8", "--summary", "all" });
    run.addArg("--cache-dir");
    run.addDirectoryArg2(
        .{ .relative = .{ .base = .local_cache, .sub_path = "consumer" } },
        .{ .make_absolute = true },
    );
    run.addArg("--prefix");
    run.addDirectoryArg2(
        .{ .relative = .{ .base = .install_prefix } },
        .{ .make_absolute = true },
    );
    run.addArg("--");
    run.addPassthruArgs();
    run.has_side_effects = true;
    return run;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const system_default = b.option(
        bool,
        "system",
        "Link an installed libfreetype instead of compiling src/. The default is false, because this package's job is to build FreeType from its own vendored source.",
    );
    const use_system = b.systemIntegrationOption(lib_name, .{ .default = system_default });
    const library: Library = if (use_system) .system else .bundled;

    const linkage_option = b.option(
        std.lang.LinkMode,
        "linkage",
        "How the library is delivered. static gives libfreetype.a, which is upstream's own build product; dynamic gives a real shared object.",
    );
    const linkage: std.lang.LinkMode = linkage_option orelse
        (if (library == .system) .dynamic else .static);

    const runtime_loaded = b.option(
        bool,
        "runtime",
        "Resolve FreeType's entry points through the platform loader at run time instead of linking them. Orthogonal to -Dlinkage, which still decides which artifact is delivered and installed. Default false.",
    ) orelse false;

    // Keep the manifest, vendored headers, and build report on one release.
    if (manifest_version.order(upstream_version) != .eq) {
        @panic("build.zig.zon .version no longer matches the version read out of include/freetype/freetype.h; see UPSTREAM.md");
    }

    checkMatrixPartition(b);

    const published = addGraph(b, target, optimize, library, linkage, runtime_loaded, true);

    if (published.c_lib) |c_lib| {
        b.installArtifact(c_lib);
        add_pkg_config(b, published.platform, deliveredLinkage(target, linkage));
        install_licence_records(b);
    }

    const example_mod = b.createModule(.{
        .root_source_file = b.path(example_source),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    example_mod.addImport(lib_name, published.module);
    const example = b.addExecutable(.{ .name = "freetype-smoke", .root_module = example_mod });
    b.getInstallStep().dependOn(&example.step);

    const run_example = b.addRunArtifact(example);
    run_example.addPassthruArgs();
    b.step("smoke", "Run the deterministic example program").dependOn(&run_example.step);

    b.step("consumer", "Build or run the standalone consumer package for the selected target")
        .dependOn(&runConsumer(b, target, optimize, library, linkage, runtime_loaded).step);

    const test_mod = b.createModule(.{
        .root_source_file = b.path(test_source),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_mod.addImport(lib_name, published.module);
    const unit_tests = b.addTest(.{ .name = "freetype-tests", .root_module = test_mod });
    const run_tests = b.addRunArtifact(unit_tests);
    run_tests.has_side_effects = true;
    b.step("test", "Run the behavioural tests").dependOn(&run_tests.step);

    const check_step = b.step(
        "check",
        "Compile the library, facade, tests and example for the cross targets, running nothing",
    );
    if (!target.query.isNative()) {
        add_target_check(b, target, optimize, library, linkage, runtime_loaded, check_step);
    } else {
        for (check_targets[0..]) |query| {
            const cross_target = b.resolveTargetQuery(query);
            if ((linkage == .dynamic or runtime_loaded) and !targetHasDynamicLinker(cross_target)) continue;
            add_target_check(b, cross_target, optimize, library, linkage, runtime_loaded, check_step);
        }
    }

    std.debug.print(
        \\
        \\freetype {f}, compiled from this repository's own src/ and builds/
        \\  units: {d} base + {d} modules + {d} base extensions + ftsystem + ftdebug
        \\  include root: {s}/  (installed as {s})
        \\  platform: {s}
        \\  delivery: {s}
        \\
    , .{
        upstream_version,
        base_sources.len,
        module_sources.len,
        base_extensions.len,
        include_dir,
        install_include_subdir,
        published.platform.kind(),
        if (library == .system)
            "an installed libfreetype"
        else switch (deliveredLinkage(target, linkage)) {
            .static => "a static archive, libfreetype.a",
            .dynamic => b.fmt("a shared object, libfreetype.so.{d}.{d}.{d} (SONAME libfreetype.so.{d})", .{
                abi_version.major,
                abi_version.minor,
                abi_version.patch,
                abi_version.major,
            }),
        },
    });

    if (runtime_loaded) {
        std.debug.print(
            "  dispatch: every FT_* entry point is resolved through the platform loader; call load() first\n",
            .{},
        );
    }
    if (library == .system) {
        std.debug.print(
            "  system mode: nothing is compiled from src/, and this package's tests are not a result about that library\n",
            .{},
        );
    }
}
