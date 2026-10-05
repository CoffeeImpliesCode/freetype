// SPDX-License-Identifier: MIT
// See FORK-LICENSE.md for what that identifier covers.

//! A deterministic example program for the FreeType SDK.
//!
//! It opens the embedded fixture font, prints what it measured and compares each
//! answer with a value this file states, so a run either prints one closing line
//! or fails with both sides named. Nothing here is a golden image or a golden
//! count: every expected value is one number this file is willing to explain.
//!
//! Under `-Druntime=true` it needs `FREETYPE_TEST_PROVIDER`; a linked build
//! needs nothing.

const std = @import("std");
const ft = @import("freetype");

const font_bytes = @embedFile("tests/fixtures/HarfBust.ttf");
const provider_variable = "FREETYPE_TEST_PROVIDER";

/// Any failure below is one named condition, not a panic in the middle of a
/// sentence, so a failing smoke run says what was wrong.
const SmokeError = error{
    ProviderCheckFailed,
    EnvironmentCheckFailed,
    MetricsCheckFailed,
    OutlineCheckFailed,
    RenderCheckFailed,
};

/// Load the runtime provider, or do nothing in a linked build.
fn nativeReady() !void {
    if (comptime !ft.runtime_loaded) return;
    if (ft.loadedSource() != null) return;
    const path = std.c.getenv(provider_variable) orelse return error.EnvironmentCheckFailed;
    ft.load(.{ .path = std.mem.span(path) }) catch return error.ProviderCheckFailed;
}

/// Print one labelled answer and compare it.
fn check(comptime label: [:0]const u8, expected: anytype, actual: @TypeOf(expected)) SmokeError!void {
    std.debug.print("  {s: <28} {any}\n", .{ label, actual });
    if (expected != actual) {
        std.debug.print("  {s: <28} expected {any}, got {any}\n", .{ label, expected, actual });
        return error.MetricsCheckFailed;
    }
}

pub fn main() !void {
    try nativeReady();

    std.debug.print(
        \\
        \\freetype smoke: {f}, {s}
        \\
    , .{ ft.version, if (ft.runtime_loaded) "runtime-loaded provider" else "linked" });

    var lib = try ft.Lib.init();
    defer lib.deinit();

    // Printed, never compared: the version is provenance, and a test that pins
    // it would be testing a string constant.
    std.debug.print("  library reports             {any}\n", .{lib.version()});

    var face = try lib.openMemoryFaceFirst(font_bytes);
    defer face.deinit();

    std.debug.print("  family                      {s}\n", .{face.familyName() orelse "<none>"});

    try check("design grid (units/em)", @as(u16, 2048), face.unitsPerEm());
    try check("glyph count", @as(u31, 99), face.glyphCount());
    try check("'H' glyph slot", @as(u31, 10), face.glyphIndex('H'));
    try check("'z' glyph slot", @as(u31, 53), face.glyphIndex('z'));

    // A codepoint the font does not map is `.notdef`, which is a real answer.
    try check("unmapped U+4E2D -> .notdef", @as(u31, 0), face.glyphIndex(0x4E2D));

    // Font units, which is the only mode whose numbers come straight out of the
    // font's own `hmtx`.
    const h = try face.loadGlyph(10, ft.no_scale_no_hinting);
    try check("'H' advance (font units)", @as(i64, 1022), h.horizontalAdvance());
    // `FT_Get_Advance` takes its unit from the flags: `ftadvanc.h:101-103` says
    // 16.16 only when `load_flags` cause scaling, and `no_scale` does not, so
    // this agrees with the loader's answer above rather than being its 16.16
    // form.
    try check("'H' advance (FT_Get_Advance)", @as(i64, 1022), try face.advance(10, ft.no_scale));
    try check("'H' outline points", @as(u32, 12), h.pointCount());
    try check("'H' outline contours", @as(u32, 1), h.contourCount());

    const box = h.controlBox();
    std.debug.print("  'H' control box             {d} {d} {d} {d}\n", .{ box.x_min, box.y_min, box.x_max, box.y_max });
    try check("'H' control box x_min", @as(i64, 78), box.x_min);
    try check("'H' control box y_max", @as(i64, 1760), box.y_max);

    // 26.6 pixels, which is a different unit and is only comparable because the
    // two calls below ask for it explicitly.
    try face.setCharSize(0, 16 * 64);
    const scaled = try face.loadGlyph(10, .{ .no_hinting = true });
    // 26.6 pixels: font_units * ppem * 64 / unitsPerEm =
    // 1022 * 16 * 64 / 2048 = 511.
    try check("'H' advance at 16pt (26.6)", @as(i64, 511), scaled.horizontalAdvance());

    const rendered = try face.loadGlyph(10, .{ .no_hinting = true, .render = true });
    const bitmap = rendered.bitmap();
    try check("'H' bitmap rendered", @as(bool, true), bitmap.isRendered());
    std.debug.print("  'H' bitmap                  {d}x{d}, {d} grey levels\n", .{ bitmap.width(), bitmap.rows(), bitmap.numGrays() });
    if (!bitmap.isRendered()) return error.RenderCheckFailed;

    var inked: usize = 0;
    for (bitmap.pixels()) |value| {
        if (value != 0) inked += 1;
    }
    try check("'H' inked pixels > 0", @as(bool, true), inked > 0);

    // The two error paths, because an example that cannot fail is not evidence
    // that anything works.
    //
    // A zero pixel size is *not* one of them in FreeType 2.14.3: `FT_Set_Pixel_
    // Sizes` substitutes the non-zero argument and clamps `(0, 0)` to 1x1, so
    // the call succeeds. Printing the resulting ppem is what shows the
    // substitution actually happened rather than the call being skipped.
    try face.setPixelSizes(0, 0);
    {
        const size = face.handle().size orelse return error.MetricsCheckFailed;
        const rec: *ft.c.FT_SizeRec = @ptrCast(size);
        std.debug.print("  zero pixel size becomes      {d}x{d} ppem\n", .{
            rec.metrics.x_ppem, rec.metrics.y_ppem });
        if (rec.metrics.x_ppem != 1 or rec.metrics.y_ppem != 1) {
            return error.MetricsCheckFailed;
        }
    }
    // `openFace` is a `Lib` method, not a `Face` one: the library is what holds
    // the `FT_Stream` a face reads from.
    // The success payload is a `Face` this probe has no use for; `_` is
    // explicit about dropping it rather than leaving it to `catch`'s type.
    _ = lib.openFace("/nonexistent-freetype-fixture/no-such.ttf", 0) catch |err| {
        std.debug.print("  missing font                 {s}\n", .{@errorName(err)});
        if (err != error.CannotOpenResource) return error.EnvironmentCheckFailed;
    };

    face.deinit();
    lib.deinit();
    std.debug.print("\nevery answer matched the value this example states\n", .{});
}