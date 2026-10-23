# Zig facade API

```zig
const ft = @import("freetype");
```

The facade exposes translated declarations through `ft.c` and typed wrappers for library, face and glyph operations.

## Runtime loader

| Declaration | Contract |
|---|---|
| `runtime_loaded` | `true` when this build uses the generated runtime dispatch. |
| `LoadSource` | Explicit provider path or loader-searched basename/SONAME. |
| `LoadError` | Errors returned by `load`. |
| `load(source) LoadError!void` | Runtime builds resolve every `FT_*` entry point. Call before `Lib.init`; linked builds panic if called. |
| `loadedSource() ?LoadSource` | Published provider, or `null` for linked builds and before a successful load. |

Runtime loading has no default provider or fallback. A provider must report the FreeType version used by this build's headers.

## Library and face lifetime

| Type | API | Ownership |
|---|---|---|
| `Lib` | `init() Error!Lib`, `deinit()`, `isOpen()`, `handle()`, `version()` | Owns one `FT_Library`; deinitialize every `Face` first. `handle()` panics after close. |
| `Lib` | `openFace(path: [*:0]const u8, index: c_long) Error!Face` | Opens a NUL-terminated path; the caller owns the face. |
| `Lib` | `openMemoryFace(bytes: []const u8, index: c_long) Error!Face`; `openMemoryFaceFirst(bytes)` | Bytes must remain alive and unchanged until the returned face is deinitialized. Oversized buffers return `InvalidArgument`. |
| `Face` | `deinit()`, `isOpen()`, `handle()` | Owns one `FT_Face`, borrows its `Lib`; deinitialize it before the library. `handle()` panics after close. |
| `Face` | `glyphCount()`, `faceCount()`, `unitsPerEm()`, `familyName()`, `styleName()`, `glyphIndex(codepoint)` | Names borrow face-owned storage and may be `null`; glyph index 0 is `.notdef` or no mapping. |

`version` is the header version. `Lib.version()` queries the loaded library.

## Loading and rendering

| `Face` method | Result |
|---|---|
| `setPixelSizes(width, height) Error!void` | Sets pixel dimensions; zero dimensions are substituted and clamped to at least one. |
| `setCharSize(width, height) Error!void` | Sets 26.6 point sizes at 72 dpi. |
| `loadGlyph(index, flags) Error!Glyph`; `loadChar(codepoint, flags) Error!Glyph` | Loads a glyph with `Flags`; the returned `Glyph` views the face's slot and changes on the next load. |
| `renderLoaded(mode) Error!void` | Renders the current glyph using `RenderMode`. |
| `advance(index, flags) Error!i64` | Returns font units with `no_scale`, otherwise 16.16 advance units. |
| `glyphName(index, buffer) Error![]const u8` | Writes into caller-owned, nonempty storage and returns the bytes before NUL. |

`Glyph` reads the borrowed slot: `index()`, `horizontalAdvance()`, `linearHorizontalAdvance()`, `width()`, `height()`, `controlBox()`, `exactBox() Error!BBox`, `pointCount()`, `contourCount()` and `bitmap()`. The slot and bitmap data are overwritten by the next glyph load.

`BBox` contains `x_min`, `y_min`, `x_max` and `y_max`; its units follow the load flags. `Bitmap` provides `width()`, `rows()`, `numGrays()`, `pixels()` and `isRendered()`. Its pixel slice borrows FreeType-owned memory.

## Flags, units and render modes

`Flags` is a `packed struct(u32)` with all fields defaulting to `false`; `toInt()` returns the C `FT_Int32` mask. Set supported fields by name: `no_scale`, `no_hinting`, `render`, `no_bitmap`, `vertical`, `force_autohint`, `no_recurse`, `ignore_transform`, `monochrome`, `linear_design` and `no_autohint`. Reserved fields preserve upstream bit positions. `linear`, `no_subpixel`, `no_autosubpixel` and `default_` occupy unused bits, not upstream flags.

`no_scale` and `no_scale_no_hinting` are presets. `Glyph` metrics use font units under `no_scale` and 26.6 pixels otherwise; `linearHorizontalAdvance()` is a font-unit design metric when `linear_design` is set.

`RenderMode` is FreeType's translated `FT_Render_Mode` enum. Constants: `render_normal`, `render_light`, `render_mono`, `render_lcd`, `render_lcd_v` and `render_sdf`.

## Errors

Fallible wrappers return `ft.Error`: `CannotOpenResource`, `UnknownFileFormat`, `InvalidFileSize`, `InvalidArgument`, `InvalidPixelSize`, `InvalidGlyphIndex`, `InvalidOutline`, `UnimplementedFeature`, `OutOfMemory` or `UnexpectedError`. Unmapped FreeType codes become `UnexpectedError`; use `ft.c` for the raw `FT_Error` value.
