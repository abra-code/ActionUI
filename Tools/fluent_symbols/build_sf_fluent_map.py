#!/usr/bin/env python3
"""
build_sf_fluent_map.py - compile the SF Symbols -> Fluent System Icons mapping into the compact table
ActionUI reads beside its Material one, for the SF names Material has no usable glyph for.

Input (from the sf-symbols-material-map repo, and Microsoft's fluentui-system-icons at one commit):
  sf_to_fluent.json      { "_meta": {...}, "map": { "<sf_name>": { "fluent", "filled", "score",
                         "alternatives", "note" }, ... } }: the SF names without a usable Material
                         match, each with the Fluent icon (base name, such as "arrow_down") judged
                         closest; "filled" (default false) picks the filled face.
  FluentSystemIcons-Resizable.json   "ic_fluent_<name>_20_<regular|filled>" -> decimal codepoint, from
                         the commit in fluent-icons-font.commit (the Resizable family: one design per
                         icon, drawn at any size).

Output:
  sf_to_fluent.map       one line per SF symbol, sorted by SF name -

      <sf_name> <hexcodepoint>

  The codepoint is the Fluent glyph of the face the row names (regular and filled are separate glyphs
  at separate codepoints), resolved at build time as the Material map's are, so a renderer needs this
  table and the font of the same commit. Rows scored below --min-score (default 60, as the Material
  map) are left out: below it a glyph tends to say something else, and no icon is the honest answer.

  A renderer uses a row only where the Material map has none for the name (Material first).

Old SF names: with --aliases, old names get their current name's row and the other way around, as
build_sf_material_map.py does (its functions are used here).

Usage:
  build_sf_fluent_map.py \\
      --mapping   /path/to/sf-symbols-material-map/out/sf_to_fluent.json \\
      --names     FluentSystemIcons-Resizable.json \\
      --out       Tools/fluent_symbols/sf_to_fluent.map \\
      [--aliases /System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/name_aliases.strings] \\
      [--min-score N]
"""

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "material_symbols"))
# No __pycache__ written into the repository by the import.
sys.dont_write_bytecode = True
from build_sf_material_map import DEFAULT_MIN_SCORE, Entry, add_alias_entries, parse_aliases  # noqa: E402

HEADER = [
    "# SF Symbols -> Fluent System Icons (Resizable family), compiled by Tools/fluent_symbols/build_sf_fluent_map.py",
    "# Format: <sf_name> <codepoint_hex> - the glyph of the face the row names (regular or filled), in the",
    "# font of the commit in fluent-icons-font.commit. Used only where the Material map has no row for the name.",
    "# Renamed SF Symbols (macOS name_aliases.strings) have rows for old and new names.",
    "# Generated artifact - do not edit by hand; regenerate from the sf-symbols-material-map mapping.",
]


def build_entries(mapping: dict, names: dict, min_score: int) -> tuple[list[Entry], int, list[str]]:
    """The rows scored at least `min_score`, resolved to codepoints; the count left out for their score,
    and the SF names whose Fluent glyph the font does not have. Pure."""
    entries = []
    below = 0
    unresolved = []
    for sf_name, row in mapping.items():
        fluent = row.get("fluent")
        if not isinstance(fluent, str) or not fluent:
            continue
        score = row.get("score")
        if isinstance(score, (int, float)) and score < min_score:
            below += 1
            continue
        face = "filled" if row.get("filled") else "regular"
        codepoint = names.get(f"ic_fluent_{fluent}_20_{face}")
        if not isinstance(codepoint, int):
            unresolved.append(sf_name)
            continue
        entries.append(Entry(sf_name, codepoint, False, None))
    entries.sort(key=lambda entry: entry.sf_name)
    return entries, below, unresolved


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Compile the SF -> Fluent map.")
    parser.add_argument("--mapping", required=True, help="sf-symbols-material-map out/sf_to_fluent.json")
    parser.add_argument("--names", required=True, help="FluentSystemIcons-Resizable.json of the pinned commit")
    parser.add_argument("--out", required=True, help="output sf_to_fluent.map")
    parser.add_argument("--aliases", help="macOS name_aliases.strings: add rows for old SF names")
    parser.add_argument("--min-score", type=int, default=DEFAULT_MIN_SCORE)
    args = parser.parse_args(argv)
    try:
        mapping = json.loads(Path(args.mapping).read_text(encoding="utf-8"))["map"]
        names = json.loads(Path(args.names).read_text(encoding="utf-8"))
    except (OSError, ValueError, KeyError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    entries, below, unresolved = build_entries(mapping, names, args.min_score)
    if unresolved:
        print(f"error: the font has no glyph for {len(unresolved)} rows, such as {unresolved[:5]}; "
              "is --names of another commit?", file=sys.stderr)
        return 1
    alias_rows = 0
    if args.aliases is not None:
        try:
            aliases = parse_aliases(Path(args.aliases).read_bytes())
        except (OSError, ValueError) as error:
            print(f"error: cannot read aliases '{args.aliases}': {error}", file=sys.stderr)
            return 1
        entries, alias_rows = add_alias_entries(entries, aliases)
    lines = HEADER + [f"{entry.sf_name} {entry.codepoint:x}" for entry in entries]
    Path(args.out).write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote {args.out}: {len(entries)} rows ({alias_rows} for old SF names), {below} left out below "
          f"score {args.min_score}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
