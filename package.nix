# SPDX-License-Identifier: MIT
# See FORK-LICENSE.md and NOTICE.md for licence scope.

{ lib
, stdenv
, zig
, patchelf
  # Pass linkage through to `zig build`; empty preserves the build graph's default.
, linkage ? "static"
, optimize ? "ReleaseSafe"
}:

let
  requestedLinkage =
    if builtins.elem linkage [ "" "static" "dynamic" ] then linkage
    else throw "package.nix: linkage must be \"\", \"static\" or \"dynamic\", not ${toString linkage}";

# Keep upstream and package files; filter local build and development state.
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

# patchelf is needed only for ELF rpath cleanup.
isElfTarget = !stdenv.hostPlatform.isDarwin;
in

# This Nix derivation is native-only; the Zig build graph supports cross-targets.
assert stdenv.buildPlatform.system == stdenv.hostPlatform.system;

stdenv.mkDerivation {
  pname = "freetype";
  version = "2.14.3";

  inherit src;

  strictDeps = true;
  dontPatch = true;

  # Run the Zig install phase only; avoid an extra setup-hook build.
  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [ zig ] ++ lib.optional isElfTarget patchelf;

  # Bundled inflate and disabled codecs leave libc and platform libm as dependencies.
  propagatedBuildInputs = [ stdenv.cc.libc ];

  doCheck = false;
  dontUseZigCheck = true;

  installPhase = ''
    runHook preInstall

    # Keep Zig caches outside the source tree.
    export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-local-cache"
    export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global-cache"

    # build.zig owns source selection, flags, pkg-config and installed paths.
    zig build install \
      --prefix "$out" \
      -j"''${NIX_BUILD_CORES:-1}" \
      -Doptimize=${optimize} \
      -Dcpu=baseline \
      ${lib.optionalString (requestedLinkage != "") "-Dlinkage=${requestedLinkage}"}

    # Remove build-cache rpaths from installed ELF files; retain dependencies and `$ORIGIN`.
    # Resolve SONAME symlinks first so patchelf rewrites the object.
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
    # NOTICE.md selects the FreeType License for upstream files without their own license.
    license = lib.licenses.ftl;
    platforms = lib.platforms.unix;
  };
}
