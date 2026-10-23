# FreeType fork notes

## Source deviations

The imported FreeType tree is unmodified; the fork adds these sources:

- `zig/translate.h`: translates the core, outline, bounding-box and advance headers used by the facade.
- `zig/root.zig`: adds typed Zig wrappers for library, face and glyph operations, plus FreeType error mapping.
- `runtime/generate.zig`: generates target-specific dispatch from `translate-c` output instead of copying C signatures by hand.
- `runtime/graph.zig`: wires the generated dispatch and synchronization without linking the C archive in runtime mode.
- `runtime/loader.zig`: adds explicit, process-wide dynamic loading with no provider fallback or unload.
- `runtime/library.zig`: binds FreeType's dispatch and checks the provider version against the headers.
- `runtime/sync.h`: declares namespaced loader synchronization functions.
- `runtime/sync.c`: implements synchronization with pthreads, Windows primitives, or single-thread WASI/Emscripten stubs.
- `tests.zig`: adds regression tests for the Zig facade.
- `smoke.zig`: adds a linked or runtime-loaded smoke program.
- `consumer/`: exercises `dep.module("freetype")` from a standalone package with `.path = ".."`.
- `tests/fixtures/HarfBust.ttf` and `.gz`: add HarfBuzz's Latin test font for package tests.

## Build graph deviations

- `build.zig` replaces upstream build systems and compiles 40 C translation units: two base units, 20 registered module units, 16 base extensions, one target-specific `ftsystem.c`, and `ftdebug.c`.
- The shipped `ftmodule.h` selects modules; `src/cache/` is not registered and is not compiled.
- The target selects Unix mmap, Windows file-mapping, or stdio `ftsystem.c`; optional zlib, HarfBuzz, Brotli, PNG, bzip2 and subpixel rendering remain disabled.
- The build runs no configure step and generates no headers; it writes a relocatable `freetype2.pc` using `${pcfiledir}`.
- Runtime mode routes `FT_*` calls through an explicit provider; `-Dsystem=true` selects an installed library, while linkage can be static or dynamic.
- Dynamic ELF builds export `FT_*` through a version script; Mach-O and COFF use no version script.
- ELF SONAME is `libfreetype.so.6`; Zig names the versioned file `libfreetype.so.6.26.20`, while upstream libtool names it `libfreetype.so.6.20.6`.
- The consumer step launches Zig 0.17 with `--build-file`, forwards `ZIG_GLOBAL_CACHE_DIR` and `ZIG_LIB_DIR`, and uses a separate local cache.
- Cross-target consumer steps build and install without running; native consumer steps run the program.

## Platform boundaries

- `wasm32-wasi` cannot compile FreeType with Zig 0.16.0's wasi-libc: `ftstdlib.h` includes `setjmp.h`, which requires WebAssembly exception handling.
- Zig 0.16.0 `translate-c` fails on NetBSD headers that expand `_Pragma`, 32-bit OpenBSD's `size_t` typedef, MIPS BSD endianness macros, and 32-bit Windows' missing `_ALLOCA_S_MARKER_SIZE`; these failures reproduce without FreeType source.
- Runtime loading requires a platform dynamic loader and a provider that reports FreeType 2.14.3, matching the package headers.
