# FreeType 2.14.3

FreeType 2.14.3 is a C font engine for TrueType and OpenType. This package builds its unchanged upstream source with Zig 0.17.0.
It exposes one typed Zig module and supports linked or runtime-loaded use.

## Source deviations from upstream

The imported FreeType files under `include/`, `src/`, `builds/`, `docs/`, `tests/`, `devel/`, `subprojects/` and the upstream release files are unmodified.

This fork adds the Zig facade and translation header in `zig/`, the runtime loader in `runtime/`, its build graph, tests, smoke program, consumer example, provenance tool and package documentation.

`tests/fixtures/HarfBust.ttf` is HarfBuzz 14.5.1's Latin test font, distributed with its gzip copy and SIL Open Font License 1.1 text in `tests/fixtures/COPYING`. It is test data, not FreeType source.

## Build deviations

`build.zig` replaces upstream's build systems. It compiles forty translation units: two base units, twenty registered module unity units, sixteen base extensions, one target-specific `ftsystem.c`, and `src/base/ftdebug.c`. The shipped `include/freetype/config/ftmodule.h` controls registrations; `src/cache/` is not registered and is not compiled.

The target selects `ftsystem.c`: `builds/unix/ftsystem.c` where the required Unix headers exist, `builds/windows/ftsystem.c` on Windows, and upstream's stdio-only `src/base/ftsystem.c` elsewhere.

The optional zlib, HarfBuzz, Brotli, PNG, bzip2 and subpixel-rendering options remain undefined. FreeType uses its bundled inflate implementation and links none of those optional libraries.

No configure step runs and no header is generated. The build writes a relocatable `freetype2.pc` using `${pcfiledir}`. On RISC-V, the build passes `translate-c` the float-ABI macro derived from the target's F and D features. Dynamic ELF builds use a version script that exports `FT_*`; Mach-O and COFF builds do not use a version script.

## Support matrix

| Mode or target | Build behavior and boundary |
|---|---|
| Static, default | Builds the `freetype` artifact as `libfreetype.a`. |
| Dynamic | Builds a shared artifact; ELF uses SONAME `libfreetype.so.6` and file name `libfreetype.so.6.26.20`. The target must have a dynamic linker. |
| Runtime loading | `-Druntime=true` resolves `FT_*` through the platform loader. It is independent of linkage and requires an explicit provider. |
| System library | `-Dsystem=true` or `-fsys=freetype` uses an installed `libfreetype` instead of compiling `src/`. |
| Target platform | Unix-like targets with the required headers use mmap; Windows uses its file-mapping implementation; other targets use the stdio implementation. |
| Cross-target graph | `x86_64-linux-gnu`, `aarch64-linux-gnu`, `aarch64-macos-none`, `x86_64-windows-gnu`, `riscv64-linux-gnu`, `wasm32-wasi`. |
| `wasm32-wasi` | Selects stdio `ftsystem.c`, but `ftstdlib.h` includes `<setjmp.h>` and the pinned wasi-libc requires WebAssembly exception handling for setjmp. |

## Consumption

For a local checkout, add this dependency to `build.zig.zon`:

```zig
.dependencies = .{
    .freetype = .{ .path = "../freetype" },
},
```

The dependency and its C artifact are named `freetype`. Import the typed module with `dep.module("freetype")`; `dep.artifact("freetype")` names the library artifact.

```zig
const dep = b.dependency("freetype", .{
    .target = target,
    .optimize = optimize,
    .linkage = .static, // or .dynamic
    .runtime = false, // or true
});
exe_mod.addImport("freetype", dep.module("freetype"));
```

`linkage` defaults to `.static`; `runtime` defaults to `false`. Use `-Dsystem=true` or `-fsys=freetype` to select an installed library. Standard `target` and `optimize` options also apply.

For C consumers, use `pkg-config --cflags --libs freetype2` from the installed tree. Its include root is `freetype2`.
