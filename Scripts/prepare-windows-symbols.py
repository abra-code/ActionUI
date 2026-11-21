#!/usr/bin/env python3
"""prepare-windows-symbols.py - generates the Material Symbols outlines, and the Fluent System Icons ones for
the SF names Material has no glyph for, that ActionUI shows for SF Symbols on Windows, before the shim is
built. They go into the shim DLL as C++ source (ActionUIWinUI/Shim/src/generated/symbols.inc, gitignored), so
no font ships with an app. Without this step the shim still builds, with no symbols: SF Symbols then show
nothing (logged).

The Material outlines are those of the Linux icons (Tools/material_symbols/generate-symbol-icons.c), but at
most weight 300 (WINDOWS_MAX_WEIGHT): Windows' own icons are drawn thinner than SF Symbols, whose strokes the
map's weights match (mostly 300, 400 where a row names none), and the Fluent fill-ins below, drawn as Fluent
draws them, are about as thin as Material at 300. One path per distinct (codepoint, fill, weight) of
ActionUIAndroid's sf_to_material.map so capped, drawn from the Material Symbols Rounded variable font at
optical size 24 and grade 0, in the font's em box (960 units, y down, the baseline
at the bottom), coordinates to one decimal. Then, for each SF name of Tools/fluent_symbols/sf_to_fluent.map
that the Material map has no row for, the Fluent glyph (the Resizable family, its regular or filled face as
the row names it), drawn as it is (Windows' own thinner icon look), its em box filling the same square as
Material's: measured on 51 concepts both sets draw (house, folder, calendar, the circles, arrows...), a Fluent
glyph so drawn has its Material counterpart's ink size (median ratio 1.01, quartiles 0.99-1.22; star, plus
and play are larger, Material drawing those small), where at the bare font size it would be 0.86 of it. The
include holds those paths, each ending in a NUL, as one
block compressed with Windows' Compression API (LZMS; about 2.1 MB of path text in about 0.6 MB, which
the shim unpacks once, at the first symbol it draws), their offsets in it, and the map's rows (SF name ->
path), sorted by name.

  1. The font, Tools/material_symbols/font/MaterialSymbolsRounded.ttf (gitignored): when it is missing,
     the font of the commit the map was made from (ActionUIAndroid/library/material-symbols-font.commit)
     is downloaded from google/material-design-icons, as fetch-material-symbols-font.sh does for that
     commit (run that script to move to a newer release). The Fluent font,
     Tools/fluent_symbols/font/FluentSystemIcons-Resizable.ttf (gitignored), likewise from
     microsoft/fluentui-system-icons at the commit in Tools/fluent_symbols/fluent-icons-font.commit (the
     one sf_to_fluent.map was built for), when it is missing or of another commit.
  2. fontTools reads it (pip install fonttools).
  3. The paths are compressed with cabinet.dll, so the script writes the include on Windows only; with
     --check it draws the outlines on any system and writes nothing.
  4. The include is replaced only when its text changed, so the shim is not rebuilt for nothing.

Usage: python Scripts/prepare-windows-symbols.py [--check]
Exit status: 0 the include is ready (or, with --check, the outlines were drawn), 1 a step failed.
"""

import platform
import sys
import time
from pathlib import Path

COMPRESS_ALGORITHM_LZMS = 5

REPO = Path(__file__).resolve().parent.parent
TOOLS = REPO / "Tools" / "material_symbols"
FONT = TOOLS / "font" / "MaterialSymbolsRounded.ttf"
COMMIT = TOOLS / "font" / "COMMIT"
MAP = REPO / "ActionUIAndroid" / "library" / "src" / "main" / "assets" / "symbols" / "sf_to_material.map"
ACCEPTED_COMMIT = REPO / "ActionUIAndroid" / "library" / "material-symbols-font.commit"
FONT_URL = ("https://raw.githubusercontent.com/google/material-design-icons/{commit}/variablefont/"
            "MaterialSymbolsRounded%5BFILL,GRAD,opsz,wght%5D.ttf")
OUTPUT = REPO / "ActionUIWinUI" / "Shim" / "src" / "generated" / "symbols.inc"

# Windows' thinner look: a map row's heavier weight (400 when it names none) is drawn at this one.
WINDOWS_MAX_WEIGHT = 300

FLUENT_TOOLS = REPO / "Tools" / "fluent_symbols"
FLUENT_MAP = FLUENT_TOOLS / "sf_to_fluent.map"
FLUENT_ACCEPTED_COMMIT = FLUENT_TOOLS / "fluent-icons-font.commit"
FLUENT_FONT = FLUENT_TOOLS / "font" / "FluentSystemIcons-Resizable.ttf"
FLUENT_COMMIT = FLUENT_TOOLS / "font" / "COMMIT"
FLUENT_FONT_URL = ("https://raw.githubusercontent.com/microsoft/fluentui-system-icons/{commit}/fonts/"
                   "FluentSystemIcons-Resizable.ttf")


def fail(message):
    print(f"prepare-windows-symbols: {message}", file=sys.stderr)
    return 1


def accepted_commit(path):
    """The commit hash in `path`, or None."""
    if not path.is_file():
        return None
    commit = path.read_text(encoding="utf-8").strip()
    if len(commit) != 40 or any(character not in "0123456789abcdef" for character in commit):
        return None
    return commit


def download_font(accepted=ACCEPTED_COMMIT, font=FONT, commit_file=COMMIT, url=FONT_URL):
    """Downloads the font of the accepted commit into `font`, with its commit file. Returns an error message,
    or None."""
    import urllib.request

    commit = accepted_commit(accepted)
    if commit is None:
        return f"no commit hash in {accepted}"
    font.parent.mkdir(parents=True, exist_ok=True)
    partial = font.with_suffix(".download")
    # Three tries, 5 and 15 seconds apart: a CI runner's connection to GitHub is dropped now and then
    # ("An existing connection was forcibly closed by the remote host").
    delays = [5, 15]
    for attempt in range(len(delays) + 1):
        try:
            with urllib.request.urlopen(url.format(commit=commit), timeout=120) as response:
                partial.write_bytes(response.read())
            break
        except OSError as error:
            if attempt == len(delays):
                return f"could not download the font of {commit}: {error}"
            print(f"prepare-windows-symbols: the download failed ({error}); trying again in {delays[attempt]} seconds",
                  flush=True)
            time.sleep(delays[attempt])
    partial.replace(font)
    commit_file.write_text(commit + "\n", encoding="utf-8")
    return None


def read_map(path):
    """The map's rows as (sf name, codepoint, fill, weight); no fill means 0, no weight 400. A malformed row
    raises ValueError, as the Linux generator refuses one."""
    rows = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        try:
            codepoint = int(parts[1], 16) if len(parts) >= 2 else 0
        except ValueError:
            codepoint = 0
        if not 0 < codepoint <= 0x10FFFF:
            raise ValueError(f"map line {line_number}: expected <name> <hex codepoint>")
        fill = 0
        weight = 400
        for token in parts[2:]:
            value = int(token) if token.isascii() and token.isdigit() else -1
            if value == 1:
                fill = 1
            elif 100 <= value <= 700:
                weight = value
            else:
                raise ValueError(f"map line {line_number}: unknown value \"{token}\"")
        rows.append((parts[0], codepoint, fill, weight))
    if not rows:
        raise ValueError("the map has no rows")
    return rows


def number(value):
    """One decimal, without a trailing .0 or a "-0", as the Linux generator writes coordinates (halves
    rounded away from zero)."""
    tenths = int(abs(value) * 10 + 0.5)
    sign = "-" if value < 0 and tenths != 0 else ""
    return f"{sign}{tenths // 10}" if tenths % 10 == 0 else f"{sign}{tenths // 10}.{tenths % 10}"


def outlines(rows):
    """{(codepoint, fill, weight): path} for every distinct glyph the rows use."""
    from fontTools.pens.svgPathPen import SVGPathPen
    from fontTools.pens.transformPen import TransformPen
    from fontTools.ttLib import TTFont

    font = TTFont(FONT)
    upem = font["head"].unitsPerEm
    cmap = font.getBestCmap()
    axes = {axis.axisTag for axis in font["fvar"].axes} if "fvar" in font else set()
    missing_axes = {"FILL", "GRAD", "opsz", "wght"} - axes
    if missing_axes:
        raise ValueError(f"the font lacks the axes {sorted(missing_axes)}")
    glyph_sets = {}
    paths = {}
    for name, codepoint, fill, weight in rows:
        key = (codepoint, fill, weight)
        if key in paths:
            continue
        glyph_name = cmap.get(codepoint)
        if glyph_name is None:
            raise ValueError(f"the font has no glyph for U+{codepoint:04X} ({name}); is the map made for another release?")
        location = (fill, weight)
        if location not in glyph_sets:
            glyph_sets[location] = font.getGlyphSet(location={"FILL": fill, "GRAD": 0, "opsz": 24, "wght": weight})
        glyph_set = glyph_sets[location]
        pen = SVGPathPen(glyph_set, ntos=number)
        # Font units with y flipped: the em box's top is 0 and the baseline is at upem.
        glyph_set[glyph_name].draw(TransformPen(pen, (1, 0, 0, -1, 0, upem)))
        paths[key] = pen.getCommands()
    return upem, paths


def read_fluent_map(path):
    """The Fluent map's rows as (sf name, codepoint). A malformed row raises ValueError."""
    rows = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        try:
            codepoint = int(parts[1], 16) if len(parts) == 2 else 0
        except ValueError:
            codepoint = 0
        if not 0 < codepoint <= 0x10FFFF:
            raise ValueError(f"Fluent map line {line_number}: expected <name> <hex codepoint>")
        rows.append((parts[0], codepoint))
    return rows


def fluent_outlines(rows, units):
    """{codepoint: path} for the Fluent glyphs the rows use, in the Material em box of `units` (y down):
    the Fluent em box scaled to fill it."""
    from fontTools.pens.svgPathPen import SVGPathPen
    from fontTools.pens.transformPen import TransformPen
    from fontTools.ttLib import TTFont

    font = TTFont(FLUENT_FONT)
    upem = font["head"].unitsPerEm
    cmap = font.getBestCmap()
    glyph_set = font.getGlyphSet()
    scale = units / upem
    paths = {}
    for name, codepoint in rows:
        if codepoint in paths:
            continue
        glyph_name = cmap.get(codepoint)
        if glyph_name is None:
            raise ValueError(f"the Fluent font has no glyph for U+{codepoint:04X} ({name}); is the map made for "
                             "another commit?")
        pen = SVGPathPen(glyph_set, ntos=number)
        # Font units, y up from the baseline (the em box's bottom), to the Material box, y down.
        glyph_set[glyph_name].draw(TransformPen(pen, (scale, 0, 0, -scale, 0, units)))
        paths[codepoint] = pen.getCommands()
    return paths


def compress(data):
    """`data` compressed with Windows' Compression API (cabinet.dll, LZMS)."""
    import ctypes
    from ctypes import wintypes

    cabinet = ctypes.WinDLL("cabinet", use_last_error=True)
    cabinet.CreateCompressor.argtypes = [wintypes.DWORD, ctypes.c_void_p, ctypes.POINTER(ctypes.c_void_p)]
    cabinet.CreateCompressor.restype = wintypes.BOOL
    cabinet.Compress.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t,
                                 ctypes.POINTER(ctypes.c_size_t)]
    cabinet.Compress.restype = wintypes.BOOL
    cabinet.CloseCompressor.argtypes = [ctypes.c_void_p]
    cabinet.CloseCompressor.restype = wintypes.BOOL
    handle = ctypes.c_void_p()
    if not cabinet.CreateCompressor(COMPRESS_ALGORITHM_LZMS, None, ctypes.byref(handle)):
        raise OSError(f"CreateCompressor failed (error {ctypes.get_last_error()})")
    try:
        source = ctypes.create_string_buffer(data, len(data))
        needed = ctypes.c_size_t(0)
        # Asked with no buffer, Compress fails and gives the size it needs.
        cabinet.Compress(handle, source, len(data), None, 0, ctypes.byref(needed))
        if needed.value == 0:
            raise OSError(f"Compress gave no size (error {ctypes.get_last_error()})")
        out = ctypes.create_string_buffer(needed.value)
        written = ctypes.c_size_t(0)
        if not cabinet.Compress(handle, source, len(data), out, needed.value, ctypes.byref(written)):
            raise OSError(f"Compress failed (error {ctypes.get_last_error()})")
        return out.raw[:written.value]
    finally:
        cabinet.CloseCompressor(handle)


def include_text(rows, upem, paths):
    """`rows` are (sf name, key) and `paths` maps each key to its outline."""
    keys = []
    index = {}
    for _, key in rows:
        if key not in index:
            index[key] = len(keys)
            keys.append(key)
    if len(keys) > 0xFFFF:
        raise ValueError(f"{len(keys)} outlines do not fit the rows' 16-bit index")
    offsets = []
    text = bytearray()
    for key in keys:
        offsets.append(len(text))
        text += paths[key].encode("ascii") + b"\0"
    data = compress(bytes(text))
    commit = COMMIT.read_text(encoding="utf-8").strip() if COMMIT.is_file() else "unknown"
    fluent_commit = FLUENT_COMMIT.read_text(encoding="utf-8").strip() if FLUENT_COMMIT.is_file() else "unknown"
    lines = [
        "// symbols.inc - generated by Scripts/prepare-windows-symbols.py; do not edit.",
        f"// Material Symbols Rounded (upstream commit {commit}), optical size 24, grade 0, weight at most {WINDOWS_MAX_WEIGHT}; rows of",
        "// ActionUIAndroid/library/src/main/assets/symbols/sf_to_material.map; then Fluent System Icons, Resizable",
        f"// (upstream commit {fluent_commit}), for the rows of Tools/fluent_symbols/sf_to_fluent.map Material has",
        "// none for. Paths in the Material em box, y down, each ending in a NUL, compressed together with",
        "// Windows' Compression API.",
        "",
        f"#define ACTIONUI_SYMBOL_UNITS {upem}",
        f"#define ACTIONUI_SYMBOL_ALGORITHM {COMPRESS_ALGORITHM_LZMS} // COMPRESS_ALGORITHM_LZMS",
        f"#define ACTIONUI_SYMBOL_TEXT_SIZE {len(text)}",
        "",
        "static const unsigned char kSymbolData[] = {",
    ]
    for start in range(0, len(data), 24):
        lines.append("    " + ",".join(f"{byte}" for byte in data[start:start + 24]) + ",")
    lines += ["};", "", "// Where each outline starts in the unpacked text.", "static const unsigned int kSymbolOffsets[] = {"]
    for start in range(0, len(offsets), 16):
        lines.append("    " + ",".join(str(offset) for offset in offsets[start:start + 16]) + ",")
    lines += ["};", "", "static const SymbolRow kSymbolRows[] = {"]
    for name, key in sorted(rows, key=lambda row: row[0].encode("utf-8")):
        lines.append(f'    {{"{name}", {index[key]}}},')
    lines += ["};", ""]
    return "\n".join(lines), len(text), len(data)


def main():
    check = sys.argv[1:] == ["--check"]
    if sys.argv[1:] and not check:
        return fail("usage: prepare-windows-symbols.py [--check]")
    if not check and platform.system() != "Windows":
        return fail("writes the include on Windows only (it compresses with Windows' Compression API); "
                    "--check draws the outlines on any system")
    if not MAP.is_file():
        return fail(f"no map at {MAP}")
    if not FLUENT_MAP.is_file():
        return fail(f"no Fluent map at {FLUENT_MAP}")
    if not FONT.is_file():
        print("prepare-windows-symbols: no font yet; downloading it", flush=True)
        error = download_font()
        if error is not None:
            return fail(error)
    fluent_commit = accepted_commit(FLUENT_ACCEPTED_COMMIT)
    if fluent_commit is None:
        return fail(f"no commit hash in {FLUENT_ACCEPTED_COMMIT}")
    if not FLUENT_FONT.is_file() or accepted_commit(FLUENT_COMMIT) != fluent_commit:
        print("prepare-windows-symbols: no Fluent font of the map's commit yet; downloading it", flush=True)
        error = download_font(FLUENT_ACCEPTED_COMMIT, FLUENT_FONT, FLUENT_COMMIT, FLUENT_FONT_URL)
        if error is not None:
            return fail(error)
    try:
        import fontTools  # noqa: F401
    except ImportError:
        return fail("fontTools is needed (pip install fonttools)")
    try:
        material_rows = [(name, codepoint, fill, min(weight, WINDOWS_MAX_WEIGHT))
                         for name, codepoint, fill, weight in read_map(MAP)]
        upem, material_paths = outlines(material_rows)
        material_names = {name for name, _, _, _ in material_rows}
        fluent_rows = [row for row in read_fluent_map(FLUENT_MAP) if row[0] not in material_names]
        fluent_paths = fluent_outlines(fluent_rows, upem)
    except (ValueError, OSError) as error:
        return fail(str(error))
    # One table: each name to its outline's key, Material's or Fluent's.
    rows = [(name, ("material", codepoint, fill, weight)) for name, codepoint, fill, weight in material_rows]
    rows += [(name, ("fluent", codepoint)) for name, codepoint in fluent_rows]
    paths = {("material",) + key: path for key, path in material_paths.items()}
    paths.update({("fluent", codepoint): path for codepoint, path in fluent_paths.items()})
    if check:
        size = sum(len(path) + 1 for path in paths.values())
        print(f"prepare-windows-symbols: drew {len(paths)} outlines ({len(fluent_paths)} Fluent) for {len(rows)} names "
              f"({len(fluent_rows)} from Fluent; {size // 1024} KiB of path text); wrote nothing (--check)")
        return 0
    try:
        text, raw, packed = include_text(rows, upem, paths)
    except (ValueError, OSError) as error:
        return fail(str(error))
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    if OUTPUT.is_file() and OUTPUT.read_text(encoding="utf-8") == text:
        print(f"prepare-windows-symbols: {OUTPUT} is up to date ({len(paths)} outlines, {len(rows)} names)")
        return 0
    OUTPUT.write_text(text, encoding="utf-8")
    print(f"prepare-windows-symbols: wrote {OUTPUT} ({len(paths)} outlines, {len(rows)} names; "
          f"{raw // 1024} KiB of path text compressed to {packed // 1024} KiB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
