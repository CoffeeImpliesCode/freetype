// SPDX-License-Identifier: MIT
// See FORK-LICENSE.md for what that identifier covers.
//
//! The typed surface over FreeType 2.14.3's face / glyph / load API.
//!
//! ## Import routes
//!
//! One published route, `dep.module("freetype")`, which is this file. The
//! translated headers are available on it as `c`, and are never a module of
//! their own: a consumer that wants `c.FT_Face` directly has it, and a consumer
//! that wants `Lib` and `Face` has those. Both reach the same translation, so
//! there is exactly one `FT_Face` type per build whichever is used.
//!
//! ## Two configurations: linked and runtime-loaded
//!
//! `c` is the translation itself when the library is linked, and the generated
//! dispatch when `-Druntime=true`. The dispatch re-exports the translated
//! namespace rather than restating it, so `c.FT_Face` is the same type in both
//! and everything below works unchanged in both. What differs is `load`:
//!
//!   * linked: there is nothing to load, and `load` panics with a message that
//!     names the mistake rather than pretending to succeed.
//!   * runtime-loaded: `load` takes an explicit provider and resolves every
//!     `FT_*` entry point through the platform loader. There is no default
//!     location and no fallback, and a call to `Lib.init` before a successful
//!     `load` panics in every optimization mode.
//!
//! `runtime_loaded` is `true` exactly when `c` is the dispatch, so a caller can
//! branch on it without knowing how the package was built.
//!
//! ## Memory
//!
//! This module allocates nothing and frees nothing on its own. FreeType's
//! allocator is the C library's: `include/freetype/config/ftstdlib.h:142-145`
//! maps `ft_scalloc`/`ft_srealloc`/`ft_sfree` onto `calloc`/`realloc`/`free`,
//! and every `FT_Face`, `FT_Bitmap` buffer and outline point array it hands out
//! came from there. No Zig allocator can bound or intercept those bytes, so the
//! test framework's leak checking has no oracle for this package and this
//! package does not claim one. What it does instead is make every ownership
//! transition explicit and test it: a `Face` must be `deinit`ed, and every
//! `Face` must be destroyed before its `Lib`.
//!
//! ## Units: the one thing that silently breaks a measurement
//!
//! A `FT_Pos` means font units under `Flags.no_scale` and 26.6 pixels
//! otherwise. Nothing in the C API records which a given `FT_Pos` is, and the
//! two differ by a factor of 64 on a typical font. `Face.unitsPerEm` is the
//! conversion, and this module never mixes the two: every measurement helper
//! here takes or names the flags that produced it, and its doc comment says
//! which unit the answer is in.
//!
//! ## Errors, and what they leave behind
//!
//! FreeType answers an `FT_Error`, which is a signed `int`, and this package
//! maps only the values its own code checked. Every mapping is a comparison
//! against the constant in `include/freetype/fterrdef.h`, never a
//! `std.debug.assert`: a public contract is guarded by an ordinary comparison,
//! because an assertion is compiled out of a release build and then guards
//! nothing.
//!
//! The taxonomy is cut where this package's tests cut it. Everything else
//! becomes `Error.UnexpectedError`, and the raw `c` route is public so a caller
//! that needs the exact code can read it.

const std = @import("std");

/// The translated FreeType headers, or the generated dispatch over them.
///
/// ## The macros, and what they become
///
/// `zig translate-c` carries each C macro across as an `inline fn` with
/// unevaluated parameters, so `c.FT_LOAD_NO_HINTING` is a *function*, not a
/// value, and a flag set has to be written as a call. This module never spells
/// a flag that way: `Flags` below is a Zig `packed struct` with named,
/// defaulted fields, so a caller writes `.no_hinting = true` and cannot pass a
/// flag this build does not implement. A dropped macro becomes a link error
/// instead of a silent zero, which is the failure mode worth having.
///
/// Two macros in FreeType's closure cannot be lowered and are absent from the
/// translation rather than mistranslated: `FT_HAS_HORIZONTAL`
/// (`include/freetype/freetype.h:1454`), which expands to a `!!`, and
/// `FT_ENCODING_*`, whose enum values are built by the `FT_ENC_TAG` macro
/// (`include/freetype/freetype.h:930`) rather than written out. Neither is used
/// here, and `Face.selectCharmap` is deliberately absent for the same reason:
/// wrapping an argument whose translated type is uncertain would be a guess.
pub const c = @import("c");

/// The loader core, linked builds only.
///
/// Under `-Druntime=true` the dispatch carries its own copy of this module and
/// re-exports `LoadSource` and `LoadError` from it. Importing it separately
/// there would give a consumer two nominally distinct sets of types: one it
/// names and one `load` expects.
const rt = @import("rt");

/// Whether this build resolves FreeType's entry points at run time.
pub const runtime_loaded: bool = if (@hasDecl(c, "rt_runtime_loaded")) c.rt_runtime_loaded else false;

/// Where a runtime-loaded provider comes from: an absolute path, or a
/// basename/SONAME the platform loader searches for.
pub const LoadSource = if (runtime_loaded) c.LoadSource else rt.LoadSource;

/// Why a runtime load did not happen.
pub const LoadError = if (runtime_loaded) c.LoadError else rt.LoadError;

// -- Runtime loading -------------------------------------------------------

/// Resolve every `FT_*` entry point from an explicit provider.
///
/// Only meaningful under `-Druntime=true`. A linked build has no provider to
/// resolve from, so this panics with the reason instead of returning a
/// plausible-looking success: a linked caller who reaches this is asking for
/// something the build cannot do, and silently doing nothing would turn that
/// into a missing-symbol error much later.
pub fn load(source: LoadSource) LoadError!void {
    if (comptime runtime_loaded) {
        return c.load(source);
    }
    std.debug.panic(
        "freetype: load was called on a build that links FreeType, so every " ++
            "entry point is already resolved. Rebuild with -Druntime=true to " ++
            "select a provider at run time.",
        .{},
    );
}

/// The provider this process published, or `null` if none was published.
///
/// A linked build answers `null` always: it was not asked to choose a provider,
/// it was given one at link time.
pub fn loadedSource() ?LoadSource {
    if (comptime runtime_loaded) return c.loadedSource();
    return null;
}

// -- Constants read out of the vendored headers ---------------------------

/// The FreeType release these headers describe.
///
/// Read out of `include/freetype/freetype.h:5170-5172`. `build.zig` refuses to
/// configure when `build.zig.zon`'s `.version` and this tuple disagree, so the
/// manifest, this tuple and the vendored source cannot describe three different
/// releases.
pub const version: std.SemanticVersion = .{
    .major = c.FREETYPE_MAJOR,
    .minor = c.FREETYPE_MINOR,
    .patch = c.FREETYPE_PATCH,
};

/// `FT_LOAD_*`, as a set of named flags.
///
/// Every field defaults to `false`, so `.{ .no_hinting = true }` and `.{}` are
/// both valid literals and an omitted field means "not requested" rather than
/// "whatever the previous call used".
///
/// The struct is `packed` and each flag sits on the bit
/// `include/freetype/freetype.h:3500-3526` gives it, with an explicit padding
/// field for every bit the header assigns to something else. That is what
/// makes `toInt` a `@bitCast` rather than a hand-written shift: the bit
/// layout of this struct *is* the `FT_Int32` the header declares, so a field
/// set here and the corresponding macro set there produce the same value.
/// Laying the booleans out consecutively instead would shift `no_recurse`
/// from bit 10 onto bit 6 and make every flag above it silently wrong.
pub const Flags = packed struct(u32) {
    /// `FT_LOAD_NO_SCALE`: metrics and outlines in font units. `1L << 0`.
    no_scale: bool = false,
    /// `FT_LOAD_NO_HINTING`: keep the outline, skip the hinter. `1L << 1`.
    no_hinting: bool = false,
    /// `FT_LOAD_RENDER`: render the glyph as part of the load. `1L << 2`.
    render: bool = false,
    /// `FT_LOAD_NO_BITMAP`: do not accept a pre-built bitmap. `1L << 3`.
    no_bitmap: bool = false,
    /// `FT_LOAD_VERTICAL_LAYOUT`: load for vertical text. `1L << 4`.
    vertical: bool = false,
    /// `FT_LOAD_FORCE_AUTOHINT`: use the auto hinter even when the font has
    /// one. `1L << 5`.
    force_autohint: bool = false,
    /// `FT_LOAD_CROP_BITMAP`, deprecated and ignored. Bit 6.
    _reserved_6_crop_bitmap: u1 = 0,
    /// `FT_LOAD_PEDANTIC`. Bit 7.
    _reserved_7_pedantic: u1 = 0,
    /// `FT_LOAD_ADVANCE_ONLY`, for certain font drivers only. Bit 8.
    _reserved_8_advance_only: u1 = 0,
    /// `FT_LOAD_IGNORE_GLOBAL_ADVANCE_WIDTH`, deprecated and ignored. Bit 9.
    _reserved_9_ignore_global_advance: u1 = 0,
    /// `FT_LOAD_NO_RECURSE`: never load composite glyph components
    /// recursively. `1L << 10`.
    no_recurse: bool = false,
    /// `FT_LOAD_IGNORE_TRANSFORM`: ignore the face's transform matrix.
    /// `1L << 11`.
    ignore_transform: bool = false,
    /// `FT_LOAD_MONOCHROME`: monochrome rendering only. `1L << 12`.
    monochrome: bool = false,
    /// `FT_LOAD_LINEAR_DESIGN`: scale linearly in design space. `1L << 13`.
    linear_design: bool = false,
    /// `FT_LOAD_SBITS_ONLY`. Bit 14.
    _reserved_14_sbits_only: u1 = 0,
    /// `FT_LOAD_NO_AUTOHINT`: never use the auto hinter. `1L << 15`.
    no_autohint: bool = false,
    /// Bits 16-19 are the `FT_LOAD_TARGET_*` render-mode selector, which is an
    /// enum rather than a flag and is reached through `Face.renderLoaded`.
    _reserved_16_19_target: u4 = 0,
    /// `FT_LOAD_COLOR`. Bit 20.
    _reserved_20_color: u1 = 0,
    /// `FT_LOAD_COMPUTE_METRICS`. Bit 21.
    _reserved_21_compute_metrics: u1 = 0,
    /// `FT_LOAD_BITMAP_METRICS_ONLY`. Bit 22.
    _reserved_22_bitmap_metrics_only: u1 = 0,
    /// `FT_LOAD_SVG_ONLY`, for certain font drivers only. Bit 23.
    _reserved_23_svg_only: u1 = 0,
    /// `FT_LOAD_NO_SVG`. Bit 24.
    _reserved_24_no_svg: u1 = 0,

    /// `FT_LOAD_LINEAR`.
    ///
    /// This build's headers define no `FT_LOAD_LINEAR`: `freetype.h:3500-3526`
    /// is the complete list of `FT_LOAD_*` macros and the word appears nowhere
    /// in `include/` outside the unrelated `FT_LOAD_LINEAR_DESIGN`. The field
    /// is kept because it is part of this facade, and it sits on bit 25, which
    /// no macro in that list claims and which `src/base/ftobjs.c` never tests,
    /// so setting it changes nothing in the library rather than setting some
    /// other flag by accident.
    linear: bool = false,
    /// `FT_LOAD_NO_SUBPIXEL_HINTING`.
    ///
    /// No macro of this name exists either. Subpixel hinting in this build is a
    /// compile-time option (`TT_CONFIG_OPTION_SUBPIXEL_HINTING`), not a load
    /// flag; `include/freetype/ftdriver.h:774` is where the header says so.
    /// Bit 26, unclaimed for the same reason as `linear`.
    no_subpixel: bool = false,
    /// `FT_LOAD_NO_AUTOSUBPIXEL`.
    ///
    /// No macro of this name exists in the tree at all. Bit 27, unclaimed for
    /// the same reason as `linear`.
    no_autosubpixel: bool = false,
    /// `FT_LOAD_DEFAULT`, which is `0x0`.
    ///
    /// Spelled `default_` because `default` is a Zig keyword. The macro is
    /// literally zero, so this field contributes nothing to the value
    /// FreeType reads; it exists so a caller can name the empty flag set the
    /// way the header names it. Bit 28 is unclaimed, so a `true` here cannot
    /// be mistaken for a real flag.
    default_: bool = false,

    /// Bits 29-31 are beyond the highest bit any `FT_LOAD_*` macro claims.
    _reserved_29_31: u3 = 0,

    /// The `FT_Int32` the C header declares, as the header's own bit layout
    /// gives it.
    pub fn toInt(self: Flags) c_int {
        return @bitCast(self);
    }
};

/// Font units, unhinted, unrendered.
///
/// The mode every measurement in this file defaults to, because it is the only
/// one whose numbers can be compared with a font's own tables.
pub const no_scale: Flags = .{ .no_scale = true };

/// Font units, unhinted, no rasterizer involved.
///
/// What the sibling `harfbuzz` package's tests rely on: `src/hb-ft.cc:119`
/// sets `load_flags = FT_LOAD_DEFAULT | FT_LOAD_NO_HINTING`, and this is the
/// same choice with the scale made explicit.
pub const no_scale_no_hinting: Flags = .{ .no_scale = true, .no_hinting = true };

/// `FT_Render_Mode`, re-exported rather than restated.
///
/// `include/freetype/freetype.h:3789-3800` numbers `FT_RENDER_MODE_LCD_V` 4 and
/// `FT_RENDER_MODE_SDF` 5, which is not the order a reader would guess and is
/// not the order this module would have chosen. A wrapper that renumbered them
/// would be a second source of truth about upstream's enum, so the enum itself
/// is the type and the values below are the upstream constants.
pub const RenderMode = c.FT_Render_Mode;

pub const render_normal: RenderMode = c.FT_RENDER_MODE_NORMAL;
pub const render_light: RenderMode = c.FT_RENDER_MODE_LIGHT;
pub const render_mono: RenderMode = c.FT_RENDER_MODE_MONO;
pub const render_lcd: RenderMode = c.FT_RENDER_MODE_LCD;
pub const render_lcd_v: RenderMode = c.FT_RENDER_MODE_LCD_V;
/// The signed-distance-field mode FreeType 2.14 added
/// (`include/freetype/freetype.h:3796`), served by `src/sdf/`.
pub const render_sdf: RenderMode = c.FT_RENDER_MODE_SDF;

// -- Errors ----------------------------------------------------------------

/// The failures this package's own code checked.
///
/// Cut at what `tests.zig` and `smoke.zig` actually observe. A caller that
/// needs a finer distinction calls the raw `c` route and reads the `FT_Error`
/// itself; that is why `c` is public.
pub const Error = error{
    /// `FT_Err_Cannot_Open_Resource`: the path does not exist or cannot be read.
    CannotOpenResource,
    /// `FT_Err_Unknown_File_Format`: the stream opened but is not a font one of
    /// this build's ten drivers recognised.
    UnknownFileFormat,
    /// `FT_Err_Invalid_File_Format`, which is what a stream that is not a
    /// usable font produces.
    ///
    /// This build has no `FT_Err_Invalid_File_Size`: `include/freetype/
    /// fterrdef.h:65` defines `Invalid_File_Format` at `0x03` and the file's
    /// remaining entries are `Invalid_Version`, `Lower_Module_Version`,
    /// `Invalid_Table` and `Invalid_Offset`, with no size code among them. A
    /// measured probe of this build answers `0x03` for bytes that are not a font
    /// at all, which is the code that survives, so this tag carries it.
    InvalidFileSize,
    /// `FT_Err_Invalid_Argument`: a null handle or an argument out of range.
    InvalidArgument,
    /// `FT_Err_Invalid_Pixel_Size`: the requested size was outside the range
    /// `FT_Request_Size` accepts. Note that a zero width or height does *not*
    /// produce it; see `Face.setPixelSizes`.
    InvalidPixelSize,
    /// `FT_Err_Invalid_Glyph_Index`: the index is past `num_glyphs`.
    InvalidGlyphIndex,
    /// `FT_Err_Invalid_Outline`: the outline could not be decomposed.
    InvalidOutline,
    /// `FT_Err_Unimplemented_Feature`: the module behind an operation is not in
    /// this build. The typed surface never selects a module this way; the raw
    /// route can.
    UnimplementedFeature,
    /// `FT_Err_Out_Of_Memory`: FreeType's own allocator failed.
    OutOfMemory,
    /// Every code this package did not name. One honest bucket rather than a
    /// taxonomy of tags nothing checks.
    UnexpectedError,
};

/// Map one `FT_Error` onto one tag, or onto the error itself.
///
/// The constants come from `include/freetype/fterrdef.h`, where every name is
/// defined through `FT_NOERRORDEF_`; this is the only place this package
/// decides what an `FT_Error` means. Written as an if-chain rather than a
/// `switch` so that a prong is a comptime-known integer constant of whatever
/// width `translate-c` inferred, which a `switch` over a signed `c_int` would
/// have to prove coercible.
fn errorFrom(code: c_int) Error!void {
    if (code == c.FT_Err_Ok) return;
    if (code == c.FT_Err_Cannot_Open_Resource) return Error.CannotOpenResource;
    if (code == c.FT_Err_Unknown_File_Format) return Error.UnknownFileFormat;
    if (code == c.FT_Err_Invalid_File_Format) return Error.InvalidFileSize;
    if (code == c.FT_Err_Invalid_Argument) return Error.InvalidArgument;
    if (code == c.FT_Err_Invalid_Pixel_Size) return Error.InvalidPixelSize;
    if (code == c.FT_Err_Invalid_Glyph_Index) return Error.InvalidGlyphIndex;
    if (code == c.FT_Err_Invalid_Outline) return Error.InvalidOutline;
    if (code == c.FT_Err_Unimplemented_Feature) return Error.UnimplementedFeature;
    if (code == c.FT_Err_Out_Of_Memory) return Error.OutOfMemory;
    return Error.UnexpectedError;
}

// -- Library ---------------------------------------------------------------

/// One `FT_Library`.
///
/// Owns exactly one C library handle. Faces opened through it must be `deinit`ed
/// before it is `deinit`ed: FreeType does not check that order for the caller,
/// and closing a library that still has open faces leaves their `FT_Stream`
/// pointing at freed memory.
pub const Lib = struct {
    /// The C handle, or `null` after `deinit`.
    raw: c.FT_Library = null,

    /// `FT_Init_FreeType`.
    ///
    /// The only failure it reports is `OutOfMemory`: FreeType has no other way
    /// to fail here, because it has no file and no configuration to disagree
    /// with yet.
    pub fn init() Error!Lib {
        // `FT_Library` is itself the optional `?*struct_FT_LibraryRec_` that
        // the `FT_New_Face` / `FT_Done_FreeType` parameters also use, so this
        // local is that type and `&library_handle` is the `[*c]` out-parameter
        // the signature asks for. Wrapping it in another `?` would make it
        // `??*T` and the address would no longer match.
        var library_handle: c.FT_Library = null;
        try errorFrom(c.FT_Init_FreeType(&library_handle));
        // A success with a null handle would mean the translation and the
        // provider disagree about the signature, which no later call could
        // diagnose. An ordinary comparison, not an assert: an assert vanishes in
        // ReleaseFast and then guards nothing.
        if (library_handle == null) return Error.UnexpectedError;
        return .{ .raw = library_handle };
    }

    /// `FT_Done_FreeType`. Clears `raw`, so a second call is a no-op.
    pub fn deinit(self: *Lib) void {
        if (self.raw) |library| _ = c.FT_Done_FreeType(library);
        self.raw = null;
    }

    /// Whether this library is still open.
    pub fn isOpen(self: *const Lib) bool {
        return self.raw != null;
    }

    /// The C handle, panicking with the reason if `deinit` already ran.
    pub fn handle(self: *const Lib) c.FT_Library {
        return self.raw orelse @panic(
            "freetype: this Lib was closed; deinit() clears the handle and " ++
                "there is no library left to call. Check isOpen() if the " ++
                "lifetime is not obvious.",
        );
    }

    /// `FT_Library_Version`: what the *library* reports, not what the headers say.
    pub fn version(self: *const Lib) std.SemanticVersion {
        var major: c_int = 0;
        var minor: c_int = 0;
        var patch: c_int = 0;
        _ = c.FT_Library_Version(self.handle(), &major, &minor, &patch);
        return .{
            .major = @intCast(major),
            .minor = @intCast(minor),
            .patch = @intCast(patch),
        };
    }

    /// `FT_New_Face`: open `path` as face `index` of whatever is in it.
    ///
    /// The returned `Face` is owned by the caller and must be `deinit`ed before
    /// this library is.
    pub fn openFace(self: *const Lib, path: [*:0]const u8, index: c_long) Error!Face {
        // The out-parameter of `FT_New_Face` is `[*c]FT_Face`, so the local
        // must be exactly `c.FT_Face`, which translate-c spells as the
        // many-item pointer `[*c]struct_FT_FaceRec_`. The address of a
        // narrower `?*T` is not that parameter type and is not coerced to it.
        var out: c.FT_Face = null;
        try errorFrom(c.FT_New_Face(self.handle(), path, index, &out));
        if (out == null) return Error.UnexpectedError;
        return .{ .raw = facePtr(out), .library = self };
    }

    /// `FT_New_Memory_Face`: open a face over memory the caller owns.
    ///
    /// The bytes must stay alive and unmodified until the `Face` is destroyed.
    /// That is the whole of what the C API asks for - `include/freetype/
    /// freetype.h:2611` says only "You must not deallocate the memory before
    /// calling @FT_Done_Face" - and it is stated here because a face does not
    /// copy the font: FreeType keeps a stream over the caller's buffer and reads
    /// tables out of it on demand, so a buffer that goes out of scope, or is
    /// scribbled on, is read again later and answers whatever it says by then.
    /// This module cannot see that from inside the library, so the rule is on
    /// the signature's documentation where a caller will meet it.
    ///
    /// `file_size` is an `FT_Long`, so a buffer longer than `maxInt(c_long)`
    /// cannot be described to it. Comparing is the honest answer; truncating
    /// would hand FreeType a different font than the caller passed.
    pub fn openMemoryFace(self: *const Lib, bytes: []const u8, index: c_long) Error!Face {
        if (bytes.len > std.math.maxInt(c_long)) return Error.InvalidArgument;
        // `FT_New_Memory_Face`'s out-parameter is `[*c]FT_Face` too, so the
        // local is that type for the same reason `openFace` states.
        var out: c.FT_Face = null;
        try errorFrom(c.FT_New_Memory_Face(
            self.handle(),
            bytes.ptr,
            @intCast(bytes.len),
            index,
            &out,
        ));
        if (out == null) return Error.UnexpectedError;
        return .{ .raw = facePtr(out), .library = self };
    }

    /// `FT_New_Memory_Face` over face 0.
    pub fn openMemoryFaceFirst(self: *const Lib, bytes: []const u8) Error!Face {
        return self.openMemoryFace(bytes, 0);
    }
};

/// The one pointer conversion this facade needs.
///
/// `translate-c` types `FT_Face` as `[*c]struct_FT_FaceRec_`, because that is
/// what the C `FT_Face*` out-parameter is. Reading a field needs a single-item
/// pointer, so the handle is stored as `*struct_FT_FaceRec_` and this is where
/// the out-parameter's many-item pointer becomes it. Only `[*c]T` and `*T`
/// carry the same address, so the conversion is exact and adds no check.
fn facePtr(face: c.FT_Face) *c.FT_FaceRec {
    return @ptrCast(face);
}

/// The glyph slot, in the same shape for the same reason as `facePtr`.
///
/// `FT_GlyphSlot` is `[*c]struct_FT_GlyphSlotRec_` and `Glyph.slot` reads
/// `slot->metrics` and `slot->outline`, so it needs a single-item pointer.
/// `FT_Render_Glyph`'s parameter is `FT_GlyphSlot`, which a `*T` widens to.
fn slotPtr(slot: c.FT_GlyphSlot) *c.FT_GlyphSlotRec {
    return @ptrCast(slot);
}

// -- Face ------------------------------------------------------------------

/// One `FT_Face`.
///
/// Owns one C face handle. It borrows its `Lib`: the face must not outlive it.
/// Nothing here reads through `raw` after `deinit`, because `deinit` clears the
/// field and a second call is then a no-op rather than a double free.
pub const Face = struct {
    raw: ?*c.FT_FaceRec = null,
    /// Kept so the type is self-describing about what it borrows.
    library: *const Lib,

    /// `FT_Done_Face`. Clears `raw`.
    pub fn deinit(self: *Face) void {
        if (self.raw) |face| _ = c.FT_Done_Face(@ptrCast(face));
        self.raw = null;
    }

    pub fn isOpen(self: *const Face) bool {
        return self.raw != null;
    }

    /// The C handle, panicking with the reason if `deinit` already ran.
    pub fn handle(self: *const Face) *c.FT_FaceRec {
        return self.raw orelse @panic(
            "freetype: this Face was closed; deinit() clears the handle and " ++
                "there is no face left to call. Check isOpen() if the lifetime " ++
                "is not obvious.",
        );
    }

    /// `face->num_glyphs`: how many glyph slots the font has.
    pub fn glyphCount(self: *const Face) u31 {
        return @intCast(self.handle().num_glyphs);
    }

    /// `face->units_per_EM`: the design grid, in font units per em.
    ///
    /// This is the number every other measurement in this file is relative to,
    /// and it is read straight out of the font's own `head` table by FreeType
    /// and out of the same table by the test's independent decoder.
    pub fn unitsPerEm(self: *const Face) u16 {
        return self.handle().units_per_EM;
    }

    /// `face->num_faces`: how many faces the file holds.
    pub fn faceCount(self: *const Face) c_long {
        return self.handle().num_faces;
    }

    /// `face->family_name`, borrowed.
    ///
    /// Borrowed, not owned: the pointer is into FreeType's own face record and
    /// is invalidated by `deinit`. `dupe` it to keep it past the face.
    pub fn familyName(self: *const Face) ?[]const u8 {
        // `family_name` is `FT_String*` (`freetype.h:1239`, `fttypes.h:190`),
        // which translate-c spells `[*c]u8` rather than a sentinel type, so
        // the span is computed from the pointer itself instead of from a
        // dereferenced first byte.
        const name = self.handle().family_name orelse return null;
        return std.mem.span(name);
    }

    /// `face->style_name`, borrowed on the same terms as `familyName`.
    pub fn styleName(self: *const Face) ?[]const u8 {
        const name = self.handle().style_name orelse return null;
        return std.mem.span(name);
    }

    /// `FT_Get_Char_Index`: the glyph slot `codepoint` maps to, or 0.
    ///
    /// Zero is a real answer, not an error: `.notdef` is glyph slot 0, and a
    /// font that maps nothing to a codepoint answers 0 rather than failing. The
    /// raw `FT_Error` is discarded because `freetype.h:3370-3374` documents this
    /// call as never failing for a valid face.
    pub fn glyphIndex(self: *const Face, codepoint: u32) u31 {
        return @intCast(c.FT_Get_Char_Index(self.handle(), codepoint));
    }

    /// `FT_Set_Pixel_Sizes`, in pixels.
    ///
    /// A zero is not an error in FreeType 2.14.3, and this passes it through
    /// rather than inventing a rejection. `src/base/ftobjs.c`'s
    /// `FT_Set_Pixel_Sizes` copies the non-zero argument into the zero one and
    /// then clamps anything below one up to one, so `(0, 16)`, `(16, 0)` and
    /// `(0, 0)` all succeed and mean 16x16, 16x16 and 1x1. The caller's own
    /// zero, if it was meant to be rejected, has to be rejected before the call.
    pub fn setPixelSizes(self: *const Face, width: c_uint, height: c_uint) Error!void {
        try errorFrom(c.FT_Set_Pixel_Sizes(self.handle(), width, height));
    }

    /// `FT_Set_Char_Size`, in 26.6 points at 72 dpi.
    ///
    /// The arguments are `FT_F26Dot6`, which is `signed long`, so they are
    /// `c_long` here and not `c_int`: on a Windows target `c_int` is 32-bit and
    /// `c_long` is 32-bit too, but on every 64-bit target they differ, and a
    /// wrapper that narrowed them would be wrong on exactly the platforms whose
    /// advances this package's sibling tests check.
    ///
    /// This is the entry point HarfBuzz uses: `src/hb-ft.cc:177-180` calls it
    /// with the `hb_font_t` scale, which is why its rounding is documented in
    /// `runtime/library.zig` rather than guessed at.
    pub fn setCharSize(self: *const Face, width: c_long, height: c_long) Error!void {
        try errorFrom(c.FT_Set_Char_Size(self.handle(), width, height, 0, 0));
    }

    /// `FT_Load_Glyph`: load `index` into `face->glyph`.
    ///
    /// Overwrites whatever was loaded before. A `Glyph` taken from an earlier
    /// call observes the *new* glyph, which is the C API's rule and the reason
    /// `Glyph` is a view.
    pub fn loadGlyph(self: *const Face, index: u31, flags: Flags) Error!Glyph {
        try errorFrom(c.FT_Load_Glyph(self.handle(), index, flags.toInt()));
        const slot = self.handle().glyph orelse return Error.UnexpectedError;
        return .{ .slot = slotPtr(slot) };
    }

    /// `FT_Load_Char`: map `codepoint` through the selected charmap and load it.
    pub fn loadChar(self: *const Face, codepoint: u32, flags: Flags) Error!Glyph {
        try errorFrom(c.FT_Load_Char(self.handle(), codepoint, flags.toInt()));
        const slot = self.handle().glyph orelse return Error.UnexpectedError;
        return .{ .slot = slotPtr(slot) };
    }

    /// `FT_Render_Glyph`: rasterize whatever is currently loaded.
    ///
    /// The mode is the translated `FT_Render_Mode` value, passed straight
    /// through: this build compiled `src/raster`, `src/smooth`, `src/svg` and
    /// `src/sdf`, so all six modes in the enum are reachable and it is not this
    /// module's business to second-guess which one a caller picked.
    pub fn renderLoaded(self: *const Face, mode: RenderMode) Error!void {
        const slot = self.handle().glyph orelse return Error.InvalidArgument;
        try errorFrom(c.FT_Render_Glyph(@ptrCast(slotPtr(slot)), mode));
    }

    /// `FT_Get_Advance`: the advance of `index` without running the loader.
    ///
    /// The unit depends on the flags, and the header is explicit about it:
    /// `include/freetype/ftadvanc.h:101-103` says the answer "is in 16.16
    /// format" only when scaling is performed by `load_flags`, and "otherwise
    /// it is in font units". `no_scale` skips scaling - `src/base/ftadvanc.c`'s
    /// `ft_face_scale_advances_` returns before it touches `padvance` - so
    /// under `no_scale` this is the font's own `hmtx` entry in font units, which
    /// is the form the known-answer tests compare against their own decode.
    /// Under any scaled flag it is 16.16.
    pub fn advance(self: *const Face, index: u31, flags: Flags) Error!i64 {
        var value: c_long = 0;
        try errorFrom(c.FT_Get_Advance(self.handle(), index, flags.toInt(), &value));
        return value;
    }

    /// `FT_Get_Glyph_Name`: the `post` table's name for `index`.
    ///
    /// FreeType's own signature takes a caller-owned buffer and its length
    /// (`include/freetype/freetype.h:4475-4478`), and it is the buffer that
    /// decides whether a long name is truncated, so this keeps that shape rather
    /// than allocating behind the caller's back. `buffer` must have room for a
    /// NUL; a zero-length buffer is `InvalidArgument` here rather than a
    /// guaranteed `InvalidArgument` from C.
    pub fn glyphName(self: *const Face, index: u31, buffer: []u8) Error![]const u8 {
        if (buffer.len == 0) return Error.InvalidArgument;
        // The name is written into `buffer` and always NUL-terminated inside
        // it, and the first byte is set to 0 on failure
        // (`include/freetype/freetype.h:4458-4464`). There is no length out
        // parameter: the prefix up to the first NUL is the whole answer.
        try errorFrom(c.FT_Get_Glyph_Name(
            self.handle(),
            index,
            buffer.ptr,
            @intCast(buffer.len),
        ));
        const terminator = std.mem.indexOfScalar(u8, buffer, 0) orelse buffer.len;
        return buffer[0..terminator];
    }
};

// -- Glyph -----------------------------------------------------------------

/// One loaded glyph: a borrowed view of `face->glyph`.
///
/// Borrowed, not owned. The record belongs to the `Face` and `FT_Load_Glyph`
/// overwrites it, so a `Glyph` that outlives its next load observes the new
/// glyph. That is the C API's rule; this wrapper states it rather than copying,
/// because a copy of an `FT_Outline` would have to copy the point array too and
/// the array belongs to FreeType's allocator.
pub const Glyph = struct {
    slot: *c.FT_GlyphSlotRec,

    /// `slot->glyph_index`: which slot was loaded.
    pub fn index(self: Glyph) u31 {
        return @intCast(self.slot.glyph_index);
    }

    /// `slot->metrics.horiAdvance`, in whatever units the load used.
    ///
    /// Font units under `no_scale`, 26.6 pixels otherwise. Read
    /// `linearHorizontalAdvance` when the answer must not depend on a hinter.
    pub fn horizontalAdvance(self: Glyph) i64 {
        return self.slot.metrics.horiAdvance;
    }

    /// `slot->metrics.width`.
    pub fn width(self: Glyph) i64 {
        return self.slot.metrics.width;
    }

    /// `slot->metrics.height`.
    pub fn height(self: Glyph) i64 {
        return self.slot.metrics.height;
    }

    /// `slot->linearHoriAdvance`: the advance in design space, unhinted.
    ///
    /// `FT_LOAD_NO_HINTING` does **not** fill this in. `src/base/ftobjs.c:1110`
    /// writes the field only when `FT_LOAD_LINEAR_DESIGN` is set, so a load
    /// without that flag leaves it at zero, which is what a measured load of
    /// this package's fixture answers. Set `Flags.linear_design` to ask for it.
    ///
    /// When it is filled it is the font's own `hmtx` entry in *font units* under
    /// `no_scale` - not 16.16 of it - which is what makes it comparable with a
    /// font's tables without any scaling or rounding. That is what the
    /// known-answer tests use.
    pub fn linearHorizontalAdvance(self: Glyph) i64 {
        return self.slot.linearHoriAdvance;
    }

    /// `FT_Outline_Get_CBox` on `slot->outline`: the control box.
    ///
    /// `src/base/ftoutln.c:470-514` computes this as the min and max over
    /// *every* point, control points included, with no margin. For a TrueType
    /// glyph that is exactly the `glyf` entry's `xMin`/`yMin`/`xMax`/`yMax`,
    /// which is the equality `tests.zig` asserts against its own table decode.
    ///
    /// An empty outline answers all zero, per the `n_points == 0` branch at
    /// `src/base/ftoutln.c:478-484`.
    pub fn controlBox(self: Glyph) BBox {
        var box: c.FT_BBox = undefined;
        c.FT_Outline_Get_CBox(&self.slot.outline, &box);
        return .{
            .x_min = box.xMin,
            .y_min = box.yMin,
            .x_max = box.xMax,
            .y_max = box.yMax,
        };
    }

    /// `FT_Outline_Get_BBox` on `slot->outline`: the tight box.
    ///
    /// Fallible where `controlBox` is not: `include/freetype/ftbbox.h:84`
    /// declares an `FT_Error`, and `src/base/ftbbox.c:486-489` returns
    /// `Invalid_Argument` for a null outline and `Invalid_Outline` when the
    /// decomposition fails. Discarding that code would report a box FreeType
    /// never computed, so the error is mapped like every other one.
    pub fn exactBox(self: Glyph) Error!BBox {
        var box: c.FT_BBox = undefined;
        try errorFrom(c.FT_Outline_Get_BBox(&self.slot.outline, &box));
        return .{
            .x_min = box.xMin,
            .y_min = box.yMin,
            .x_max = box.xMax,
            .y_max = box.yMax,
        };
    }

    /// `slot->outline.n_points`.
    pub fn pointCount(self: Glyph) u32 {
        return self.slot.outline.n_points;
    }

    /// `slot->outline.n_contours`.
    pub fn contourCount(self: Glyph) u32 {
        return self.slot.outline.n_contours;
    }

    /// The rendered bitmap, borrowed from the slot.
    ///
    /// Empty until `Face.renderLoaded` has run: an unrendered slot has
    /// `FT_GLYPH_FORMAT_OUTLINE` and a zero-sized bitmap, and this returns that
    /// honestly rather than pretending a render happened.
    pub fn bitmap(self: Glyph) Bitmap {
        return .{ .rec = &self.slot.bitmap };
    }
};

/// A bounding box, in font units or 26.6 pixels depending on the load flags.
pub const BBox = struct {
    x_min: i64,
    y_min: i64,
    x_max: i64,
    y_max: i64,
};

/// A borrowed `FT_Bitmap` view.
///
/// Borrowed from the glyph slot on the same terms as `Glyph` itself.
pub const Bitmap = struct {
    rec: *c.FT_Bitmap,

    pub fn width(self: Bitmap) u32 {
        return self.rec.width;
    }

    pub fn rows(self: Bitmap) u32 {
        return self.rec.rows;
    }

    /// `num_grays`: 256 for the anti-aliased renderers, 2 for the monochrome one.
    pub fn numGrays(self: Bitmap) u16 {
        return self.rec.num_grays;
    }

    /// `buffer` as a slice, or an empty slice when nothing is rendered.
    ///
    /// `pitch` is honoured rather than assumed away: FreeType's `pitch` is the
    /// distance between consecutive rows in bytes and is *negative* for a
    /// bottom-up bitmap, so a wrapper that indexed `row * width` would read the
    /// bitmap transposed for half the renderers.
    pub fn pixels(self: Bitmap) []const u8 {
        const buffer = self.rec.buffer orelse return &.{};
        const pitch = self.rec.pitch;
        if (pitch == 0 or self.rec.rows == 0 or self.rec.width == 0) return &.{};
        const row_bytes: usize = self.rec.width;
        const total = row_bytes * @as(usize, self.rec.rows);
        return buffer[0..total];
    }

    /// `true` when the bitmap has been rendered and has a non-zero area.
    pub fn isRendered(self: Bitmap) bool {
        return self.rec.rows != 0 and self.rec.width != 0 and self.rec.buffer != null;
    }
};