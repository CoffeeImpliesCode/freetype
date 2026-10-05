# FORK-LICENSE.md — the grant for this fork's own files

[`NOTICE.md`](NOTICE.md) is the inventory: which files are upstream's, which are
this fork's, and which term covers each. This file is the grant itself, for the
second group only.

## 1. The native source is not covered by anything below

The 854 upstream files — `include/`, `src/`, `builds/`, `docs/`, `tests/`,
`devel/`, `subprojects/` and the fifteen top-level files — are FreeType's, whole
from the 2.14.3 release, and never edited. They ship under the FreeType License,
`docs/FTL.TXT`, with the per-file exceptions `NOTICE.md` inventories; the
alternative arm upstream offers, `docs/GPLv2.TXT`, travels beside it and is not
taken. Nothing in this file re-grants, narrows, widens or conditions any of
those terms, and nothing here asserts that FreeType, David Turner, Robert
Wilhelm, Werner Lemberg, the BDF or PCF driver authors, nyorain, Craig A. Berry
or any other named author wrote, reviewed or endorsed a line of fork code.

The one vendored file that is neither upstream's nor ours — the HarfBuzz test
font under the SIL Open Font License 1.1 — is covered by section 3.

## 2. The fork-authored material

Everything else in this repository — the Zig build graph, the typed module and
its tests, the example, the consumer package, the runtime-loading route, the
packaging, the integrity script and the documentation — was written for this
fork. The runtime-loading route is the six files under `runtime/`: the reusable
loader, this SDK's descriptor, the build half that wires them together, the
build-time generator, and the two C files that supply the synchronization the
descriptor binds. All six are fork work under this grant; none of them is
upstream material and none is derived from a third-party source.

### Grant

**Those files are released under the MIT License**, matching the practical
posture of this project's primary upstream term, whose text is:

```
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

The same obligation this applies to: keep the notice with copies of the fork's
files.

### Why MIT, and what it is not

The owner of this repository authorized per-project licensing for fork-authored
additions as part of the SDK contract migration, with the term chosen per
project. The choice here is recorded rather than derived, and it rests on two
things rather than on a claim that upstream grants it:

* This project's primary term is the FTL, which is permissive — the only
  obligation is attribution — so MIT is its practical counterpart for
  independently authored code. It is **not** the same text as the FTL, and this
  fork does not relicense any upstream file under it.
* The alternative would be to declare the fork's own files under the FTL, which
  would extend a document upstream wrote for *its* archive to material upstream
  has never seen. That is a choice about this fork's files only, and it would
  carry the advertising clause upstream's text defines
  (`docs/FTL.TXT:35-38`) onto a library that has no reason to.

The authorization is recorded here and in `NOTICE.md`; the term above is the
owner's, reached by that authorization and not by any upstream grant.

The owner is not named and no individual copyright holder is invented: the
copyright line above is deliberately the collective one.

### SPDX identifier

```
MIT
```

The plain registered identifier, with no `LicenseRef-` wrapper. That is a
deliberate distinction and not a shortcut: **this package ships the native
source under the FTL**, which carries an advertising clause, so the two terms in
this repository differ and a consumer scanning only the native headers will not
see the fork's own grant. `MIT` is the accurate identifier for the files listed
in section 2 — which are the files that carry it — and `NOTICE.md` is where the
two terms are stated side by side so that neither can be missed.

Every fork-authored **source, build, packaging and script** file carries
`SPDX-License-Identifier: MIT` on its own first comment line. Twenty-three files
do, and they are named one by one in [`NOTICE.md`](NOTICE.md). The documentation
and digest records do not carry a tag: they are prose and data, and `NOTICE.md`
names each of them explicitly so that a scanner finding no identifier in
`README.md` reads a recorded reason rather than an apparent gap.

### What this does not do

* It does not re-license, sublicense or add a condition to any FreeType file, to
  the FTL, or to the GPLv2 text that travels beside it.
* It does not assert that FreeType, the FreeType Project, David Turner, Robert
  Wilhelm, Werner Lemberg or any other named author authored, reviewed,
  endorsed or is affiliated with the fork's files.
* It does not discharge the FTL's attribution obligation. A consumer who ships a
  FreeType 2.14.3 static library, shared object or header still owes the credit
  `docs/FTL.TXT:50-56` asks for; see `NOTICE.md` for where it travels.
* It does not re-grant the vendored test font. That file is HarfBuzz's, under
  the SIL Open Font License 1.1, and nothing here touches it.

## 3. Material carried but not authored here

**One file group, and it is not upstream's either.** `tests/fixtures/` holds
HarfBuzz's own Latin in-house test font and the licence text beside it:

| Path | Term |
|---|---|
| `tests/fixtures/HarfBust.ttf` | SIL Open Font License 1.1 |
| `tests/fixtures/HarfBust.ttf.gz` | SIL Open Font License 1.1 |
| `tests/fixtures/COPYING` | the licence text itself |

Those three files are carried under their own terms, they are recorded in
`UPSTREAM.sha256` as fork material rather than as upstream digests, and nothing
in this file re-grants them. Provenance — which HarfBuzz release, which
directory, which digest — is in [`UPSTREAM.md`](UPSTREAM.md).

Three further groups look like vendored code and are not carried by this fork:
the inflate implementation under `src/gzip/`, the `dlg` logger under `src/dlg/`
and `include/dlg/`, and the HarfBuzz-derived headers under `src/autofit/`. All
three arrive inside upstream's own release, under zlib's terms, the Boost
Software License 1.0 and the 'Old MIT' terms respectively, and
[`NOTICE.md`](NOTICE.md) inventories each one. This fork neither copied them nor
changed them.

The two files this build generates are not carried material either, and the
distinction is worth keeping exact rather than dropping a category to make the
sentence short. Under `-Druntime=true`, `runtime/generate.zig` writes the
dispatch and its patched translation into the build cache, so neither lands in
this tree, and both are built from the translation of `zig/translate.h` and
upstream's own headers that this same build has just produced for the target
being built. Nothing is fetched to make them, no third-party code is in them,
and neither is installed or shipped: every file under `runtime/` in this tree is
a fork-authored file under section 2.

## 4. Why a separate file at all

`NOTICE.md` names which fork-authored files carry an `SPDX-License-Identifier`
line and which carry the same grant in prose without one, and it records which
term covers each of the 854 upstream files. This file exists so that the
authority, the grant text and the limits of that grant live in one place, next
to the inventory rather than scattered across the files themselves.
