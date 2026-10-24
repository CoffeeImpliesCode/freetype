# Changelog

- Mark Nix outputs with the FreeType License instead of an unfree license.
- Install the public configuration-header closure for C consumers and custom-prefix system builds with either linkage.
- Fix runtime provider validation and test diagnostics; forward custom system-library search prefixes to translation and the standalone consumer, preserving static or dynamic linkage.
- Filter unsupported cross-check targets in dynamic and runtime-loaded builds without changing the selected artifact's linkage.
- Port to Zig 0.17.0.
- Match the RISC-V target ABI in facade translation.
- Select the FreeType License for upstream files without an explicit license and install both upstream license texts.
- Add the FreeType 2.14.3 Zig package, `freetype` module, typed facade, and explicit-provider runtime loading.
