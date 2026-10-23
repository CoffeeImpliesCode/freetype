// SPDX-License-Identifier: MIT
// See FORK-LICENSE.md for what that identifier covers.
//
//! FreeType facade for library, face, and glyph operations.

const std = @import("std");

/// Translated FreeType declarations or their runtime dispatch.
pub const c = @import("c");

const rt = @import("rt");

/// Whether this build resolves FreeType's entry points at run time.
pub const runtime_loaded: bool = if (@hasDecl(c, "rt_runtime_loaded")) c.rt_runtime_loaded else false;

/// Provider path or loader-searched basename for runtime loading.
pub const LoadSource = if (runtime_loaded) c.LoadSource else rt.LoadSource;

/// Why a runtime load did not happen.
pub const LoadError = if (runtime_loaded) c.LoadError else rt.LoadError;

/// Loads all FreeType entry points from an explicit provider.
/// Runtime-loaded builds require this before library initialization.
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

/// Returns the published provider, or null for linked builds or before loading.
pub fn loadedSource() ?LoadSource {
    if (comptime runtime_loaded) return c.loadedSource();
    return null;
}

/// FreeType version reported by the translated headers.
pub const version: std.SemanticVersion = .{
    .major = c.FREETYPE_MAJOR,
    .minor = c.FREETYPE_MINOR,
    .patch = c.FREETYPE_PATCH,
};

/// FreeType load flags with upstream bit positions.
/// Reserved fields preserve the C mask layout; all flags default to false.
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

    /// No upstream `FT_LOAD_LINEAR` flag exists; bit 25 is unused.
    linear: bool = false,
    /// No upstream `FT_LOAD_NO_SUBPIXEL_HINTING` flag exists; bit 26 is unused.
    no_subpixel: bool = false,
    /// No upstream `FT_LOAD_NO_AUTOSUBPIXEL` flag exists; bit 27 is unused.
    no_autosubpixel: bool = false,
    /// `FT_LOAD_DEFAULT` is zero; bit 28 is not an upstream flag.
    default_: bool = false,

    /// Bits 29-31 are beyond the highest bit any `FT_LOAD_*` macro claims.
    _reserved_29_31: u3 = 0,

    /// Converts this layout to the C `FT_Int32` mask.
    pub fn toInt(self: Flags) c_int {
        return @bitCast(self);
    }
};

/// Font-unit mode without hinting or rendering.
pub const no_scale: Flags = .{ .no_scale = true };

/// Font-unit mode with hinting disabled.
pub const no_scale_no_hinting: Flags = .{ .no_scale = true, .no_hinting = true };

/// The translated upstream `FT_Render_Mode` enum.
pub const RenderMode = c.FT_Render_Mode;

pub const render_normal: RenderMode = c.FT_RENDER_MODE_NORMAL;
pub const render_light: RenderMode = c.FT_RENDER_MODE_LIGHT;
pub const render_mono: RenderMode = c.FT_RENDER_MODE_MONO;
pub const render_lcd: RenderMode = c.FT_RENDER_MODE_LCD;
pub const render_lcd_v: RenderMode = c.FT_RENDER_MODE_LCD_V;
/// FreeType's signed-distance-field rendering mode.
pub const render_sdf: RenderMode = c.FT_RENDER_MODE_SDF;

/// Errors mapped from FreeType codes; all other codes become `UnexpectedError`.
pub const Error = error{
    /// `FT_Err_Cannot_Open_Resource`: the path does not exist or cannot be read.
    CannotOpenResource,
    /// `FT_Err_Unknown_File_Format`: the stream opened but is not a font one of
    /// this build's ten drivers recognised.
    UnknownFileFormat,
    /// `FT_Err_Invalid_File_Format` for unusable font data.
    InvalidFileSize,
    /// `FT_Err_Invalid_Argument`: a null handle or an argument out of range.
    InvalidArgument,
    /// `FT_Err_Invalid_Pixel_Size` for unsupported dimensions.
    InvalidPixelSize,
    /// `FT_Err_Invalid_Glyph_Index`: the index is past `num_glyphs`.
    InvalidGlyphIndex,
    /// `FT_Err_Invalid_Outline`: the outline could not be decomposed.
    InvalidOutline,
    /// `FT_Err_Unimplemented_Feature` for unsupported operations.
    UnimplementedFeature,
    /// `FT_Err_Out_Of_Memory`: FreeType's own allocator failed.
    OutOfMemory,
    /// Any unmapped FreeType error code.
    UnexpectedError,
};

/// Maps checked FreeType error codes; comparisons handle translated constant widths.
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

/// Owns one `FT_Library`; deinitialize every borrowed `Face` first.
pub const Lib = struct {
    /// The C handle, or `null` after `deinit`.
    raw: c.FT_Library = null,

    /// Initializes FreeType and maps initialization errors.
    pub fn init() Error!Lib {
        // Use the translated FT_Library pointer type for FreeType's out-parameter.
        var library_handle: c.FT_Library = null;
        try errorFrom(c.FT_Init_FreeType(&library_handle));
        // Reject a null handle explicitly; assertions disappear in ReleaseFast.
        if (library_handle == null) return Error.UnexpectedError;
        return .{ .raw = library_handle };
    }

    /// Closes the library and clears `raw`; repeated calls are safe.
    pub fn deinit(self: *Lib) void {
        if (self.raw) |library| _ = c.FT_Done_FreeType(library);
        self.raw = null;
    }

    /// Whether this library is still open.
    pub fn isOpen(self: *const Lib) bool {
        return self.raw != null;
    }

    /// Returns the open C handle; panics after `deinit`.
    pub fn handle(self: *const Lib) c.FT_Library {
        return self.raw orelse @panic(
            "freetype: this Lib was closed; deinit() clears the handle and " ++
                "there is no library left to call. Check isOpen() if the " ++
                "lifetime is not obvious.",
        );
    }

    /// Returns the version reported by the library, not the headers.
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

    /// Opens a path as face `index`; the caller owns the returned `Face`.
    /// Deinitialize the face before this library; returns mapped FreeType errors.
    pub fn openFace(self: *const Lib, path: [*:0]const u8, index: c_long) Error!Face {
        // The translated FT_Face pointer type is required for this out-parameter.
        var out: c.FT_Face = null;
        try errorFrom(c.FT_New_Face(self.handle(), path, index, &out));
        if (out == null) return Error.UnexpectedError;
        return .{ .raw = facePtr(out), .library = self };
    }

    /// Opens a face over caller-owned bytes; keep them alive and unchanged until `Face.deinit`.
    /// Rejects buffers larger than `c_long` can represent and maps FreeType errors.
    pub fn openMemoryFace(self: *const Lib, bytes: []const u8, index: c_long) Error!Face {
        if (bytes.len > std.math.maxInt(c_long)) return Error.InvalidArgument;
        // FT_New_Memory_Face uses the same translated FT_Face out-parameter.
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

    /// Opens face 0 from caller-owned bytes; the bytes must outlive the `Face`.
    pub fn openMemoryFaceFirst(self: *const Lib, bytes: []const u8) Error!Face {
        return self.openMemoryFace(bytes, 0);
    }
};

/// Converts translate-c's FT_Face out-parameter to the record pointer used here.
/// Both pointer types carry the same address.
fn facePtr(face: c.FT_Face) *c.FT_FaceRec {
    return @ptrCast(face);
}

/// Converts `FT_GlyphSlot` to the record pointer used to read glyph data.
/// FreeType also accepts this pointer form for rendering.
fn slotPtr(slot: c.FT_GlyphSlot) *c.FT_GlyphSlotRec {
    return @ptrCast(slot);
}

/// Owns one face handle and borrows its `Lib`; deinitialize it first.
/// `deinit` clears the handle, so repeated calls are safe.
pub const Face = struct {
    raw: ?*c.FT_FaceRec = null,
    library: *const Lib,

    /// Closes the face and clears `raw`.
    pub fn deinit(self: *Face) void {
        if (self.raw) |face| _ = c.FT_Done_Face(@ptrCast(face));
        self.raw = null;
    }

    pub fn isOpen(self: *const Face) bool {
        return self.raw != null;
    }

    /// Returns the open C handle; panics after `deinit`.
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

    /// Returns font units per em from the face's design grid.
    pub fn unitsPerEm(self: *const Face) u16 {
        return self.handle().units_per_EM;
    }

    /// `face->num_faces`: how many faces the file holds.
    pub fn faceCount(self: *const Face) c_long {
        return self.handle().num_faces;
    }

    /// Borrowed family name; valid until `Face.deinit`, or null if absent.
    pub fn familyName(self: *const Face) ?[]const u8 {
        // translate-c exposes `FT_String*` as `[*c]u8`; span it to find NUL.
        const name = self.handle().family_name orelse return null;
        return std.mem.span(name);
    }

    /// Borrowed style name; valid until `Face.deinit`, or null if absent.
    pub fn styleName(self: *const Face) ?[]const u8 {
        const name = self.handle().style_name orelse return null;
        return std.mem.span(name);
    }

    /// Returns the glyph slot for `codepoint`; 0 means `.notdef` or no mapping.
    /// FreeType documents this call as non-failing for a valid face.
    pub fn glyphIndex(self: *const Face, codepoint: u32) u31 {
        return @intCast(c.FT_Get_Char_Index(self.handle(), codepoint));
    }

    /// Sets pixel dimensions; zero dimensions are substituted and clamped to at least 1.
    /// Returns mapped FreeType errors.
    pub fn setPixelSizes(self: *const Face, width: c_uint, height: c_uint) Error!void {
        try errorFrom(c.FT_Set_Pixel_Sizes(self.handle(), width, height));
    }

    /// Sets character dimensions in 26.6 points at 72 dpi.
    /// Uses `c_long` to match `FT_F26Dot6`; returns mapped FreeType errors.
    pub fn setCharSize(self: *const Face, width: c_long, height: c_long) Error!void {
        try errorFrom(c.FT_Set_Char_Size(self.handle(), width, height, 0, 0));
    }

    /// Loads glyph `index`; the returned view changes on the next glyph load.
    /// Returns mapped FreeType errors.
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

    /// Renders the current glyph with an upstream mode; returns mapped errors.
    pub fn renderLoaded(self: *const Face, mode: RenderMode) Error!void {
        const slot = self.handle().glyph orelse return Error.InvalidArgument;
        try errorFrom(c.FT_Render_Glyph(@ptrCast(slotPtr(slot)), mode));
    }

    /// Returns the advance; `no_scale` uses font units, scaled flags use 16.16.
    /// Returns mapped FreeType errors.
    pub fn advance(self: *const Face, index: u31, flags: Flags) Error!i64 {
        var value: c_long = 0;
        try errorFrom(c.FT_Get_Advance(self.handle(), index, flags.toInt(), &value));
        return value;
    }

    /// Writes the post-table name to caller-owned storage and returns bytes up to NUL.
    /// The buffer must be nonempty; returns mapped FreeType errors.
    pub fn glyphName(self: *const Face, index: u31, buffer: []u8) Error![]const u8 {
        if (buffer.len == 0) return Error.InvalidArgument;
        // FreeType NUL-terminates the buffer and provides no separate length.
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

/// Borrowed view of `face->glyph`; the next glyph load overwrites it.
/// The `Face` owns the glyph slot and its buffers.
pub const Glyph = struct {
    slot: *c.FT_GlyphSlotRec,

    /// `slot->glyph_index`: which slot was loaded.
    pub fn index(self: Glyph) u31 {
        return @intCast(self.slot.glyph_index);
    }

    /// Returns the advance in font units under `no_scale`, 26.6 pixels otherwise.
    /// Use `linearHorizontalAdvance` for design-space metrics.
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

    /// Returns design-space advance in font units; set `linear_design` to populate it.
    /// Without that flag, FreeType may leave the field zero.
    pub fn linearHorizontalAdvance(self: Glyph) i64 {
        return self.slot.linearHoriAdvance;
    }

    /// Returns the control box over all outline points; an empty outline yields zero.
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

    /// Returns the tight outline box or a mapped error if FreeType cannot compute it.
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

    /// Returns a borrowed bitmap view; it is empty until rendering produces pixels.
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

/// Borrowed bitmap view; invalidated by the next glyph load or `Face.deinit`.
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

    /// Returns `width * rows` buffer bytes, or empty when data is unavailable.
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
