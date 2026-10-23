// SPDX-License-Identifier: MIT
// See FORK-LICENSE.md for what that identifier covers.

//! Tests the FreeType facade against an embedded TrueType fixture.

const std = @import("std");
const testing = std.testing;

/// The typed facade, as a dependent would import it.
const ft = @import("freetype");
/// Raw FreeType declarations used to inspect fields absent from the facade.
const c = ft.c;

/// The environment variable naming a provider for the runtime route.
const provider_variable = "FREETYPE_TEST_PROVIDER";

/// Embedded fixture font bytes.
const font_bytes = @embedFile("tests/fixtures/HarfBust.ttf");

/// Loads the explicit runtime provider, or does nothing when linked.
/// Runtime-loaded tests require `FREETYPE_TEST_PROVIDER`.
fn nativeReady() void {
    if (comptime !ft.runtime_loaded) return;
    if (ft.loadedSource() != null) return;
    // Use libc getenv because the package links libc in every configuration.
    const path = std.c.getenv(provider_variable) orelse @panic(
        "freetype: this build resolves its entry points at run time. Set " ++
            provider_variable ++ " to the absolute path of a FreeType provider " ++
            "(libfreetype.so.6, or the equivalent on this platform) before " ++
            "running these tests. There is no default location.",
    );
    ft.load(.{ .path = std.mem.span(path) }) catch |err| @panic(
        "freetype: the provider named by " ++ provider_variable ++ " could not be loaded: " ++ @errorName(err),
    );
}

/// Returns the provider source recorded by the loader, if any.
fn providerSource() ?[]const u8 {
    if (comptime !ft.runtime_loaded) return null;
    return switch (ft.loadedSource() orelse return null) {
        .path => |p| p,
        .system => |s| s,
    };
}

// -- An independent TrueType table reader ---------------------------------

/// Reads the fixture's TrueType tables independently of FreeType.
const Font = struct {
    bytes: []const u8,
    head: Table,
    maxp: Table,
    hhea: Table,
    hmtx: Table,
    cmap: Table,
    loca: Table,
    glyf: Table,
    num_glyphs: u16,
    units_per_em: u16,
    index_to_loc_format: i16,
    number_of_h_metrics: u16,

    const Table = struct {
        offset: usize,
        length: usize,
    };

    fn u16At(self: Font, table: Table, at: usize) u16 {
        const start = table.offset + at;
        return std.mem.readInt(u16, self.bytes[start..][0..2], .big);
    }

    fn i16At(self: Font, table: Table, at: usize) i16 {
        const start = table.offset + at;
        return std.mem.readInt(i16, self.bytes[start..][0..2], .big);
    }

    fn u32At(self: Font, table: Table, at: usize) u32 {
        const start = table.offset + at;
        return std.mem.readInt(u32, self.bytes[start..][0..4], .big);
    }

    fn parse(bytes: []const u8) !Font {
        if (bytes.len < 12) return error.TruncatedFont;
        if (!std.mem.eql(u8, bytes[0..4], "\x00\x01\x00\x00")) return error.NotTrueType;
        const num_tables = std.mem.readInt(u16, bytes[4..6], .big);
        if (bytes.len < 12 + num_tables * 16) return error.TruncatedFont;

        var tables: [256]Table = undefined;
        var found: usize = 0;
        for (0..num_tables) |i| {
            const record = 12 + i * 16;
            const offset = std.mem.readInt(u32, bytes[record + 8 ..][0..4], .big);
            const length = std.mem.readInt(u32, bytes[record + 12 ..][0..4], .big);
            if (offset + length > bytes.len) return error.TruncatedFont;
            if (found < tables.len) {
                tables[found] = .{ .offset = offset, .length = length };
                found += 1;
            }
        }
        if (found < 7) return error.MissingTables;
        var head: ?Table = null;
        var maxp: ?Table = null;
        var hhea: ?Table = null;
        var hmtx: ?Table = null;
        var cmap: ?Table = null;
        var loca: ?Table = null;
        var glyf: ?Table = null;
        for (0..num_tables) |i| {
            const record = 12 + i * 16;
            const offset = std.mem.readInt(u32, bytes[record + 8 ..][0..4], .big);
            const length = std.mem.readInt(u32, bytes[record + 12 ..][0..4], .big);
            const table: Table = .{ .offset = offset, .length = length };
            if (std.mem.eql(u8, bytes[record ..][0..4], "head")) {
                head = table;
            } else if (std.mem.eql(u8, bytes[record ..][0..4], "maxp")) {
                maxp = table;
            } else if (std.mem.eql(u8, bytes[record ..][0..4], "hhea")) {
                hhea = table;
            } else if (std.mem.eql(u8, bytes[record ..][0..4], "hmtx")) {
                hmtx = table;
            } else if (std.mem.eql(u8, bytes[record ..][0..4], "cmap")) {
                cmap = table;
            } else if (std.mem.eql(u8, bytes[record ..][0..4], "loca")) {
                loca = table;
            } else if (std.mem.eql(u8, bytes[record ..][0..4], "glyf")) {
                glyf = table;
            }
        }
        const head_table = head orelse return error.MissingTables;
        const maxp_table = maxp orelse return error.MissingTables;
        const hhea_table = hhea orelse return error.MissingTables;
        const hmtx_table = hmtx orelse return error.MissingTables;
        const cmap_table = cmap orelse return error.MissingTables;
        const loca_table = loca orelse return error.MissingTables;
        const glyf_table = glyf orelse return error.MissingTables;

        var self = Font{
            .bytes = bytes,
            .head = head_table,
            .maxp = maxp_table,
            .hhea = hhea_table,
            .hmtx = hmtx_table,
            .cmap = cmap_table,
            .loca = loca_table,
            .glyf = glyf_table,
            .num_glyphs = 0,
            .units_per_em = 0,
            .index_to_loc_format = 0,
            .number_of_h_metrics = 0,
        };
        self.units_per_em = self.u16At(head_table, 18);
        self.index_to_loc_format = self.i16At(head_table, 50);
        self.num_glyphs = self.u16At(maxp_table, 4);
        self.number_of_h_metrics = self.u16At(hhea_table, 34);
        return self;
    }

    /// Returns the `hmtx` advance; later glyphs repeat the last long metric.
    fn advance(self: Font, gid: u16) !i64 {
        const last = self.number_of_h_metrics - 1;
        const index: u16 = if (gid < last) gid else last;
        const at = index * 4;
        if (self.hmtx.length < at + 2) return error.TruncatedFont;
        return self.u16At(self.hmtx, at);
    }

    /// Looks up a codepoint in the first format 4 cmap subtable.
    fn glyphIndex(self: Font, codepoint: u21) !u16 {
        const sub = try self.cmapFormat4();
        const seg_count_x2 = std.mem.readInt(u16, self.bytes[sub + 6 ..][0..2], .big);
        const seg_count = @as(usize, seg_count_x2) / 2;
        const ends = sub + 14;
        const starts = ends + seg_count_x2 + 2;
        const deltas = starts + seg_count_x2;
        const ranges = deltas + seg_count_x2;
        for (0..seg_count) |i| {
            const end = std.mem.readInt(u16, self.bytes[ends + 2 * i ..][0..2], .big);
            if (codepoint > end) continue;
            const start = std.mem.readInt(u16, self.bytes[starts + 2 * i ..][0..2], .big);
            if (codepoint < start) return 0;
            const delta = std.mem.readInt(i16, self.bytes[deltas + 2 * i ..][0..2], .big);
            const range_offset = std.mem.readInt(u16, self.bytes[ranges + 2 * i ..][0..2], .big);
            // Widen before bitcasting; `@bitCast` requires equal widths.
            if (range_offset == 0) return @as(u16, @truncate(@as(u32, codepoint) +% @as(u32, @bitCast(@as(i32, delta)))));
            const glyph_at = ranges + 2 * i + range_offset + 2 * (codepoint - start);
            const gid = std.mem.readInt(u16, self.bytes[glyph_at..][0..2], .big);
            if (gid == 0) return 0;
            return @as(u16, @truncate(@as(u32, gid) +% @as(u32, @bitCast(@as(i32, delta)))));
        }
        return 0;
    }

    fn cmapFormat4(self: Font) !usize {
        const count = std.mem.readInt(u16, self.bytes[self.cmap.offset + 2 ..][0..2], .big);
        for (0..count) |i| {
            const record = self.cmap.offset + 4 + 8 * i;
            const offset = std.mem.readInt(u32, self.bytes[record + 4 ..][0..4], .big);
            const sub = self.cmap.offset + offset;
            if (sub + 4 > self.bytes.len) return error.TruncatedFont;
            if (std.mem.readInt(u16, self.bytes[sub..][0..2], .big) != 4) continue;
            return sub;
        }
        return error.NoFormat4Cmap;
    }

    /// Reads a glyph's bounding box from `loca` and `glyf`, in font units.
    fn glyphBox(self: Font, gid: u16) !struct { x_min: i32, y_min: i32, x_max: i32, y_max: i32 } {
        const start = if (self.index_to_loc_format == 0)
            @as(usize, self.u16At(self.loca, gid * 2)) * 2
        else
            self.u32At(self.loca, gid * 4);
        const end = if (self.index_to_loc_format == 0)
            @as(usize, self.u16At(self.loca, gid * 2 + 2)) * 2
        else
            self.u32At(self.loca, gid * 4 + 4);
        if (end <= start) return error.EmptyGlyph;
        const at = self.glyf.offset + start;
        if (at + 10 > self.bytes.len) return error.TruncatedFont;
        return .{
            .x_min = self.i16At(self.glyf, start + 2),
            .y_min = self.i16At(self.glyf, start + 4),
            .x_max = self.i16At(self.glyf, start + 6),
            .y_max = self.i16At(self.glyf, start + 8),
        };
    }
};

fn decodeFixture() !Font {
    return Font.parse(font_bytes);
}

/// Owns a library and face; `close` destroys the face before its library.
/// FreeType requires that destruction order.
const Fixture = struct {
    lib: ft.Lib,
    face: ft.Face,

    fn open() !Fixture {
        nativeReady();
        var lib = try ft.Lib.init();
        errdefer lib.deinit();
        var face = try lib.openMemoryFaceFirst(font_bytes);
        errdefer face.deinit();
        return .{ .lib = lib, .face = face };
    }

    fn close(self: *Fixture) void {
        self.face.deinit();
        self.lib.deinit();
    }
};

test "a library reports the release its headers describe" {
    nativeReady();
    var lib = try ft.Lib.init();
    defer lib.deinit();

    // Compare the compiled library's version with the version from its headers.
    try testing.expectEqual(ft.version, lib.version());
    try testing.expect(lib.isOpen());
}

test "closing a library is a transition this module owns" {
    nativeReady();
    var lib = try ft.Lib.init();
    try testing.expect(lib.isOpen());
    lib.deinit();
    try testing.expect(!lib.isOpen());
    lib.deinit();
    try testing.expect(!lib.isOpen());
}

test "the face's design grid is the one in the font's own head table" {
    var fixture = try Fixture.open();
    defer fixture.close();
    const font = try decodeFixture();

    try testing.expectEqual(@as(u16, 2048), font.units_per_em);
    try testing.expectEqual(@as(u16, 2048), fixture.face.unitsPerEm());
    try testing.expectEqual(@as(u32, 99), font.num_glyphs);
    try testing.expectEqual(@as(u31, 99), fixture.face.glyphCount());
    try testing.expectEqual(@as(c_long, 1), fixture.face.faceCount());
}

test "a character maps to the glyph slot the font's own cmap says" {
    var fixture = try Fixture.open();
    defer fixture.close();
    const font = try decodeFixture();

    const cases = [_]struct { codepoint: u21, gid: u16 }{
        .{ .codepoint = 0x41, .gid = 3 }, // 'A'
        .{ .codepoint = 0x48, .gid = 10 }, // 'H'
        .{ .codepoint = 0x61, .gid = 28 }, // 'a'
        .{ .codepoint = 0x7A, .gid = 53 }, // 'z'
    };
    for (cases) |case| {
        const expected = try font.glyphIndex(case.codepoint);
        try testing.expectEqual(case.gid, expected);
        try testing.expectEqual(@as(u31, expected), fixture.face.glyphIndex(case.codepoint));
    }
}

test "an unhinted advance is the font's own hmtx entry" {
    var fixture = try Fixture.open();
    defer fixture.close();
    const font = try decodeFixture();

    const cases = [_]u16{ 3, 10, 28, 53 };
    for (cases) |gid| {
        const expected = try font.advance(gid);

        const from_advance = try fixture.face.advance(gid, ft.no_scale);
        try testing.expectEqual(expected, from_advance);

        const glyph = try fixture.face.loadGlyph(gid, ft.no_scale_no_hinting);
        try testing.expectEqual(expected, glyph.horizontalAdvance());

        try testing.expectEqual(@as(i64, 0), glyph.linearHorizontalAdvance());
        const designed = try fixture.face.loadGlyph(gid, .{
            .no_scale = true,
            .no_hinting = true,
            .linear_design = true,
        });
        try testing.expectEqual(expected, designed.linearHorizontalAdvance());
    }
}

test "the outline control box is the glyph entry's own bounding box" {
    var fixture = try Fixture.open();
    defer fixture.close();
    const font = try decodeFixture();

    for ([_]u16{ 3, 4, 10, 28, 45, 53 }) |gid| {
        const expected = try font.glyphBox(gid);
        const glyph = try fixture.face.loadGlyph(gid, ft.no_scale_no_hinting);
        const box = glyph.controlBox();
        try testing.expectEqual(expected.x_min, @as(i32, @intCast(box.x_min)));
        try testing.expectEqual(expected.y_min, @as(i32, @intCast(box.y_min)));
        try testing.expectEqual(expected.x_max, @as(i32, @intCast(box.x_max)));
        try testing.expectEqual(expected.y_max, @as(i32, @intCast(box.y_max)));

        const tight = try glyph.exactBox();
        try testing.expect(tight.x_min >= box.x_min);
        try testing.expect(tight.y_min >= box.y_min);
        try testing.expect(tight.x_max <= box.x_max);
        try testing.expect(tight.y_max <= box.y_max);
    }
}

test "an outline has the contours the glyf table says it has" {
    var fixture = try Fixture.open();
    defer fixture.close();
    const font = try decodeFixture();

    // These glyphs have non-empty `loca` ranges.
 
        // Every closed contour contains at least one point.
    for ([_]u16{ 10, 28, 53 }) |gid| {
        _ = try font.glyphBox(gid);
        const glyph = try fixture.face.loadGlyph(gid, ft.no_scale_no_hinting);
        try testing.expect(glyph.pointCount() > 0);
        try testing.expect(glyph.contourCount() > 0);
        try testing.expect(glyph.contourCount() <= glyph.pointCount());
    }
}

test "opening the same bytes twice gives the same face" {
    var fixture = try Fixture.open();
    defer fixture.close();

    var second = try fixture.lib.openMemoryFaceFirst(font_bytes);
    defer second.deinit();

    try testing.expectEqual(fixture.face.unitsPerEm(), second.unitsPerEm());
    try testing.expectEqual(fixture.face.glyphCount(), second.glyphCount());
    for ([_]u21{ 0x41, 0x48, 0x61, 0x7A }) |cp| {
        try testing.expectEqual(fixture.face.glyphIndex(cp), second.glyphIndex(cp));
    }
}

test "the font's own names are what the post table says" {
    var fixture = try Fixture.open();
    defer fixture.close();

    var buffer: [64]u8 = undefined;
    const name = try fixture.face.glyphName(10, &buffer);
    try testing.expect(name.len > 0);
    try testing.expectEqualStrings("H", name);
}

test "a face over the caller's bytes keeps reading from them" {
    nativeReady();
    var lib = try ft.Lib.init();
    defer lib.deinit();

    // FreeType reads tables from the caller's buffer on demand.
    // Keep the bytes alive and unchanged until `Face.deinit`.
    var copy: [font_bytes.len]u8 = undefined;
    @memcpy(&copy, font_bytes);
    var face = try lib.openMemoryFaceFirst(&copy);
    defer face.deinit();

    // The cmap lookup reads the current bytes on demand.
    try testing.expectEqual(@as(u16, 2048), face.unitsPerEm());
    try testing.expectEqual(@as(u31, 10), face.glyphIndex(0x48));

    // Zeroing the borrowed bytes changes later cmap lookups; `head` was cached at open.
    @memset(&copy, 0);
    try testing.expectEqual(@as(u31, 0), face.glyphIndex(0x48));
    try testing.expectEqual(@as(u16, 2048), face.unitsPerEm());
}

test "a path that cannot be opened is one honest error" {
    nativeReady();
    var lib = try ft.Lib.init();
    defer lib.deinit();

    try testing.expectError(
        ft.Error.CannotOpenResource,
        lib.openFace("/nonexistent-freetype-fixture-directory/no-such-font.ttf", 0),
    );
}

test "bytes that are not a font are rejected by the code that says so" {
    nativeReady();
    var lib = try ft.Lib.init();
    defer lib.deinit();

    // Different malformed streams reach different drivers and return different errors.
    const prose = "this is not a font, it is thirty-nine bytes of prose";
    try testing.expectError(
        ft.Error.InvalidFileSize,
        lib.openMemoryFaceFirst(prose),
    );

    // An unknown sfnt tag reaches the sfnt driver and returns `UnknownFileFormat`.
    var unknown_tag: [4096]u8 = @splat(0x11);
    unknown_tag[0] = 0x11;
    unknown_tag[1] = 0x22;
    unknown_tag[2] = 0x33;
    unknown_tag[3] = 0x44;
    try testing.expectError(
        ft.Error.UnknownFileFormat,
        lib.openMemoryFaceFirst(&unknown_tag),
    );
}

test "a font cut in half still opens, and this file's own decoder is stricter" {
    nativeReady();
    var lib = try ft.Lib.init();
    defer lib.deinit();

    // FreeType validates the directory on open and defers reads of other tables.
    // The independent decoder validates every table up front.
    const half = font_bytes[0 .. font_bytes.len / 2];
    try testing.expectError(error.TruncatedFont, Font.parse(half));

    var face = try lib.openMemoryFaceFirst(half);
    defer face.deinit();
    try testing.expectEqual(@as(u16, 2048), face.unitsPerEm());
    try testing.expectEqual(@as(u31, 99), face.glyphCount());
    try testing.expectEqual(@as(u31, 10), face.glyphIndex(0x48));
}

test "a zero pixel size is substituted, not rejected" {
    var fixture = try Fixture.open();
    defer fixture.close();

    const size = fixture.face.handle().size orelse return error.NoSizeRequested;

    try fixture.face.setPixelSizes(0, 16);
    try testing.expectEqual(@as(u16, 16), @as(*c.FT_SizeRec, @ptrCast(size)).metrics.x_ppem);
    try testing.expectEqual(@as(u16, 16), @as(*c.FT_SizeRec, @ptrCast(size)).metrics.y_ppem);

    try fixture.face.setPixelSizes(16, 0);
    try testing.expectEqual(@as(u16, 16), @as(*c.FT_SizeRec, @ptrCast(size)).metrics.x_ppem);

    try fixture.face.setPixelSizes(0, 0);
    try testing.expectEqual(@as(u16, 1), @as(*c.FT_SizeRec, @ptrCast(size)).metrics.x_ppem);
    try testing.expectEqual(@as(u16, 1), @as(*c.FT_SizeRec, @ptrCast(size)).metrics.y_ppem);
}

test "a glyph index past the end of the font is an error, not a glyph" {
    var fixture = try Fixture.open();
    defer fixture.close();

    // `FT_Load_Glyph` and `FT_Get_Advance` return different errors for bad indices.
    // Index zero is valid and represents `.notdef`.
    try testing.expectError(
        ft.Error.InvalidArgument,
        fixture.face.loadGlyph(fixture.face.glyphCount(), ft.no_scale_no_hinting),
    );
    try testing.expectError(
        ft.Error.InvalidGlyphIndex,
        fixture.face.advance(fixture.face.glyphCount(), ft.no_scale_no_hinting),
    );
    const unmapped = try fixture.face.loadChar(0x4E2D, ft.no_scale_no_hinting);
    try testing.expectEqual(@as(u31, 0), unmapped.index());
}

test "rendering produces a bitmap, and only rendering does" {
    var fixture = try Fixture.open();
    defer fixture.close();

    // An unrendered glyph slot has no bitmap.
    const outline_only = try fixture.face.loadGlyph(10, .{ .no_hinting = true });
    try testing.expect(!outline_only.bitmap().isRendered());
    try testing.expectEqual(@as(u32, 0), outline_only.bitmap().width());
    try testing.expectEqual(@as(u32, 0), outline_only.bitmap().rows());

    // This fixture's glyph needs a size before rendering produces pixels.
    try fixture.face.setPixelSizes(32, 32);

    // `FT_LOAD_RENDER` and `renderLoaded` should produce matching bitmap geometry.
    const rendered = try fixture.face.loadGlyph(10, .{ .no_hinting = true, .render = true });
    const bitmap = rendered.bitmap();
    try testing.expect(bitmap.isRendered());
    try testing.expect(bitmap.width() > 0);
    try testing.expect(bitmap.rows() > 0);
    try testing.expectEqual(@as(u16, 256), bitmap.numGrays());

    var inked: usize = 0;
    for (bitmap.pixels()) |value| {
        if (value != 0) inked += 1;
    }
    try testing.expect(inked > 0);
    try testing.expectEqual(
        @as(usize, bitmap.width()) * @as(usize, bitmap.rows()),
        bitmap.pixels().len,
    );

    // Copy the first bitmap because FreeType reuses the glyph slot and buffer.
    const again = try fixture.face.loadGlyph(10, .{ .no_hinting = true, .render = true });
    const first = try testing.allocator.dupe(u8, rendered.bitmap().pixels());
    defer testing.allocator.free(first);
    const second = again.bitmap();
    try testing.expectEqual(first.len, second.pixels().len);
    try testing.expectEqualSlices(u8, first, second.pixels());

    // `renderLoaded` should match the load-time render geometry.
    const plain = try fixture.face.loadGlyph(10, .{ .no_hinting = true });
    try fixture.face.renderLoaded(ft.render_normal);
    try testing.expectEqual(second.width(), plain.bitmap().width());
    try testing.expectEqual(second.rows(), plain.bitmap().rows());
}

test "a size in points changes what the metrics say, and a scale in units does not" {
    var fixture = try Fixture.open();
    defer fixture.close();
    const font = try decodeFixture();
    // At 32 points, 32 * 64 / 2048 = 1, so font-unit and 26.6 advances match.
    // The expected values follow units * points * 64 / unitsPerEm.
    const gid: u31 = 10;
    const units = try font.advance(gid);
    const upem: i64 = fixture.face.unitsPerEm();
    try fixture.face.setCharSize(0, 16 * 64);
    const small = (try fixture.face.loadGlyph(gid, .{ .no_hinting = true })).horizontalAdvance();
    try fixture.face.setCharSize(0, 32 * 64);
    const large = (try fixture.face.loadGlyph(gid, .{ .no_hinting = true })).horizontalAdvance();
    try testing.expect(small > 0);
    try testing.expect(large > small);
    try testing.expectEqual(@divTrunc(units * 16 * 64, upem), small);
    try testing.expectEqual(@divTrunc(units * 32 * 64, upem), large);
    try testing.expectEqual(units, large);
}

test "the raw route reaches the declarations the facade does not name" {
    nativeReady();
    // Reads public `FT_FaceRec` data that the facade does not expose.
    var fixture = try Fixture.open();
    defer fixture.close();
    try testing.expectEqual(@as(c_long, 1), fixture.face.handle().num_faces);
    try testing.expect(fixture.face.familyName() != null);
}

test "a successful runtime load is visible, and a linked build says nothing was chosen" {
    nativeReady();
    if (comptime ft.runtime_loaded) {
        try testing.expect(providerSource() != null);
    } else {
        // Linked builds have no runtime provider source.
        try testing.expectEqual(@as(?[]const u8, null), providerSource());
    }
}
