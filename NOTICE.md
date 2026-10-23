# Notice

FreeType files without an explicit license use the FreeType License in `docs/FTL.TXT`. This package does not select the GPLv2 alternative in `LICENSE.TXT`. Fork-authored files use the MIT grant in `FORK-LICENSE.md`. Both upstream license texts are installed under `share/licenses/freetype/`.

## Attribution

`docs/FTL.TXT:50-56` requests this credit:

```
Portions of this software are copyright © 2026 The FreeType
Project (https://freetype.org).  All rights reserved.
```

Upstream copyright notices:

```
Copyright 1996-2002, 2006 by
David Turner, Robert Wilhelm, and Werner Lemberg
```

```
Copyright (C) 2006-2026 by
David Turner, Robert Wilhelm, and Werner Lemberg.
```

## Upstream file licenses

The release has 854 files. `UPSTREAM.sha256` records their digests. Forty-nine files carry a term of their own; the remaining 805 have no notice of their own and use the FreeType License under `docs/FTL.TXT:19-22`.

| Path | Files | License and attribution | Notice |
|---|---:|---|---|
| All other upstream files | 805 | FreeType License | No notice in the file; `docs/FTL.TXT:19-22` applies |
| `src/bdf/**` | 9 | X Window System-like MIT-style license; Computing Research Labs, New Mexico State University, and Francesco Zappa Nardelli | Each file; `src/bdf/README:102-121` and `:123-144` |
| `src/pcf/**` except `pcferror.h` and `pcfutil.c` | 10 | X Window System-like MIT-style license | Each file; `src/pcf/README:69-88` |
| `src/base/fthash.c`, `include/freetype/internal/fthash.h` | 2 | X Window System-like MIT-style license | Lines 9-31 in each file |
| `src/gzip/` zlib-derived files | 15 | zlib license | Full grant in `src/gzip/zlib.h:1-29`; other files carry or reference it |
| `src/autofit/ft-hb-ft.c`, `ft-hb-decls.h`, `ft-hb-ft.h`, `ft-hb-types.h`, `hb-script-list.h` | 5 | HarfBuzz “Old MIT” license; Red Hat and Google | Each file. `LICENSE.TXT:38-41` lists four; `ft-hb-ft.h` carries the same notice |
| `src/base/md5.c`, `src/base/md5.h` | 2 | Public domain, with an ISC-style fallback | Lines 11-23 in each file; `LICENSE.TXT:43-44` |
| `include/dlg/dlg.h`, `include/dlg/output.h`, `src/dlg/dlg.c` | 3 | Boost Software License 1.0; copyright (c) 2019 nyorain | Lines 1-3 in each file; not listed in `LICENSE.TXT` |
| `src/tools/vms_shorten_symbol.c` | 1 | MIT-style license; copyright (c) 2010, 2017 Craig A. Berry | Lines 2-4; not listed in `LICENSE.TXT` |
| `src/tools/apinames.c`, `src/tools/chktrcmp.py` | 2 | Public domain | `src/tools/apinames.c:15`, `src/tools/chktrcmp.py:6`; not listed in `LICENSE.TXT` |

The FreeType License also covers `src/pcf/pcferror.h`, `src/pcf/pcfutil.c`, `src/gzip/ftgzip.c`, `src/gzip/rules.mk`, `src/gzip/README.freetype`, `src/gzip/patches/freetype-zlib.diff`, `src/dlg/dlgwrap.c`, and `src/dlg/rules.mk`. The first three gzip files are FreeType files; the patch is a diff against adjacent zlib sources. The two `src/dlg/` files are FreeType's wrapper and make fragment around the BSL code.

## Third-party test font

| Path | License | Notice |
|---|---|---|
| `tests/fixtures/HarfBust.ttf`, `tests/fixtures/HarfBust.ttf.gz` | SIL Open Font License 1.1 | `tests/fixtures/COPYING` |
| `tests/fixtures/COPYING` | License text | — |

The two font files are HarfBuzz's Latin in-house test font, not FreeType or fork-authored material. `COPYING` contains the license.

## File scope

The 854 files imported from the FreeType release are unmodified. They are under `include/`, `src/`, `builds/`, `docs/`, `tests/`, `devel/`, `subprojects/`, and the 15 upstream top-level files. The table above records the bundled third-party license exceptions.

Fork-authored files use the MIT grant in `FORK-LICENSE.md`: `build.zig`, `build.zig.zon`, `.gitignore`, `cross-test.profile.sh`, `zig/`, `runtime/`, `tests.zig`, `smoke.zig`, `consumer/`, `package.nix`, `flake.nix`, `devenv.nix`, `devenv.yaml`, `.envrc`, `tools/check-provenance.sh`, `README.md`, `README.zig.md`, `NOTICE.md`, `UPSTREAM.md`, `UPSTREAM.sha256`, `FORK-LICENSE.md`, `CHANGELOG.md`, and `FORK-NOTES.md`.
