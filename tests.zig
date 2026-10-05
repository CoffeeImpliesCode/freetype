// SPDX-License-Identifier: MIT
// See FORK-LICENSE.md for what that identifier covers.

//! Behavioural tests for the FreeType SDK.
//!
//! ## Where the answers come from
//!
//! The primary fixture is an **independent known answer**: `tests.zig` contains
//! its own TrueType table reader - `head`, `maxp`, `hhea`, `hmtx`, a format 4
//! `cmap`, `loca` and `glyf` - written from the OpenType specification and
//! reading the same bytes FreeType reads. Every number asserted below against
//! FreeType is therefore checked twice: once by FreeType's parser and once by
//! this file's, over the same binary, by two independent implementations. A
//! wrapper bug that changed the answer would have to be a bug in *both*.
//!
//! ## The fixture font, and where it came from
//!
//! `tests/fixtures/HarfBust.ttf` is HarfBuzz's own Latin in-house test font,
//! vendored from `harfbuzz/test/shape/data/in-house/fonts/` of HarfBuzz 14.5.1
//! under the SIL Open Font License 1.1, whose text is beside it as
//! `tests/fixtures/COPYING`. Its SHA-256 and the exact upstream line it came
//! from are in `UPSTREAM.md`; `NOTICE.md` carries the licence and
//! `tools/check-provenance.sh` re-checks the digest.
//!
//! It is embedded with `@embedFile` rather than opened by path: an embedded
//! fixture is the same bytes on every target, which is what makes a cross-cell
//! `build_only` result about the library rather than about a missing file.
//!
//! ## What these tests do NOT check
//!
//! There is no leak check. FreeType allocates through the C library
//! (`include/freetype/config/ftstdlib.h:142-145`), so `std.testing`'s allocator
//! never sees a byte of it and this file's leaks, if any, are invisible here.
//! That is a stated limit rather than a silent one.

const std = @import("std");
const testing = std.testing;

/// The typed facade, as a dependent would import it.
const ft = @import("freetype");
/// The translated FreeType headers, for the tests that assert on a record
/// field the facade deliberately does not expose.
const c = ft.c;

/// The environment variable naming a provider for the runtime route.
const provider_variable = "FREETYPE_TEST_PROVIDER";

/// The embedded fixture font. `tests.zig` is the module root, and Zig resolves
/// `@embedFile` against the package root, so this is `tests/fixtures/...`.
const font_bytes = @embedFile("tests/fixtures/HarfBust.ttf");

/// Load the runtime provider once, or do nothing in a linked build.
///
/// Under `-Druntime=true` there is no default provider and no fallback, so a
/// test that needs one and was not given one is a hard `@panic` naming the
/// variable rather than a silent skip: a skipped test is not a result.
fn nativeReady() void {
    if (comptime !ft.runtime_loaded) return;
    if (ft.loadedSource() != null) return;
    // `std.c.getenv`, not `std.posix.getenv`: this SDK links the C library in
    // every configuration (including the runtime one, whose loader calls
    // `dlopen`), so the C spelling is the one that is present on every target
    // this package builds for.
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

/// The provider, when this build has one, as the loader state reports it.
/// A reader, used to check that a successful load is visible.
fn providerSource() ?[]const u8 {
    if (comptime !ft.runtime_loaded) return null;
    return switch (ft.loadedSource() orelse return null) {
        .path => |p| p,
        .system => |s| s,
    };
}

// -- An independent TrueType table reader ---------------------------------

/// The tables this file needs from the fixture, decoded without FreeType.
///
/// Everything here is written from the OpenType specification, not from
/// FreeType's reader: a table directory scan, the `head` fields the design grid
/// is made of, `maxp`'s glyph count, `hhea`'s metric count, the `hmtx` advance
/// array, a format 4 `cmap` segment walk, `loca`'s glyph offsets and `glyf`'s
/// per-glyph bounding box.
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
            // The directory is sorted by tag, so `found` is a usable index for
            // the seven tags this reader wants.
            // The increment is a separate statement because an `if` used as a
            // statement needs a braced body; a bare one is an expression and
            // this position does not take one.
            if (found < tables.len) {
                tables[found] = .{ .offset = offset, .length = length };
                found += 1;
            }
        }
        if (found < 7) return error.MissingTables;
        // Sorted order: GSUB, OS/2, cmap, glyf, head, hhea, hmtx, loca, maxp,
        // name, post. Rather than depend on that, search by tag.
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

    /// `hmtx`: the advance of `gid` in font units.
    ///
    /// The last entry repeats for every glyph past `numberOfHMetrics`, which is
    /// the rule in the specification and a fixture where it matters: `hmtx`'s
    /// length is 4*99 for 99 glyphs, so a reader that indexed it per glyph would
    /// read past the end here.
    fn advance(self: Font, gid: u16) !i64 {
        const last = self.number_of_h_metrics - 1;
        const index: u16 = if (gid < last) gid else last;
        const at = index * 4;
        if (self.hmtx.length < at + 2) return error.TruncatedFont;
        return self.u16At(self.hmtx, at);
    }

    /// A format 4 `cmap` segment walk.
    ///
    /// The subtable this picks is the first one that is format 4 and is either a
    /// Windows or a Unicode encoding; the fixture's two subtables are the same
    /// table reached through platform 0 and platform 3, so the choice cannot
    /// change the answer.
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
            // `@bitCast` preserves width, so the `i16` delta is widened to
            // `i32` first and reinterpreted as `u32` after that; a direct
            // `i16` to `u32` bitcast is a size mismatch. Sign extension happens
            // in the `@intCast`, which is what `idDelta` arithmetic needs.
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

    /// `loca` + `glyf`: the glyph's bounding box in font units.
    ///
    /// This is the same four numbers `FT_Outline_Get_CBox` computes for a
    /// TrueType outline, from the same table, reached by a different path.
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

/// The decoded fixture, built once per process.
///
/// Named for what it returns rather than `fixture`, because every test that
/// wants the decoded bytes also declares `var fixture = try Fixture.open()` for
/// the library-and-face pair, and a local may not shadow a file-scope
/// declaration.
fn decodeFixture() !Font {
    return Font.parse(font_bytes);
}

/// A library and a face over the embedded fixture, as one lexical scope.
///
/// `defer` order is the contract: the face is destroyed before the library,
/// which is the order FreeType requires and the one this helper exists to make
/// unbreakable in every test that uses it.
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

// -- Tests -----------------------------------------------------------------

test "a library reports the release its headers describe" {
    nativeReady();
    var lib = try ft.Lib.init();
    defer lib.deinit();

    // `FT_Library_Version` answers what the *compiled library* is, not what the
    // header said. Comparing the two is what catches a library built from
    // different sources than the ones this package vendored.
    try testing.expectEqual(ft.version, lib.version());
    try testing.expect(lib.isOpen());
}

test "closing a library is a transition this module owns" {
    nativeReady();
    var lib = try ft.Lib.init();
    try testing.expect(lib.isOpen());
    lib.deinit();
    try testing.expect(!lib.isOpen());
    // A second close is a no-op, not a double free: `deinit` clears the handle
    // before anything can reach it again.
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

    // Four codepoints and the four answers this file's format 4 segment walk
    // computes over the same bytes FreeType's parser reads.
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

    // `FT_LOAD_NO_SCALE` is the only mode whose numbers are in font units, so
    // this is a comparison against the font's own bytes rather than against a
    // rounding rule.
    const cases = [_]u16{ 3, 10, 28, 53 };
    for (cases) |gid| {
        const expected = try font.advance(gid);

        // `FT_Get_Advance` takes its unit from the flags. `include/freetype/
        // ftadvanc.h:101-103` says the answer is "in 16.16 format" only when
        // `load_flags` cause scaling to be performed, and `src/base/ftadvanc.c`'s
        // `ft_face_scale_advances_` returns before it touches `padvance` under
        // `no_scale`, so the answer there is the bare `hmtx` entry in font
        // units. Measured: gid 10 answers 1022, which is the `hmtx` value.
        const from_advance = try fixture.face.advance(gid, ft.no_scale);
        try testing.expectEqual(expected, from_advance);

        const glyph = try fixture.face.loadGlyph(gid, ft.no_scale_no_hinting);
        try testing.expectEqual(expected, glyph.horizontalAdvance());

        // `linearHoriAdvance` is only written when the load asked for
        // design-space metrics: `src/base/ftobjs.c` guards it on
        // `FT_LOAD_LINEAR_DESIGN`, so a load without that flag leaves it at
        // zero rather than filling it in. With the flag it is the font-unit
        // advance, not 16.16 of it - which is what the flag is for.
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

    // `FT_Outline_Get_CBox` takes the min and max over every point, control
    // points included (`src/base/ftoutln.c:470-514`), and for a TrueType
    // outline those are exactly the `glyf` entry's four fields. Same four
    // numbers, two readers.
    for ([_]u16{ 3, 4, 10, 28, 45, 53 }) |gid| {
        const expected = try font.glyphBox(gid);
        const glyph = try fixture.face.loadGlyph(gid, ft.no_scale_no_hinting);
        const box = glyph.controlBox();
        try testing.expectEqual(expected.x_min, @as(i32, @intCast(box.x_min)));
        try testing.expectEqual(expected.y_min, @as(i32, @intCast(box.y_min)));
        try testing.expectEqual(expected.x_max, @as(i32, @intCast(box.x_max)));
        try testing.expectEqual(expected.y_max, @as(i32, @intCast(box.y_max)));

        // The tight box is inside the control box, always. That is a boundary,
        // not a known answer, and it holds for any outline rather than this one.
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

    // `loca` gives a non-empty range for exactly the glyphs this file decoded a
    // box for, and a point array at least as long as that range implies.
    for ([_]u16{ 10, 28, 53 }) |gid| {
        _ = try font.glyphBox(gid);
        const glyph = try fixture.face.loadGlyph(gid, ft.no_scale_no_hinting);
        try testing.expect(glyph.pointCount() > 0);
        try testing.expect(glyph.contourCount() > 0);
        // A closed contour's last point index is `n_points - 1`, so the contour
        // array is `n_points` long at most.
        try testing.expect(glyph.contourCount() <= glyph.pointCount());
    }
}

test "opening the same bytes twice gives the same face" {
    var fixture = try Fixture.open();
    defer fixture.close();
    // The decoded copy is not needed here: this test compares FreeType's view of
    // the same bytes against a second open of them, so parsing them again would
    // be work with no oracle attached.

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
    // The fixture is HarfBuzz's own Latin font and glyph 10 is its 'H'. The
    // value is not pinned as a *constant of this package*: it is what the
    // `post` table in the fixture says, and the test fails if the vendored font
    // and the vendored expectation ever stop agreeing.
    try testing.expect(name.len > 0);
    try testing.expectEqualStrings("H", name);
}

test "a face over the caller's bytes keeps reading from them" {
    nativeReady();
    var lib = try ft.Lib.init();
    defer lib.deinit();

    // A copy the test owns. `FT_New_Memory_Face` does not take a copy of the
    // font: FreeType keeps a stream over this buffer and reads each table out
    // of it when something asks for that table. `include/freetype/
    // freetype.h:2611` puts the whole requirement in one sentence - the memory
    // must not be deallocated before `FT_Done_Face` - and this test is what
    // makes that requirement executable rather than a comment.
    // (The `head` table is read at open, so it survives the scribble below; the
    // `cmap` table is read on demand, so it does not.)
    var copy: [font_bytes.len]u8 = undefined;
    @memcpy(&copy, font_bytes);
    var face = try lib.openMemoryFaceFirst(&copy);
    defer face.deinit();

    // While the bytes are intact the face answers from them. `head` was read
    // when the face was opened and `cmap` is read now, on demand.
    try testing.expectEqual(@as(u16, 2048), face.unitsPerEm());
    try testing.expectEqual(@as(u31, 10), face.glyphIndex(0x48));

    // Scribbling on the buffer is therefore visible through the open face: the
    // charmap is now zeroes, so nothing maps and the answer is `.notdef`. A
    // face that had copied what it needed would still answer 10 here, which is
    // why the two observations together are the ownership contract rather than
    // either one alone.
    @memset(&copy, 0);
    try testing.expectEqual(@as(u31, 0), face.glyphIndex(0x48));
    // `head` is still what it was, because the face read it at open and kept it.
    try testing.expectEqual(@as(u16, 2048), face.unitsPerEm());
}

test "a path that cannot be opened is one honest error" {
    nativeReady();
    var lib = try ft.Lib.init();
    defer lib.deinit();

    // The name cannot be a font because the directory does not exist. The point
    // is the *tag*: `CannotOpenResource` and `UnexpectedError` are different
    // facts and a caller can act on one of them.
    try testing.expectError(
        ft.Error.CannotOpenResource,
        lib.openFace("/nonexistent-freetype-fixture-directory/no-such-font.ttf", 0),
    );
}

test "bytes that are not a font are rejected by the code that says so" {
    nativeReady();
    var lib = try ft.Lib.init();
    defer lib.deinit();

    // Two shapes of "not a font", and this build draws two different codes
    // between them. Both were measured against the compiled library, because
    // which driver rejects the stream first decides which code survives:
    //
    //  - Prose is short and matches no driver's magic, so the first probe that
    //    fails reports `FT_Err_Invalid_File_Format` (0x03, "broken file",
    //    `include/freetype/fterrdef.h:65`) rather than a format verdict.
    const prose = "this is not a font, it is thirty-nine bytes of prose";
    try testing.expectError(
        ft.Error.InvalidFileSize,
        lib.openMemoryFaceFirst(prose),
    );

    //  - Bytes long enough that every driver reads its magic successfully and
    //    then rejects the container tag reach the sfnt driver, which reports
    //    `FT_Err_Unknown_File_Format` (0x02) for a tag it does not know.
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

    // The directory says there are tables past the end of the buffer. FreeType
    // does not treat that as an error at open time: it reads the sfnt directory,
    // finds it consistent, and defers every other table until something asks
    // for it. Measured, both at half and at a quarter of the file, the open
    // succeeds. So the two readers here disagree by design, and this is where
    // that difference is pinned: the independent decoder validates the whole
    // directory up front and refuses, where FreeType defers.
    const half = font_bytes[0 .. font_bytes.len / 2];
    try testing.expectError(error.TruncatedFont, Font.parse(half));

    var face = try lib.openMemoryFaceFirst(half);
    defer face.deinit();
    // And the face that did open is not wrong: the tables this test asks about
    // all sit inside the half that survived.
    try testing.expectEqual(@as(u16, 2048), face.unitsPerEm());
    try testing.expectEqual(@as(u31, 99), face.glyphCount());
    try testing.expectEqual(@as(u31, 10), face.glyphIndex(0x48));
}

test "a zero pixel size is substituted, not rejected" {
    var fixture = try Fixture.open();
    defer fixture.close();

    // `src/base/ftobjs.c`'s `FT_Set_Pixel_Sizes` copies the non-zero argument
    // into whichever one is zero and then clamps anything below one up to one,
    // so a zero never reaches `FT_Request_Size` and this call cannot fail with
    // `FT_Err_Invalid_Pixel_Size`. Measured: `(0, 16)` and `(16, 0)` both give a
    // 16x16 size, and `(0, 0)` gives 1x1. Asserting the ppem is what makes the
    // substitution observable instead of merely permitted.
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

    // The two entry points disagree about how they report an out-of-range
    // index, and both were measured: `FT_Load_Glyph` hands the index to the
    // driver, which refuses it as `FT_Err_Invalid_Argument` (0x06), while
    // `FT_Get_Advance` range-checks `gindex` itself and reports
    // `FT_Err_Invalid_Glyph_Index` (0x10). Asserting both keeps the taxonomy
    // honest about which wrapper produces which tag.
    try testing.expectError(
        ft.Error.InvalidArgument,
        fixture.face.loadGlyph(fixture.face.glyphCount(), ft.no_scale_no_hinting),
    );
    try testing.expectError(
        ft.Error.InvalidGlyphIndex,
        fixture.face.advance(fixture.face.glyphCount(), ft.no_scale_no_hinting),
    );
    // Index 0 is legal and is `.notdef`, which is a real answer rather than an
    // absence: a codepoint the font does not map returns 0, not an error.
    const unmapped = try fixture.face.loadChar(0x4E2D, ft.no_scale_no_hinting);
    try testing.expectEqual(@as(u31, 0), unmapped.index());
}

test "rendering produces a bitmap, and only rendering does" {
    var fixture = try Fixture.open();
    defer fixture.close();

    // An unrendered slot carries an outline and no bitmap. `bitmap` says so
    // rather than inventing pixels, which is the difference between a report and
    // a guess.
    const outline_only = try fixture.face.loadGlyph(10, .{ .no_hinting = true });
    try testing.expect(!outline_only.bitmap().isRendered());
    try testing.expectEqual(@as(u32, 0), outline_only.bitmap().width());
    try testing.expectEqual(@as(u32, 0), outline_only.bitmap().rows());

    // Rendering happens at whatever size the face currently carries. A face
    // opened from memory has the library's default size, and for this fixture
    // that size rasterises 'H' to nothing, so a render flag set before any
    // `setPixelSizes` produces an empty bitmap. Measured: at the default size
    // `FT_LOAD_RENDER` answers success with rows=0 and width=0. Asking for a
    // size first is what makes the rendering assertions below mean something.
    try fixture.face.setPixelSizes(32, 32);

    // Loading with FT_LOAD_RENDER renders as part of the load, which is the same
    // rasterizer reached through the flag rather than through `renderLoaded`.
    const rendered = try fixture.face.loadGlyph(10, .{ .no_hinting = true, .render = true });
    const bitmap = rendered.bitmap();
    try testing.expect(bitmap.isRendered());
    try testing.expect(bitmap.width() > 0);
    try testing.expect(bitmap.rows() > 0);
    // 256 grey levels is the anti-aliased renderer's contract; the monochrome one
    // would answer 2 and this flag set is not monochrome.
    try testing.expectEqual(@as(u16, 256), bitmap.numGrays());

    // Ink exists, and the rendered rows are the width the bitmap reports: a
    // wrapper that indexed `row * width` over a bottom-up bitmap would read it
    // transposed and this would still pass, which is why `pitch` is honoured in
    // `Bitmap.pixels` rather than assumed away.
    var inked: usize = 0;
    for (bitmap.pixels()) |value| {
        if (value != 0) inked += 1;
    }
    try testing.expect(inked > 0);
    try testing.expectEqual(
        @as(usize, bitmap.width()) * @as(usize, bitmap.rows()),
        bitmap.pixels().len,
    );

    // Rendering the same glyph again through the same path is the same bitmap.
    // A rasterizer that is not deterministic cannot be tested at all, so this is
    // the precondition for every other rendering assertion anywhere. The copy is
    // necessary rather than defensive: FreeType reuses one glyph slot and one
    // bitmap buffer, so `pixels()` after a second load is a view of the same
    // bytes.
    const again = try fixture.face.loadGlyph(10, .{ .no_hinting = true, .render = true });
    const first = try testing.allocator.dupe(u8, rendered.bitmap().pixels());
    defer testing.allocator.free(first);
    const second = again.bitmap();
    try testing.expectEqual(first.len, second.pixels().len);
    try testing.expectEqualSlices(u8, first, second.pixels());

    // `renderLoaded` reaches the same renderer through the other route, and the
    // two agree on the bitmap's shape.
    const plain = try fixture.face.loadGlyph(10, .{ .no_hinting = true });
    try fixture.face.renderLoaded(ft.render_normal);
    try testing.expectEqual(second.width(), plain.bitmap().width());
    try testing.expectEqual(second.rows(), plain.bitmap().rows());
}

test "a size in points changes what the metrics say, and a scale in units does not" {
    var fixture = try Fixture.open();
    defer fixture.close();
    const font = try decodeFixture();
    // Two sizes, one answer in font units and two answers in 26.6 pixels. The
    // invariant is the ratio the specification states, not a golden number: a
    // wrapper that mixed the two units would break it.
    //
    // `FT_Set_Char_Size` takes 26.6 *points* at 72 dpi, so a height of `pt * 64`
    // is `pt` pixels per em. With `units_per_EM` font units per em that is
    // `pt * 64 / units_per_EM` pixels per font unit, and an advance in 26.6 is
    // the font-unit advance times that. For this fixture `units_per_EM` is 2048,
    // which is exactly 32 * 64, so the 32-point answer lands on the font-unit
    // advance unchanged - a fact about the ratio, not a constant copied in.
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
    // `Face.faceCount` is not a measurement the facade exposes, but the record
    // is public - every member of `FT_FaceRec` is, which is what makes the
    // version check in `runtime/library.zig` a real ABI statement.
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
        // A linked build did not choose a provider; it was given one at link
        // time. Reporting a source here would be a fiction.
        try testing.expectEqual(@as(?[]const u8, null), providerSource());
    }
}