#!/usr/bin/env python3
"""prepare-windows-symbols.py - generates the Material Symbols outlines that ActionUI shows for SF Symbols on
Windows, before the shim is built. They go into the shim DLL as C++ source
(ActionUIWinUI/Shim/src/generated/symbols.inc, gitignored), so no font ships with an app. Without this step
the shim still builds, with no symbols: SF Symbols then show nothing (logged).

The outlines are those of the Linux icons (Tools/material_symbols/generate-symbol-icons.c): one path per
distinct (codepoint, fill, weight) of ActionUIAndroid's sf_to_material.map, drawn from the Material Symbols
Rounded variable font at optical size 24 and grade 0, in the font's em box (960 units, y down, the baseline
at the bottom), coordinates to one decimal. The include holds those paths, each ending in a NUL, as one
block compressed with Windows' Compression API (LZMS; about 1.7 MB of path text in about 0.5 MB, which
the shim unpacks once, at the first symbol it draws), their offsets in it, and the map's rows (SF name ->
path), sorted by name.

  1. The font, Tools/material_symbols/font/MaterialSymbolsRounded.ttf (gitignored): when it is missing,
     the font of the commit the map was made from (ActionUIAndroid/library/material-symbols-font.commit)
     is downloaded from google/material-design-icons, as fetch-material-symbols-font.sh does for that
     commit (run that script to move to a newer release).
  2. fontTools reads it (pip install fonttools).
  3. The paths are compressed with cabinet.dll, so the script writes the include on Windows only; with
     --check it draws the outlines on any system and writes nothing.
  4. The include is replaced only when its text changed, so the shim is not rebuilt for nothing.

Usage: python Scripts/prepare-windows-symbols.py [--check]
Exit status: 0 the include is ready (or, with --check, the outlines were drawn), 1 a step failed.
"""

import platform
import sys
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


def fail(message):
    print(f"prepare-windows-symbols: {message}", file=sys.stderr)
    return 1


def download_font():
    """Downloads the font of the accepted commit into FONT, with its COMMIT file. Returns an error message,
    or None."""
    import urllib.request

    if not ACCEPTED_COMMIT.is_file():
        return f"no {ACCEPTED_COMMIT}"
    commit = ACCEPTED_COMMIT.read_text(encoding="utf-8").strip()
    if len(commit) != 40 or any(character not in "0123456789abcdef" for character in commit):
        return f"{ACCEPTED_COMMIT} does not hold a commit hash"
    FONT.parent.mkdir(parents=True, exist_ok=True)
    partial = FONT.with_suffix(".download")
    try:
        with urllib.request.urlopen(FONT_URL.format(commit=commit), timeout=120) as response:
            partial.write_bytes(response.read())
    except OSError as error:
        return f"could not download the font of {commit}: {error}"
    partial.replace(FONT)
    COMMIT.write_text(commit + "\n", encoding="utf-8")
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
    keys = []
    index = {}
    for _, codepoint, fill, weight in rows:
        key = (codepoint, fill, weight)
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
    lines = [
        "// symbols.inc - generated by Scripts/prepare-windows-symbols.py; do not edit.",
        f"// Material Symbols Rounded (upstream commit {commit}), optical size 24, grade 0; rows of",
        "// ActionUIAndroid/library/src/main/assets/symbols/sf_to_material.map. Paths in the em box, y down,",
        "// each ending in a NUL, compressed together with Windows' Compression API.",
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
    for name, codepoint, fill, weight in sorted(rows, key=lambda row: row[0].encode("utf-8")):
        lines.append(f'    {{"{name}", {index[(codepoint, fill, weight)]}}},')
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
    if not FONT.is_file():
        print("prepare-windows-symbols: no font yet; downloading it", flush=True)
        error = download_font()
        if error is not None:
            return fail(error)
    try:
        import fontTools  # noqa: F401
    except ImportError:
        return fail("fontTools is needed (pip install fonttools)")
    try:
        rows = read_map(MAP)
        upem, paths = outlines(rows)
    except (ValueError, OSError) as error:
        return fail(str(error))
    if check:
        size = sum(len(path) + 1 for path in paths.values())
        print(f"prepare-windows-symbols: drew {len(paths)} outlines for {len(rows)} names ({size // 1024} KiB of "
              "path text); wrote nothing (--check)")
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
