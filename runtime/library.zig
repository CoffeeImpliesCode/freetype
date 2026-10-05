// SPDX-License-Identifier: MIT
// See FORK-LICENSE.md for what that identifier covers.
//
//! FreeType's side of the runtime loader: the names its synchronization
//! binding has, what it requires of a provider beyond resolving its symbols,
//! and what the external ABI boundary for this provider actually is.
//!
//! Everything else about the runtime route is generic. `runtime/loader.zig` is
//! the state machine and the platform layer; `runtime/generate.zig` builds the
//! dispatch from whatever the translation step actually produced;
//! `runtime/graph.zig` wires them together. This file is what makes them
//! FreeType's, and it is the file another SDK replaces.

const std = @import("std");
const rt = @import("rt");

/// What a provider must export, and what it must answer correctly.
///
/// `zig/translate.h` includes `<ft2build.h>` and `<freetype/freetype.h>`, which
/// reach every public FreeType header through
/// `include/freetype/config/ftheader.h`. Every `FT_*` declaration that reaches
/// the translation is routed: this configuration has no config-gated entry
/// points, so `provider_optional` and `provider_excluded` in `runtime/graph.zig`
/// are both empty and a provider that exports only part of the header-declared
/// API is refused rather than half used.
///
/// The C library surface that reaches the translation through
/// `include/freetype/config/ftstdlib.h` is classified as *noise* there and is
/// not owed by a provider: `libfreetype.so` exports `FT_*` and nothing else,
/// and a loader that asked it for `ft_memcpy` would either fail the load or
/// resolve the symbol out of the provider's own libc dependency.
///
/// ## The external ABI boundary, stated honestly
///
/// FreeType's ABI family is `FREETYPE_MAJOR`/`FREETYPE_MINOR` — read out of
/// `include/freetype/freetype.h:5170-5172`, which are 2, 14 and 3 for the
/// release this package vendors. A provider is accepted only when
/// `FT_Library_Version` answers those three numbers, which is the same
/// statement upstream states in `docs/CHANGES` for each release: the structure
/// layouts and calling conventions that a consumer depends on are the ones that
/// number names.
///
/// What crosses that boundary, and what a caller must know:
///
///   * `FT_Library` and `FT_Face` are pointers to `FT_LibraryRec` and
///     `FT_FaceRec`, and *every* member of both records is public
///     (`include/freetype/fttypes.h`). A consumer that reads `face->glyph`
///     directly is depending on the record layout, not just on the accessor
///     functions, so the version check is not a formality.
///   * Memory crosses into FreeType's own allocator and out of it. FreeType
///     calls `ft_smalloc`/`ft_scalloc`/`ft_srealloc`/`ft_sfree`, which
///     `include/freetype/config/ftstdlib.h:142-145` maps onto
///     `malloc`/`calloc`/`realloc`/`free` of the C library. A Zig allocator can
///     neither bound nor intercept that, and `zig/std`'s leak checking has no
///     oracle for it: a library built this way is tested for behaviour, never
///     for leaks.
///   * `FT_Set_Char_Size`, `FT_Set_Pixel_Sizes` and `FT_Load_Glyph` report
///     metrics in 26.6 fixed point, while `FT_LOAD_NO_SCALE` reports them in
///     font units. Both are the same `FT_Pos` type; the scale is a *mode*, not a
///     different unit, and a caller that mixes them gets numbers that look
///     plausible and are wrong by a factor of 64.
///   * Errors are `FT_Error`, which is a signed `int` and is *not* a POSIX errno
///     and not a FreeType `FT_Error_Code` either; see
///     `include/freetype/fterrors.h`. Only the values this package's own code
///     checked are named in its error set.
///
/// A provider that is a different FreeType — for example one built with the
/// `TT_CONFIG_OPTION_BYTECODE_INTERPRETER` interpreter replaced by Subpixel
/// — still passes this check, and that is deliberate: the version is the only
/// thing a loader can verify without reimplementing the library.

/// The process-wide synchronization this SDK's loader uses.
///
/// The prefix `freetype_rt` is spelled in exactly two places: the `extern`
/// names below and `runtime/graph.zig`'s `sync_prefix`, which is what
/// `runtime/sync.c` is compiled with. A build where the two disagree does not
/// link, and that is the whole error report — there is no runtime path that
/// could hide it.
pub const Sync = struct {
    extern fn freetype_rt_lock() void;
    extern fn freetype_rt_unlock() void;
    extern fn freetype_rt_wait() void;
    extern fn freetype_rt_broadcast() void;
    // `unsigned long long`. Declared as u64, which is the same type in every
    // ABI this SDK targets: 64-bit on x86_64, aarch64, riscv64 and wasm32.
    extern fn freetype_rt_thread_self() u64;

    pub fn lock() void {
        freetype_rt_lock();
    }
    pub fn unlock() void {
        freetype_rt_unlock();
    }
    pub fn wait() void {
        freetype_rt_wait();
    }
    pub fn broadcast() void {
        freetype_rt_broadcast();
    }
    pub fn threadSelf() u64 {
        return freetype_rt_thread_self();
    }
};

/// The FreeType release the vendored headers describe.
///
/// Read out of `include/freetype/freetype.h:5170-5172`. It is the version of
/// the C library this package compiles, not a version of this wrapper.
const expected_version: [3]c_int = .{ 2, 14, 3 };

/// The configuration this package builds with.
///
/// FreeType's configuration is a set of macros in
/// `include/freetype/config/ftoption.h`, and two of them change what a
/// provider can do rather than what it exports:
///
///   * `FT_CONFIG_OPTION_USE_HARFBUZZ` is **not** defined. With it, the auto
///     hinter would resolve shaping through HarfBuzz — the sibling SDK in this
///     workspace — and `libfreetype` would link `libharfbuzz`. This package
///     leaves it off, so `FT_Library` and every `FT_Face` are usable without a
///     text-shaping library present. `harfbuzz/` is the direction that
///     dependency points instead.
///   * `FT_CONFIG_OPTION_SYSTEM_ZLIB` is **not** defined, so
///     `include/freetype/config/ftoption.h:198` selects FreeType's own bundled
///     inflate (`src/gzip/*.c`) rather than a system `libz`. A provider is
///     therefore self-contained with respect to decompression and is not
///     expected to export zlib's names.
const config_name = "FT_CONFIG_OPTION_SYSTEM_ZLIB off; FT_CONFIG_OPTION_USE_HARFBUZZ off";

/// The descriptor the generated dispatch builds its loader over.
///
/// `dispatch` is passed as a type rather than imported, so this file never
/// depends on generated code: the dependency runs one way only, and a build that
/// could see both halves would have a cycle.
pub fn Config(comptime dispatch: type) type {
    return struct {
        /// The name `load` reports and the name the loader state is keyed on.
        pub const library_name = "freetype";

        /// The one table this process will ever publish, one per build.
        pub const table = dispatch.Table;
        pub const symbols = dispatch.symbols;
        pub const optional_symbols = dispatch.optional_symbols;
        pub const sync = Sync;

        /// Where the single published table lives.
        pub fn tablePtr() *table {
            return dispatch.tablePtr();
        }

        /// The readiness flag every routed call pays one acquire load for.
        pub fn ready() *rt.Ready {
            return &dispatch.ready;
        }

        pub fn assign(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assign(index, dst, address);
        }

        pub inline fn assignOptional(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assignOptional(index, dst, address);
        }

        pub inline fn assignMissing(comptime index: usize, dst: *table) void {
            dispatch.assignMissing(index, dst);
        }

        /// What this SDK checks about a provider *after* every symbol resolved.
        ///
        /// Two questions, both of which raise an error instead of aborting, and
        /// both of which the `lua` package's equivalent deliberately does not
        /// ask: a loader that has to answer `ValidationFailed` can only run
        /// checks that *return*.
        ///
        /// 1. Does the resolved `FT_Library_Version` report the version these
        ///    headers describe? See the ABI notes above for why that is the
        ///    whole family check.
        /// 2. Can the provider actually create and destroy a library? That
        ///    exercises its allocator, its `ft_smalloc`/`ft_sfree` pair and its
        ///    stream layer once, and a provider that cannot is not usable.
        ///
        /// Deliberately **not** checked: anything that raises. FreeType's
        /// `FT_Error` path returns an `FT_Error` and this is called with every
        /// symbol already resolved, so nothing here can trap.
        pub fn validate(dst: *const table) ?[]const u8 {
            // `FT_Init_FreeType` takes an out-parameter and answers an
            // `FT_Error`, so the null check is on what it wrote rather than on
            // what it returned. `?*anyopaque` is what the translation gives the
            // pointer parameter; the dispatch hands the same pointer to
            // `FT_Done_FreeType` below.
            var handle: ?*anyopaque = null;
            if (dst.FT_Init_FreeType(&handle) != 0) return
                "FT_Init_FreeType reported an error, so this provider could " ++
                "not allocate a library and cannot serve one";
            if (handle == null) return
                "FT_Init_FreeType reported success and left a null library, " ++
                "so this provider does not do what its own header says it does";
            // From here on the library is live whatever the answer is.
            defer _ = dst.FT_Done_FreeType(handle);

            var major: c_int = 0;
            var minor: c_int = 0;
            var patch: c_int = 0;
            _ = dst.FT_Library_Version(handle, &major, &minor, &patch);
            const seen = [3]c_int{ major, minor, patch };
            if (!std.mem.eql(c_int, &seen, &expected_version)) {
                std.debug.print(
                    "freetype: provider reports {d}.{d}.{d}, this SDK's headers " ++
                        "describe {d}.{d}.{d}; they are different external ABIs\n",
                    .{ major, minor, patch, expected_version[0], expected_version[1], expected_version[2] },
                );
                return "this provider implements a different FreeType ABI family " ++
                    "than the one this SDK's headers describe";
            }
            return null;
        }

        /// The configuration string, for a load-time report.
        pub fn describeConfiguration() []const u8 {
            return config_name;
        }
    };
}