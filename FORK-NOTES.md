# FORK-NOTES.md

A worker's notes: what was decided, what was observed, what was not, and what
the driver still owes this package. Written by the slice that finished the tree
(template files, provenance, licence records, packaging, CI) on 2026-10-05.

## Status

* **`SOURCE-CONFIRMED`** — the 854 digests in `UPSTREAM.sha256` were recomputed
  with `sha256sum -c UPSTREAM.sha256` on 2026-10-05 and all matched, and the
  upstream file set was compared against the manifest. That is a statement about
  bytes and about what the records say about them.
* **`OBSERVED`** — the 53-platform `cross-test` matrix was run on 2026-10-05,
  run `20261005-191553-53412-16665`, harness exit code **1**: 20 cells pass
  with `19/19` each, 17 are `build_only` with no execution, 16 fail to build
  for a toolchain reason reproduced without any FreeType code. The receipt,
  the per-cell classification and the five causes are in *The 53-platform
  matrix, and the sixteen cells the pinned toolchain cannot compile* below.
* **`OBSERVED`** — `zig build` and `zig build check` were run on 2026-10-05
  with cache `/home/tmp2/gertullj/cache/foundation-libs/wave10-fresh/freetype`.
  `zig build` exited 0, and `zig build check` exited 1 with exactly one failing
  row, `wasm32-wasi`; five of the six rows compile. The failing row is
  diagnosed below and is a platform boundary, not a pass. Receipts:
  `local://freetype-check-six-targets-2026-10-05.log` and
  `local://freetype-check-riscv64-linux-gnu-2026-10-05.log`.
* **`PENDING-VERIFICATION`** — everything else. `zig build test` in Debug and
  ReleaseSafe, `zig build smoke`, `zig build consumer`, the consumer's
  `zig build run`, `-Dlinkage=dynamic`, `-Druntime=true`, and the Nix builds
  and CI have not been observed. Nothing in this repository may be read as a
  gate result for any of them.

## What this slice added

The nineteen files the package was missing: `consumer/build.zig`,
`consumer/build.zig.zon` and `consumer/src/main.zig`; `UPSTREAM.md` and
`UPSTREAM.sha256`; `tools/check-provenance.sh`; `README.md`, `README.zig.md`,
`NOTICE.md`, `CHANGELOG.md`, `FORK-LICENSE.md`; `package.nix`, `flake.nix`,
`devenv.nix`, `devenv.yaml`, `.envrc`, `.gitignore` and
`.github/workflows/verify.yml`.

It also replaced the commentary in `cross-test.profile.sh`, which described a
different library, and left every setting in it unchanged. See CHANGELOG entry 5.

## Open items, for the driver

1. **The release tarball's sha256 is not recorded**, and neither is which of
   `freetype-2.14.3.tar.gz` / `freetype-2.14.3.tar.xz` this tree came from. The
   canonical index publishes `.sig` files and no checksum (read 2026-10-05), so
   there was nothing to copy out. Re-fetch, compute the digest, and add it to
   `UPSTREAM.md`'s table and to `UPSTREAM.sha256`'s header in one change;
   `tools/check-provenance.sh` then takes the other branch and requires the two
   records to name the same digest.
2. **Both `.fingerprint` fields are absent**, in `build.zig.zon` and in
   `consumer/build.zig.zon`. Zig 0.16.0 derives them from the package name and
   prints the suggested value when the field is missing. Filling them in by hand
   would be writing an identifier nobody read out of anything, so the first
   `zig build` prints both and they go in as a mechanical follow-up.
3. **`flake.lock` and `devenv.lock` are absent** and belong to the driver, as
   `flake.nix`, `devenv.nix` and `devenv.yaml` each state. `devenv.yaml` pins its
   own nixpkgs revision, so the devenv route needs no lock file; the flake route
   needs `flake.lock` to resolve its input.
4. **Three claims in files this slice does not own are contradicted by the files
   they cite** — CHANGELOG entry 4. None changes what is built; the header-count
   one is re-derived by `tools/check-provenance.sh` on every run.
5. **The gate matrix has not been run at all.** Per `AGENTS.md` §6: `zig build`,
   `zig build test` in Debug and ReleaseSafe, `zig build smoke`, `zig build
   consumer`, `zig build check`, and the same through `-Dlinkage=dynamic` and
   `-Druntime=true`, plus `cross-test` over the 53-platform table. Each of those
   is a separate claim; the matrix in `README.md` names what each would settle.

## Decisions taken without running the compiler

Everything a worker could not settle by running Zig 0.16.0 is settled here by
reading the pinned compiler's own `lib/std` or by copying a shape an existing,
already-landed file in this repository uses. Where neither was possible, the
decision is named with its risk.

* **`pub fn main(init: std.process.Init) !void`**, `init.io`,
  `std.Io.File.stdout().writerStreaming(io, &buffer)` and `{s: <44}` column
  padding in the consumer program: copied from `lua/consumer/src/main.zig`,
  which is the same contract on the same compiler and is the only in-repository
  precedent. Not re-derived from `lib/std`.
* **A synthetic TrueType font in the consumer**, rather than the vendored fixture:
  `@embedFile` resolves against the package root, and the consumer package's root
  is `consumer/`, so `tests/fixtures/HarfBust.ttf` is unreachable from it by
  design. Writing the font is also the stronger test — the answers come from
  fields the program wrote, not from a fixture both sides already agree about.
* **The font's layout was checked against upstream's parsers, not recalled**:
  the `head` table is exactly 54 bytes because `src/sfnt/ttload.c:260` rejects a
  shorter one; the format 4 subtable has `idRangeOffset = 0` in both segments
  and the mandatory `0xFFFF` sentinel because that is what
  `src/sfnt/ttcmap.c:899-1100` validates; the directory's search fields are
  written correctly even though `src/sfnt/ttload.c:375-379` has that check
  behind `#if 0`; and the advance of 512 on a 1024-unit grid makes the scaled
  answer at 16 points exact rather than a rounding rule this file would have to
  restate.
* **`ft.no_scale`, not `.{ .no_scale = true }`, at the call sites** where the
  facade already names the preset, and `Flags.toInt()` rather than a shift. The
  packed struct is `@bitCast` to `c_int` in `zig/root.zig`, and a hand-written
  shift would be a second place the bit layout could go wrong.
* **Error assertions compare tags** (`expectError` in the consumer,
  `testing.expectError` in the tests) rather than asserting that a call does not
  fail. Every one of them names the tag the C API's own constant maps to.
* **The consumer takes the provider from `--provider` or
  `FREETYPE_TEST_PROVIDER`, never from a default**, and prints the reason when
  neither is present instead of skipping. A runtime-loading build that silently
  loaded nothing would be a green run that proved nothing.
* **`std.SemanticVersion.order(a, b) == .eq`** rather than `eql`, because `order`
  is the call `build.zig` itself makes on the same type.
* **Eight-bit x deltas and sixteen-bit y deltas** in the synthetic glyph, from
  the flag bits rather than from a guess: `0x03` is on-curve plus x-is-a-byte,
  which is what lets a 700-unit rectangle and a 400-unit width both fit.

## What the provenance gate covers, and what it does not

`tools/check-provenance.sh` checks five things without a compiler: the 854
digests; the exact upstream file set under `include/`, `src/`, `builds/`,
`docs/`, `tests/`, `devel/` and `subprojects/`; the three fixture digests, and
that no fixture file is recorded as an upstream digest; that the manifest, the
vendored header and `UPSTREAM.md` name one release and one tag; and that every
licence notice is still in the file that carries it. It also re-derives the
installed header set from `meson.build`'s own list and checks that every path
`build.zig.zon` packages exists.

Its deliberate limits: it does not check the **top-level** file set against the
manifest, because the fork's own files live at the top level too and the
distinction would need a second list to maintain; and it does not check that the
compiled unit list still matches `modules.cfg`, which is a build-graph property
that a source-integrity script has no business owning. Both are stated here
rather than left for a reader to assume.

## Facts worth keeping, with their boundary

* **FreeType's own licence index is not a complete inventory of its archive.**
  Condition: the four terms in `NOTICE.md` that `LICENSE.TXT` does not mention.
  Symptom: a tree summarised as "FTL or GPLv2" is wrong in five directions.
  Fix: inventory per file, and check each notice is still where it was.
  Targets bound: this release, 2.14.3, and any future re-sync until upstream's
  index changes.
* **Upstream's `tests/` directory can hold a `test()` target that a build graph's
  commentary denies.** Condition: `tests/meson.build` for 2.14.3. Symptom: a
  comment claiming there is no upstream suite when there is one. Fix: read the
  file the comment names. Targets bound: 2.14.3's `tests/` only.
* **`configure.raw`'s libtool numbers do not survive Zig's own version fields.**
  Condition: any `-Dlinkage=dynamic` delivery. Symptom: the right SONAME with a
  versioned file name libtool would not have produced. Fix: state both in the
  release notes so a consumer who hard-codes the libtool name knows. Targets
  bound: ELF deliveries of this package, Zig 0.16.0.

## The 53-platform matrix, and the sixteen cells the pinned toolchain cannot compile

**OBSERVED**, 2026-10-05, run `20261005-191553-53412-16665`, `cross-test` from
the package root with this tree's own `cross-test.profile.sh` unchanged,
`--jobs 8 --build-jobs 8`, Zig 0.16.0 at
`/home/tmp2/gertullj/zig-global-cache/p/N-V-__8AAFFSVRWqblwBIcA-Yqv-u7sbjsJoww8K0mWaHbmJ/zig`,
53 of 53 cells attempted, **harness exit code 1**. Per-cell logs and the
harness's own `summary.json` are under
`$HOST_SCRATCH_ROOT/scratch/foundation-libs/cross/freetype/runs/20261005-191553-53412-16665/`.

* **20 pass.** Every Linux cell: `x86_64-linux`, `aarch64-linux`,
  `aarch64_be-linux`, `arm-linux`, `armeb-linux`, `thumb-linux`,
  `thumbeb-linux`, `hexagon-linux`, `loongarch64-linux`, `mips-linux`,
  `mipsel-linux`, `mips64-linux`, `mips64el-linux`, `powerpc-linux`,
  `powerpc64-linux`, `powerpc64le-linux`, `riscv32-linux`, `riscv64-linux`,
  `s390x-linux`, `x86-linux`. Each reports `19/19 tests passed` and
  `tests_complete`, from a real execution: `x86_64-linux` natively, the other
  19 under QEMU user mode. All twenty include the big-endian rows and the
  32-bit rows, and all twenty report upstream's mmap `ftsystem.c`.
* **17 build_only.** `aarch64-freebsd`, `arm-freebsd`, `x86_64-freebsd`,
  `powerpc64-freebsd`, `powerpc64le-freebsd`, `riscv64-freebsd`,
  `aarch64-macos`, `x86_64-macos`, `aarch64-maccatalyst`,
  `x86_64-maccatalyst`, `aarch64-openbsd`, `x86_64-openbsd`,
  `powerpc64-openbsd`, `riscv64-openbsd`, `aarch64-windows`,
  `x86_64-windows`, `thumb-windows`. Every one compiled (`5/6 steps
  succeeded (1 skipped)`, `run test freetype-tests skipped`) and **none
  executed a test**: the reason is `runtime_unavailable`, and this host has no
  Wine, no wasmtime and no executor for those systems. These are compile
  results and nothing else. **They are not passes and no file in this fork
  counts one as a pass.**
* **16 build_failed**, all nine NetBSD cells, five of the nine OpenBSD cells,
  `wasm32-wasi` and `x86-windows`. **Zero runtime failures**: no cell that
  compiled went on to fail a test, and no cell is `partial`.

### The sixteen build failures are five toolchain defects, not this package's

Every one of the sixteen reproduces with **no FreeType code in the build at
all**. A four-file probe — `build.zig`, `build.zig.zon`, `probe.c`, one
`src/root.zig` whose only C dependency is a `@cImport` of the seven libc
headers `include/freetype/config/ftstdlib.h` pulls (`stddef.h`, `limits.h`,
`string.h`, `stdio.h`, `stdlib.h`, `setjmp.h`, `stdarg.h`) plus `strings.h`,
which `string.h` reaches on its own under `__BSD_VISIBLE` — fails on all
sixteen and passes natively (`3/3 steps succeeded; 1/1 tests passed`).
`zig cc -target T -c probe.c` compiles all sixteen cleanly, so the cause is
specific to the aro (`translate-c`) front end, not to the compiler as a whole.
Probe: `$HOST_SCRATCH_ROOT/scratch/foundation-libs/cross/freetype/probe/`.

1. **NetBSD, 7 cells** (`aarch64-netbsd`, `aarch64_be-netbsd`, `arm-netbsd`,
   `armeb-netbsd`, `powerpc-netbsd`, `x86-netbsd`, `x86_64-netbsd`).
   `libc/include/generic-netbsd/sys/cdefs.h:413` defines `__END_PUBLIC_DECLS`
   as `__END_EXTERN_C _Pragma("GCC visibility pop")`, and `__END_DECLS` at
   line 432 aliases it. Aro expands the `_Pragma` operator into a scratch
   buffer and then re-lexes the result as C tokens, so
   `generic-netbsd/string.h:95` fails with `unknown type name 'pragma'`,
   `expected ';', found 'an identifier'`, `unknown type name 'visibility'` and
   `expected ';', found ''` — 105 such errors for `aarch64-netbsd`. The same
   macro is reached from `strings.h:65`, `stdio.h:151` and `stdio.h:282`.
   **Targets bound:** the NetBSD header set as shipped in Zig 0.16.0, to every
   architecture in the matrix that uses it.
2. **OpenBSD, 3 cells** (`arm-openbsd`, `powerpc-openbsd`, `x86-openbsd`).
   `libc/include/generic-openbsd/strings.h:45-47` guards its `size_t` typedef
   with `_SIZE_T_DEFINED_`. Aro's own `compiler/aro/include/stddef.h:8` is
   `#pragma once` and **never defines that macro** — it defines
   `__STDC_VERSION_STDDEF_H__` instead — so both definitions survive and
   `strings.h:47` collides with `aro/include/stddef.h:8`:
   `typedef redefinition with different types ('__size_t' (aka 'unsigned long')
   vs 'unsigned int')`. `generic-openbsd/string.h:46-48` reaches `strings.h`
   under `__BSD_VISIBLE`, which `sys/cdefs.h:431` sets. **Targets bound:** the
   32-bit OpenBSD rows. The four 64-bit OpenBSD rows
   (`x86_64-openbsd`, `aarch64-openbsd`, `powerpc64-openbsd`,
   `riscv64-openbsd`) compile, because `machine/_types.h:123` and the
   `mips64/_types.h:128` spell `__size_t` `unsigned long` on all of them and
   the collision needs the 32-bit width.
3. **MIPS on NetBSD and OpenBSD, 4 cells** (`mips-netbsd`, `mipsel-netbsd`,
   `mips64-openbsd`, `mips64el-openbsd`).
   `libc/include/mips-netbsd-eabi/machine/endian_machdep.h:3-9` and
   `libc/include/generic-openbsd/mips64/endian.h:32-41` both `#error` unless
   `__MIPSEL__` or `__MIPSEB__` is defined. Aro's architecture macro block,
   `compiler/aro/aro/Compilation.zig:635-642`, defines `__mips__` and `_mips`
   for `.mips`/`.mipsel`/`.mips64`/`.mips64el` and **defines neither
   endianness macro**. `grep -rl __MIPSEL__` over `lib/compiler` and
   `lib/std` returns nothing. **Targets bound:** the four MIPS BSD rows.
4. **`wasm32-wasi`.** `libc/include/wasm-wasi-musl/setjmp.h:12-14` is
   `#if !defined(__wasm_exception_handling__) #error Setjmp/longjmp support
   requires Exception handling support`, and `ftstdlib.h:166` includes
   `<setjmp.h>` with no guard, so every FreeType unit reaches it. This is the
   boundary already recorded and analysed for this tree's `zig build check`
   row below, under *"`wasm32-wasi` — a platform boundary, and this package
   cannot move it"*; the 53-platform matrix reproduces it identically, and the
   probe reaches it with no FreeType code at all, which is the one fact this
   entry adds. **Targets bound:** `wasm32-wasi` with this wasi-libc.
5. **`x86-windows`.** `libc/include/any-windows-any/malloc.h:183-187` defines
   `_ALLOCA_S_MARKER_SIZE` only under `_ARM_`, `_X86_` with `!__x86_64`,
   `__ia64__`, `__x86_64` or `__aarch64__`, then uses it unconditionally at
   line 193. Aro's x86 block, `compiler/aro/aro/Compilation.zig:449-450`,
   defines neither `_X86_` nor `_M_IX86` outside the `msvc` ABI, and
   `any-windows-any/stdlib.h:717` pulls `malloc.h` in. Hence
   `use of undeclared identifier '_ALLOCA_S_MARKER_SIZE'` at lines 193 and 221.
   **Targets bound:** the 32-bit Windows row. `x86_64-windows` compiles,
   because `Compilation.zig:436-440` does define `__x86_64` there.

Nothing here is a reason to drop a cell, sample the tests, or remap an
optimization mode, and nothing here is a defect in FreeType: the forty-unit
closure, `Platform.forTarget`'s three `ftsystem.c` branches and the sixteen
base extensions all compiled for every cell that the toolchain's own headers
allowed. **Fix:** none in this tree; all five need a change in the pinned
toolchain's libc headers or in aro's macro and pragma handling. No
`-D` workaround is applied, because each would be a compile flag that hides a
real defect rather than a fix.

## The two cross-target cells that were red, one fixed and one bound

`zig build check` walks six targets. On 2026-10-05 two of them were red and both
were red inside a `setjmp.h` this package does not own. They have different
causes and different answers, so they are recorded separately.

### `riscv64-linux-gnu` — the translator and the C compiler disagreed about one macro

* **Condition.** `zig build check` with no `-Dtarget`, walking the
  `riscv64-linux-gnu` row, which builds the C library, translates
  `zig/translate.h` and compiles the facade, the tests and the example.
* **Symptom.** The C library compiled and the `translate-c` step did not:

  ```text
  /home/tmp2/gertullj/zig-global-cache/p/N-V-__8AAFFSVRWqblwBIcA-Yqv-u7sbjsJoww8K0mWaHbmJ/lib/libc/include/riscv-linux-gnu/bits/setjmp.h:35:3: error: unsupported FLEN
  # error unsupported FLEN
  ```

  `Build Summary: 2/6 steps succeeded (1 failed)` for the single-cell run, with
  `compile lib freetype-riscv64-linux...` beside `translate-c 2 errors`. The
  header is reached from `include/freetype/config/ftstdlib.h:166`, which
  includes `<setjmp.h>` with no guard.
* **Cause, read out of the pinned toolchain.** `bits/setjmp.h:32-36` gives the
  RISC-V `jmp_buf` twelve callee-saved `double` registers when
  `__riscv_float_abi_double` is defined, none when `__riscv_float_abi_soft` is,
  and raises `#error unsupported FLEN` for `__riscv_float_abi_single`, the only
  ABI left with no layout there. Clang and Aro disagree about which one that
  is: `zig cc -target riscv64-linux-gnu` predefines
  `__riscv_float_abi_double` (observed with an `#error` probe that names the
  macro), so this package's C library compiles for the target, while
  `translate-c` predefines none of the three and stops on the same line.
* **Fix.** `build.zig` gives the translation the macro the compile was given.
  `translateCRiscvFloatAbi` derives it from the target being built — `d` gives
  `__riscv_float_abi_double`, `f` without `d` gives
  `__riscv_float_abi_single`, neither gives `__riscv_float_abi_soft` — and hands
  it to `translate.defineCMacro`, so the facade is translated against the ABI
  the library was compiled with. It goes on the translation only: clang already
  predefines it on every C compile line. It is null off RISC-V, so no other
  architecture sees a `-D` it did not need, and a `single`-ABI target still
  fails inside glibc rather than having its failure translated away.
* **Result, observed.** `zig build check -Dtarget=riscv64-linux-gnu` exited 0
  after the change, `Build Summary: 6/6 steps succeeded`, with
  `translate-c success 557ms`. Before it, the same command exited 1.
* **Targets bound.** Zig 0.16.0, and the `riscv32`/`riscv64` rows of any build
  graph that translates a header reaching `<setjmp.h>` under glibc. The whole
  entry rests on Aro's predefine set for RISC-V, so a toolchain that teaches
  `translate-c` the macro retires it and this stays correct either way: the
  `-D` is then a redefinition of what the translator already knows.

### `wasm32-wasi` — a platform boundary, and this package cannot move it

* **Condition.** The `wasm32-wasi` row of `zig build check`, the same six-target
  matrix.
* **Symptom.** Both halves of the row fail, with the pinned toolchain's own
  message:

  ```text
  /home/tmp2/gertullj/zig-global-cache/p/N-V-__8AAFFSVRWqblwBIcA-Yqv-u7sbjsJoww8K0mWaHbmJ/lib/libc/include/wasm-wasi-musl/setjmp.h:13:2: error: Setjmp/longjmp support requires Exception handling support, which is [not yet standardized](https://github.com/WebAssembly/proposals?tab=readme-ov-file#phase-3---implementation-phase-cg--wg). To enable it, compile with `-mllvm -wasm-enable-sjlj` and use an engine that implements the Exception handling proposal.
  #error Setjmp/longjmp support requires Exception handling support, which is [not yet standardized](https://github.com/WebAssembly/proposals?tab=readme-ov-file#phase-3---implementation-phase-cg--wg). To enable it, compile with `-mllvm -wasm-enable-sjlj` and use an engine that implements the Exception handling proposal.
  ```

  The C library reports `compile lib freetype-wasm32-wasi... 40 errors` and the
  facade's translation reports `translate-c 2 errors`; both name
  `include/freetype/config/ftstdlib.h:166` on the way in. `zig build check`
  exits 1 and will keep doing so.
* **Cause, read out of the pinned toolchain.**
  `libc/include/wasm-wasi-musl/setjmp.h:10-15` opens `/* WASI has no setjmp */`
  and raises that `#error` unless `__wasm_exception_handling__` is defined, so
  the refusal is in wasi-libc's own header and not in any compiler setting this
  package controls. `bits/setjmp.h` beside it is the upstream musl one and the
  rest of the file is declarations with no implementation behind them on this
  target.
* **Why this package cannot configure its way out.** The include is
  unconditional and upstream has no switch for it: `include/freetype/config/`
  carries no `setjmp` or `longjmp` guard anywhere, and the one configuration
  file upstream does ship, `include/freetype/config/ftoption.h`, has no
  `FT_CONFIG_OPTION_*` that turns it off. Defining `__wasilibc_unmodified_upstream`
  or `__wasm_exception_handling__` from a build would silence the header while
  leaving declarations with no implementation behind them, which is a fake
  fallback and not a build.
* **Fix.** None here, and none in this repository. The two real moves are both
  outside it: the pinned toolchain's wasi-libc gaining the exception-handling
  proposal, or a documented upstream source deviation guarding
  `ftstdlib.h:166`. Vendoring a replacement `setjmp.h` or editing the vendored
  header would break upstream integrity, so neither was done.
* **Status of the cell.** Not a pass and not a refusal. `wasm32-wasi` stays in
  `check_targets` and `refused_check_targets` stays empty, so the row keeps
  failing loudly and visibly rather than disappearing from the matrix. A reader
  who wants the six-target table green needs the toolchain or upstream to
  change first.
* **Targets bound.** `wasm32-wasi` on Zig 0.16.0's wasi-libc, for any build of
  this package. The same boundary binds any HarfBuzz build that translates
  `<hb-ft.h>`, and it is not specific to FreeType: libpng reaches the same
  header from its own `src/pngconf.h:48-50`.
