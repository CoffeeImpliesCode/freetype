# README.zig.md — the typed surface

What `dep.module("freetype")` hands a dependent: the shapes, the units, the
ownership rules, the errors, and the two routes the library can be reached
through. The native-source and build story is in [`README.md`](README.md); the
licence story is in [`NOTICE.md`](NOTICE.md). The native source ships under the
FreeType License, `docs/FTL.TXT`; the alternative arm upstream offers,
`docs/GPLv2.TXT`, travels beside it and is not taken.

## Import routes

One published route, `dep.module("freetype")`, whose root is `zig/root.zig`. The
translated headers are available on it as `c`, and are never a module of their
own: a consumer that wants `c.FT_Face` directly has it, and a consumer that
wants `Lib` and `Face` has those. Both reach the same translation, so there is
exactly one `FT_Face` type per build whichever route is taken.

`zig/translate.h` is what gets translated, and it is upstream's own recipe —
`<ft2build.h>`, `<freetype/freetype.h>`, `<freetype/ftoutln.h>` and
`<freetype/ftadvanc.h>` — with no declaration copied out of a header and no
macro of its own. `ftoutln.h` is in there because `freetype.h` does not include
it, and this surface uses `FT_Outline_Get_CBox`, `FT_Outline_Get_BBox` and
`FT_Outline_Decompose`; `ftadvanc.h` is there for `FT_Get_Advance`. A consumer
who wants the whole installed header set writes its own aggregate and points the
translation at it: nothing here depends on `zig/translate.h` being the only one.

Two macros cannot be lowered and are absent from the translation rather than
mistranslated: `FT_HAS_HORIZONTAL`, which expands to `!!`, and `FT_ENCODING_*`,
whose enum values are built by the `FT_ENC_TAG` macro rather than written out.
Neither is used here, and `Face.selectCharmap` is deliberately absent for the
same reason: wrapping an argument whose translated type is uncertain would be a
guess.

## The shapes

| Type | What it owns | What it borrows |
|---|---|---|
| `Lib` | one `FT_Library` handle | — |
| `Face` | one `FT_Face` handle | its `Lib`, which must outlive it |
| `Glyph` | nothing | the face's glyph slot, which the next load overwrites |
| `Bitmap` | nothing | the slot's `FT_Bitmap` |
| `BBox`, `Flags`, `RenderMode` | nothing | plain data |

`Lib.init` / `Lib.deinit` are `FT_Init_FreeType` / `FT_Done_FreeType`.
`Lib.openFace` and `Lib.openMemoryFace` are `FT_New_Face` and
`FT_New_Memory_Face`. `Face.loadGlyph` / `Face.loadChar` are `FT_Load_Glyph` /
`FT_Load_Char`, `Face.setPixelSizes` / `Face.setCharSize` are `FT_Set_Pixel_Sizes`
/ `FT_Set_Char_Size`, `Face.renderLoaded` is `FT_Render_Glyph`, `Face.advance` is
`FT_Get_Advance`, and `Face.glyphName` is `FT_Get_Glyph_Name`.

Three wrappers keep a shape the C API already has, because changing the shape
would allocate behind the caller's back:

* `Flags` is a `packed struct(u32)` with named, defaulted boolean fields, so a
  caller writes `.no_hinting = true` and cannot pass a flag this build does not
  implement. `zig translate-c` turns each `FT_LOAD_*` macro into an `inline fn`,
  which is a *function*, not a value — spelling a flag that way would compile and
  mean nothing. `Flags.toInt` is a `@bitCast`, not a hand-written shift.
* `RenderMode` is the translated `FT_Render_Mode` enum itself, and
  `render_normal` … `render_sdf` are the upstream constants. `FT_RENDER_MODE_LCD_V`
  is 4 and `FT_RENDER_MODE_SDF` is 5, which is not the order a reader would
  guess; renumbering them would be a second source of truth about upstream's
  enum.
* `Face.glyphName` keeps upstream's caller-owned buffer and length rather than
  allocating, because that buffer is what decides whether a long name is
  truncated. A zero-length buffer is `InvalidArgument` here instead of a
  guaranteed `InvalidArgument` from C.

`Face.openMemoryFace`'s bytes may go out of scope as soon as the call returns —
that is the C API's documented behaviour, and it is stated in the doc comment
because a buffer that goes out of scope *before* the call is a use-after-free
inside FreeType, not something this module can see. A length longer than
`maxInt(c_long)` is `InvalidArgument` rather than a truncation, because
truncating would hand FreeType a different font than the caller passed.

## Units: the one thing that silently breaks a measurement

An `FT_Pos` means **font units** under `Flags.no_scale` and **26.6 pixels**
otherwise. Nothing in the C API records which a given value is, and on a typical
font the two differ by a factor of 64.

`Face.unitsPerEm` is the conversion. Every measurement helper in this surface
takes or names the flags that produced it, and its doc comment says which unit
the answer is in:

| Call | Unit |
|---|---|
| `loadGlyph(gid, ft.no_scale_no_hinting)` → `Glyph.horizontalAdvance` | font units |
| `loadGlyph(gid, .{ .no_scale = true, .no_hinting = true, .linear_design = true })` → `Glyph.linearHorizontalAdvance` | font units |
| `Face.advance(gid, ft.no_scale)` | font units |
| `loadGlyph(gid, .{ .no_hinting = true })` after `setCharSize` | 26.6 pixels |
| `Glyph.controlBox`, `Glyph.exactBox`, `pointCount` | whatever the load used |

`ft.no_scale` and `ft.no_scale_no_hinting` are the two presets a caller reaches
for most: `no_scale` for metric comparisons against a font's own tables, and
`no_scale_no_hinting` for the same with the hinter out of the way. The second is
also the flag set HarfBuzz uses (`src/hb-ft.cc:119` in the sibling package sets
`FT_LOAD_DEFAULT | FT_LOAD_NO_HINTING`), which is why it is a named constant
here rather than two literals typed at each call site.

## Ownership and lifetime

Three rules, all of them consequences of what FreeType's own records are:

* A `Face` must be `deinit`ed before its `Lib`. FreeType does not check that
  order for the caller, and closing a library with faces still open leaves their
  `FT_Stream` pointing at freed memory.
* `deinit` clears the handle, so a second call is a no-op rather than a double
  free, and `isOpen`/`handle` report the state. `handle()` on a closed value
  panics naming the mistake, because there is no record left to call.
* A `Glyph` is a **view**. `FT_Load_Glyph` overwrites `face->glyph`, so a `Glyph`
  that outlives its next load observes the new glyph. That is the C API's rule;
  the wrapper states it rather than copying, because a copy of an `FT_Outline`
  would have to copy the point array too, and that array belongs to FreeType's
  allocator.

## Memory, and the leak oracle this package does not have

This module allocates nothing and frees nothing on its own. FreeType's allocator
is the C library's: `include/freetype/config/ftstdlib.h:142-145` maps
`ft_scalloc` / `ft_srealloc` / `ft_sfree` onto `calloc` / `realloc` / `free`, and
every `FT_Face`, `FT_Bitmap` buffer and outline point array it hands out came
from there.

No Zig allocator can bound or intercept those bytes, so `std.testing`'s leak
checking has no oracle for this package and this package does not claim one.
That is a stated limit, not a silent one: `tests.zig` says so in its own header
comment. What the tests do instead is make every ownership transition explicit
and test it — a `Face` must be `deinit`ed, and every `Face` must be destroyed
before its `Lib`.

Note also that FreeType 2.14.3's public API has no allocator hook: there is no
`FT_Set_Memory_Alloc` in `include/freetype/` in this release, so a caller cannot
intercept those allocations even in principle, and the module does not pretend
otherwise.

## Errors

FreeType answers an `FT_Error`, a signed `int`, and this surface maps only the
values its own code checked:

| Tag | `FT_Err_*` | What left it in that state |
|---|---|---|
| `CannotOpenResource` | `Cannot_Open_Resource` | the path does not exist or cannot be read; no face exists |
| `UnknownFileFormat` | `Unknown_File_Format` | the stream opened, and none of this build's ten drivers recognised it; no face exists |
| `InvalidFileSize` | `Invalid_File_Size` | the stream is shorter than the tables its directory claims |
| `InvalidArgument` | `Invalid_Argument` | a null handle, an out-of-range argument, or a buffer too small |
| `InvalidPixelSize` | `Invalid_Pixel_Size` | `setPixelSizes` was given a zero; the previous size is unchanged |
| `InvalidGlyphIndex` | `Invalid_Glyph_Index` | the index is past `num_glyphs`; the previous glyph is unchanged |
| `InvalidOutline` | `Invalid_Outline` | the outline could not be decomposed |
| `UnimplementedFeature` | `Unimplemented_Feature` | the module behind an operation is not in this build |
| `OutOfMemory` | `Out_Of_Memory` | FreeType's own allocator failed |
| `UnexpectedError` | everything else | one honest bucket rather than a taxonomy of tags nothing checks |

Every mapping is a comparison against the constant in
`include/freetype/fterrdef.h`, never a `std.debug.assert`: a public contract is
guarded by an ordinary comparison, because an assertion is compiled out of a
release build and then guards nothing. `Lib.init` and the two face-opening calls
additionally check for a null handle after a success, for the same reason.

Two results that are **not** errors, because they are real answers:

* `Face.glyphIndex` returns 0 for a codepoint the font does not map. `.notdef` is
  glyph slot 0, and a font that maps nothing answers 0 rather than failing.
* An empty outline answers all zero from `Glyph.controlBox`, which is what
  `src/base/ftoutln.c` computes for an outline with no points.

A caller that needs the exact code reads it on the raw route: `c` is public for
that reason, and `c.FT_Err_*` is the same set of constants the wrapper compares
against.

## Two routes: linked and runtime-loaded

`ft.runtime_loaded` is `true` exactly when `c` is the generated dispatch rather
than the translation, so a caller can branch on it without knowing how the
package was built.

| | linked | `-Druntime=true` |
|---|---|---|
| `c` | the translation | the generated dispatch, which re-exports the translated namespace |
| how an entry point is reached | the linker | `dlopen`/`dlsym`, or `LoadLibraryExW`/`GetProcAddress` |
| `load(…)` | panics, naming the mistake | resolves every `FT_*` from the provider it is given |
| `loadedSource()` | always `null` | the provider this process published |

A runtime-loaded build has **no default provider and no fallback**. One is named
explicitly, as an absolute path or as a name for the platform loader:

```zig
if (comptime ft.runtime_loaded) {
    ft.load(.{ .path = "/usr/lib/libfreetype.so.6" }) catch |err| …;
}
```

There is no path-to-system fallback in either direction, no search path of our
own, and no retry nobody asked for. The table is published with a single release
store only after every required symbol has resolved and the provider has passed
its own validation, so a partial table is never reachable; a candidate that
fails at any step is closed and leaves nothing behind. A call through the table
before that is an ordinary panic in **every** optimization mode, because a call
into an uninitialized table is not something to discover later.

A provider is accepted only when `FT_Library_Version` answers the
`FREETYPE_MAJOR` / `FREETYPE_MINOR` / `FREETYPE_PATCH` that this build's headers
declare. That is the whole of the external ABI check, and `runtime/library.zig`
says so in full: every member of `FT_LibraryRec` and `FT_FaceRec` is public, so
a consumer that reads `face->glyph` directly depends on the record layout and
not only on the accessors; memory crosses into FreeType's own allocator and back
out of it; `FT_Pos` means different things under different load flags; and an
`FT_Error` is neither a POSIX errno nor an `FT_Error_Code`. A different FreeType
that passes the version check — one built with a replaced bytecode interpreter,
say — still passes, and that is deliberate: the version is the only thing a
loader can verify without reimplementing the library.

The loader's own state is process-global and has no unload and no reset. Under
this SDK it is built from `runtime/loader.zig` (the reusable state machine and
platform layer), `runtime/library.zig` (this SDK's descriptor, its namespaced
synchronization binding and its one load-time check), `runtime/graph.zig` (the
build half) and `runtime/generate.zig` (the build-time generator, which writes
the dispatch into the build cache from the real translation output for the target
being built — so no generated source is checked in).

## The raw route

`c` is the translation itself, or the dispatch over it, and every declaration in
`zig/translate.h` is reachable through it. That is not an escape hatch to be
avoided: it is how a caller gets `FT_Get_Advances`, `FT_Set_Transform`,
`FT_Outline_Decompose`, `FT_Get_Glyph_Name` and the rest of the 46-header
surface that the typed API deliberately does not wrap. What this module does
*not* do is wrap an argument whose translated type it has not verified.

## The tests, and what they check against

`tests.zig` and the consumer's `src/main.zig` both answer against something
outside FreeType, in two different ways, and neither of them is a round trip
through the same code.

**`tests.zig` decodes the fixture font itself.** It contains its own TrueType
table reader — `head`, `maxp`, `hhea`, `hmtx`, a format 4 `cmap`, `loca`, `glyf`
— written from the OpenType specification and reading the same bytes FreeType
reads. Every number it asserts against FreeType is therefore checked twice, by
two independent implementations over one binary: the design grid, the glyph
count, four character-to-slot mappings, the advances of four glyphs in two
forms, and the bounding box of six glyphs. A wrapper bug that changed an answer
would have to be a bug in *both*. The fixture is
`tests/fixtures/HarfBust.ttf`, HarfBuzz's own Latin test font, embedded with
`@embedFile` so that a cross-target `build_only` cell is a statement about the
library rather than about a missing file.

**The consumer writes its own font.** `consumer/src/main.zig` builds a seven
table TrueType file into a buffer — 1024 units per em, two glyph slots, an
advance of 512, a rectangular outline, `'A'` mapped to slot 1 — and checks
FreeType's answers against the fields it wrote. A dependent brings its own font,
so the library's fixture is not part of the contract being demonstrated, and the
answers do not depend on anything this SDK ships.

What neither of them checks: leaks, because the allocator is the C library's (see
above); and behaviour of a font format other than TrueType, because the fixture
and the synthetic font are both TrueType. Both are boundaries, and both are
named in the files themselves.

The `lib.version()` / `ft.version` comparison in the consumer is not a version
pin: the two answers come from different places on purpose — one from this
build's translation of the header, one from the compiled library's own
`FT_Library_Version` — so the check is a statement about the two agreeing.
`build.zig` refuses to configure at all when `build.zig.zon`'s `.version`
disagrees with the three macros in `include/freetype/freetype.h`, so the
manifest, that header and the vendored source cannot describe three releases.

## Boundaries, stated

* `src/cache/` is not compiled, so `FT_Cache` is declared and not backed. The
  header is installed; the sub-system is not there.
* The optional format support is off: no PNG embedded bitmaps, no WOFF2, no
  bzip2-compressed streams, no HarfBuzz-assisted auto-hinting. The public
  headers for all of them are still installed.
* `wasm32-wasi` does not compile, and this package cannot make it. The
  expectation recorded here before 2026-10-05 — that the row would compile
  because `Platform.forTarget` picks the stdio-only `ftsystem.c` — was wrong:
  the platform unit was never the problem. Both halves of the row fail inside
  the pinned toolchain's wasi-libc, whose `libc/include/wasm-wasi-musl/setjmp.h:13`
  raises `#error` unless `__wasm_exception_handling__` is defined, and
  `include/freetype/config/ftstdlib.h:166` includes `<setjmp.h>` with no guard
  and no upstream switch behind it. `zig build check` therefore exits 1, and the
  row is neither passed nor refused. See [`FORK-NOTES.md`](FORK-NOTES.md) for the
  full diagnosis, the exact message and what would have to change.
* `riscv64-linux-gnu` compiles. It needed one `-D` on the translation to match
  what the C compiler already predefines, and `build.zig` now derives it per
  target rather than assuming it.
* No upstream conformance suite runs here, because the release ships one
  regression program whose fonts are not in the tree. See
  [`UPSTREAM.md`](UPSTREAM.md).
