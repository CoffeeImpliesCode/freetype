# Flake interface for the FreeType SDK.
#
# Portable counterpart to devenv.nix. Both call ./package.nix, so the package a
# flake builds and the package devenv builds are the same derivation; this file
# only decides which systems are exposed and which variants of that derivation
# they get.
#
# Canonical development is `devenv shell` (see devenv.nix and .envrc). This
# flake exists so the SDK can be built and consumed off this host. `nix develop`
# here is parity, not the canonical entry point, and it deliberately does not
# build the SDK: entering a shell must not require building a library.
#
# flake.lock is not written here: the driver owns locks.
#
# SPDX-License-Identifier: MIT

{
  description = "FreeType 2.14.3, the TrueType and OpenType font engine, packaged for Zig 0.16";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/c7def046b9a883d46974757852106483d741586f";
  };

  outputs = { self, nixpkgs }:
    let
      # These are the systems package.nix claims: it builds for the compiler's
      # own native target and refuses a cross build rather than producing a
      # host-architecture library under a foreign name. The build graph itself
      # is far more portable than that -- it selects the platform `ftsystem.c`
      # from the target being built, and `zig build check` walks six targets
      # including `x86_64-windows-gnu` and `wasm32-wasi` -- so this list is a
      # boundary of the derivation, documented in README.md's support matrix,
      # not a statement about the library. Documented here, not worked around.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "riscv64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
        "x86_64-freebsd"
      ];

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs:
        let
          mk = linkage: pkgs.callPackage ./package.nix {
            inherit linkage;
            zig = pkgs.zig_0_16;
          };
        in
        {
          # The build graph's own default, and what upstream's make produces.
          static = mk "static";

          # A separate variant of the same derivation, not a second SDK.
          # "shared" names the artefact; the flag it passes is Zig's own
          # `-Dlinkage=dynamic`, and the SONAME it delivers is upstream's
          # `libfreetype.so.6` either way.
          shared = mk "dynamic";

          default = mk "static";
        });

      # Parity only. The canonical development environment is devenv.nix.
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.zig_0_16
            pkgs.gnumake
            pkgs.pkg-config
            pkgs.patchelf
            pkgs.bashInteractive
          ];
        };
      });
    };
}
