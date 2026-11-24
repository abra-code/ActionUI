#!/usr/bin/env python3
"""make_symbol_fonts.py - builds the symbol fonts ActionUI draws SF Symbols and materialName with on Android
and on the web. Nothing it writes is committed.

Mode "android": the library's Gradle build runs it (task generateSymbolFonts) into a generated assets folder,
which receives:

  fonts/MaterialSymbols.ttf
      Every glyph of Material Symbols Rounded (Tools/material_symbols/font), still a variable font on its
      weight (wght) and fill (FILL) axes, with its grade (GRAD) pinned at 0 and its optical size (opsz) at
      24 (MATERIAL_PINNED_AXES), as Linux and Windows draw it: about a quarter of the whole font's size,
      and each glyph still takes any weight and fill. Its code points are Material's own.
  fonts/FluentSymbols.ttf
      The Fluent System Icons glyphs (the Resizable font in Tools/fluent_symbols/font) that
      Tools/fluent_symbols/sf_to_fluent.map names, at their own code points. A regular-face glyph is
      emboldened as on Linux (FLUENT_EMBOLDEN_UNITS, the outline offset HarfBuzz's synthetic bold makes),
      so its strokes match Material's at the map's weights; a filled one is kept as drawn. The line box
      (ascent and descent) is Material's in proportion to the em, so a Fluent glyph lays out like a
      Material one.
  symbols/sf_to_fluent.map
      A copy of Tools/fluent_symbols/sf_to_fluent.map, unchanged: its code points are those of
      FluentSymbols.ttf. The library reads it after sf_to_material.map, whose rows win.
  licenses/MaterialSymbols-LICENSE.txt, licenses/FluentSystemIcons-LICENSE.txt
      The two icon sets' licenses (Apache 2.0 and MIT), each after a paragraph saying what was taken and how
      it was changed.

The two fonts' code points overlap (Fluent's lie inside Material's private use range), so they stay two
fonts, and the library draws each glyph from the font its map row names.

Mode "web": ActionUIWeb/scripts/make-symbol-fonts.sh runs it into ActionUIWeb/assets, which receives only the
Fluent half, since the web draws Material with the Material Symbols web font the host page loads:

  fonts/FluentSymbols.woff2
      The same font as Android's FluentSymbols.ttf, compressed as WOFF2 (which needs the brotli module). Its
      line box is Material Symbols Rounded's (MATERIAL_LINE_BOX), so this mode needs no Material font.
  symbols/sf_to_fluent.map, licenses/FluentSystemIcons-LICENSE.txt
      As in mode "android".

Licenses - both allow taking parts of the fonts, changing them, and shipping the result:
  - Material Symbols, Apache License 2.0: section 2 grants making and distributing derivative works, and
    section 4 sets the conditions, met here: the license ships with the result (licenses/), the changed font
    says it was changed (its description, name 10, and the paragraph in front of the license), and there is
    no NOTICE file upstream to carry along.
  - Fluent System Icons, MIT License: grants the right to "use, copy, modify, merge" on condition that
    Microsoft's copyright notice and the license text ship with it (licenses/).
  - Neither license asks a changed font to be renamed: that is the SIL Open Font License's "Reserved Font
    Name" rule, and neither font is under it. Both get their own family names anyway (MATERIAL_FAMILY,
    FLUENT_FAMILY), so neither passes for the upstream font; the Apache License grants no use of the
    licensor's trade names (section 6). On Android a name could not collide in any case: an app cannot
    install a font system-wide, and the library builds its typefaces from the asset bytes, never looking
    a font up by family name. On the web the family name is scoped to the page that declares it.

Needs: fontTools (the Gradle build and the web script install a pinned version into a private Python
environment; the web script adds brotli), and the fonts with their LICENSE and COMMIT files, which the Gradle
build downloads, as do Tools/material_symbols/fetch-material-symbols-font.sh and
Tools/fluent_symbols/fetch-fluent-icons-font.sh. Mode "web" needs only the Fluent font.

Usage: python3 Tools/material_symbols/make_symbol_fonts.py android|web OUTPUT_FOLDER
Exit status: 0 written, 1 an input is missing or does not fit the map, 64 bad arguments.
"""

import math
import shutil
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent
MATERIAL_FOLDER = REPO / "Tools" / "material_symbols" / "font"
MATERIAL_FONT = MATERIAL_FOLDER / "MaterialSymbolsRounded.ttf"
FLUENT_FOLDER = REPO / "Tools" / "fluent_symbols" / "font"
FLUENT_FONT = FLUENT_FOLDER / "FluentSystemIcons-Resizable.ttf"
FLUENT_ACCEPTED_COMMIT = REPO / "Tools" / "fluent_symbols" / "fluent-icons-font.commit"
FLUENT_MAP = REPO / "Tools" / "fluent_symbols" / "sf_to_fluent.map"

MATERIAL_OUT = Path("fonts") / "MaterialSymbols.ttf"
FLUENT_OUT = Path("fonts") / "FluentSymbols.ttf"
FLUENT_WEB_OUT = Path("fonts") / "FluentSymbols.woff2"
FLUENT_MAP_OUT = Path("symbols") / "sf_to_fluent.map"
LICENSES_OUT = Path("licenses")

MATERIAL_FAMILY = "ActionUI Material Symbols"
FLUENT_FAMILY = "ActionUI Fluent Symbols"
# What a regular Fluent glyph's strokes gain: 6 of Fluent's 500 units (11.5 of Material's 960), as on Linux
# (Tools/material_symbols/generate-symbol-icons.c), where HarfBuzz rounds the strength to whole font units.
FLUENT_EMBOLDEN_UNITS = 6

# The Material axes fixed in MaterialSymbols.ttf, which drops them; wght and FILL stay variable.
#   GRAD (grade) is stripped: no ActionUI JSON uses the Android-only materialGrade property, and keeping the
#   axis doubles the font (8.7 MB instead of 4.2 MB, about 2 MB more compressed in an app). The Android
#   library still reads materialGrade and sends the grade, so to make that property work again, delete
#   "GRAD" here and rebuild, and list materialGrade again in the element schemas that leave it out (see
#   the "bundled fonts" doc in ActionUIAndroid's Helpers/MaterialSymbolFont.kt); no library code changes.
#   opsz (optical size) is fixed at 24, as Linux and Windows draw Material.
MATERIAL_PINNED_AXES = {"GRAD": 0, "opsz": 24}
AXIS_NAMES = {"GRAD": "grade", "opsz": "optical size"}

# Material Symbols Rounded's line box, in its 960 units (hhea and OS/2): mode "web" gives the Fluent font these
# proportions without reading the Material font; mode "android" reads them from the font it instances.
MATERIAL_LINE_BOX = {
    "units": 960,
    "ascent": 1056, "descent": -96, "lineGap": 0,
    "sTypoAscender": 1056, "sTypoDescender": -96, "sTypoLineGap": 0,
    "usWinAscent": 1062, "usWinDescent": 91,
}


def fail(message, status=1):
    print(f"make_symbol_fonts: {message}", file=sys.stderr)
    return status


def read_commit(path):
    """The commit hash in `path`, or None."""
    if not path.is_file():
        return None
    commit = path.read_text(encoding="utf-8").strip()
    if len(commit) != 40 or any(character not in "0123456789abcdef" for character in commit):
        return None
    return commit


def fluent_codepoints(path):
    """The code points of the Fluent map's rows; a malformed row raises ValueError."""
    codepoints = set()
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip() or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) != 2:
            raise ValueError(f"{path} line {number}: expected <name> <hex codepoint>")
        codepoints.add(int(parts[1], 16))
    return codepoints


# ---------- outlines, and HarfBuzz's emboldening ----------

class OutlineRecorder:
    """A fontTools segment pen that records what HarfBuzz's recording pen would: per contour, the points of
    its move, lines and curves (a quadratic's control and end point, a cubic's two controls and end point),
    with a closing line to the start when the contour does not end there, and the segments that use them."""

    def __init__(self):
        from fontTools.pens.basePen import BasePen

        recorder = self

        class Pen(BasePen):
            def _moveTo(self, point):
                recorder.contours.append({"points": [point], "segments": []})
                recorder.start = point

            def _lineTo(self, point):
                recorder.add("line", [point])

            def _qCurveToOne(self, control, point):
                recorder.add("quad", [control, point])

            def _curveToOne(self, control1, control2, point):
                recorder.add("cubic", [control1, control2, point])

            def _closePath(self):
                current = recorder.contours[-1]["points"][-1]
                if current != recorder.start:
                    recorder.add("line", [recorder.start])

            _endPath = _closePath

        self.contours = []
        self.start = None
        self.pen = Pen(None)

    def add(self, kind, points):
        contour = self.contours[-1]
        contour["segments"].append((kind, len(contour["points"]), len(points)))
        contour["points"].extend(points)


def control_area(contours):
    """HarfBuzz's hb_outline_t::control_area: the signed area of the control polygons."""
    area = 0.0
    for contour in contours:
        points = contour["points"]
        for i, (x0, y0) in enumerate(points):
            x1, y1 = points[(i + 1) % len(points)]
            area += x0 * y1 - y0 * x1
    return area * 0.5


def normalize(vector):
    """The unit vector of `vector` and its length (0 and the vector itself when it has none)."""
    length = math.hypot(vector[0], vector[1])
    if length == 0:
        return vector, 0.0
    return (vector[0] / length, vector[1] / length), length


def embolden(contours, strength):
    """HarfBuzz's synthetic bold in place (hb_outline_t::embolden with x_shift 0 and y_shift strength / 2, a
    port of FreeType's FT_Outline_EmboldenXY): every point moves out along the bisector of its two edges so
    each stroke gains `strength` font units, and the glyph rises by half of it."""
    x_shift = 0.0
    y_shift = strength / 2.0
    half = strength / 2.0
    negative = control_area(contours) < 0
    for contour in contours:
        points = [list(point) for point in contour["points"]]
        last = len(points) - 1
        first = 0
        in_vector = (0.0, 0.0)
        anchor = (0.0, 0.0)
        l_in = 0.0
        l_anchor = 0.0
        i, j, k = last, first, -1
        while j != i and i != k:
            if j != k:
                out_vector, l_out = normalize((points[j][0] - points[i][0], points[j][1] - points[i][1]))
                if l_out == 0:
                    j = j + 1 if j < last else first
                    continue
            else:
                out_vector, l_out = anchor, l_anchor
            if l_in != 0:
                if k < 0:
                    k = i
                    anchor = in_vector
                    l_anchor = l_in
                d = in_vector[0] * out_vector[0] + in_vector[1] * out_vector[1]
                if d > -15.0 / 16:
                    d = d + 1.0
                    shift_x = in_vector[1] + out_vector[1]
                    shift_y = in_vector[0] + out_vector[0]
                    if negative:
                        shift_x = -shift_x
                    else:
                        shift_y = -shift_y
                    q = out_vector[0] * in_vector[1] - out_vector[1] * in_vector[0]
                    if negative:
                        q = -q
                    shortest = min(l_in, l_out)
                    shift_x = shift_x * half / d if half * q <= shortest * d else shift_x * shortest / q
                    shift_y = shift_y * half / d if half * q <= shortest * d else shift_y * shortest / q
                else:
                    shift_x = shift_y = 0.0
                while i != j:
                    points[i][0] += x_shift + shift_x
                    points[i][1] += y_shift + shift_y
                    i = i + 1 if i < last else first
            else:
                i = j
            in_vector = out_vector
            l_in = l_out
            j = j + 1 if j < last else first
        contour["points"] = [tuple(point) for point in points]


def replay(contours, pen):
    """Draws the recorded contours into a segment pen."""
    for contour in contours:
        points = contour["points"]
        pen.moveTo(points[0])
        for kind, start, count in contour["segments"]:
            segment = points[start:start + count]
            if kind == "line":
                pen.lineTo(segment[0])
            elif kind == "quad":
                pen.qCurveTo(*segment)
            else:
                pen.curveTo(*segment)
        pen.closePath()


def redrawn_glyph(glyph_set, glyph_name, units, bold):
    """The Fluent glyph `glyph_name` as a simple TrueType glyph, drawn where HarfBuzz draws it, and emboldened
    when `bold`. The glyph set draws a glyph at its hmtx left side bearing, which in the Resizable font is
    not always the glyph's own xMin (the filled glyphs' outlines start at x 0, their bearing is 50 of 500);
    the redrawn glyph has that offset in its points."""
    from fontTools.pens.cu2quPen import Cu2QuPen
    from fontTools.pens.ttGlyphPen import TTGlyphPen

    recorder = OutlineRecorder()
    glyph_set[glyph_name].draw(recorder.pen)
    if not recorder.contours:
        raise ValueError(f"the Fluent glyph {glyph_name} has no outline")
    if bold:
        embolden(recorder.contours, FLUENT_EMBOLDEN_UNITS)
    pen = TTGlyphPen(None)
    # A cubic (none in the Resizable font today) becomes quadratics within a hundredth of the em.
    replay(recorder.contours, Cu2QuPen(pen, units / 100.0, reverse_direction=False))
    return pen.glyph()


# ---------- the fonts ----------

def set_names(font, family, postscript, description):
    """Gives the font its own family name, so it is not taken for the upstream font, and says in the
    description (name 10) what it was made from. Name 5 keeps the upstream "Version <n>.<n>"."""
    name_table = font["name"]
    for name_id in (1, 3, 4, 6, 16, 17, 21, 22, 25):
        name_table.removeNames(nameID=name_id)
    name_table.setName(family, 1, 3, 1, 0x409)
    name_table.setName("Regular", 2, 3, 1, 0x409)
    name_table.setName(postscript, 3, 3, 1, 0x409)
    name_table.setName(family, 4, 3, 1, 0x409)
    name_table.setName(postscript, 6, 3, 1, 0x409)
    name_table.setName(description, 10, 3, 1, 0x409)


def build_material(commit):
    """Material Symbols Rounded with grade and optical size pinned."""
    from fontTools.ttLib import TTFont
    from fontTools.varLib import instancer

    # Keep the upstream modified date: a save stamped with the current time would make every build differ.
    font = TTFont(MATERIAL_FONT, recalcTimestamp=False)
    axes = {axis.axisTag for axis in font["fvar"].axes}
    if not {"FILL", "wght", "GRAD", "opsz"} <= axes:
        raise ValueError(f"{MATERIAL_FONT} lacks an axis of FILL, wght, GRAD, opsz (it has {sorted(axes)})")
    font = instancer.instantiateVariableFont(font, MATERIAL_PINNED_AXES)
    # No glyph names (post format 3, 0.1 MB less): the library looks glyphs up by code point. GSUB stays: it
    # swaps in the filled glyphs at FILL 1, besides the name ligatures.
    font["post"].formatType = 3.0
    set_names(font, MATERIAL_FAMILY, "ActionUIMaterialSymbols",
              f"Material Symbols Rounded by Google (Apache License 2.0), commit {commit}, instanced at "
              f"{pinned_axes_text()} by ActionUI's make_symbol_fonts.py.")
    return font


def pinned_axes_text():
    """MATERIAL_PINNED_AXES in words, as in "grade 0 and optical size 24"."""
    return " and ".join(f"{AXIS_NAMES[tag]} {value}" for tag, value in MATERIAL_PINNED_AXES.items())


def line_box_of(material):
    """The line box of the Material font `material`, in the shape of MATERIAL_LINE_BOX."""
    hhea = material["hhea"]
    os2 = material["OS/2"]
    return {
        "units": material["head"].unitsPerEm,
        "ascent": hhea.ascent, "descent": hhea.descent, "lineGap": hhea.lineGap,
        "sTypoAscender": os2.sTypoAscender, "sTypoDescender": os2.sTypoDescender,
        "sTypoLineGap": os2.sTypoLineGap,
        "usWinAscent": os2.usWinAscent, "usWinDescent": os2.usWinDescent,
    }


def build_fluent(codepoints, commit, line_box):
    """The Fluent glyphs of `codepoints`, the regular ones emboldened, with Material's line box `line_box`."""
    from fontTools import subset
    from fontTools.ttLib import TTFont

    font = TTFont(FLUENT_FONT, recalcTimestamp=False)
    units = font["head"].unitsPerEm
    cmap = font.getBestCmap()
    missing = sorted(codepoint for codepoint in codepoints if codepoint not in cmap)
    if missing:
        raise ValueError(f"the Fluent font has no glyph for U+{missing[0]:04X}; is the map made for another "
                         "commit?")

    glyph_set = font.getGlyphSet()
    glyf = font["glyf"]
    hmtx = font["hmtx"]
    # Every used glyph is redrawn first, from the unchanged glyph set; the face is in the glyph's name
    # (ic_fluent_<name>_20_filled or _regular), as on Linux.
    redrawn = {glyph_name: redrawn_glyph(glyph_set, glyph_name, units, not glyph_name.endswith("_filled"))
               for glyph_name in sorted({cmap[codepoint] for codepoint in codepoints})}
    for glyph_name, glyph in redrawn.items():
        glyph.recalcBounds(glyf)
        glyf[glyph_name] = glyph
        advance, _ = hmtx[glyph_name]
        hmtx[glyph_name] = (advance, glyph.xMin if glyph.numberOfContours else 0)

    options = subset.Options()
    options.layout_features = []
    options.name_IDs = ["*"]
    options.name_languages = ["*"]
    options.notdef_outline = True
    options.hinting = False
    options.glyph_names = False
    subsetter = subset.Subsetter(options)
    subsetter.populate(unicodes=sorted(codepoints))
    subsetter.subset(font)

    # Material's line box in proportion to the em (above the baseline 1.1 em, below it 0.1 em at 960 units),
    # so a Fluent glyph is placed and sized in its text line as a Material one is.
    def scaled(key):
        return round(line_box[key] * units / line_box["units"])

    hhea = font["hhea"]
    os2 = font["OS/2"]
    for key in ("ascent", "descent", "lineGap"):
        setattr(hhea, key, scaled(key))
    for key in ("sTypoAscender", "sTypoDescender", "sTypoLineGap", "usWinAscent", "usWinDescent"):
        setattr(os2, key, scaled(key))

    set_names(font, FLUENT_FAMILY, "ActionUIFluentSymbols",
              f"Fluent System Icons (Resizable) by Microsoft (MIT License), commit {commit}: the glyphs "
              "ActionUI's sf_to_fluent.map uses, the regular ones emboldened, with the line box of Material "
              "Symbols, by ActionUI's make_symbol_fonts.py.")
    return font


def save(font, path):
    """Writes `font` beside `path` and moves it over, so a failed save leaves no half-written font."""
    partial = path.with_suffix(".partial")
    try:
        font.save(partial)
        partial.replace(path)
    except OSError:
        partial.unlink(missing_ok=True)
        raise


def license_text(title, paragraph, license_path):
    return f"{title}\n\n{paragraph}\n\n" + license_path.read_text(encoding="utf-8")


def write_fluent_extras(out, fluent_commit, font_path):
    """The Fluent map, copied unchanged, and the Fluent license naming the changed font `font_path`."""
    shutil.copyfile(FLUENT_MAP, out / FLUENT_MAP_OUT)
    (out / LICENSES_OUT / "FluentSystemIcons-LICENSE.txt").write_text(license_text(
        "Fluent System Icons",
        "The symbol icons of this library that Material Symbols has no glyph for are glyphs of the Fluent "
        "System Icons font by Microsoft\n(https://github.com/microsoft/fluentui-system-icons, commit "
        f"{fluent_commit}),\nthe regular ones emboldened, in {font_path.as_posix()}, a changed version "
        "named \"ActionUI Fluent Symbols\".\nThe MIT License below permits using, modifying and merging "
        "them; they are used under it:",
        FLUENT_FOLDER / "LICENSE"), encoding="utf-8")


def make_web(out, fluent_commit):
    """Mode "web": the Fluent font as WOFF2, the Fluent map and its license."""
    try:
        import brotli  # noqa: F401
    except ImportError:
        return fail("the brotli module is needed for WOFF2 (pip install brotli)")
    codepoints = fluent_codepoints(FLUENT_MAP)
    fluent = build_fluent(codepoints, fluent_commit, MATERIAL_LINE_BOX)
    fluent.flavor = "woff2"
    for folder in (FLUENT_WEB_OUT.parent, FLUENT_MAP_OUT.parent, LICENSES_OUT):
        (out / folder).mkdir(parents=True, exist_ok=True)
    save(fluent, out / FLUENT_WEB_OUT)
    write_fluent_extras(out, fluent_commit, FLUENT_WEB_OUT)
    print(f"{out / FLUENT_WEB_OUT}: {(out / FLUENT_WEB_OUT).stat().st_size} bytes, {len(codepoints)} glyphs")
    return 0


def make_android(out, fluent_commit):
    """Mode "android": both fonts as TrueType, the Fluent map and both licenses."""
    material_commit = read_commit(MATERIAL_FOLDER / "COMMIT")
    if not MATERIAL_FONT.is_file() or not (MATERIAL_FOLDER / "LICENSE").is_file() or material_commit is None:
        return fail(f"no Material Symbols font with its LICENSE and COMMIT in {MATERIAL_FOLDER}; build the "
                    "Android library, or run Tools/material_symbols/fetch-material-symbols-font.sh")
    codepoints = fluent_codepoints(FLUENT_MAP)
    material = build_material(material_commit)
    fluent = build_fluent(codepoints, fluent_commit, line_box_of(material))
    for folder in (MATERIAL_OUT.parent, FLUENT_MAP_OUT.parent, LICENSES_OUT):
        (out / folder).mkdir(parents=True, exist_ok=True)
    save(material, out / MATERIAL_OUT)
    save(fluent, out / FLUENT_OUT)
    write_fluent_extras(out, fluent_commit, FLUENT_OUT)
    (out / LICENSES_OUT / "MaterialSymbols-LICENSE.txt").write_text(license_text(
        "Material Symbols",
        "The symbol icons of this library, other than the Fluent System Icons ones, are glyphs of the "
        "Material Symbols Rounded font by Google\n(https://github.com/google/material-design-icons, commit "
        f"{material_commit}),\ninstanced at {pinned_axes_text()} into fonts/MaterialSymbols.ttf, a "
        "changed version named \"ActionUI Material Symbols\".\nThe Apache License 2.0 below permits such "
        "derivative works (sections 2 and 4); they are used under it:",
        MATERIAL_FOLDER / "LICENSE"), encoding="utf-8")
    print(f"{out / MATERIAL_OUT}: {(out / MATERIAL_OUT).stat().st_size} bytes; {out / FLUENT_OUT}: "
          f"{(out / FLUENT_OUT).stat().st_size} bytes, {len(codepoints)} glyphs")
    return 0


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("android", "web") or sys.argv[2].startswith("-"):
        return fail("usage: make_symbol_fonts.py android|web OUTPUT_FOLDER", 64)
    mode, out = sys.argv[1], Path(sys.argv[2])
    fluent_commit = read_commit(FLUENT_ACCEPTED_COMMIT)
    if fluent_commit is None:
        return fail(f"no commit hash in {FLUENT_ACCEPTED_COMMIT}")
    if not FLUENT_FONT.is_file() or not (FLUENT_FOLDER / "LICENSE").is_file() \
            or read_commit(FLUENT_FOLDER / "COMMIT") != fluent_commit:
        return fail(f"no Fluent font of commit {fluent_commit} with its LICENSE in {FLUENT_FOLDER}; build the "
                    "Android library, or run Tools/fluent_symbols/fetch-fluent-icons-font.sh")
    try:
        import fontTools  # noqa: F401
    except ImportError:
        return fail("fontTools is needed (pip install fonttools)")
    try:
        return make_web(out, fluent_commit) if mode == "web" else make_android(out, fluent_commit)
    except (OSError, ValueError) as error:
        return fail(str(error))


if __name__ == "__main__":
    sys.exit(main())
