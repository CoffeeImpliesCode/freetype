# Upstream

## FreeType source

| Field | Value |
|---|---|
| Project | FreeType 2, the FreeType Project |
| Project site | <https://freetype.org/> |
| Release | 2.14.3, released 2026-03-22 |
| Upstream VCS | <https://gitlab.freedesktop.org/freetype/freetype> |
| VCS tag | `VER-2-14-3` |
| Import | Complete release archive; archive name, format, and digest are not recorded |
| Commit | None; the source was imported from a release archive |
| File set | 854 files, 19,676,746 bytes |
| File digests | `UPSTREAM.sha256` |

The imported paths are `include/`, `src/`, `builds/`, `docs/`, `tests/`, `devel/`, `subprojects/`, and 15 upstream top-level files. No upstream files were removed. The archive's empty `objs/` output directory is not included.

The upstream README is preserved as `README`. This package's documentation is in `README.md` and `README.zig.md`.

## Third-party test font

| Path | Source | License | Digest record |
|---|---|---|---|
| `tests/fixtures/HarfBust.ttf` | HarfBuzz 14.5.1, `harfbuzz/test/shape/data/in-house/fonts/` | SIL Open Font License 1.1; see `tests/fixtures/COPYING` | `UPSTREAM.sha256` |
| `tests/fixtures/HarfBust.ttf.gz` | Compressed copy of the same font | SIL Open Font License 1.1; see `tests/fixtures/COPYING` | `UPSTREAM.sha256` |
| `tests/fixtures/COPYING` | License text for the font | SIL Open Font License 1.1 | `UPSTREAM.sha256` |

The font's SHA-256 is `116106c52c9c4b101497bd3aaf973d3b4e265658151d36db9aff412201bd4d29`. These files are third-party test material, not FreeType release files or fork-authored files.
