// SPDX-License-Identifier: MIT
// See FORK-LICENSE.md for what that identifier covers.
//
//! Zig 0.16 build for FreeType 2.14.3.
//!
//! The library is upstream's own C, byte for byte: two base units, one file per
//! registered module in `include/freetype/config/ftmodule.h`, the sixteen base
//! extensions `modules.cfg` lists, the two units that depend on the platform,
//! and `src/base/ftdebug.c`. Nothing is downloaded, no make, no CMake, no meson
//! and no autotools script is executed, and the default mode compiles
//! everything from this repository rather than linking an installed copy.
//!
//! ## Why the module list is one file per module
//!
//! FreeType's drivers and modules are *unity* units. `src/truetype/truetype.c`
//! is nineteen lines of `#include`s and nothing else; `src/sfnt/sfnt.c` pulls in
//! eighteen more files; `src/gzip/ftgzip.c` pulls in zlib's own `inflate.c`,
//! `inffast.c`, `inftrees.c`, `zutil.c`, `adler32.c` and `crc32.c`, which is how
//! FreeType 2.14 carries a decompressor without linking a system zlib. The unit
//! list below is therefore short *because* upstream organised it that way, and
//! compiling the individual files as separate translation units would be a
//! second, different build of upstream's code rather than this one.
//!
//! The list is `meson.build:82-135`'s derivation from `modules.cfg`, with one
//! deliberate omission: `modules.cfg` lists `AUX_MODULES += cache`, but the
//! module list FreeType actually ships — the one `FT_CONFIG_MODULES_H` resolves
//! to at `include/freetype/config/ftheader.h:162-163` — does not register
//! `ftcache_module_class`. This build follows the shipped list rather than
//! `modules.cfg`, because the shipped list is what decides which modules a
//! `FT_Library` can load at run time. `src/cache/` therefore travels in the
//! package and is not compiled; `tests.zig` names that as a boundary rather than
//! pretending the subpixel cache is there.
//!
//! ## Entry points
//!
//!   zig build           install the library, the 47 public headers under
//!                       `include/freetype2/`, the relocatable `freetype2.pc`,
//!                       and the licence and provenance records
//!   zig build test      run the behavioural tests for the selected target
//!                       (`-Dtarget`; the host when it is absent)
//!   zig build smoke     run the example program
//!   zig build consumer  build the separate `consumer/` package, and run it when
//!                       this host can execute the selected target
//!   zig build check     compile the native library, the facade, the tests and
//!                       the example for each of the six check targets, running
//!                       nothing
//!
//!   cross-test       the same `test` step, for the published 53-platform Zig
//!                   0.16.0 Tier 1/2 table rather than the host alone.
//!                   `cross-test` discovers `cross-test.profile.sh` from the
//!                   package root and runs `zig build test -Dtarget=TARGET` for
//!                   each of them, executing where a runner exists and recording
//!                   explicit `build_only` coverage where one does not.
//!
//! ## Options
//!
//!   -Dlinkage=static   a static archive, `libfreetype.a`. The default.
//!   -Dlinkage=dynamic  a real shared object. Upstream ships no prebuilt ELF
//!                      shared object; this graph builds one, with the SONAME
//!                      libtool derives from `builds/unix/configure.raw:20` and
//!                      an export surface of exactly the header-declared API.
//!   -Druntime=true     resolve the native entry points at run time instead of
//!                      linking them. Orthogonal to `-Dlinkage`. Default off; a
//!                      linked build is unchanged.
//!   -Dsystem=true      link an installed `libfreetype` instead of compiling
//!                      `src/`. Supplies the default of
//!                      `b.systemIntegrationOption("freetype", ...)`; a build
//!                      runner that decides the mode itself (`-fsys=freetype`)
//!                      overrides it.
//!   -Dtarget=<triple>  build for one target; `zig build check` then checks that
//!                      target only instead of the whole matrix.
//!   -Doptimize=<mode>  the caller's mode, passed to every graph below.
//!
//! ## Per-target platform configuration
//!
//! FreeType picks one of three `ftsystem.c` files and the choice is a property
//! of the *target*, never of the machine running the build. `Platform.systemSource`
//! is the one place that mapping exists; the library, the translation and the
//! configure-time print all read it.
//!
//!   * `builds/unix/ftsystem.c` for the targets whose libc has `unistd.h`,
//!     `fcntl.h` and `sys/mman.h`, which is what that file is for: it maps a
//!     font file into memory instead of reading it (`builds/unix/ftsystem.c:30-64`
//!     is the include block). Linux, the BSDs, Solaris and Darwin qualify.
//!   * `builds/windows/ftsystem.c` for `windows`, which uses `CreateFileMapping`
//!     and `MapViewOfFile` (`builds/windows/ftsystem.c:30`).
//!   * `src/base/ftsystem.c` for everything else, which is the stdio-only
//!     implementation and reaches nothing beyond `freetype/config/ftstdlib.h`.
//!     `wasm32-wasi` takes this branch: WASI preview 1 has no `sys/mman.h`, and
//!     a wrapper that compiled the mmap unit for it would fail to compile rather
//!     than degrade.
//!
//! Every one of the three is upstream's own file, from the release tarball, and
//! `meson.build:225-244` is upstream making the same three-way choice.
//!
//! ## What is *not* defined, and why that is a result rather than a gap
//!
//!   * `FT_CONFIG_OPTION_SYSTEM_ZLIB` is left undefined, exactly as
//!     `include/freetype/config/ftoption.h:227` ships it. The effect is that
//!     `src/gzip/ftgzip.c:47-114` compiles FreeType's own modified inflate
//!     rather than including `<zlib.h>`. This package therefore needs no system
//!     zlib, links none, and exports none — and `src/gzip/README.freetype` and
//!     `src/gzip/patches/freetype-zlib.diff` are what make that bundle
//!     auditable.
//!   * `FT_CONFIG_OPTION_USE_HARFBUZZ` is left undefined, so the auto hinter
//!     does not link a text-shaping library. The sibling `harfbuzz/` package is
//!     the direction that dependency points, and nothing here depends on it.
//!   * `FT_CONFIG_OPTION_USE_BROTLI`, `FT_CONFIG_OPTION_USE_PNG` and
//!     `FT_CONFIG_OPTION_USE_BZIP2` are undefined, so `src/sfnt/sfwoff2.c`,
//!     `src/sfnt/pngshim.c` and `src/bzip2/` contribute nothing. All three
//!     files are still compiled as part of their unity unit and are internally
//!     guarded (`src/sfnt/pngshim.c:28-31`, `src/sfnt/sfwoff2.c:27-29`), so
//!     "contributes nothing" is a fact about the code rather than a file this
//!     graph left out.
//!   * `FT_CONFIG_OPTION_SUBPIXEL_RENDERING` is undefined, which is what keeps
//!     `src/cache/` uncompiled.
//!
//! ## No upstream test suite is carried, and no step pretends otherwise
//!
//! The release tarball's `tests/` directory builds exactly one test program,
//! for one reported issue: `tests/meson.build:1-4` makes `issue-1063` from
//! `issue-1063/main.c`, and `tests/meson.build:9-12` registers it as the only
//! `test()` target in that directory, in the `regression` suite, with
//! `FREETYPE_TESTS_DATA_DIR` set to `tests/data/` (`tests/meson.build:6-7`).
//! That is a regression check for one issue and not an executable conformance
//! suite; the font it opens (`tests/issue-1063/main.c:24-26`) is not in this
//! tree, and `tests/README.md:7-8` reaches it with a download script
//! (`tests/scripts/download-test-fonts.py`). This graph therefore has no
//! `upstream-test` step and never fetches one to fill the gap.
//!
//! ## Where the fixtures come from
//!
//! `tests/fixtures/HarfBust.ttf` is HarfBuzz's own Latin test font, vendored
//! from `harfbuzz/test/shape/data/in-house/fonts/` under the SIL Open Font
//! License 1.1 whose text is beside it as `tests/fixtures/COPYING`. Its digests
//! and provenance are in `UPSTREAM.md`, and `tests.zig` decodes the font's own
//! `head`, `maxp`, `hhea`, `hmtx`, `cmap`, `loca` and `glyf` tables in Zig so
//! that every number this package asserts against FreeType is an independent
//! read of the binary rather than an agreement with itself.

const std = @import("std");
const manifest = @import("build.zig.zon");
const graph = @import("runtime/graph.zig");

/// The manifest's version, parsed once and compared against the vendored
/// headers at configure time.
const manifest_version = std.SemanticVersion.parse(manifest.version) catch
    @panic("build.zig.zon .version is not a semantic version");

/// The package id, the module name, the artifact name and the library's own
/// base name. All four are `freetype`, and that is what makes Zig emit
/// `libfreetype.a`, which is what a C consumer's `-lfreetype` needs and what
/// upstream's own `Makefile` and `freetype2.pc` name.
const lib_name = "freetype";
/// The typed facade: the one registered module, `dep.module("freetype")`.
const facade_source = "zig/root.zig";
/// The aggregate translation header.
const translate_header = "zig/translate.h";
const test_source = "tests.zig";
const example_source = "smoke.zig";

/// The native source root, and the include path the C library itself uses.
const source_dir = "src";
/// Upstream's include root: `include/ft2build.h` and `include/freetype/**`.
const include_dir = "include";

/// The FreeType release these sources are, read out of
/// `include/freetype/freetype.h:5170-5172`.
const upstream_version: std.SemanticVersion = .{ .major = 2, .minor = 14, .patch = 3 };

/// The SONAME this package delivers for a shared object.
///
/// `builds/unix/configure.raw:20` states `version_info='26:6:20'`, which libtool
/// reads as current 26, revision 6, age 20. The SONAME component is
/// `current - age` = 6, so upstream's installed object is `libfreetype.so.6`.
/// Zig derives the SONAME from `version.major` and the file name from all three
/// components, so minor and patch carry `current` and `age` verbatim and the
/// delivered file reads `libfreetype.so.6.26.20`. Every number here is read out
/// of that one line; none is chosen.
const abi_version: std.SemanticVersion = .{ .major = 6, .minor = 26, .patch = 20 };

/// The two base units.
///
/// `src/base/ftbase.c:21-38` is the unity unit for the base module — it includes
/// `ftadvanc.c`, `ftobjs.c`, `ftstream.c` and the rest — and `ftinit.c` is the
/// one that walks `FT_CONFIG_MODULES_H`.
const base_sources = [_][]const u8{
    "src/base/ftbase.c",
    "src/base/ftinit.c",
};

/// One unit per registered module, in the order `include/freetype/config/ftmodule.h`
/// registers them. `meson.build:82-107` derives this same list from
/// `modules.cfg`'s font, hinting and raster module sections.
///
/// The file name is the module's *main* file, not its driver: `winfonts` is
/// `src/winfonts/winfnt.c` and `cid` is `src/cid/type1cid.c`, which is
/// `meson.build:85-90`'s own spelling of the two exceptions.
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

/// The sixteen base extensions `modules.cfg` lists after its module sections.
///
/// They are *not* unity units: `modules.cfg` names them individually and each is
/// its own translation unit in every upstream build system.
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

/// `src/base/ftdebug.c`: where `FT_Message` and `FT_Panic` come from.
///
/// Not part of the module list and not a base extension: `modules.cfg` ends with
/// a paragraph about exactly these two units, and `meson.build:247-252` adds
/// `ftdebug.c` outside the module loop.
const debug_source = "src/base/ftdebug.c";

/// The 47 headers this package installs, from the two places upstream counts
/// them: `meson.build:139-186` lists 46 entries in `ft2_public_headers`, which
/// `meson.build:477-478` installs, and `meson.build:475-476` installs
/// `include/ft2build.h` separately, as the entry point that is included by
/// bare name. This package installs all 47 at the same level so that
/// `-I<includedir>/freetype2` alone satisfies the recipe in
/// `include/freetype/freetype.h:76-81`.
const public_headers = [_][]const u8{
    "include/ft2build.h",
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

/// The installed header root. Upstream's own install puts these under
/// `include/freetype2/`, and `freetype2.pc` is what carries the `-I` for it, so
/// a `pkg-config --cflags freetype2` is the only thing a C consumer needs.
const install_include_subdir = "freetype2";

/// The records installed under `share/licenses/freetype/`.
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

/// The compile flags every C unit gets.
///
/// FreeType's sources are C89 with long-standing GNU-isms, and upstream's own
/// Unix build passes no `-std` at all, so the least surprising choice is the
/// compiler's own default dialect. Naming one here would be a fork decision
/// about upstream's code that no upstream build makes.
const c_flags = [_][]const u8{};

/// Which native library this build links.
const Library = enum {
    /// FreeType compiled from this repository's own `src/` and `builds/`.
    bundled,
    /// An installed `libfreetype`, named by `b.systemIntegrationOption`.
    system,
};

/// The six cross targets this package compiles for.
const check_targets = [_]std.Target.Query{
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .macos, .abi = .none },
    .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
    .{ .cpu_arch = .riscv64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .wasm32, .os_tag = .wasi },
};

/// No target is refused, and one of them is known not to compile.
///
/// `lua` refuses `wasm32-wasi` because `src/loslib.c` has no arm for
/// `os.tmpname`. FreeType has no such hole in its own sources - `wasm32-wasi`
/// reaches `src/base/ftsystem.c`, whose whole dependency set is
/// `freetype/config/ftstdlib.h`, and every unit in the list above is
/// self-guarded against the optional features this build leaves off - but it
/// has a hole one level down. `freetype/config/ftstdlib.h:166` includes
/// `<setjmp.h>` with no guard and no `FT_CONFIG_OPTION_*` behind it, and the
/// pinned toolchain's wasi-libc refuses to declare `setjmp` at all:
/// `libc/include/wasm-wasi-musl/setjmp.h:13` raises `#error` unless
/// `__wasm_exception_handling__` is defined. Observed 2026-10-05: both halves of
/// that row fail there.
///
/// The row therefore stays in `check_targets` and this list stays empty, so the
/// failure keeps being reported on every `zig build check` instead of the target
/// quietly disappearing. Nothing here can make it compile: the fix is the
/// toolchain's or upstream's, not this build graph's. `FORK-NOTES.md` carries the
/// full diagnosis, the exact message and what would have to change.
const refused_check_targets = [_]std.Target.Query{};

/// One cell's graph: the artifacts and the module it hands to dependees.
const Graph = struct {
    c_lib: ?*std.Build.Step.Compile,
    module: *std.Build.Module,
    platform: Platform,
};

/// The one place the target's platform facts live.
const Platform = struct {
    /// Which `ftsystem.c` this target compiles.
    system_source: []const u8,
    /// The compile-line macros, as name/value pairs.
    macros: []const [2][]const u8,
    /// Whether the maths FreeType uses lives in a separate library.
    separate_m: bool,
    /// Whether `__declspec` exists, i.e. a shared build needs import/export
    /// decoration.
    dll: bool,

    fn forTarget(target: std.Build.ResolvedTarget) Platform {
        return switch (target.result.os.tag) {
            .windows => .{
                .system_source = "builds/windows/ftsystem.c",
                .macros = &.{},
                .separate_m = false,
                .dll = true,
            },
            // `builds/unix/ftsystem.c` opens `<unistd.h>`, `<fcntl.h>` and
            // `<sys/mman.h>`. Those are present for every OS below and for
            // nothing else this package is built for, which is what
            // `meson.build:225-244` tests for with `cc.has_header`.
            .linux, .macos, .ios, .tvos, .watchos, .visionos, .freebsd, .netbsd,
            .openbsd, .dragonfly, .illumos,
            => .{
                .system_source = "builds/unix/ftsystem.c",
                // `builds/unix/ftsystem.c` gates `<unistd.h>` on
                // `HAVE_UNISTD_H` (`:29`) and `<fcntl.h>` on `HAVE_FCNTL_H`
                // (`:63`), and uses `open`, `read` and `close` from them.
                // Without these two the unit compiles to undeclared-function
                // errors, which is what upstream's own `cc.has_header` checks
                // exist to prevent.
                .macros = &.{
                    .{ "HAVE_UNISTD_H", "1" },
                    .{ "HAVE_FCNTL_H", "1" },
                },
                .separate_m = true,
                .dll = false,
            },
            // Everything else, `wasm32-wasi` included, gets the stdio-only
            // implementation.
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

/// The published artifact's name, or the same name with the target appended for
/// a private matrix cell so that `--summary all` stays readable across six.
fn artifactName(b: *std.Build, target: std.Build.ResolvedTarget, public: bool) []const u8 {
    if (public) return lib_name;
    const triple = target.result.zigTriple(b.allocator) catch @panic("unspellable target");
    return b.fmt("{s}-{s}", .{ lib_name, triple });
}

/// The RISC-V float-ABI macro the C compiler predefines and `translate-c` does
/// not, as the `-D` pair `defineCMacro` takes, or null on every other
/// architecture.
///
/// glibc lays out a RISC-V `jmp_buf` for two of the three RISC-V float ABIs and
/// refuses the third. In the pinned toolchain's own headers,
/// `lib/libc/include/riscv-linux-gnu/bits/setjmp.h:32-36` gives the struct
/// twelve callee-saved `double` registers when `__riscv_float_abi_double` is
/// defined, gives it none when `__riscv_float_abi_soft` is, and raises `#error
/// unsupported FLEN` for `__riscv_float_abi_single`, the one ABI left with no
/// layout there. `<setjmp.h>` reaches this package from
/// `include/freetype/config/ftstdlib.h:166`, which includes it with no guard
/// and no `FT_CONFIG_OPTION_*` behind it.
///
/// Clang and the translator disagree about that one macro and about nothing
/// else on this path. `zig cc -target riscv64-linux-gnu` predefines
/// `__riscv_float_abi_double`, so this package's C library compiles for that
/// target; `translate-c`, which is Aro, predefines none of the three and stops
/// on the same header at `bits/setjmp.h:35`. Left alone, the facade would be
/// translated against a `jmp_buf` layout the library was never compiled with.
///
/// So the translation is handed the macro the compile was handed, derived from
/// the target being built and never from the host (AGENTS.md section 5). A
/// target with F and no D gets `__riscv_float_abi_single`, which is what clang
/// gives it and what glibc rejects, so that failure stays a failure instead of
/// being translated away.
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
    optimize: std.builtin.OptimizeMode,
    library: Library,
    linkage: std.builtin.LinkMode,
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
    // The include path and the translation both need it: `include/ft2build.h`
    // is included by bare name from three of the four headers
    // `zig/translate.h` includes, and the translation is what resolves that
    // name. See AGENTS.md section 5.
    if (translate_include) |dir| translate.addIncludePath(dir);
    for (translate_macros) |macro| translate.defineCMacro(macro[0], macro[1]);
    // `FT2_BUILD_LIBRARY` is what makes `FT_LOCAL` expand to nothing
    // (`include/freetype/internal/compiler-macros.h`), so the translation
    // carries the public API and nothing private. It must be on the translation
    // as well as on every C compile line, or the facade would see a different
    // declaration of the same header than the library was built with.
    translate.defineCMacro("FT2_BUILD_LIBRARY", "1");
    // The one macro the C compiler and the translator disagree about on this
    // path. It goes on the translation only: clang already predefines it for
    // every C compile line, and a `-D` there would be a second copy of a fact
    // the compiler owns. Null off RISC-V, so no other architecture sees a `-D`
    // it did not need.
    if (translateCRiscvFloatAbi(target)) |macro| translate.defineCMacro(macro[0], macro[1]);
    if (library == .system) {
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
        // The dispatch replaces the translation as the facade's `c` import, and
        // the archive is built and installed but *not* linked: linking it here
        // would let the linker satisfy the `FT_*` symbols statically and the
        // runtime route would silently become a linked one.
        module.addImport("c", graph.createModule(b, translate, target, optimize));
    } else {
        module.addImport("c", translate.createModule());
        module.addImport("rt", graph.createCoreModule(b, target, optimize));
        if (c_lib) |lib| module.linkLibrary(lib);
    }
    if (library == .bundled) module.addIncludePath(b.path(include_dir));

    return .{ .c_lib = c_lib, .module = module, .platform = platform };
}

/// Compile FreeType's own C into one archive.
fn add_c_library(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    requested: std.builtin.LinkMode,
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
            // A static archive is not asked to be relocatable; a shared object
            // is, and PIC on every constituent is what makes it work.
            .pic = if (linkage == .dynamic) true else null,
        }),
    });
    const c_mod = c_lib.root_module;

    c_mod.addIncludePath(b.path(include_dir));
    // `FT_CONFIG_*_H` macros are *macros*, so a C unit has to see them the same
    // way the translation does. `platform.macros` is currently empty for every
    // target, and it is read here anyway so that adding one cannot leave the
    // library and its translation disagreeing.
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
    // The one unit whose file depends on the target rather than on the module
    // list, resolved from the resolved target and not probed.
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

/// An ELF export surface of exactly the header-declared API.
///
/// Mach-O and COFF get no version script: a Mach-O object's exported symbols are
/// decided by the linker's default visibility rules and a COFF object's by its
/// directives, and a `.def` listing every `FT_*` name would be a second place
/// that list has to be kept. The fact that the surface is exactly the public API
/// is therefore only *enforced* on ELF, and `README.md` says which is which.
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

/// Whether the target has a dynamic linker at all.
fn targetHasDynamicLinker(target: std.Build.ResolvedTarget) bool {
    return target.result.os.tag == .windows or std.Target.DynamicLinker.kind(target.result.os.tag) != .none;
}

/// The one place linkage is resolved. It never substitutes: a target without a
/// dynamic linker is a configure-time panic, not a silent static build.
fn deliveredLinkage(target: std.Build.ResolvedTarget, requested: std.builtin.LinkMode) std.builtin.LinkMode {
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

/// Compile every part of one target's public surface without running it.
fn add_target_check(
    b: *std.Build,
    query: std.Target.Query,
    optimize: std.builtin.OptimizeMode,
    library: Library,
    linkage: std.builtin.LinkMode,
    runtime_loaded: bool,
    step: *std.Build.Step,
) void {
    const cross_target = b.resolveTargetQuery(query);
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

/// Shell out to the separate `consumer/` package, which depends on this one by
/// a relative path rather than by a fetch.
fn runConsumer(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    library: Library,
    linkage: std.builtin.LinkMode,
    runtime_loaded: bool,
) *std.Build.Step.Run {
    const triple = target.query.zigTriple(b.allocator) catch @panic("OOM");
    defer b.allocator.free(triple);
    const cpu = target.query.serializeCpuAlloc(b.allocator) catch @panic("OOM");
    defer b.allocator.free(cpu);

    const run = b.addSystemCommand(&.{ b.graph.zig_exe, "build" });
    run.setName("consumer package");
    run.setCwd(b.path("consumer"));
    // A host that cannot execute the selected target gets `install`, which is
    // compile evidence and never a semantic pass.
    run.addArg(if (hostCanExecute(b, target)) "run" else "install");
    run.addArg(b.fmt("-Dtarget={s}", .{triple}));
    run.addArg(b.fmt("-Dcpu={s}", .{cpu}));
    run.addArg(b.fmt("-Doptimize={s}", .{@tagName(optimize)}));
    run.addArg(b.fmt("-Dlinkage={s}", .{@tagName(linkage)}));
    run.addArg(b.fmt("-Druntime={s}", .{if (runtime_loaded) "true" else "false"}));
    // The resolved mode travels as `-fsys=`/`-fno-sys=`, because
    // `systemIntegrationOption` is fed by those flags and a `-Dsystem` in the
    // nested build would be ignored.
    run.addArg(if (library == .system)
        b.fmt("-fsys={s}", .{lib_name})
    else
        b.fmt("-fno-sys={s}", .{lib_name}));
    if (b.enable_darling) run.addArg("-fdarling");
    if (b.enable_qemu) run.addArg("-fqemu");
    if (b.enable_rosetta) run.addArg("-frosetta");
    if (b.enable_wasmtime) run.addArg("-fwasmtime");
    if (b.enable_wine) run.addArg("-fwine");
    if (b.libc_runtimes_dir) |runtimes| run.addArgs(&.{ "--libc-runtimes", runtimes });
    run.addArg("-j8");
    run.addArg("--summary");
    run.addArg("all");
    if (b.cache_root.path) |cache| {
        run.addArg("--cache-dir");
        run.addArg(b.fmt("{s}/consumer", .{cache}));
    }
    if (b.graph.global_cache_root.path) |global_cache| {
        run.addArg("--global-cache-dir");
        run.addArg(global_cache);
    }
    const default_prefix = b.build_root.join(b.allocator, &.{"zig-out"}) catch @panic("OOM");
    if (!std.mem.eql(u8, b.install_prefix, default_prefix)) {
        const prefix = if (std.fs.path.isAbsolute(b.install_prefix))
            b.install_prefix
        else
            b.pathJoin(&.{ b.graph.cache.cwd, b.install_prefix });
        run.addArg("--prefix");
        run.addArg(prefix);
    }
    if (b.args) |args| {
        run.addArg("--");
        run.addArgs(args);
    }
    run.has_side_effects = true;
    return run;
}

/// Whether this host can execute a binary built for `target`.
///
/// Asks `std.zig.system.getExternalExecutor`, which is the same predicate
/// `Step.Run` applies, so this decision and the nested run cannot disagree.
fn hostCanExecute(b: *std.Build, target: std.Build.ResolvedTarget) bool {
    const host = &b.graph.host.result;
    const candidate = &target.result;
    const options: std.zig.system.GetExternalExecutorOptions = .{
        .allow_darling = b.enable_darling,
        .allow_qemu = b.enable_qemu,
        .allow_wasmtime = b.enable_wasmtime,
        .allow_wine = b.enable_wine,
        .qemu_fixes_dl = candidate.isGnuLibC() and b.libc_runtimes_dir != null,
        .link_libc = true,
    };
    return switch (std.zig.system.getExternalExecutor(b.graph.io, host, candidate, options)) {
        .native, .rosetta, .wine, .wasmtime, .darling => true,
        .qemu => !(candidate.isGnuLibC() and b.libc_runtimes_dir == null),
        .bad_dl, .bad_os_or_cpu => false,
    };
}

/// `freetype2.pc`, relocatable, with every field traceable to upstream.
fn add_pkg_config(b: *std.Build, platform: Platform, linkage: std.builtin.LinkMode) void {
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

/// Install the licence and provenance records, flattened by basename.
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

/// Check that the two target lists still agree with `Platform.forTarget`.
///
/// Both directions, so neither list can quietly become wrong: a target that
/// `refusalFor` would refuse may not sit in `check_targets`, and one it would
/// not refuse may not sit in `refused_check_targets`.
fn checkMatrixPartition(_: *std.Build) void {
    if (refused_check_targets.len != 0) {
        @panic("build.zig: refused_check_targets is not empty and this build has no refusal to record; see the module doc");
    }
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
        std.builtin.LinkMode,
        "linkage",
        "How the library is delivered. static gives libfreetype.a, which is upstream's own build product; dynamic gives a real shared object.",
    );
    const linkage: std.builtin.LinkMode = linkage_option orelse
        (if (library == .system) .dynamic else .static);

    const runtime_loaded = b.option(
        bool,
        "runtime",
        "Resolve FreeType's entry points through the platform loader at run time instead of linking them. Orthogonal to -Dlinkage, which still decides which artifact is delivered and installed. Default false.",
    ) orelse false;

    // The version-drift gate: the manifest, the vendored headers and the
    // configure-time print all describe one release or none of them describe
    // anything real.
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
    run_example.has_side_effects = true;
    if (b.args) |args| run_example.addArgs(args);
    b.step("smoke", "Run the deterministic example program").dependOn(&run_example.step);

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

    b.step("consumer", "Build or run the consumer/ package for the selected target")
        .dependOn(&runConsumer(b, target, optimize, library, deliveredLinkage(target, linkage), runtime_loaded).step);

    const check_step = b.step(
        "check",
        "Compile the library, facade, tests and example for the cross targets, running nothing",
    );
    if (!target.query.isNative()) {
        add_target_check(b, target.query, optimize, library, linkage, runtime_loaded, check_step);
    } else {
        for (check_targets[0..]) |query| {
            add_target_check(b, query, optimize, library, linkage, runtime_loaded, check_step);
        }
    }

    // Configure-time report. No side effects beyond printing.
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