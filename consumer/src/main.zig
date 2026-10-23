// SPDX-License-Identifier: MIT
//
//! Writes a small SFNT font and checks the published FreeType API.
//! Runtime builds require a provider from `--provider` or `FREETYPE_TEST_PROVIDER`.

const std = @import("std");
const ft = @import("freetype");

/// A runtime-loading build has no provider until one is named.
const ConfigurationError = error{NoProviderConfigured};

/// Consumer failures identify provider setup, font parsing, or a failed check.
const ConsumerError = error{
    /// No provider path came from the command line or environment.
    NoProviderConfigured,
    /// FreeType rejected the synthetic font and returned an `FT_Error`.
    SyntheticFontRejected,
    /// The writer emitted a table length that differs from the expected length.
    FontLayoutMismatch,
    /// A measured answer differs from its expected value.
    ConsumerCheckFailed,
};

/// Reads the provider path from `--provider` or `FREETYPE_TEST_PROVIDER`.
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

const design = struct {
    const units_per_em: u16 = 1024;
    const num_glyphs: u16 = 2;
    /// The `.notdef` slot has no advance or outline.
    const empty_slot: u32 = 0;
    /// The rectangle glyph mapped from `'A'`.
    const drawn_slot: u32 = 1;
    const advance: u16 = 512;
    const left_side_bearing: i16 = 100;
    const ascender: i16 = 800;
    const descender: i16 = -200;
    const x_min: i16 = 100;
    const y_min: i16 = 0;
    const x_max: i16 = 500;
    const y_max: i16 = 700;
    /// Four on-curve points form one contour.
    const points: u16 = 4;
    /// 16 pt at 72 dpi yields an exact 512-unit advance on this grid.
    const point_size: u16 = 16;
};

/// Keep this literal: deriving it from `tags` creates a comptime cycle.
const tag_count = 7;

/// SFNT tags appear in directory order. The format requires sorted tags.
const tags = [tag_count][4]u8{
    "cmap".*,
    "glyf".*,
    "head".*,
    "hhea".*,
    "hmtx".*,
    "loca".*,
    "maxp".*,
};
/// Expected table lengths in tag order.
// The `glyf` length includes 16-bit x/y deltas for all four points.
const expected_lengths = [tag_count]u32{ 44, 34, 54, 36, 8, 6, 32 };
/// 12-byte SFNT header plus one 16-byte record per table.
const directory_size = 12 + tag_count * 16;
/// Capacity covers the directory and all seven padded tables.
const font_capacity = 512;

const Font = struct {
    bytes: [font_capacity]u8,
    len: usize,

    fn slice(self: *const Font) []const u8 {
        return self.bytes[0..self.len];
    }
};

/// Writes the synthetic font into one fixed buffer.
/// Tables precede the directory because their final offsets are not known earlier.
const Builder = struct {
    bytes: [font_capacity]u8 = undefined,
    cursor: usize = directory_size,
    offsets: [tag_count]u32 = undefined,
    lengths: [tag_count]u32 = undefined,

    /// Aligns the next table to four bytes and records its start.
    fn begin(self: *Builder, tag: usize) void {
        while (self.cursor % 4 != 0) : (self.cursor += 1) {
            self.bytes[self.cursor] = 0;
        }
        self.offsets[tag] = @intCast(self.cursor);
        self.lengths[tag] = 0;
    }

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

    /// Maps `'A'` to the drawn slot with the required `0xFFFF` sentinel.
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

    /// Writes a four-point glyph with on-curve points and signed 16-bit deltas.
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
        // Rectangle deltas start at the origin and follow the contour.
        for ([_]i16{ 100, 400, 0, -400 }) |dx| self.putI16(dx);
        for ([_]i16{ 0, 0, 700, 0 }) |dy| self.putI16(dy);
        self.end(1);
    }

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

    fn writeHmtx(self: *Builder) void {
        self.begin(4);
        self.putU16(0); // advanceWidth of the empty slot
        self.putI16(0); // left side bearing of the empty slot
        self.putU16(design.advance); // advanceWidth of the drawn slot
        self.putI16(design.left_side_bearing); // left side bearing of it
        self.end(4);
    }

    /// The empty slot has equal offsets. The drawn slot spans the glyph data.
    fn writeLoca(self: *Builder) void {
        self.begin(5);
        self.putU16(0); // the empty slot starts here
        self.putU16(0); // the drawn slot starts here
        self.putU16(expected_lengths[1] / 2); // the slot after it would start here
        self.end(5);
    }

    fn writeMaxp(self: *Builder) void {
        self.begin(6);
        self.putU32(0x00010000); // version
        self.putU16(design.num_glyphs);
        self.putU16(design.points); // maxPoints
        self.putU16(1); // maxContours
        for (0..11) |_| self.putU16(0); // every remaining maximum
        self.end(6);
    }

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

/// Builds the synthetic font without allocating.
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

    // Runtime builds load the requested provider before any FreeType call.
    if (comptime ft.runtime_loaded) {
        try ft.load(.{ .path = try providerRequest(init) });
    }

    try w.print("freetype consumer\n", .{});
    try w.print("{s} provider reports: {f}\n", .{
        if (ft.runtime_loaded) "loaded" else "linked",
        ft.version,
    });

    var library = try ft.Lib.init();
    defer library.deinit();

    // Compare the provider's version with the translated header version.
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

    try checkInt(w, "units per em", @as(u16, design.units_per_em), face.unitsPerEm());
    try checkInt(w, "glyph slots", @as(u31, design.num_glyphs), face.glyphCount());
    try checkInt(w, "faces in the file", @as(c_long, 1), face.faceCount());
    try checkInt(w, "'A' -> the drawn slot", @as(u31, design.drawn_slot), face.glyphIndex('A'));
    try checkInt(w, "an unmapped codepoint -> .notdef", @as(u31, design.empty_slot), face.glyphIndex('B'));

    // `no_scale` metrics use font units.
    const drawn_slot: u31 = @intCast(design.drawn_slot);
    const drawn = try face.loadGlyph(drawn_slot, ft.no_scale_no_hinting);
    try checkInt(w, "advance in font units", @as(i64, design.advance), drawn.horizontalAdvance());
    // FreeType sets `linearHoriAdvance` only with `FT_LOAD_LINEAR_DESIGN`.
    // Under `no_scale`, that field is in font units.
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
    // Under `no_scale`, `FT_Get_Advance` returns font units (ftadvanc.h:101-103).
    try checkInt(
        w,
        "FT_Get_Advance under no_scale, font units",
        @as(i64, design.advance),
        try face.advance(drawn_slot, ft.no_scale),
    );

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

    // The `.notdef` slot has no points and is not rendered.
    const empty = try face.loadGlyph(@intCast(design.empty_slot), ft.no_scale_no_hinting);
    try checkInt(w, "the empty slot has no points", @as(u32, 0), empty.pointCount());
    try checkTrue(w, "the empty slot is not rendered", !empty.bitmap().isRendered());

    // At 16 pt and 72 dpi, this grid yields exact 26.6 pixel metrics.
    try face.setCharSize(0, design.point_size * 64);
    // `Glyph` views the face's reused slot. Read metrics before the next load.
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

    // Exercise raw `FT_Get_Advances`, which the facade does not wrap.
    // It returns the advance for a glyph run in 16.16 format.
    var advance: c_long = 0;
    try checkInt(
        w,
        "raw FT_Get_Advances status",
        0,
        ft.c.FT_Get_Advances(face.handle(), @intCast(design.drawn_slot), 1, ft.no_scale.toInt(), &advance),
    );
    try checkInt(w, "its answer is this font's hmtx entry", @as(i64, design.advance), advance);
    // FreeType clamps pixel size `(0, 0)` to 1x1.
    try face.setPixelSizes(0, 0);
    try checkInt(
        w,
        "a zero pixel size becomes 1x1",
        @as(u16, 1),
        @as(*ft.c.FT_SizeRec, @ptrCast(face.handle().size orelse return error.NoSize)).metrics.x_ppem,
    );
    // `FT_Get_Advance` returns `Invalid_Argument`. `Face.advance` returns `Invalid_Glyph_Index`.
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
    // Invalid font bytes return `Invalid_File_Format` (0x03).
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
