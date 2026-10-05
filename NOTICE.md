# Notice

Two separate things are recorded here: what the canonical native source is and
which grant covers each of its files, and what this fork wrote on top of it.
[`FORK-LICENSE.md`](FORK-LICENSE.md) carries the grant for the second group.

## The term this SDK ships under

FreeType is dual-licensed, and the choice is the distributor's:
`LICENSE.TXT:4-11` says the project "is distributed it under two mutually
exclusive open-source licenses" and that "*you* must choose *one* of the two".

**This SDK ships under the FreeType License, `docs/FTL.TXT`.** That is a choice
this fork made, recorded here and in [`FORK-LICENSE.md`](FORK-LICENSE.md); it is
not a grant upstream made on this fork's behalf. Four facts out of the files
decide it:

* `docs/FTL.TXT:19-22` defines the FTL as the term for "all files found in such
  packages, and which do not fall under their own explicit license". It is
  upstream's own default for the archive, and this SDK ships the archive.
* `LICENSE.TXT:23-26` offers the alternative as the GNU General Public License
  version 2 "for programs which already use the GPL". Nothing in this SDK is
  GPL-licensed: the fork's own files are under
  [`FORK-LICENSE.md`](FORK-LICENSE.md), and the native source is upstream's.
* `LICENSE.TXT:20-21` records that the FTL "is compatible to the GNU General
  Public License version 3, but not version 2", and `LICENSE.TXT:25-26` that
  "the FTL is incompatible with GPLv2 due to its advertisement clause". That is
  upstream's statement about the two arms, and it is why this SDK does not offer
  a GPLv2 build as a second variant: nothing here would be changed by one, and a
  GPLv2-only consumer could not take this build at all.
* The FTL's obligation is an attribution one, and it is met. `docs/FTL.TXT:35-38`
  requires that a product acknowledge in its documentation that it used the
  FreeType code, and `docs/FTL.TXT:46-56` gives the text upstream asks for. It
  is reproduced verbatim below and in [`README.md`](README.md).

Both licence texts travel and both are installed
(`share/licenses/freetype/FTL.TXT` and `.../GPLv2.TXT`), because a consumer who
must take the other arm needs the text of the arm they are taking. The
declaration that the two are mutually exclusive is `LICENSE.TXT:4-11`, and it
travels too.

### The credit the FTL asks for

`docs/FTL.TXT:50-56`, with `<year>` filled in as `docs/FTL.TXT:55-56` asks — the
release this SDK vendors:

```
Portions of this software are copyright © 2026 The FreeType
Project (https://freetype.org).  All rights reserved.
```

### The upstream copyright

`docs/FTL.TXT:6-7` and `README:100-101` name the authors:

```
Copyright 1996-2002, 2006 by
David Turner, Robert Wilhelm, and Werner Lemberg
```

```
Copyright (C) 2006-2026 by
David Turner, Robert Wilhelm, and Werner Lemberg.
```

Both lines appear in the installed records. A consumer who receives a
`libfreetype.a`, a `libfreetype.so.6` or any of the 47 installed headers still
owes the FTL's credit clause, and the installed tree carries everything needed
to discharge it.

## Inventory of the upstream files

854 files, 19676746 bytes, every one digested in
[`UPSTREAM.sha256`](UPSTREAM.sha256). **49 of them carry a term of their own**;
the remaining 805 have no notice of their own and are covered by the FTL, by
`docs/FTL.TXT:19-22`'s own scope rule. Reducing this tree to one label would be
wrong in five directions, so the per-file exceptions come first and the default
comes last.

| Path | Files | Term | Notice in the files |
|---|---:|---|---|
| everything not listed below | 805 | **FreeType License** (`docs/FTL.TXT`), Copyright David Turner, Robert Wilhelm, Werner Lemberg | **none in the file** — covered by `docs/FTL.TXT:19-22` |
| `src/bdf/**` | 9 | X Window System-like (MIT-style), two holders | the grant in each file, e.g. `src/bdf/bdf.h:2-3`; `src/bdf/README:102-121` for the driver and `:123-144` for the `bdflib.c`/`bdf.h` portions (Computing Research Labs, New Mexico State University, and Francesco Zappa Nardelli) |
| `src/pcf/**` | 10 of 12 | X Window System-like (MIT-style) | the grant in each of the ten, e.g. `src/pcf/pcfutil.h`; `src/pcf/README:69-88`. **Two files have no notice of their own** — `src/pcf/pcferror.h` and `src/pcf/pcfutil.c` — and fall under the FTL by `docs/FTL.TXT:19-22` |
| `src/base/fthash.c`, `include/freetype/internal/fthash.h` | 2 | X Window System-like (MIT-style) | `src/base/fthash.c:9-31`, `include/freetype/internal/fthash.h:9-31` |
| `src/gzip/` — the zlib-derived files | 15 | **zlib** | `src/gzip/zlib.h:1-29` carries the full grant; the others either carry it (`src/gzip/zutil.c`, `src/gzip/zutil.h`, `src/gzip/ftzconf.h`) or point at it (`src/gzip/inflate.c:1-3`: "For conditions of distribution and use, see copyright notice in zlib.h") |
| `src/gzip/ftgzip.c`, `src/gzip/rules.mk`, `src/gzip/README.freetype`, `src/gzip/patches/freetype-zlib.diff` | 4 | FreeType License for the first three; the patch is a diff against the zlib sources beside it | `src/gzip/README.freetype:16-22` is what describes the bundle and the patch |
| `src/autofit/ft-hb-ft.c`, `ft-hb-decls.h`, `ft-hb-ft.h`, `ft-hb-types.h`, `hb-script-list.h` | 5 | **'Old MIT'** (HarfBuzz), Red Hat and Google | `src/autofit/ft-hb-types.h:1-25`, `src/autofit/hb-script-list.h:1-27`, and the same in each of the others. `LICENSE.TXT:38-41` names four of the five: `ft-hb-ft.h` carries the same notice and is not in that list |
| `src/base/md5.c`, `src/base/md5.h` | 2 | **public domain**, with an ISC-style fallback | `src/base/md5.c:11-23`, `src/base/md5.h:11-23`; `LICENSE.TXT:43-44` |
| `include/dlg/dlg.h`, `include/dlg/output.h`, `src/dlg/dlg.c` | 3 | **Boost Software License 1.0**, Copyright (c) 2019 nyorain | `:1-3` of each. **`LICENSE.TXT` does not list this term at all** |
| `src/tools/vms_shorten_symbol.c` | 1 | MIT-style, Copyright (c) 2010, 2017 Craig A. Berry | `src/tools/vms_shorten_symbol.c:2-4`. **Not in `LICENSE.TXT`** |
| `src/tools/apinames.c`, `src/tools/chktrcmp.py` | 2 | public domain | `src/tools/apinames.c:15`, `src/tools/chktrcmp.py:6`. **Not in `LICENSE.TXT`** |
| `src/dlg/dlgwrap.c`, `src/dlg/rules.mk` | 2 | FreeType License | **none in the file** — FreeType's own wrapper and make fragment around the BSL-1.0 code |

Two facts about that table are worth stating plainly rather than leaving for a
reader to discover:

* **Four terms appear in this tree that `LICENSE.TXT` does not mention** — the
  Boost Software License for the `dlg` logger, the MIT-style grant in one
  development tool, and the public-domain dedication in two more. Upstream's own
  index is not a complete inventory of its archive, and this one is.
* **`dlg` is not FreeType's code at all.** `builds/toplevel.mk:116-122` and
  `:171-182` show it arriving as a git submodule copied into `src/dlg/` and
  `include/dlg/`. It is third-party material that the release happens to carry,
  under its own licence, and it is not compiled by this SDK.

The four terms upstream calls *compatible* with the FTL and the GPLv2 — the
X Window System-like grant, zlib, the 'Old MIT' notices and the public-domain
MD5 — are stated that way at `LICENSE.TXT:28-44`. Compatibility is not the same
thing as being covered by the FTL, and this inventory does not collapse the two.

## Vendored material this fork carries

One fixture, from a third project, under its own licence:

| Path | Term | Notice |
|---|---|---|
| `tests/fixtures/HarfBust.ttf` | **SIL Open Font License 1.1** | `tests/fixtures/COPYING` |
| `tests/fixtures/HarfBust.ttf.gz` | SIL Open Font License 1.1 | the same |
| `tests/fixtures/COPYING` | the licence text itself | — |

These three files are HarfBuzz's Latin in-house test font, not FreeType's and
not this fork's. Their digests are at the end of
[`UPSTREAM.sha256`](UPSTREAM.sha256), they are deliberately *not* recorded as
upstream digests, and `tools/check-provenance.sh` checks both facts. Provenance
is in [`UPSTREAM.md`](UPSTREAM.md), "Third-party material in this repository".

## What this fork changed in upstream files

**Nothing.** No file under `include/`, `src/`, `builds/`, `docs/`, `tests/`,
`devel/` or `subprojects/`, and none of the fifteen top-level files, has been
edited. The 854 digests in [`UPSTREAM.sha256`](UPSTREAM.sha256) are the
checkable form of that claim, and `tools/check-provenance.sh` adds the
exact-file-set check, the licence checks and the one-release check.

`STATUS`: `SOURCE-CONFIRMED` from the recorded digests, checked by recomputing
every one of them on 2026-10-05 with `sha256sum -c UPSTREAM.sha256` and again
through `tools/check-provenance.sh`. That is a statement about bytes, not about
a build: **no compiler has been run against this tree**, so every gate result in
this SDK is `PENDING-VERIFICATION` until the driver runs one.
[`README.md`](README.md) carries the observed runs and names each gate it does
not cover.

## Fork-specific notice

Every file below was written for this fork. None of it carries an upstream
copyright, no upstream permission is claimed over it, and it is released under
the MIT terms recorded in [`FORK-LICENSE.md`](FORK-LICENSE.md):

* `build.zig`, `build.zig.zon`, `.gitignore`, `cross-test.profile.sh`,
  `.github/workflows/verify.yml`
* `zig/root.zig`, the typed facade, and `zig/translate.h`, the aggregate
  translation header this build runs `translate-c` over
* `tests.zig`, `smoke.zig`, `consumer/build.zig`, `consumer/build.zig.zon`,
  `consumer/src/main.zig`
* `runtime/` — the load-at-runtime route, as the six files it holds today.
  `loader.zig` is the reusable state machine and platform layer, holding no
  per-SDK name; `library.zig` is this SDK's descriptor, the namespaced
  synchronization binding and the one load-time check; `graph.zig` is the build
  half that wires them together and substitutes `createModule` for the
  translation's own; `generate.zig` is the build-time generator that writes the
  dispatch from the real translation output for the target being built, so the
  generated file lands in the build cache and this directory holds no generated
  source. `sync.h` and `sync.c` are the two C files that give the loader its
  process-global mutex, condition variable and thread identity under an
  `RT_SYNC_PREFIX` this SDK sets to `freetype_rt`; `sync.c` is compiled into the
  dispatch and `sync.h` is the only header the route compiles C against. All six
  are fork work under this grant; none of them is upstream material, and
  `sync.c` is not a substitute for any upstream unit.
* `package.nix`, `flake.nix`, `devenv.nix`, `devenv.yaml`, `.envrc`
* `tools/check-provenance.sh`
* this file, `README.md`, `README.zig.md`, `UPSTREAM.md`, `UPSTREAM.sha256`,
  `FORK-LICENSE.md`, `CHANGELOG.md`, `FORK-NOTES.md`

`build.zig.zon`'s `.paths` is the package's file filter, and the rule governing
it is that every path it names must exist: `zig fetch` hashes the named paths,
so naming one that is absent would fail the fetch rather than record an absence.
`tools/check-provenance.sh` checks exactly that.

`flake.lock` is **absent** from this tree and `devenv.lock` is **absent** from
it as well: both belong to the driver, `flake.nix` and `devenv.yaml` carry their
own revision pins, and neither lock file is named in `.paths`.

### Which of those files carry the SPDX tag, and which do not

Twenty-three fork-authored files carry `SPDX-License-Identifier: MIT` on their
first comment line: `build.zig`, `build.zig.zon`, `zig/root.zig`,
`zig/translate.h`, `tests.zig`, `smoke.zig`, all six files of `runtime/`,
`consumer/build.zig`, `consumer/src/main.zig`, `tools/check-provenance.sh`,
`cross-test.profile.sh`, `package.nix`, `flake.nix`, `devenv.nix`, `devenv.yaml`,
`.envrc`, `.gitignore` and `.github/workflows/verify.yml`. That set was read out
of the files rather than assumed.

The rest carry the same grant without a tag, and are named here rather than left
for a scanner to read as unlicensed. One is comment-capable data,
`consumer/build.zig.zon`, whose grant is this inventory and
[`FORK-LICENSE.md`](FORK-LICENSE.md). The eight documentation and digest records
— this file, `README.md`, `README.zig.md`, `UPSTREAM.md`, `UPSTREAM.sha256`,
`FORK-LICENSE.md`, `CHANGELOG.md` and `FORK-NOTES.md` — are prose and data with
no comment position a tag is expected in, and their grant is the same MIT text.

Upstream's attribution obligation is unaffected by any of this: a consumer who
receives a FreeType 2.14.3 static library, shared object or header still owes
the FTL's credit clause, and the installed tree carries it. `zig build`
installs fifteen records under `share/licenses/freetype/` — `LICENSE.TXT`,
`docs/FTL.TXT`, `docs/GPLv2.TXT`, `src/bdf/README`, `src/pcf/README`,
`src/gzip/zlib.h`, `tests/fixtures/COPYING`, `README`, and this fork's own
`NOTICE.md`, `FORK-LICENSE.md`, `UPSTREAM.md`, `UPSTREAM.sha256`,
`FORK-NOTES.md`, `CHANGELOG.md` and `README.md` — which is exactly the
`licence_records` list in `build.zig`, and what `package.nix` installs because it
runs the same `zig build install`.
