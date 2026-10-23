// SPDX-License-Identifier: MIT
//
//! FreeType-specific runtime-loader descriptor.
//! Providers must export translated `FT_*` symbols and report ABI version 2.14.3.
//! FreeType owns its C allocations.
//! Zig leak checks do not cover them.
//! FreeType errors are signed `FT_Error` values, not POSIX `errno`.

const std = @import("std");
const rt = @import("rt");

/// Process-wide synchronization bindings for the runtime loader.
pub const Sync = struct {
    extern fn freetype_rt_lock() void;
    extern fn freetype_rt_unlock() void;
    extern fn freetype_rt_wait() void;
    extern fn freetype_rt_broadcast() void;
    // C uses `unsigned long long`. `u64` matches it on supported targets.
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

/// Required provider ABI version from the vendored headers.
const expected_version: [3]c_int = .{ 2, 14, 3 };

/// System zlib and HarfBuzz are disabled.
/// FreeType uses bundled inflate.
const config_name = "FT_CONFIG_OPTION_SYSTEM_ZLIB off; FT_CONFIG_OPTION_USE_HARFBUZZ off";

/// Descriptor for the generated dispatch loader.
pub fn Config(comptime dispatch: type) type {
    return struct {
        /// The name `load` reports and the name the loader state is keyed on.
        pub const library_name = "freetype";

        /// The one table this process will ever publish, one per build.
        pub const table = dispatch.Table;
        pub const symbols = dispatch.symbols;
        pub const optional_symbols = dispatch.optional_symbols;
        pub const sync = Sync;

        /// Returns the generated dispatch table.
        pub fn tablePtr() *table {
            return dispatch.tablePtr();
        }

        /// Returns the dispatch readiness flag.
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

        /// Checks provider version and library creation, returning a diagnostic on failure.
        pub fn validate(dst: *const table) ?[]const u8 {
            // Check the out handle separately from `FT_Init_FreeType`'s status.
            // Pass every non-null handle to `FT_Done_FreeType`.
            var handle: ?*anyopaque = null;
            if (dst.FT_Init_FreeType(&handle) != 0) return
                "FT_Init_FreeType reported an error, so this provider could " ++
                "not allocate a library and cannot serve one";
            if (handle == null) return
                "FT_Init_FreeType reported success and left a null library, " ++
                "so this provider does not do what its own header says it does";
            // A live handle must be destroyed on every return path.
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

        /// Returns the package configuration for load diagnostics.
        pub fn describeConfiguration() []const u8 {
            return config_name;
        }
    };
}
