# Changelog

Every entry names what changed, why, and what it does *not* claim. Entries 1 to
5 were written by a slice that ran no compiler and are `PENDING-VERIFICATION`
throughout. Entries 6 and 7 record gates that were run on 2026-10-05, and name
the receipt for each. Nothing here is a gate result that was not observed: a row
that says "not run" was not run.

## 1. Land the FreeType 2.14.3 SDK package

The package is FreeType 2.14.3, imported whole from the official release, built
by `build.zig` with no autotools, CMake, meson or GNU make in the build, and
presented to a dependent as one registered module, `dep.module("freetype")`.

* **Native source**: `include/`, `src/`, `builds/`, `docs/`, `tests/`,
  `devel/`, `subprojects/` and the fifteen top-level files, byte for byte as the
  release carries them. 854 files, 19676746 bytes.
* **Build graph**: `build.zig` compiles the forty-unit closure upstream's own
  `modules.cfg` describes — two base units, twenty module unity units, the
  sixteen base extensions, one platform `ftsystem.c` selected from the target
  being built, and `src/base/ftdebug.c` — and installs the library, the 47 public
  headers, a relocatable `freetype2.pc` and the licence and provenance records.
* **Typed facade**: `zig/root.zig` over `FT_Library` / `FT_Face` / glyph
  loading, with `Flags` as a defaulted `packed struct` rather than a macro spelled
  as a call, the upstream `FT_Render_Mode` numbering kept as-is, and an error set
  cut at what this package's own code checked.
* **Runtime route**: `runtime/` gives `-Druntime=true` one process-lifetime table
  per module, an explicit provider with no default and no fallback, atomic
  publication, explicit retry after failure, and a pre-initialization panic in
  every optimization mode.
* **Tests and example**: `tests.zig` decodes the vendored fixture's own tables in
  Zig and compares them against FreeType; `smoke.zig` prints and compares a
  closed set of answers.
* **Consumer**: a separate package that reaches the library through a relative
  path dependency and writes its own TrueType font, so its answers are
  independent of anything this SDK ships.
* **Records**: `UPSTREAM.md`, `UPSTREAM.sha256`, `NOTICE.md`, `FORK-LICENSE.md`,
  `README.md`, `README.zig.md`, this file, `FORK-NOTES.md`.
* **Packaging and CI**: `package.nix`, `flake.nix`, `devenv.nix`, `devenv.yaml`,
  `.envrc`, `.gitignore` and `.github/workflows/verify.yml`.

`SOURCE-CONFIRMED`: all 854 digests in `UPSTREAM.sha256` were recomputed on
2026-10-05 with `sha256sum -c` and matched, and the upstream file set was
compared against the manifest. That is a statement about bytes. **No build, no
test, no smoke run and no cross-target compile has been observed.**

## 2. Name the release tarball's digest as missing, not as unknown

The canonical download index publishes detached GPG signatures for both 2.14.3
archives and no checksum for either, and nothing in this workspace records which
archive this tree was imported from or what either one hashes to.

`UPSTREAM.md` and `UPSTREAM.sha256` therefore carry **no** release digest, and
say so in both files. A digest that was never observed would be a fabricated
identifier in the one field whose purpose is to be unguessable; the alternative
is worse, which is a plausible-looking value nobody read out of anything. The
gap is a named prerequisite in `FORK-NOTES.md`: the driver owns downloads, so
re-fetching the archive and recording its sha256 is its step, in one change with
these two records. `tools/check-provenance.sh` reads whichever state the two
files are in and fails if they disagree about it.

The 854 per-file digests are what pins this tree in the meantime, and the
exact-file-set check covers the one thing a checksum run cannot see.

## 3. Inventory the licences per file rather than under one label

`LICENSE.TXT` offers two mutually exclusive terms and names five per-file
exceptions. This tree carries four more that `LICENSE.TXT` does not mention:
the Boost Software License 1.0 for the `dlg` logger (`src/dlg/dlg.c:1-3`,
`include/dlg/dlg.h:1-3`, `include/dlg/output.h:1-3`), an MIT-style grant in
`src/tools/vms_shorten_symbol.c:2-4`, and public-domain dedications in
`src/tools/apinames.c:15` and `src/tools/chktrcmp.py:6`. Two PCF driver files
have no notice of their own and fall under the FreeType License by the scope
rule at `docs/FTL.TXT:19-22`.

`NOTICE.md` states, per file, which term covers it and where that term is written
down; 49 of the 854 upstream files carry a term of their own and 805 do not.
`tools/check-provenance.sh` checks that each of those notices is still in the
file that carries it, and that the fork's own records name both licence arms.

The shipped choice is the **FreeType License**, `docs/FTL.TXT`, chosen for the
reasons `NOTICE.md` gives and recorded as a choice in `FORK-LICENSE.md`. The
GPLv2 arm travels and is not taken; `LICENSE.TXT:20-26` is upstream's own
statement that the FTL is compatible with GPLv3 and not with GPLv2.

## 4. Record three claims in the build graph that the files they cite contradict

Found while writing the provenance records, and recorded rather than fixed,
because `build.zig`, `zig/translate.h` and `zig/root.zig` belong to the build and
API roles:

1. `build.zig:120-124` says `tests/meson.build` declares no `test()` target; it
   declares one at `tests/meson.build:9-12`. The conclusion — no `upstream-test`
   step, nothing fetched — is unaffected.
2. `build.zig:246-247` and `zig/translate.h:35` call the installed header set 42
   headers. `meson.build:139-184` lists 46, and `build.zig` installs those 46 plus
   `ft2build.h`.
3. `zig/root.zig:204` and `zig/root.zig:487-489` cite two line numbers in the
   sibling `harfbuzz` package's `src/hb-ft.cc`; the statements are at 119 and
   177-180 there.

`tools/check-provenance.sh` re-derives the header-list claim on every run, so
item 2 cannot turn into a real divergence unnoticed.

## 5. Replace the Lua commentary in `cross-test.profile.sh`

The file carried the settings of this SDK's harness profile and the commentary of
a different library: it called itself "the Lua SDK" and described "the 32-unit
closure of `src/Makefile`'s `CORE_O` and `LIB_O`" and Lua's `lparser.c`. The four
settings — `CROSS_BUILD_STEP=test`, `CROSS_BUILD_JOBS=4`,
`CROSS_BUILD_TIMEOUT=3600`, `CROSS_TIMEOUT=1800` — are unchanged and correct for
this package; only the commentary now describes FreeType's own unit list and
`Platform.forTarget`'s three `ftsystem.c` branches. `SPDX-License-Identifier: MIT`
was added at the same time, which the file did not carry.

## 6. One `-D` on the translation, and one platform boundary recorded

`zig build check` walks six targets. On 2026-10-05 two rows were red inside a
`setjmp.h` this package does not own. One was fixable here and is; the other is
not and is now written down where a reader will meet it.

### Fixed — `riscv64-linux-gnu`

The C library compiled for that target and the facade's `translate-c` step did
not, with
`libc/include/riscv-linux-gnu/bits/setjmp.h:35:3: error: unsupported FLEN` on
the way in from `include/freetype/config/ftstdlib.h:166`. glibc lays out a
RISC-V `jmp_buf` only for `__riscv_float_abi_double` and
`__riscv_float_abi_soft`; clang predefines the first for
`riscv64-linux-gnu` and Aro, which runs `translate-c`, predefines none of the
three. `build.zig` now derives the macro clang would use from the target being
built and hands it to `translate.defineCMacro`, so the facade is translated
against the ABI the library was compiled with. It goes on the translation only,
and only on RISC-V. Observed: `zig build check -Dtarget=riscv64-linux-gnu`
went from exit 1 to exit 0, `Build Summary: 6/6 steps succeeded`.

### Recorded — `wasm32-wasi`

Both halves of the row fail with the pinned toolchain's own message,
`libc/include/wasm-wasi-musl/setjmp.h:13: error: Setjmp/longjmp support
requires Exception handling support`, which that header raises unless
`__wasm_exception_handling__` is defined. `include/freetype/config/ftstdlib.h:166`
includes `<setjmp.h>` with no guard, and `include/freetype/config/ftoption.h`
offers no `FT_CONFIG_OPTION_*` that turns it off, so no configuration in this
package reaches it. The row stays in `check_targets`, `refused_check_targets`
stays empty, and `zig build check` exits 1: a failing cell that stays visible,
not a dropped one and not a pass. The full diagnosis, the exact message and the
two things that would have to change — the toolchain's wasi-libc, or a
documented upstream deviation — are in [`FORK-NOTES.md`](FORK-NOTES.md). No
vendored header was edited and no replacement `setjmp.h` was vendored.

## 7. Run the 53-platform matrix, and name the sixteen cells the toolchain owns

`cross-test` ran from the package root on 2026-10-05, run
`20261005-191553-53412-16665`, with this tree's `cross-test.profile.sh` read
and not edited, `--jobs 8 --build-jobs 8`, Zig 0.16.0 at its recorded path.
All 53 cells attempted; **harness exit code 1**. Observed, per cell:

* **20 pass**, every Linux row including the big-endian and 32-bit ones, each
  reporting `19/19 tests passed` and `tests_complete`. `x86_64-linux` ran
  natively; the other nineteen ran under QEMU user mode.
* **17 `build_only`**: all six FreeBSD rows, both macOS rows, both
  MacCatalyst rows, the four 64-bit OpenBSD rows, three Windows rows and
  `aarch64-windows`. Each compiled — `5/6 steps succeeded (1 skipped)` with
  `run test freetype-tests skipped` — and none executed a test, the reason
  being `runtime_unavailable` on this host. Compile results, never passes.
* **16 build_failed**: all nine NetBSD rows, five of the nine OpenBSD rows,
  `wasm32-wasi`, `x86-windows`. **No cell that compiled then failed a test, and
  no cell is partial.**

The sixteen are **not** defects of this package. A four-file probe whose only C
dependency is a `@cImport` of the seven libc headers
`include/freetype/config/ftstdlib.h` pulls, plus `strings.h` which `string.h`
reaches on its own, with no FreeType source anywhere in it,
fails on all sixteen and passes natively; `zig cc -target T -c` on the same
file compiles all sixteen. The cause is therefore the pinned toolchain's own
headers and aro's handling of them, in five shapes: NetBSD's
`sys/cdefs.h:413` `_Pragma` re-lexed as C tokens, OpenBSD's
`strings.h:45-47` guard that aro's own `stddef.h:8` never sets, the four
`__MIPSEL__`/`__MIPSEB__` `#error`s against aro's macro block at
`Compilation.zig:635-642`, the `wasm32-wasi` `setjmp.h` refusal already
recorded in entry 6, and `any-windows-any/malloc.h:183-187` leaving
`_ALLOCA_S_MARKER_SIZE` undefined for 32-bit Windows. Each is written down
with its file and line in [`FORK-NOTES.md`](FORK-NOTES.md).

No file in this tree was changed to make a cell pass, no target was dropped,
no test was sampled, no optimization mode was remapped and no `-D` was added to
mask any of the five. `build.zig`, `zig/`, the vendored sources and
`cross-test.profile.sh` are untouched by this entry; the change is to
`README.md`, `FORK-NOTES.md` and this file, and it records a result rather than
altering a build.
