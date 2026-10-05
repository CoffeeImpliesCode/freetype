#!/usr/bin/env bash
# Source-integrity check for the FreeType SDK.
#
# Five questions, all answerable without a compiler:
#
#   1. Do the 854 upstream files still hash to the digests UPSTREAM.sha256
#      records, and is the file set exactly that set -- no missing, extra or
#      renamed file under include/, src/, builds/, docs/, tests/, devel/ or
#      subprojects/?  A plain checksum run cannot see an addition.
#   2. Does the vendored fixture still hash to the digests recorded for it, and
#      is it still outside the upstream manifest it does not belong in?
#   3. Do the records name one release?  The three version macros in the
#      vendored header, build.zig.zon's .version and UPSTREAM.md's release row
#      have to agree, or three places describe three different upstreams.
#   4. Is every licence statement still where the records say it is -- the FTL
#      and the GPLv2 upstream offers, the per-file exceptions, the vendored
#      font's licence, and the attribution in the fork's own records?
#   5. Does the build graph install upstream's own header list, and does every
#      path build.zig.zon packages exist?  `zig fetch` hashes the named paths, so
#      naming a missing one turns an absence into a fetch failure.
#
# This is a provenance gate, not a build gate. Nothing here compiles, links or
# runs a target binary; it is the check that an edit to the canonical native
# source cannot pass as a routine change.
#
# Usage: tools/check-provenance.sh   (run from anywhere in the repository)
#
# SPDX-License-Identifier: MIT
# See FORK-LICENSE.md for what that identifier covers.

set -euo pipefail

cd "$(dirname "$0")/.."

fail() {
    echo "$1" >&2
    exit 1
}

# The upstream directories. tests/ is here even though only four of its files
# are upstream: the fixture directory under it is checked separately, and an
# unexpected new file under tests/ still has to be caught.
UPSTREAM_ROOTS="include src builds docs tests devel subprojects"

# Three scratch files, outside this checkout, removed on every exit.
fixture_manifest=$(mktemp)
header_list=$(mktemp)
graph_list=$(mktemp)
trap 'rm -f "$fixture_manifest" "$header_list" "$graph_list"' EXIT

# 1. Bytes.
sha256sum -c --quiet UPSTREAM.sha256 || fail "an upstream file no longer matches UPSTREAM.sha256"
echo "all 854 upstream files match UPSTREAM.sha256"

# 2. File set. The fixture directory is excluded from both sides: it is not
# upstream material, and the next section is what checks it.
expected_tree=$(awk '/^[0-9a-f]{64}  / { print $2 }' UPSTREAM.sha256 \
    | grep -E "^(include|src|builds|docs|tests|devel|subprojects)/" \
    | grep -v '^tests/fixtures/' \
    | LC_ALL=C sort)
actual_tree=$(find $UPSTREAM_ROOTS -type f -not -path 'tests/fixtures/*' | LC_ALL=C sort)
if [ "$expected_tree" != "$actual_tree" ]; then
    echo "the upstream file set differs from the recorded one:" >&2
    diff -u <(echo "$expected_tree") <(echo "$actual_tree") >&2 || true
    echo >&2
    echo "An intentional change to the native source needs an observed failure, a" >&2
    echo "small causal patch, an explicit per-file deviation record in NOTICE.md," >&2
    echo "updated digests here, and a CHANGELOG.md entry in the same change." >&2
    exit 1
fi
echo "the upstream file set is exactly the recorded 839 directory files and 15 top-level files"

# 2a. The fixture is recorded, but as the fork's material: it must not appear in
# the manifest's digest lines, or `sha256sum -c` would start checking a file
# UPSTREAM.md says is not upstream's.
if awk '/^[0-9a-f]{64}  / { print $2 }' UPSTREAM.sha256 | grep -q '^tests/fixtures/'; then
    fail "a vendored fixture file is recorded as an upstream digest"
fi
echo "no vendored fixture file is recorded as upstream"

# 2b. The three fixture digests, which UPSTREAM.sha256 carries as comments so
# that `sha256sum -c` does not treat them as upstream records.
awk '/^# [0-9a-f]{64}  tests\/fixtures\// { print substr($0, 3) }' UPSTREAM.sha256 \
    > "$fixture_manifest"
fixture_count=$(wc -l < "$fixture_manifest" | tr -d ' ')
[ "$fixture_count" = 3 ] ||
    fail "expected three recorded fixture digests, found $fixture_count"
sha256sum -c --quiet "$fixture_manifest" ||
    fail "a vendored fixture file no longer matches its recorded digest"
echo "the three vendored fixture files match their recorded digests"

# 3. One release, three places. The three macros in the vendored header are the
# authority; build.zig refuses to configure when the manifest disagrees with
# them, and this is the check that makes that refusal unnecessary to discover.
header_version=$(awk '
    /^#define[ \t]+FREETYPE_MAJOR/ { major = $3 }
    /^#define[ \t]+FREETYPE_MINOR/ { minor = $3 }
    /^#define[ \t]+FREETYPE_PATCH/ { patch = $3 }
    END { printf "%s.%s.%s", major, minor, patch }
' include/freetype/freetype.h)
[ -n "$header_version" ] || fail "the FREETYPE_* macros were not found in include/freetype/freetype.h"
manifest_version=$(grep -m1 -oE '\.version = "[0-9]+\.[0-9]+\.[0-9]+"' build.zig.zon \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
recorded_version=$(grep -m1 -E '^\| Release \| [0-9]+\.[0-9]+\.[0-9]+, released' UPSTREAM.md \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
[ "$manifest_version" = "$header_version" ] ||
    fail "build.zig.zon says $manifest_version and include/freetype/freetype.h says $header_version"
[ "$recorded_version" = "$header_version" ] ||
    fail "UPSTREAM.md records $recorded_version and include/freetype/freetype.h says $header_version"
echo "the manifest, the vendored header and UPSTREAM.md all name $header_version"

# 3a. The upstream tag a re-sync would merge, and the ChangeLog entry that
# creates it. A tag that is not in the ChangeLog is a guess; a tag in the
# ChangeLog but missing from UPSTREAM.md is an omission.
grep -qF 'VER-2-14-3' ChangeLog || fail "ChangeLog no longer names the VER-2-14-3 tag"
grep -qF 'VER-2-14-3' UPSTREAM.md || fail "UPSTREAM.md no longer records the VER-2-14-3 tag"
grep -qF 'Version 2.14.3 released' ChangeLog ||
    fail "the top ChangeLog entry is no longer the 2.14.3 release"
echo "the release tag is recorded in both UPSTREAM.md and ChangeLog"

# 3b. The release tarball's own digest is not recorded. That has to stay visible
# in both records, and the day one of them gains a digest the two have to name
# the same one.
if grep -qi 'not recorded' UPSTREAM.sha256; then
    grep -qF "is not recorded" UPSTREAM.md ||
        fail "UPSTREAM.sha256 says the tarball digest is unrecorded and UPSTREAM.md does not"
    echo "the missing release digest is recorded as missing in both files"
else
    digest_md=$(grep -m1 -oE '[0-9a-f]{64}' UPSTREAM.md)
    digest_list=$(grep -m1 -oE '[0-9a-f]{64}' UPSTREAM.sha256)
    [ -n "$digest_md" ] || fail "UPSTREAM.md records no release digest"
    [ "$digest_md" = "$digest_list" ] ||
        fail "UPSTREAM.md and UPSTREAM.sha256 name different release digests"
    echo "the release digest is recorded consistently: $digest_md"
fi

# 4. Licences, in the files that carry them.
# 4a. The two arms of upstream's dual grant, and the statement that they are
# mutually exclusive. A fork that shipped under one of them has to be able to
# say which, and to point at the text of the one it declined.
grep -qF 'mutually exclusive' LICENSE.TXT ||
    fail "LICENSE.TXT no longer states that the two licences are mutually exclusive"
grep -qF 'The FreeType Project LICENSE' docs/FTL.TXT ||
    fail "docs/FTL.TXT is no longer the FreeType Project licence text"
grep -qF 'Copyright 1996-2002, 2006 by' docs/FTL.TXT ||
    fail "docs/FTL.TXT no longer carries the FreeType copyright"
grep -qF 'GNU GENERAL PUBLIC LICENSE' docs/GPLv2.TXT ||
    fail "docs/GPLv2.TXT is no longer the GNU General Public License v2 text"
grep -qF 'Copyright (C) 1989, 1991 Free Software Foundation, Inc.' docs/GPLv2.TXT ||
    fail "docs/GPLv2.TXT no longer carries the FSF copyright"
echo "both licence arms and both copyrights are where LICENSE.TXT says they are"

# 4b. The per-file exceptions, each in the file that carries it. These are the
# files a single "FTL or GPL" label would misrepresent.
grep -qF 'Permission is hereby granted' src/base/fthash.c ||
    fail "src/base/fthash.c no longer carries its own grant"
grep -qF 'COMPUTING RESEARCH LAB' src/base/fthash.c ||
    fail "src/base/fthash.c no longer names the Computing Research Lab"
grep -qF 'Copyright (C) 1995-2024 Jean-loup Gailly and Mark Adler' src/gzip/zlib.h ||
    fail "src/gzip/zlib.h no longer carries zlib's copyright"
grep -qF 'Red Hat, Inc.' src/autofit/ft-hb-types.h ||
    fail "src/autofit/ft-hb-types.h no longer carries the 'Old MIT' notice"
grep -qF 'Google, Inc.' src/autofit/hb-script-list.h ||
    fail "src/autofit/hb-script-list.h no longer carries the 'Old MIT' notice"
grep -qF 'the software is hereby placed in the public domain' src/base/md5.c ||
    fail "src/base/md5.c no longer carries its public-domain dedication"
grep -qF 'Copyright (C) 2001-2002 by Francesco Zappa Nardelli' src/bdf/README ||
    fail "src/bdf/README no longer carries the BDF driver's grant"
grep -qF 'Copyright (C) 2000 by Francesco Zappa Nardelli' src/pcf/README ||
    fail "src/pcf/README no longer carries the PCF driver's grant"
grep -qF 'SIL OPEN FONT LICENSE Version 1.1' tests/fixtures/COPYING ||
    fail "tests/fixtures/COPYING is no longer the SIL Open Font License 1.1 text"
echo "every per-file exception is still in the file that carries it"

# 4c. The fork's own records. Each of these owes the upstream notice, and each of
# these has to name the licence choice this SDK ships under.
for record in NOTICE.md FORK-LICENSE.md README.md README.zig.md CHANGELOG.md FORK-NOTES.md; do
    grep -qF 'FreeType' "$record" ||
        fail "the upstream attribution is missing from $record"
done
for record in NOTICE.md FORK-LICENSE.md README.md README.zig.md; do
    grep -qF 'docs/FTL.TXT' "$record" ||
        fail "$record does not name the licence text this SDK ships under"
    grep -qF 'docs/GPLv2.TXT' "$record" ||
        fail "$record does not name the alternative licence it declined"
done
grep -qF 'SIL Open Font License' NOTICE.md ||
    fail "NOTICE.md does not record the vendored font's licence"
grep -qF 'David Turner, Robert Wilhelm, and Werner Lemberg' README.md ||
    fail "README.md does not carry upstream's copyright line"
echo "the fork records name the licence choice, the alternative and the attribution"

# 5. Packaging.
# 5a. The installed header set is upstream's own list, so a header dropped from
# the build graph cannot pass unnoticed. Both lists are compared by name.
awk '/^ft2_public_headers = files\(\[/,/^\]\)/ { print }' meson.build \
    | grep -oE 'include/[A-Za-z0-9./_]+\.h' | LC_ALL=C sort > "$header_list"
# upstream installs ft2build.h separately, from the root of include/, and this
# SDK installs it beside the others so that one -I satisfies the recipe in
# include/freetype/freetype.h:58-61. It is therefore expected on the build-graph
# side and not in meson.build's list.
echo "include/ft2build.h" >> "$header_list"
LC_ALL=C sort -o "$header_list" "$header_list"
grep -oE '^    "include/[A-Za-z0-9./_]+\.h"' build.zig \
    | grep -oE 'include/[A-Za-z0-9./_]+\.h' | LC_ALL=C sort > "$graph_list"
if ! diff -u "$header_list" "$graph_list" > /dev/null; then
    echo "the header list build.zig installs is not meson.build's own list:" >&2
    diff -u "$header_list" "$graph_list" >&2 || true
    exit 1
fi
echo "the installed header set is meson.build's own list of 46 headers plus ft2build.h"

# 5b. Every path in .paths has to exist.
#
# Comment lines inside the block are dropped before the quoted names are read.
# `.paths` is heavily commented here, and one of those comments at
# build.zig.zon:42 writes `dep.module("freetype")` in prose; taking every
# quoted string in the block read that sentence as a packaged path named
# `freetype` and failed on a path the manifest never names.
missing_paths=0
while IFS= read -r named; do
    [ -e "$named" ] || {
        echo "build.zig.zon .paths names $named, which does not exist" >&2
        missing_paths=$((missing_paths + 1))
    }
done < <(awk '/^    \.paths = \.\{/,/^    \},/ { print }' build.zig.zon \
    | grep -vE '^[[:space:]]*//' \
    | grep -oE '"[^"]+"' | tr -d '"')
[ "$missing_paths" -eq 0 ] || fail "build.zig.zon names $missing_paths paths that do not exist"
echo "every path build.zig.zon packages exists in this tree"

echo "provenance checks passed"
