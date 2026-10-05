// SPDX-License-Identifier: MIT
// See ../FORK-LICENSE.md for what that identifier covers.

//! Consumes the `freetype` package the way an outside project would.
//!
//! Everything here goes through the published surface only: `dep.module` in
//! `build.zig`, and `@import("freetype")` here. No path reaches into the
//! library's own tree, so if this builds and produces the answers below, the
//! module contract is real: the typed facade, the translated headers it
//! re-exports as `c`, and the native library behind both arrived through one
//! dependency line.
//!
//! ## Where the answers come from
//!
//! The font is **written by this file**, from the OpenType specification, into
//! a buffer it then hands to `FT_New_Memory_Face`. It is two glyph slots, one of
//! them mapped from `'A'`, on a design grid of 1024 units per em, with an
//! advance of 512 and a rectangular outline. Every number checked below is a
//! field this program wrote a moment earlier, so the answers do not come from
//! FreeType and are not a round trip through the same code: a wrapper that
//! changed the scale factor, the charmap, the metric or the outline would have
//! to be wrong in exactly the way its own input is wrong.
//!
//! This file carries no font file on purpose. A dependent brings its own font,
//! and the library's own tests decode the vendored fixture instead - see
//! ../tests.zig.
//!
//! The same source builds against a linked package and against a runtime-loaded
//! one. `ft.runtime_loaded` is a comptime constant, so the difference is one
//! branch and no duplicated program: in the runtime-loaded build the provider is
//! named on the command line (`--provider <path>`) or in
//! `FREETYPE_TEST_PROVIDER`, loaded once, and the same answers follow.

const std = @import("std");
const ft = @import("freetype");

/// A runtime-loading build has no provider until one is named.
const ConfigurationError = error{NoProviderConfigured};

/// Every failure below is one named condition, not a panic in the middle of a
/// sentence, so a failing consumer run says what was wrong.
const ConsumerError = error{
    /// The provider this run should load was neither named on the command line
    /// nor present in the environment.
    NoProviderConfigured,
    /// A font this program wrote was refused. The FreeType error is printed
    /// with it, because "it did not load" is a statement about this program's
    /// font writer and the reader has to be able to tell which side failed.
    SyntheticFontRejected,
    /// The writer emitted a table whose length is not the length this file
    /// states, so the bytes handed to FreeType are not the bytes this file
    /// describes.
    FontLayoutMismatch,
    /// A measured answer was not the value this file states.
    ConsumerCheckFailed,
};

/// The provider this run should load, from `--provider <path>` or from
/// `FREETYPE_TEST_PROVIDER`.
///
/// Both are explicit. Nothing here looks in a default location, and a build
/// that was not told which file to load says so rather than loading something
/// else.
fn providerRequest(init: std.process.Init) ConfigurationError![]const u8 {
    const args = init.minimal.args.toSlice(init.arena.allocator()) catch
        return noProvider();
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        if (std.mem.eql(u8, args[index], "--provider")) {
            if (index + 1 >= args.len) return noProvider();
            return args[index + 1];
        }
    }
    return init.environ_map.get("FREETYPE_TEST_PROVIDER") orelse
        return noProvider();
}

/// Say which variable is missing. An error name on its own would send the next
/// person into the loader instead of to the command line.
fn noProvider() ConfigurationError {
    std.debug.print(
        "consumer: this is a runtime-loading build. Pass --provider <path>, or " ++
            "export FREETYPE_TEST_PROVIDER with a shared object exporting the " ++
            "declarations of zig/translate.h. Nothing is loaded by default and " ++
            "no other file is tried.\n",
        .{},
    );
    return error.NoProviderConfigured;
}

/// The fields of the synthetic font. Every answer in this program is derived
/// from one of them, and every one of them is written into the bytes below.
const design = struct {
    const units_per_em: u16 = 1024;
    const num_glyphs: u16 = 2;
    /// `.notdef`: no advance, no outline, nothing to draw.
    const empty_slot: u32 = 0;
    /// The rectangle, and the slot `'A'` maps to.
    const drawn_slot: u32 = 1;
    const advance: u16 = 512;
    const left_side_bearing: i16 = 100;
    const ascender: i16 = 800;
    const descender: i16 = -200;
    const x_min: i16 = 100;
    const y_min: i16 = 0;
    const x_max: i16 = 500;
    const y_max: i16 = 700;
    /// Four on-curve points, and one contour they close.
    const points: u16 = 4;
    /// 16 points at 72 dpi over a 1024-unit grid divides without a remainder
    /// for this font, so the scaled advance is a number this file states rather
    /// than one it would have to round: 512 * 16 * 64 / 1024 = 512.
    const point_size: u16 = 16;
};


/// How many table records the writer emits.
///
/// Written as a literal rather than derived from `tags`, because `tags` is
/// declared as a `[tag_count][4]u8` and asking that array for its own length
/// inside its own type is a comptime dependency loop: the compiler rejects it
/// with "dependency loop" naming both declarations.
const tag_count = 7;

/// The table tags, in the order the directory lists them. The specification
/// requires the directory sorted by tag, and the tags are written out here so
/// that the order is visible in the source rather than implied by an index.
const tags = [tag_count][4]u8{
    "cmap".*,
    "glyf".*,
    "head".*,
    "hhea".*,
    "hmtx".*,
    "loca".*,
    "maxp".*,
};
/// The length each table below is written with, in the same order. The writer
/// compares what it emitted against this list, so a field left out of a table
/// body is reported here instead of becoming a malformed font.
// `glyf` is 34 bytes: 14 of header, four one-byte flags, and four two-byte
// deltas for each of x and y. The x deltas used to be one byte each, which is
// where the other four bytes went.
const expected_lengths = [tag_count]u32{ 44, 34, 54, 36, 8, 6, 32 };
/// Twelve bytes of sfnt header plus one sixteen-byte record per table.
const directory_size = 12 + tag_count * 16;
/// The ceiling on what the writer can reach: the directory, then the seven
/// tables, each padded to a four-byte boundary.
const font_capacity = 512;

/// The font, and the number of bytes of it that were written.
const Font = struct {
    bytes: [font_capacity]u8,
    len: usize,

    fn slice(self: *const Font) []const u8 {
        return self.bytes[0..self.len];
    }
};

/// Writes the font described by `design` into one buffer.
///
/// The tables are written first and the directory is written over the space
/// reserved in front of them, because a table's offset is only known once the
/// earlier tables have their lengths.
const Builder = struct {
    bytes: [font_capacity]u8 = undefined,
    cursor: usize = directory_size,
    offsets: [tag_count]u32 = undefined,
    lengths: [tag_count]u32 = undefined,

    /// Pad to a four-byte boundary and reserve space for the table at `tag`.
    fn begin(self: *Builder, tag: usize) void {
        while (self.cursor % 4 != 0) : (self.cursor += 1) {
            self.bytes[self.cursor] = 0;
        }
        self.offsets[tag] = @intCast(self.cursor);
        self.lengths[tag] = 0;
    }

    /// Close the table at `tag`: its length is whatever it was given.
    fn end(self: *Builder, tag: usize) void {
        self.lengths[tag] = @intCast(self.cursor - self.offsets[tag]);
    }

    fn put(self: *Builder, byte: u8) void {
        self.bytes[self.cursor] = byte;
        self.cursor += 1;
    }

    fn putU16(self: *Builder, value: u16) void {
        std.mem.writeInt(u16, self.bytes[self.cursor..][0..2], value, .big);
        self.cursor += 2;
    }

    fn putI16(self: *Builder, value: i16) void {
        std.mem.writeInt(i16, self.bytes[self.cursor..][0..2], value, .big);
        self.cursor += 2;
    }

    fn putU32(self: *Builder, value: u32) void {
        std.mem.writeInt(u32, self.bytes[self.cursor..][0..4], value, .big);
        self.cursor += 4;
    }

    fn putU16At(self: *Builder, at: usize, value: u16) void {
        std.mem.writeInt(u16, self.bytes[at..][0..2], value, .big);
    }

    fn putU32At(self: *Builder, at: usize, value: u32) void {
        std.mem.writeInt(u32, self.bytes[at..][0..4], value, .big);
    }

    /// `cmap`: one format 4 subtable, Windows/Unicode BMP, mapping `'A'` to the
    /// drawn slot and nothing else.
    ///
    /// `idRangeOffset` is zero in both segments, so a glyph index is
    /// `(code + idDelta) mod 65536` and no glyph index array is needed. The
    /// last segment is the `0xFFFF` sentinel the format requires.
    fn writeCmap(self: *Builder) void {
        self.begin(0);
        self.putU16(0); // version
        self.putU16(1); // numTables
        self.putU16(3); // platformID: Microsoft
        self.putU16(1); // encodingID: Unicode BMP
        self.putU32(12); // offset of the subtable, from the start of this table
        self.putU16(4); // format
        self.putU16(32); // length, from `format` to the end of the subtable
        self.putU16(0); // language
        self.putU16(4); // segCountX2: two segments
        self.putU16(4); // searchRange: 2 * 2^floor(log2(2))
        self.putU16(1); // entrySelector: log2(searchRange / 2)
        self.putU16(0); // rangeShift: 2 * segCount - searchRange
        self.putU16('A'); // endCode[0]
        self.putU16(0xFFFF); // endCode[1]
        self.putU16(0); // reservedPad
        self.putU16('A'); // startCode[0]
        self.putU16(0xFFFF); // startCode[1]
        // idDelta[0]: 'A' plus this is the drawn slot.
        self.putI16(@as(i16, @intCast(design.drawn_slot)) - @as(i16, 'A'));
        self.putI16(1); // idDelta[1]
        self.putU16(0); // idRangeOffset[0]
        self.putU16(0); // idRangeOffset[1]
        self.end(0);
    }

    /// `glyf`: one simple glyph, a closed rectangle of four on-curve points.
    ///
    /// Every point carries only the on-curve bit (`0x01`), so both coordinates
    /// are plain signed 16-bit deltas. The previous `0x03` set X_SHORT_VECTOR
    /// without setting X_IS_SAME_OR_POSITIVE_X_SHORT_VECTOR, which asks the
    /// reader to take every x delta as a *negative* single byte, and a single
    /// byte could not have carried the `400` this rectangle needs anyway.
    /// Sixteen-bit deltas have neither problem.
    fn writeGlyf(self: *Builder) void {
        self.begin(1);
        self.putI16(1); // numberOfContours
        self.putI16(design.x_min);
        self.putI16(design.y_min);
        self.putI16(design.x_max);
        self.putI16(design.y_max);
        self.putU16(design.points - 1); // endPtsOfContours[0]
        self.putU16(0); // instructionLength: no hinting program
        for (0..design.points) |_| self.put(0x01); // flags: on-curve
        // (100, 0) -> (500, 0) -> (500, 700) -> (100, 700), and the contour
        // closes back to the first point. The leading 100 is a delta from the
        // origin rather than a step, which is why it is `x_min`.
        for ([_]i16{ 100, 400, 0, -400 }) |dx| self.putI16(dx);
        for ([_]i16{ 0, 0, 700, 0 }) |dy| self.putI16(dy);
        self.end(1);
    }

    /// `head`: the design grid, the font-wide bounding box, and a short `loca`.
    fn writeHead(self: *Builder) void {
        self.begin(2);
        self.putU32(0x00010000); // version
        self.putU32(0); // fontRevision
        self.putU32(0); // checkSumAdjustment
        self.putU32(0x5F0F3CF5); // magicNumber
        self.putU16(0); // flags
        self.putU16(design.units_per_em);
        self.putU32(0); // created, high
        self.putU32(0); // created, low
        self.putU32(0); // modified, high
        self.putU32(0); // modified, low
        self.putI16(design.x_min);
        self.putI16(design.y_min);
        self.putI16(design.x_max);
        self.putI16(design.y_max);
        self.putU16(0); // macStyle
        self.putU16(8); // lowestRecPPEM
        self.putI16(2); // fontDirectionHint
        self.putI16(0); // indexToLocFormat: short loca
        self.putI16(0); // glyphDataFormat
        self.end(2);
    }

    /// `hhea`: one horizontal metric per glyph slot.
    fn writeHhea(self: *Builder) void {
        self.begin(3);
        self.putU32(0x00010000); // version
        self.putI16(design.ascender);
        self.putI16(design.descender);
        self.putI16(0); // lineGap
        self.putU16(design.advance); // advanceWidthMax
        self.putI16(0); // minLeftSideBearing
        self.putI16(0); // minRightSideBearing
        self.putI16(design.x_max); // xMaxExtent
        self.putI16(1); // caretSlopeRise
        self.putI16(0); // caretSlopeRun
        self.putI16(0); // caretOffset
        for (0..4) |_| self.putI16(0); // reserved
        self.putI16(0); // metricDataFormat
        self.putU16(design.num_glyphs); // numberOfHMetrics
        self.end(3);
    }

    /// `hmtx`: the advance and side bearing of each slot.
    fn writeHmtx(self: *Builder) void {
        self.begin(4);
        self.putU16(0); // advanceWidth of the empty slot
        self.putI16(0); // left side bearing of the empty slot
        self.putU16(design.advance); // advanceWidth of the drawn slot
        self.putI16(design.left_side_bearing); // left side bearing of it
        self.end(4);
    }

    /// `loca`: short offsets in two-byte units, one per slot plus one.
    ///
    /// The empty slot has equal start and end offsets, and the drawn slot runs
    /// from offset zero to the end of the one glyph this font carries.
    fn writeLoca(self: *Builder) void {
        self.begin(5);
        self.putU16(0); // the empty slot starts here
        self.putU16(0); // the drawn slot starts here
        self.putU16(expected_lengths[1] / 2); // the slot after it would start here
        self.end(5);
    }

    /// `maxp`: the counts a loader reads, and zero for everything else.
    fn writeMaxp(self: *Builder) void {
        self.begin(6);
        self.putU32(0x00010000); // version
        self.putU16(design.num_glyphs);
        self.putU16(design.points); // maxPoints
        self.putU16(1); // maxContours
        for (0..11) |_| self.putU16(0); // every remaining maximum
        self.end(6);
    }

    /// The sfnt header and the seven directory records, written over the space
    /// reserved in front of the tables.
    fn writeDirectory(self: *Builder) ConsumerError!void {
        for (expected_lengths, 0..) |expected, index| {
            if (self.lengths[index] != expected) {
                std.debug.print(
                    "consumer: table {s} is {d} bytes, this file states {d}\n",
                    .{ tags[index][0..], self.lengths[index], expected },
                );
                return error.FontLayoutMismatch;
            }
        }

        // The three search fields describe the directory's own size and are not
        // checked by a reader, but they are written correctly anyway: a font
        // whose directory lies about its shape is a bad example to ship.
        const largest_power_of_two: u16 = 4; // greatest power of two <= 7
        self.putU32At(0, 0x00010000); // sfntVersion: TrueType outlines
        self.putU16At(4, tag_count);
        self.putU16At(6, 16 * largest_power_of_two); // searchRange
        self.putU16At(8, 2); // entrySelector: log2(4)
        self.putU16At(10, 16 * tag_count - 16 * largest_power_of_two); // rangeShift

        for (tags, 0..) |tag, index| {
            const at = 12 + 16 * index;
            self.bytes[at..][0..4].* = tag;
            self.putU32At(at + 4, 0); // checkSum: a reader does not verify it
            self.putU32At(at + 8, self.offsets[index]);
            self.putU32At(at + 12, self.lengths[index]);
        }
    }
};

/// The font, written once, in this frame: no allocator is involved anywhere in
/// this program.
fn writeFont() ConsumerError!Font {
    var builder = Builder{};
    builder.writeCmap();
    builder.writeGlyf();
    builder.writeHead();
    builder.writeHhea();
    builder.writeHmtx();
    builder.writeLoca();
    builder.writeMaxp();
    try builder.writeDirectory();
    return .{ .bytes = builder.bytes, .len = builder.cursor };
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &buffer);
    const w = &stdout.interface;

    // In a runtime-loading build every call below goes through a table that
    // this one call fills. In a linked build the branch is not analyzed at all,
    // because `ft.runtime_loaded` is comptime.
    if (comptime ft.runtime_loaded) {
        try ft.load(.{ .path = try providerRequest(init) });
    }

    try w.print("freetype consumer\n", .{});
    // Through the typed surface rather than a constant compiled here, so this
    // line names the library this build reached. It is printed, not compared: a
    // version string is provenance, not behaviour.
    try w.print("{s} provider reports: {f}\n", .{
        if (ft.runtime_loaded) "loaded" else "linked",
        ft.version,
    });

    var library = try ft.Lib.init();
    defer library.deinit();

    // What the compiled library answers is not what the headers said, and those
    // two are read from different places on purpose: one from this build's
    // translation, one from the library's own `FT_Library_Version`. Comparing
    // them is a statement about the two agreeing, not about a constant.
    try checkSame(w, "library release == header release", library.version(), ft.version);

    var font = try writeFont();
    var face = library.openMemoryFaceFirst(font.slice()) catch |err| {
        std.debug.print(
            "consumer: the font this program wrote was refused: {s}\n",
            .{@errorName(err)},
        );
        return error.SyntheticFontRejected;
    };
    defer face.deinit();

    // The values the font itself states.
    try checkInt(w, "units per em", @as(u16, design.units_per_em), face.unitsPerEm());
    try checkInt(w, "glyph slots", @as(u31, design.num_glyphs), face.glyphCount());
    try checkInt(w, "faces in the file", @as(c_long, 1), face.faceCount());
    try checkInt(w, "'A' -> the drawn slot", @as(u31, design.drawn_slot), face.glyphIndex('A'));
    try checkInt(w, "an unmapped codepoint -> .notdef", @as(u31, design.empty_slot), face.glyphIndex('B'));

    // Font units: the only mode whose numbers come out of the `hmtx` this
    // program wrote.
    const drawn_slot: u31 = @intCast(design.drawn_slot);
    const drawn = try face.loadGlyph(drawn_slot, ft.no_scale_no_hinting);
    try checkInt(w, "advance in font units", @as(i64, design.advance), drawn.horizontalAdvance());
    // `linearHoriAdvance` is only written when the load asked for design-space
    // metrics (`src/base/ftobjs.c` guards it on `FT_LOAD_LINEAR_DESIGN`), so
    // this flag set leaves it at zero, and with the flag set it is the `hmtx`
    // entry in font units rather than 16.16 of it.
    try checkInt(w, "linear advance without the flag", @as(i64, 0), drawn.linearHorizontalAdvance());
    const designed = try face.loadGlyph(drawn_slot, .{
        .no_scale = true,
        .no_hinting = true,
        .linear_design = true,
    });
    try checkInt(
        w,
        "linear advance, font units",
        @as(i64, design.advance),
        designed.linearHorizontalAdvance(),
    );
    // `FT_Get_Advance` is in font units too under `no_scale`: `ftadvanc.h:101-103`
    // makes the 16.16 form conditional on the flags actually causing scaling.
    try checkInt(
        w,
        "FT_Get_Advance under no_scale, font units",
        @as(i64, design.advance),
        try face.advance(drawn_slot, ft.no_scale),
    );

    // The outline is the rectangle this program described, point for point.
    try checkInt(w, "contours", @as(u32, 1), drawn.contourCount());
    try checkInt(w, "points", @as(u32, design.points), drawn.pointCount());
    const control = drawn.controlBox();
    try checkInt(w, "control box x_min", @as(i64, design.x_min), control.x_min);
    try checkInt(w, "control box y_min", @as(i64, design.y_min), control.y_min);
    try checkInt(w, "control box x_max", @as(i64, design.x_max), control.x_max);
    try checkInt(w, "control box y_max", @as(i64, design.y_max), control.y_max);
    const tight = try drawn.exactBox();
    try checkTrue(
        w,
        "the tight box is inside the control box",
        tight.x_min >= control.x_min and tight.y_min >= control.y_min and
            tight.x_max <= control.x_max and tight.y_max <= control.y_max,
    );

    // The empty slot is empty, and it is not a zero-sized glyph pretending to
    // be drawn.
    const empty = try face.loadGlyph(@intCast(design.empty_slot), ft.no_scale_no_hinting);
    try checkInt(w, "the empty slot has no points", @as(u32, 0), empty.pointCount());
    try checkTrue(w, "the empty slot is not rendered", !empty.bitmap().isRendered());

    // 26.6 pixels: a different unit from the three checks above, and an exact
    // one here, because 16 points at 72 dpi over this grid divides without a
    // remainder.
    try face.setCharSize(0, design.point_size * 64);
    // Read the number out of the slot immediately. A `Glyph` is a view of
    // `face->glyph`, and FreeType reuses that one record, so a `Glyph` kept
    // across the next `loadGlyph` observes the *new* glyph. Capturing the value
    // while it is the one that was just loaded is what makes the pair below a
    // comparison between two sizes rather than between one size and itself.
    const scaled = (try face.loadGlyph(drawn_slot, .{ .no_hinting = true })).horizontalAdvance();
    try checkInt(
        w,
        "advance at 16pt, 26.6",
        @as(i64, design.advance) * design.point_size * 64 / design.units_per_em,
        scaled,
    );
    try face.setCharSize(0, 2 * design.point_size * 64);
    const larger = (try face.loadGlyph(drawn_slot, .{ .no_hinting = true })).horizontalAdvance();
    try checkInt(
        w,
        "twice the size is twice the advance",
        2 * scaled,
        larger,
    );

    // A render, through the same slot the outline was in.
    const rendered = try face.loadGlyph(drawn_slot, .{ .no_hinting = true, .render = true });
    const bitmap = rendered.bitmap();
    try checkTrue(w, "the rectangle rasterized", bitmap.isRendered());
    try checkTrue(w, "the bitmap has width", bitmap.width() > 0);
    try checkTrue(w, "the bitmap has rows", bitmap.rows() > 0);
    try checkInt(w, "grey levels", @as(u16, 256), bitmap.numGrays());
    try checkInt(
        w,
        "the pixel slice is width * rows",
        @as(usize, bitmap.width()) * @as(usize, bitmap.rows()),
        bitmap.pixels().len,
    );
    var inked: usize = 0;
    for (bitmap.pixels()) |value| {
        if (value != 0) inked += 1;
    }
    try checkTrue(w, "the rectangle has ink in it", inked > 0);

    // The raw route: a declaration this package's facade does not wrap, reached
    // through the same published module. `FT_Get_Advances` answers the same
    // 16.16 advance `FT_Get_Advance` does, for a run of glyph slots, and no
    // call in the facade reaches it.
    var advance: c_long = 0;
    try checkInt(
        w,
        "raw FT_Get_Advances status",
        0,
        ft.c.FT_Get_Advances(face.handle(), @intCast(design.drawn_slot), 1, ft.no_scale.toInt(), &advance),
    );
    // Font units here too: these are the same unscaled flags as above.
    try checkInt(w, "its answer is this font's hmtx entry", @as(i64, design.advance), advance);
    // The error paths a dependent has to be able to tell apart. Each is a
    // different fact, so a caller can act on one of them, and every expectation
    // here was measured against the compiled library rather than assumed.
    //
    // A zero pixel size is not one of them: `FT_Set_Pixel_Sizes` substitutes
    // the other argument and clamps `(0, 0)` to 1x1, so the call succeeds.
    try face.setPixelSizes(0, 0);
    try checkInt(
        w,
        "a zero pixel size becomes 1x1",
        @as(u16, 1),
        @as(*ft.c.FT_SizeRec, @ptrCast(face.handle().size orelse return error.NoSize)).metrics.x_ppem,
    );
    // A slot past the end reaches the driver, which says `Invalid_Argument`;
    // `Face.advance` is the entry point that range-checks and says
    // `Invalid_Glyph_Index`, so both tags are pinned here.
    try expectError(
        w,
        "a slot past the end of the font",
        ft.Error.InvalidArgument,
        face.loadGlyph(face.glyphCount(), ft.no_scale_no_hinting),
    );
    try expectError(
        w,
        "a slot past the end, through advance",
        ft.Error.InvalidGlyphIndex,
        face.advance(face.glyphCount(), ft.no_scale_no_hinting),
    );
    // Prose is short enough that the first driver's probe fails before any
    // format verdict, and this build answers `Invalid_File_Format` (0x03).
    try expectError(
        w,
        "bytes that are not a font",
        ft.Error.InvalidFileSize,
        library.openMemoryFaceFirst("forty-nine bytes of prose, not a font at all"),
    );
    try expectError(
        w,
        "a path that cannot be opened",
        ft.Error.CannotOpenResource,
        library.openFace("/nonexistent-freetype-consumer/no-such-font.ttf", 0),
    );

    try w.print("every answer matched a value this program wrote\n", .{});
    try w.flush();
}

fn checkInt(w: *std.Io.Writer, what: []const u8, stated: anytype, computed: anytype) !void {
    try w.print("{s: <44}{d}\n", .{ what, computed });
    if (computed != stated) {
        std.debug.print("consumer: {s}: expected {d}, computed {d}\n", .{ what, stated, computed });
        return error.ConsumerCheckFailed;
    }
}

fn checkTrue(w: *std.Io.Writer, what: []const u8, got: bool) !void {
    try w.print("{s: <44}{s}\n", .{ what, if (got) "yes" else "no" });
    if (!got) {
        std.debug.print("consumer: {s}: the answer was no\n", .{what});
        return error.ConsumerCheckFailed;
    }
}

fn checkSame(
    w: *std.Io.Writer,
    what: []const u8,
    got: std.SemanticVersion,
    expected: std.SemanticVersion,
) !void {
    try w.print("{s: <44}{f}\n", .{ what, got });
    if (got.order(expected) != .eq) {
        std.debug.print("consumer: {s}: expected {f}, computed {f}\n", .{ what, expected, got });
        return error.ConsumerCheckFailed;
    }
}

fn expectError(w: *std.Io.Writer, what: []const u8, expected: anyerror, result: anytype) !void {
    if (result) |_| {
        std.debug.print("consumer: {s}: the call succeeded and was expected to fail\n", .{what});
        return error.ConsumerCheckFailed;
    } else |err| {
        try w.print("{s: <44}{s}\n", .{ what, @errorName(err) });
        if (err != expected) {
            std.debug.print("consumer: {s}: expected {s}, got {s}\n", .{
                what,
                @errorName(expected),
                @errorName(err),
            });
            return error.ConsumerCheckFailed;
        }
    }
}