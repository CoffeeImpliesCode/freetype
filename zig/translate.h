/* SPDX-License-Identifier: MIT
 * See FORK-LICENSE.md for what that identifier covers.
 *
 * The one header this package translates. `zig build` runs translate-c over
 * this file.
 *
 * ## Which headers those are
 *
 * FreeType's own documentation says how a client includes it, and this file
 * does exactly that and nothing else:
 *
 *   - `include/freetype/freetype.h:76-81` gives the three-line recipe
 *     `#include <ft2build.h>`, `#include <freetype/freetype.h>`,
 *     `#include <freetype/ftoutln.h>`, and this file is that recipe.
 *   - `<ft2build.h>` (`include/ft2build.h:37`) reaches
 *     `<freetype/config/ftheader.h>`, which is a table of macros and declares
 *     nothing itself. It is what lets the rest of the public headers write
 *     `#include FT_OUTLINE_H` instead of a path.
 *   - `<freetype/freetype.h>` is the library's core surface: the `FT_Library`
 *     and `FT_Face` lifecycle, sizes, glyph loading, rendering, charmaps and
 *     the error codes.
 *   - `<freetype/ftoutln.h>` is the outline surface. `freetype.h` does *not*
 *     include it - it only reaches `fttypes.h` (-> `ftimage.h`) and
 *     `fterrors.h` - so `FT_Outline_Get_CBox` and `FT_Outline_Decompose` are
 *     reachable only through this line, and this package's facade uses both.
 *   - `<freetype/ftbbox.h>` declares `FT_Outline_Get_BBox`, the tight bounding
 *     box. `ftoutln.h` only names that function in prose (`ftoutln.h:361`);
 *     the prototype is at `include/freetype/ftbbox.h:84`, so
 *     `Glyph.exactBox` needs this line. It includes `freetype.h` and nothing
 *     else, so it adds nothing to the closure.
 *   - `<freetype/ftadvanc.h>` adds `FT_Get_Advance` and `FT_Get_Advances`, the
 *     fast advance path that does not run the glyph loader.
 *
 * `ftoutln.h:24`, `ftadvanc.h:23` and `ftbbox.h:34` each include
 * `<freetype/freetype.h>` and nothing else, so the C library include closure of
 * this file is exactly the closure of `freetype.h` itself and adds no new
 * standard header.
 *
 * ## Why the other public headers are not listed
 *
 * FreeType installs 47 public headers: the 46 of `ft2_public_headers`
 * (`meson.build:139-186`) plus `include/ft2build.h` (`meson.build:475-476`).
 * They all reduce to `#include
 * <freetype/freetype.h>` plus one of the chapter headers, and each chapter
 * header adds only that chapter's own declarations. The typed surface in
 * `zig/root.zig` is face / glyph / load, so the four headers above cover all
 * of it; adding a chapter header later is one line here and one section in the
 * facade, which is the right size of change.
 *
 * ## What is deliberately not here
 *
 * No declaration is copied out of a FreeType header, and this file defines no
 * macro of its own. The compile-line macros - `FT2_BUILD_LIBRARY`, which
 * `build.zig` puts on every C compile line and on this translation - select
 * declarations inside FreeType's own headers, so they belong on the command
 * line and not here. That is also why the translation carries the `FT_*` API a
 * provider must export under `-Druntime=true`: `FT_LOCAL` expands to nothing
 * in a library build, so nothing but the real API is declared.
 *
 * A client that wants the whole 47-header surface writes its own aggregate and
 * points `translate.h` at it; nothing in this package depends on this file
 * being the only one.
 */

#include <ft2build.h>
#include <freetype/freetype.h>
#include <freetype/ftoutln.h>
#include <freetype/ftbbox.h>
#include <freetype/ftadvanc.h>