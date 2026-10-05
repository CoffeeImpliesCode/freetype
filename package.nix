# Source-only package derivation for the FreeType SDK.
#
# One file, consumed by both flake.nix and devenv.nix, so the two entry points
# cannot describe different packages. It builds nothing but this repository: the
# native source is upstream's `include/`, `src/` and `builds/`, which are the
# complete FreeType 2.14.3 public surface and font engine imported whole from the
# official release, and build.zig owns every compile flag, the platform
# `ftsystem.c` selection and the whole installed layout. Nothing here restates a
# C flag, fetches a tarball, reaches into a sibling checkout, or installs an
# artifact of its own. The one edit it makes is the rpath of the ELF files the
# build installed: Zig records its own build cache there, and that directory
# does not exist once a binary is installed.
#
# No lock file is written here. `flake.lock` and `devenv.lock` belong to the
# driver.
#
# SPDX-License-Identifier: MIT
# See FORK-LICENSE.md for what that identifier covers, and NOTICE.md for the
# FreeType terms that cover everything in include/, src/ and builds/.

{ lib
, stdenv
, zig
, patchelf
  # Zig's own `std.builtin.LinkMode` spelling, passed straight through as
  # `-Dlinkage`. "static" and "dynamic" are two variants of one derivation, and
  # `""` passes nothing at all so the SDK's own default policy runs unchanged.
  # The build graph's default is a static archive, which is what
  # upstream's own make produces, and the shared object is the separate variant.
, linkage ? "static"
, optimize ? "ReleaseSafe"
}:

let
  requestedLinkage =
    if builtins.elem linkage [ "" "static" "dynamic" ] then linkage
    else throw "package.nix: linkage must be \"\", \"static\" or \"dynamic\", not ${toString linkage}";

# Everything except build outputs, version control and developer-tool state.
# Filtering by directory name rather than by an allow list means a file added
# here later is packaged without editing this file, while `.zig-cache/`,
# `zig-out/`, `.devenv/`, `.direnv/` and `result` stay out of a published output
# at any depth, including under consumer/. The upstream manuals, the other four
# build systems, the meson wrap files and both licence texts are deliberately
# kept: they are upstream material with digests in UPSTREAM.sha256, and the audit
# surface is the whole upstream tree.
src = lib.cleanSourceWith {
  src = ./.;
  filter = path: _type:
    let name = builtins.baseNameOf (toString path); in
    !(lib.elem name [
      ".git"
      ".direnv"
      ".devenv"
      ".zig-cache"
      "zig-cache"
      "zig-pkg"
      "zig-out"
      "result"
    ]);
};

# patchelf rewrites ELF rpaths and does not read Mach-O, so the rpath
# normalisation in the install phase exists for ELF targets only, and the tool is
# a build input exactly where that code runs.
isElfTarget = !stdenv.hostPlatform.isDarwin;
in

# These packages build for the compiler's own native target. A cross build here
# would mean hand-building a libc-suffixed triple that has to track nixpkgs, so
# this derivation refuses one instead of silently producing a host-architecture
# library under a foreign name. The comparison is against stdenv's own
# platforms, which are pure values; `builtins.currentSystem` is not evaluable
# in a sandbox and is not used. A remote builder is unaffected: this compares
# build against host, not against any particular machine. Cross-compiling the
# library is not refused by the build graph -- it selects the platform
# `ftsystem.c` from the target -- so this is a boundary of *this derivation*,
# documented in README.md's support matrix, not a limitation of the library.
assert stdenv.buildPlatform.system == stdenv.hostPlatform.system;

stdenv.mkDerivation {
  pname = "freetype";
  version = "2.14.3";

  inherit src;

  strictDeps = true;
  dontPatch = true;

  # The real work is one `zig build install` in installPhase below. Disabling
  # configure and build phases keeps the Zig setup hook from running a first,
  # differently-flagged build of its own; `dontInstall` is deliberately NOT set,
  # because that is what would disable the real install phase.
  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [ zig ] ++ lib.optional isElfTarget patchelf;

  # FreeType links against the C library and, where the platform configuration
  # asks for it, the C math library, and nothing else: this configuration leaves
  # FT_CONFIG_OPTION_SYSTEM_ZLIB, USE_HARFBUZZ, USE_BROTLI, USE_PNG, USE_BZIP2
  # and SUBPIXEL_RENDERING undefined, so the library carries its own modified
  # inflate and pulls in no system zlib, libpng, bzip2, brotli or HarfBuzz. That
  # is the whole of the native dependency closure; nothing else is propagated.
  propagatedBuildInputs = [ stdenv.cc.libc ];

  # The driver owns every gate for this SDK, and a Nix build is not a
  # verification receipt. No check phase is declared here rather than a check
  # phase that runs something smaller than the real gates; the commands that do
  # verify this package are in README.md and CHANGELOG.md.
  doCheck = false;
  dontUseZigCheck = true;

  installPhase = ''
    runHook preInstall

    # Both caches go under the Nix-provided TMPDIR, outside the unpacked source
    # tree, so a build cannot write into $src and so two parallel derivations
    # cannot share state. Any caller-supplied cache variables are left alone:
    # they are the caller's scratch, not this file's to clear.
    export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-local-cache"
    export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global-cache"

    # build.zig owns the source list, the C flags, the platform `ftsystem.c`
    # selection, the generated pkg-config file and every installed path.
    # Declaring any of them here as well would create a second place where they
    # can disagree with the build graph.
    zig build install \
      --prefix "$out" \
      -j"''${NIX_BUILD_CORES:-1}" \
      -Doptimize=${optimize} \
      -Dcpu=baseline \
      ${lib.optionalString (requestedLinkage != "") "-Dlinkage=${requestedLinkage}"}

    # Zig records the build cache in the rpath of anything that links a dynamic
    # artifact it has just built, so an installed binary names a directory that
    # is gone, and Nix rejects an installed file that names its build directory
    # at all. Both Zig caches above are under $TMPDIR, so dropping those entries
    # and no other removes it: the $ORIGIN/../lib build.zig adds, and every store
    # path a real dependency needs, stay. Symlinks are resolved first so a
    # soname link is rewritten through to the object and never replaced by a
    # copy of it.
    ${lib.optionalString isElfTarget ''
      for elf in "$out"/bin/* "$out"/lib/*.so*; do
        [ -f "$elf" ] || continue
        elf=$(readlink -f "$elf")
        rpath=$(patchelf --print-rpath "$elf") || rpath=""
        kept=""
        rest=$rpath
        while [ -n "$rest" ]; do
          entry="''${rest%%:*}"
          case "$entry" in
            "$TMPDIR"/*) ;;
            *) if [ -z "$kept" ]; then kept=$entry; else kept=$kept:$entry; fi ;;
          esac
          if [ "$entry" = "$rest" ]; then rest=""; else rest="''${rest#*:}"; fi
        done
        [ "$kept" = "$rpath" ] || patchelf --set-rpath "$kept" "$elf"
      done
    ''}

    runHook postInstall
  '';

  # The layout this derivation produces is the build graph's, not this file's:
  # $out/lib/libfreetype.a (or libfreetype.so.6.26.20 with libfreetype.so.6 as
  # its SONAME), $out/include/freetype2/ with the 46 headers `meson.build`
  # installs plus ft2build.h, $out/lib/pkgconfig/freetype2.pc,
  # $out/bin/freetype-smoke (the deterministic example the default step
  # installs) and $out/share/licenses/freetype/ with the upstream grant, the
  # alternative arm and this fork's records. Both variants keep that layout;
  # only the artifact kind differs. Nothing is copied or generated by hand here,
  # so `zig build install --prefix $out` and `nix build` produce one layout by
  # construction rather than two that have to be kept in agreement.

  enableParallelBuilding = true;

  meta = {
    description = "FreeType 2.14.3, the TrueType and OpenType font engine, built from the official release sources";
    longDescription = ''
      The complete FreeType 2.14.3 release source -- ten font drivers, two
      hinters, four rasterizers, the bundled inflate and the public C API --
      compiled from the tarball's own include/ and src/ with Zig, with no
      autotools, no CMake, no meson and no build-time download. Ships the
      library, the 47 public headers, a relocatable pkg-config file and the
      licence and provenance records the FreeType License requires to travel
      with it.
    '';
    # The FreeType License, `docs/FTL.TXT`, which carries an advertising clause
    # and is not one of the OSI-approved terms nixpkgs' `lib.licenses` names, so
    # this derivation is marked unfree rather than given a nearer-looking
    # identifier. The choice is recorded in NOTICE.md, both licence texts are
    # installed in $out/share/licenses/freetype/, and the per-file exceptions this
    # tree carries (zlib, the Boost Software License under src/dlg/, the 'Old
    # MIT' notices under src/autofit/, an X Window System-like grant in the BDF
    # and PCF drivers, and a public-domain MD5) are inventoried there too.
    license = lib.licenses.unfree;
    platforms = lib.platforms.unix;
  };
}
