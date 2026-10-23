# SPDX-License-Identifier: MIT

{ pkgs, ... }:

let
  # Use one compiler value for the assertion and package definition.
  zig = pkgs.zig_0_17;

  freetype = linkage: pkgs.callPackage ./package.nix {
    inherit linkage;
    zig = zig;
  };

  # Resolve this checkout without adding a store-path context.
  sdk_root = builtins.toString ./.;

  # Keep Zig caches outside the source tree; preserve caller cache paths.
  zig_caches = ''
    if [ -z "''${ZIG_LOCAL_CACHE_DIR:-}" ]; then
      if [ -n "''${XDG_CACHE_HOME:-}" ]; then
        export ZIG_LOCAL_CACHE_DIR="$XDG_CACHE_HOME/freetype/zig-local-cache"
      elif [ -n "''${TMPDIR:-}" ]; then
        export ZIG_LOCAL_CACHE_DIR="$TMPDIR/freetype/zig-local-cache"
      fi
    fi
    if [ -z "''${ZIG_GLOBAL_CACHE_DIR:-}" ]; then
      if [ -n "''${XDG_CACHE_HOME:-}" ]; then
        export ZIG_GLOBAL_CACHE_DIR="$XDG_CACHE_HOME/freetype/zig-global-cache"
      elif [ -n "''${TMPDIR:-}" ]; then
        export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/freetype/zig-global-cache"
      fi
    fi
    if [ -n "''${ZIG_LOCAL_CACHE_DIR:-}" ]; then
      mkdir -p "$ZIG_LOCAL_CACHE_DIR"
    fi
    if [ -n "''${ZIG_GLOBAL_CACHE_DIR:-}" ]; then
      mkdir -p "$ZIG_GLOBAL_CACHE_DIR"
    fi
  '';

  # Tasks that install must have an output directory outside the checkout.
  require_external_output = ''
    if [ -z "''${ZIG_LOCAL_CACHE_DIR:-}" ]; then
      echo "freetype devenv: ZIG_LOCAL_CACHE_DIR, XDG_CACHE_HOME and TMPDIR are all unset," >&2
      echo "so there is nowhere outside this checkout to put build output." >&2
      echo "Export one of them at approved scratch, then run the task again." >&2
      exit 1
    fi
  '';

  # Task bodies must enter this checkout; generated shells inherit caller cwd.
  in_sdk = ''
    ${zig_caches}
    ${require_external_output}
    cd "${sdk_root}" || exit 1
  '';

  # Keep caller arguments last so they can override earlier build arguments.
  native_flags = ''
    -j8 --summary all --cache-dir "$ZIG_LOCAL_CACHE_DIR/native" "''$@"
  '';

  # Isolate the consumer build cache from the SDK cache.
  consumer_flags = ''
    -j8 --summary all --cache-dir "$ZIG_LOCAL_CACHE_DIR/consumer" "''$@"
  '';
in
{
  packages = [
    zig
    pkgs.gnumake
    pkgs.pkg-config
    pkgs.valgrind
    pkgs.patchelf
  ];

  assertions = [
    {
      assertion = zig.version == "0.17.0";
      message = "The FreeType SDK requires Zig 0.17.0; nixpkgs resolved zig_0_17 to ${zig.version}";
    }
  ];

  # Apply the same external-cache rule in interactive shells.
  enterShell = ''
    ${zig_caches}
  '';

  # Outputs are lazy; building one is the packaging route.
  outputs.static = freetype "static";
  outputs.shared = freetype "dynamic";
  outputs.default = freetype "static";

  # Use only characters accepted by devenv task names.
  tasks = {
    # Install deliveries outside the source checkout.
    "sdk:build" = {
      description = ''
        Compile the forty-unit FreeType closure (default step) and install the
        delivery tree under the external cache rather than in this checkout.
      '';
      exec = ''
        ${in_sdk}
        zig build --prefix "$ZIG_LOCAL_CACHE_DIR/prefix/static" ${native_flags}
      '';
    };

    "sdk:build:shared" = {
      description = ''
        Compile the library as a shared object instead of an archive, and install
        it under its own external prefix.
      '';
      exec = ''
        ${in_sdk}
        zig build -Dlinkage=dynamic --prefix "$ZIG_LOCAL_CACHE_DIR/prefix/dynamic" ${native_flags}
      '';
    };

    # Test and check tasks use external caches without installing.
    "sdk:test" = {
      description = ''
        Run the behavioural tests. A `-Druntime=true` run needs
        FREETYPE_TEST_PROVIDER to name a provider, and has no default and no
        fallback.
      '';
      exec = ''
        ${in_sdk}
        zig build test ${native_flags}
      '';
    };

    "sdk:test:release-safe" = {
      description = "Run the behavioural tests in ReleaseSafe";
      exec = ''
        ${in_sdk}
        zig build test -Doptimize=ReleaseSafe ${native_flags}
      '';
    };

    "sdk:smoke" = {
      description = "Run the deterministic example";
      exec = ''
        ${in_sdk}
        zig build smoke ${native_flags}
      '';
    };

    "sdk:check" = {
      description = ''
        Compile and link the library, the facade, the tests and the example for
        the six check targets, running none of them.
      '';
      exec = ''
        ${in_sdk}
        zig build check ${native_flags}
      '';
    };

    "sdk:check:shared" = {
      description = "The same six-target compile check against the shared object";
      exec = ''
        ${in_sdk}
        zig build check -Dlinkage=dynamic ${native_flags}
      '';
    };

    # Build the consumer package through its relative dependency.
    "sdk:consumer" = {
      description = "Build and run the separate consumer package against this SDK";
      exec = ''
        ${in_sdk}
        cd consumer
        zig build run ${consumer_flags}
      '';
    };

    # Run provenance checks from this checkout.
    "sdk:provenance" = {
      description = ''
        Check the 854 recorded upstream digests, the exact native file set, the
        three vendored fixture digests, the one release the records name, the
        licence notices and the packaged path list. This is a source-integrity
        check, not a build gate.
      '';
      exec = ''
        ${in_sdk}
        bash tools/check-provenance.sh
      '';
    };

    # Nested devenv builds use the caller project and its lock.
    # Their outputs are store paths, not files in this checkout.
    "sdk:package:static" = {
      description = ''
        Build the static Nix variant through devenv's own lazy output. No lock
        is needed by this path; `devenv build outputs.static` resolves the
        pinned input from devenv.lock, which the driver owns.
      '';
      exec = "devenv build outputs.static";
    };

    "sdk:package:shared" = {
      description = "Build the shared Nix variant through devenv's own lazy output";
      exec = "devenv build outputs.shared";
    };
  };
}
