# FORK-LICENSE.md

[`NOTICE.md`](NOTICE.md) inventories upstream, fork-authored, and third-party files and their terms.

## Scope

The 854 files in `include/`, `src/`, `builds/`, `docs/`, `tests/`, `devel/`, `subprojects/`, and the fifteen top-level files are FreeType's unmodified 2.14.3 release. They remain under the FreeType License in `docs/FTL.TXT`, subject to the per-file exceptions in `NOTICE.md`. The alternative `docs/GPLv2.TXT` travels with the release but is not selected by this fork. Nothing here changes those terms.

Within the upstream release, the zlib-derived inflate files under `src/gzip/` use zlib terms; the `dlg` logger under `src/dlg/` and `include/dlg/` uses the Boost Software License 1.0; and the HarfBuzz-derived headers under `src/autofit/` use the HarfBuzz “Old MIT” terms. These files are upstream's, not fork-authored. `NOTICE.md` lists the per-file exceptions.

The carried HarfBuzz fixture is neither upstream material nor fork-authored. `tests/fixtures/HarfBust.ttf` and `HarfBust.ttf.gz` use the SIL Open Font License 1.1; `tests/fixtures/COPYING` is that licence text. `UPSTREAM.md` records their provenance.

## Fork-authored files

Except for the upstream files and the HarfBuzz fixture above, the remaining repository files were written for this fork and are released under the MIT License below. This includes the Zig build graph and facade, tests, examples, consumer, packaging, integrity records, and documentation.

The six runtime files—`runtime/loader.zig`, `library.zig`, `graph.zig`, `generate.zig`, `sync.h`, and `sync.c`—are fork-authored under this grant. The generated dispatch and patched translation are written to the build cache and are not carried or installed.

### MIT License

```text
MIT License

Copyright (c) 2026 the contributors to this fork

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```

`SPDX-License-Identifier: MIT` appears on fork-authored source, build, packaging, and script files. Documentation and digest records have no SPDX tag; `NOTICE.md` lists them.

This grant does not relicense FreeType files or the HarfBuzz fixture, and it does not change the terms of `docs/FTL.TXT` or `docs/GPLv2.TXT`.