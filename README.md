# FreeType 2.14.3 for Zig 0.16

FreeType 2.14.3 — the TrueType and OpenType font engine — built from its own
vendored C, with a typed Zig surface over the face, glyph and load API, one
runtime-loading route, and no autotools, CMake, meson or GNU make anywhere in the
build.

```zig
const ft = @import("freetype");

var library = try ft.Lib.init();
defer library.deinit();

var face = try library.openFace("/usr/share/fonts/…/DejaVuSans.ttf", 0);
defer face.deinit();

const glyph = try face.loadChar('H', ft.no_scale_no_hinting);
// `no_scale` means font units; without it the same field is 26.6 pixels.
const advance = glyph.horizontalAdvance();
```

Upstream's own README is preserved unaltered as [`README`](README), and its
installation and licence notes are in `docs/INSTALL*`. This file is the fork's
document.

## Status

| | |
|---|---|
| Native source | `SOURCE-CONFIRMED`: 854 upstream files, every digest in [`UPSTREAM.sha256`](UPSTREAM.sha256), recomputed and matched on 2026-10-05 |
| Build, tests, smoke, consumer, cross-target compile | **`PENDING-VERIFICATION`**: no compiler has been run against this tree by a worker, and this document records no gate result |
| Licence | **FreeType License** (`docs/FTL.TXT`); see [`NOTICE.md`](NOTICE.md) |

Every gate this SDK has is the driver's to run. Nothing below is a result; the
commands are in "What to run" and the claims they would settle are named beside
each one.

## Current native-source deviations

**There are none.** No file under `include/`, `src/`, `builds/`, `docs/`,
`tests/`, `devel/` or `subprojects/`, and none of the fifteen top-level files,
has been edited. Two statements about the tree are worth reading before anything
else:

* **One directory was added, and it is not upstream's.**
  `tests/fixtures/` holds HarfBuzz's own Latin in-house test font under the SIL
  Open Font License 1.1, its gzip copy, and the licence text. It is this fork's
  addition, its digests are recorded as fork material rather than as upstream
  digests, and `tools/check-provenance.sh` checks both facts.
* **The release tarball's own sha256 is not recorded.** The canonical download
  index publishes detached GPG signatures and no checksum for either archive,
  and nothing in this workspace records which archive this tree came from. The
  gap is named rather than filled; [`UPSTREAM.md`](UPSTREAM.md) says what the
  driver has to do to close it, and the 854 per-file digests pin the tree this
  SDK actually builds in the meantime.

Three statements in the build graph are contradicted by the files they cite, and
they are listed rather than fixed here, because `build.zig`,
`zig/translate.h` and `zig/root.zig` belong to the build and API roles:

1. `build.zig:120-124` says `tests/meson.build` declares no `test()` target. It
   declares one, at `tests/meson.build:9-12` — a regression program for one issue
   whose fonts this tree does not carry.
2. `build.zig:246-247` and `zig/translate.h:35` say the installed header set is
   42 headers. `meson.build:139-184` lists 46, and `build.zig` installs those 46
   plus `ft2build.h`. The lists are right; the two comments' numbers are wrong.
3. `zig/root.zig:204` and `zig/root.zig:487-489` cite two line numbers in the
   sibling `harfbuzz` package's `src/hb-ft.cc`; the statements are at 119 and
   177-180 there.

None of the three changes what this SDK builds. `tools/check-provenance.sh`
re-derives the header-list claim (5a) and would fail if the graph and upstream's
own list ever really diverged.

## Native-build deviations

`build.zig` is the whole build. What it does differently from every upstream
build system is listed here rather than buried in the graph.

* **The unit list is upstream's own.** Two base units, one unity unit per
  registered module (twenty), the sixteen base extensions `modules.cfg` lists,
  one platform `ftsystem.c` and `src/base/ftdebug.c`: forty translation units.
  FreeType's drivers are *unity* units — `src/truetype/truetype.c` is nineteen
  `#include`s and nothing else — so compiling their files separately would be a
  different build of the same code rather than this one.
* **The module list follows the shipped header, not the makefile.**
  `include/freetype/config/ftmodule.h:13-31` holds nineteen registrations — nine
  drivers, five modules, five renderers — and that is the list a live
  `FT_Library` gets. `modules.cfg:116` also lists the cache sub-system, which
  the shipped list does not register; `src/cache/` therefore travels and is not
  compiled.
* **The platform unit is chosen from the target being built**, in
  `Platform.forTarget`: `builds/unix/ftsystem.c` where the libc has `unistd.h`,
  `fcntl.h` and `sys/mman.h`; `builds/windows/ftsystem.c` for `windows`;
  upstream's stdio-only `src/base/ftsystem.c` for everything else, which is where
  `wasm32-wasi` lands. No host fact reaches a cross target.
* **Nothing optional is enabled.** `FT_CONFIG_OPTION_SYSTEM_ZLIB`,
  `USE_HARFBUZZ`, `USE_BROTLI`, `USE_PNG`, `USE_BZIP2` and
  `SUBPIXEL_RENDERING` are left exactly as `include/freetype/config/ftoption.h`
  ships them, undefined. The library therefore carries its own modified inflate,
  links no system zlib, and exports nothing from zlib, libpng, bzip2, brotli or
  HarfBuzz.
* **No generated inputs.** No configure step runs and no header is written. The
  one file upstream's install generates and the release does not ship,
  `freetype2.pc`, is written by `build.zig` with `${pcfiledir}`-relative paths,
  so the installed tree is correct wherever `--prefix` put it.
* **The SONAME is upstream's; the versioned file name is not.**
  `builds/unix/configure.raw:20` gives `version_info='26:6:20'`, so upstream's
  object is `libfreetype.so.6` and libtool would name it
  `libfreetype.so.6.20.6`. Zig's own version fields produce the same SONAME and
  the file name `libfreetype.so.6.26.20`. Linking `-lfreetype` or opening
  `libfreetype.so.6` gets this build either way; a consumer that hard-codes
  `libfreetype.so.6.20.6` does not.
* **The export surface is enforced only on ELF.** `-Dlinkage=dynamic` on an ELF
  target writes a version script exporting `FT_*` and nothing else, so an
  internal symbol cannot leak. A Mach-O or COFF object gets no version script,
  because its exported set is decided by the linker's default visibility and by
  the object file's own directives, and a transcribed list would be a second
  place to keep in step. On those targets the export surface is upstream's
  headers' surface by construction, not by check.
* **`wasm32-wasi` is a platform boundary, and no target is refused.**
  `refused_check_targets` is empty, so the row stays in `check` and keeps
  failing rather than disappearing from the matrix. It fails in the pinned
  toolchain's own wasi-libc: `libc/include/wasm-wasi-musl/setjmp.h:13` raises
  `#error Setjmp/longjmp support requires Exception handling support` unless
  `__wasm_exception_handling__` is defined, and
  `include/freetype/config/ftstdlib.h:166` includes `<setjmp.h>` with no guard
  and no `FT_CONFIG_OPTION_*` behind it. The diagnosis, the exact message and
  what would have to change are in [`FORK-NOTES.md`](FORK-NOTES.md). The earlier
  expectation that this row would compile was reasoned from
  `Platform.forTarget` picking the stdio `ftsystem.c`, and it was wrong: the
  platform unit was never the problem.
* **`riscv64-linux-gnu` needed one `-D`, and now has it.** The facade's
  `translate-c` step and the C compiler disagreed about
  `__riscv_float_abi_double`, which glibc's RISC-V `bits/setjmp.h` requires
  before it will define a `jmp_buf`. `build.zig` gives the translation the macro
  clang gives the compile, derived from the target's own F and D features. See
  [`FORK-NOTES.md`](FORK-NOTES.md) and `CHANGELOG.md` entry 6.
* **System mode exists but is not the default.** `-Dsystem=true`, or the build
  runner's `-fsys=freetype`, links an installed `libfreetype` instead of
  compiling `src/`. It is never a fallback and never a substitution: the
  configure-time report says so, and no result in this repository is a result
  about an installed library.

## Support matrix

Three rows of this table have been run, on 2026-10-05 with the pinned Zig 0.16.0
at its recorded path, `-j8 --summary all`, default optimize mode. Everything
else is still `PENDING-VERIFICATION`, and nothing below may be read as a gate
result for it.

| Route | What it is | Cell | Observed 2026-10-05 |
|---|---|---|---|
| Linked, static | the default: `libfreetype.a` | `zig build`, `zig build test`, `zig build smoke` | `zig build` **exit 0**; `test` and `smoke` not run |
| Linked, shared | `-Dlinkage=dynamic`, SONAME `libfreetype.so.6` | same steps with `-Dlinkage=dynamic` | not run |
| Runtime-loaded | `-Druntime=true`, every `FT_*` resolved through the platform loader at run time, `FREETYPE_TEST_PROVIDER` naming the provider | same steps with `-Druntime=true` | not run |
| System | `-Dsystem=true` / `-fsys=freetype` | needs an installed libfreetype with its own headers; no claim is made about it here | not run |
| Cross compile-only | `zig build check`, six targets: `x86_64-linux-gnu`, `aarch64-linux-gnu`, `aarch64-macos-none`, `x86_64-windows-gnu`, `riscv64-linux-gnu`, `wasm32-wasi` | compiles the library, the facade, the tests and the example; runs nothing | **exit 1**: five rows compile, `wasm32-wasi` fails inside `libc/include/wasm-wasi-musl/setjmp.h:13`, a recorded platform boundary |
| Cross with a runner | the published 53-platform table, through `cross-test` with this package's `cross-test.profile.sh` | runs where an executor exists, and records `build_only` where one does not — never a pass | **exit 1**, run `20261005-191553-53412-16665`: **20 pass** (`19/19` each, all 20 Linux rows), **17 `build_only`** (compiled, no execution), **16 build_failed**, **0 runtime failures** |

A compiling cell is not a passing test, and a passing test is not a compiling
cell. `wasm32-wasi` is a third thing: a cell that fails, with its cause in
[`FORK-NOTES.md`](FORK-NOTES.md) and no fix available inside this repository.

The 53-platform row adds sixteen build failures that are **not** this
package's: all nine NetBSD cells, five of the nine OpenBSD cells, and
`x86-windows`. Each reproduces with **no FreeType code in the build at all**,
while `zig cc` compiles the same source for the same targets, which places the
cause in the pinned toolchain's own headers and in aro's handling of them. The
five causes, each with the file and line that carries it, are in
[`FORK-NOTES.md`](FORK-NOTES.md). The 17 `build_only` rows are compile results
and no file in this fork counts one as a pass.

A cell that fails is a fact to record and diagnose. It is not a reason to drop
the cell, sample the tests, or remap Debug to an optimized mode.

## Consumption

### As a Zig dependency

One module: `dep.module("freetype")`. It carries the typed facade
(`zig/root.zig`), the translated headers as `c`, and the C artifact behind
both. The options a dependent passes through are the library's own:

```zig
const dep = b.dependency("freetype", .{
    .target = target,
    .optimize = optimize,
    .linkage = .static,   // or .dynamic
    .runtime = false,     // or true
});
exe_mod.addImport("freetype", dep.module("freetype"));
```

`ft.runtime_loaded` is comptime, so a dependent writes one branch and no
duplicated program. In a runtime-loading build there is no default provider and
no fallback: `ft.load(.{ .path = … })` or `ft.load(.{ .system = … })` names one
explicitly, and a call before a successful load panics in every optimization
mode. The external ABI boundary that load checks is stated in
`runtime/library.zig`.

For a C consumer, `pkg-config --cflags --libs freetype2` from the installed
tree is the whole recipe; the include root is `freetype2`, which is where
upstream installs these headers.

### The consumer package

`consumer/` is a separate package with its own manifest that depends on this one
by a relative path. It exists to prove the thing the library's own tests cannot
see: that the module resolves from a package that did not write it. Its
`src/main.zig` writes its own TrueType font into a buffer — seven tables, two
glyph slots, a rectangle outline, `'A'` mapped — and checks FreeType's answers
against the fields it wrote a moment earlier. No font file is involved, so the
answers are independent of anything this SDK ships.

```sh
zig build consumer                          # from the repository root
cd consumer && zig build run                # or from here
cd consumer && zig build run -Druntime=true -- --provider /path/to/libfreetype.so.6
```

### Nix and devenv

`package.nix` is the one source-only derivation, shared by `flake.nix` and
`devenv.nix` so the two entry points cannot describe different packages.
`devenv shell` is the canonical development environment; `.envrc` wires it into
direnv. Lock files belong to the driver and are absent from this tree.

```nix
# a dependent
packages = [ freetype ];
inputs.freetype.url = "github:<owner>/freetype";
```

## What to run

The driver's gates for this package, from `AGENTS.md` §6. Each is listed with
the claim it would settle, and with what the 2026-10-05 run actually observed.
The columns agree: a "not run" row was not run.

| Command | What it settles | Observed 2026-10-05 |
|---|---|---|
| `zig build` | that the forty-unit closure compiles and that the installed layout is complete | **exit 0** |
| `zig build test` (Debug and ReleaseSafe) | the behavioural tests in [`tests.zig`](tests.zig), against the vendored fixture | not run; the matrix ran this suite 20 times on other targets, each `19/19` |
| `zig build smoke` | the deterministic example in [`smoke.zig`](smoke.zig) | not run |
| `zig build consumer` | the dependent package, linked | not run |
| `zig build check` | all six cross targets, compile only | **exit 1**: five rows compile, `wasm32-wasi` does not |
| `zig build test -Druntime=true` with `FREETYPE_TEST_PROVIDER` set | the same behavioural tests through the loader, not through the linker | not run |
| `zig build test -Dlinkage=dynamic` | the same, against a real shared object | not run |
| `tools/check-provenance.sh` | the digests, the file set, the one release, and the licence records — no compiler involved | 854 of 854 digests matched |
| `cross-test` from the package root | the published 53-platform table, with `build_only` recorded where no runner exists | **exit 1**, run `20261005-191553-53412-16665`: 20 pass, 17 `build_only`, 16 build_failed |

The Zon `.fingerprint` fields are deliberately absent from both manifests: Zig
0.16.0 derives them from the package name and prints the value, and that value
belongs to a run rather than to a guess. They are a prerequisite in
[`FORK-NOTES.md`](FORK-NOTES.md).

## Licence and attribution

This SDK ships FreeType under the **FreeType License**, `docs/FTL.TXT`. The
alternative upstream offers, `docs/GPLv2.TXT`, travels with it and is not
taken; the reasoning, and the per-file exceptions this tree carries — zlib's
terms under `src/gzip/`, the Boost Software License under `src/dlg/`, the 'Old
MIT' notices under `src/autofit/`, an X Window System-like grant in the BDF and
PCF drivers, and a public-domain MD5 — are in [`NOTICE.md`](NOTICE.md).

Upstream's own copyright, which the FTL's credit clause obliges a distributor
to acknowledge:

```
Copyright (C) 2006-2026 by
David Turner, Robert Wilhelm, and Werner Lemberg.
```

and the credit text `docs/FTL.TXT:50-56` asks for, with the year filled in for
this release:

```
Portions of this software are copyright © 2026 The FreeType
Project (https://freetype.org).  All rights reserved.
```

The fork's own files — everything in [`NOTICE.md`](NOTICE.md)'s fork-specific
list — are MIT, in [`FORK-LICENSE.md`](FORK-LICENSE.md). The vendored test font
is HarfBuzz's, under the SIL Open Font License 1.1, in
`tests/fixtures/COPYING`.
