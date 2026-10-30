#!/usr/bin/env python3
"""
build_sf_material_map.py - compile the SF Symbols -> Material Symbols mapping
into the compact table embedded in ActionUIAndroid.

Input  (from the sf-symbols-material-map repo):
  sf_to_material.json   { "_meta": {...}, "map": { "<sf_name>": { "material",
                          "fill", "weight", "score", "alternatives", "note" }, ... } }
                        'fill' (default false) and 'weight' (default 400) are both
                        optional and omitted at their defaults.
  MaterialSymbolsRounded.codepoints   "<material_name> <hexcodepoint>" per line.

Output (embedded in the library, read at runtime by the systemName path):
  sf_to_material.map    one line per SF symbol -

      <sf_name> <hexcodepoint> [<fill>] [<weight>]

  - <hexcodepoint> is the Material glyph codepoint (lowercase hex, no 0x), already
    resolved from the Material name so the runtime needs only ONE name->codepoint
    table (this one). The full .codepoints table still ships for materialName.
  - axis overrides are BARE integers after the codepoint (no key= prefix),
    disambiguated by range because the value sets are disjoint:
      1          -> FILL axis = 1 (SF's '.fill' variants; omitted means FILL 0).
      100..700   -> wght axis override (omitted means the default, 400). The source
                    carries a per-match 'weight' for the rows whose stroke is best
                    matched lighter/heavier than 400 (e.g. applepencil -> wght 100).
    The hex codepoint always begins e/f (Material PUA), so it never collides with a
    decimal axis token. NB: this disjoint-range scheme only holds for fill+weight; a
    future third axis (e.g. GRAD -50..200) overlaps weight and would need a prefix.

  Lines are sorted by SF name for stable diffs. Defaults (no fill, no weight) emit
  no trailing tokens, keeping the table small and readable.

Why resolve the codepoint at build time, not ship the Material name:
  the runtime would otherwise carry sf_name -> material_name -> codepoint (two
  lookups, two tables). Baking the codepoint in drops it to one.

The Material *name* is intentionally discarded: Material renders one name across
the whole FILL axis, so the name carries no extra information once we have the
codepoint + fill flag.

Old SF names (aliases):
  Apple renames symbols and keeps accepting the old names ("doc" now draws
  "document", "mic" draws "microphone"). The mapping covers the names of one SF
  Symbols release, so with --aliases each old name gets a copy of its current
  name's row, and a name newer than that release gets its old name's row.
  The aliases come from macOS's own table, a binary property list of old -> new
  names:
      /System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/name_aliases.strings
  An old name the mapping lists itself keeps its own row. Keys with capital
  letters are skipped: they are placeholders for unannounced products, never
  names a document can use.

Usage:
  build_sf_material_map.py \
      --mapping     /path/to/sf-symbols-material-map/out/sf_to_material.json \
      --codepoints  ActionUIAndroid/.../symbols/MaterialSymbolsRounded.codepoints \
      --out         ActionUIAndroid/.../symbols/sf_to_material.map \
      [--aliases PATH]   add rows for old SF names (name_aliases.strings, above)
      [--min-score N]    drop matches scored below N (0-100); default 60
                         (pass 0 to keep the full lower-confidence tail)

  For the common case, regen-symbol-map.sh (next to this script) wraps this with
  the conventional origin/codepoints/out paths and then syncs the web copy.

Exit codes: 0 on success; 2 on bad input / unreadable files.
"""

from __future__ import annotations

import argparse
import json
import plistlib
import sys
import xml.parsers.expat
from dataclasses import dataclass
from typing import Optional


# Material Symbols 'wght' axis bounds; a weight override outside this is clamped
# (the runtime clamps too, but we keep the embedded table honest).
WEIGHT_MIN = 100
WEIGHT_MAX = 700

# Default visual-similarity floor for the embedded map: keep matches scored >= 60,
# drop 59 and below. The score is a 0..100 vision-pass judgement; below ~60 the
# Material glyph is a weak stand-in that tends to mislead more than help, so we let
# those systemName lookups degrade honestly to no-icon rather than embed them.
# Override per-run with --min-score (0 keeps the full lower-confidence tail).
DEFAULT_MIN_SCORE = 60


@dataclass(frozen=True)
class Entry:
    """One embedded row: an SF name resolved to a Material codepoint (+ axes)."""
    sf_name: str
    codepoint: int
    fill: bool
    weight: Optional[int]


@dataclass
class Stats:
    total: int = 0
    emitted: int = 0
    skipped_no_material: int = 0
    skipped_below_score: int = 0
    skipped_unresolved: int = 0
    with_fill: int = 0
    with_weight: int = 0


def parse_codepoints(text: str) -> dict[str, int]:
    """Parse the Material '.codepoints' table ('<name> <hex>' per line) into a
    name -> codepoint map. Blank / malformed / non-hex lines are skipped. Pure."""
    table: dict[str, int] = {}
    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        parts = line.split(None, 1)
        if len(parts) != 2:
            continue
        name, hexcp = parts[0], parts[1].strip()
        try:
            table[name] = int(hexcp, 16)
        except ValueError:
            continue
    return table


def build_entries(
    mapping: dict,
    codepoints: dict[str, int],
    min_score: int = 0,
) -> tuple[list[Entry], Stats, list[str]]:
    """Transform the sf-symbols-material-map mapping object into embedded [Entry] rows. Pure /
    unit-testable: takes already-parsed dicts, returns sorted entries, stats, and
    a sample of unresolved Material names (for the human-readable report).

    A row is dropped (and counted) when:
      * it has no Material name (empty / null / explicitly rejected), or
      * its score is below [min_score], or
      * its Material name is absent from [codepoints] (font release mismatch).
    """
    rows = mapping.get("map", mapping)  # tolerate a bare map or the wrapped form
    stats = Stats(total=len(rows))
    entries: list[Entry] = []
    unresolved_samples: list[str] = []

    for sf_name, info in rows.items():
        if not isinstance(info, dict):
            stats.skipped_no_material += 1
            continue
        if info.get("reject"):  # future-proof: explicit rejection wins
            stats.skipped_no_material += 1
            continue

        material = info.get("material")
        if not material:
            stats.skipped_no_material += 1
            continue

        score = info.get("score", 0)
        if isinstance(score, (int, float)) and score < min_score:
            stats.skipped_below_score += 1
            continue

        codepoint = codepoints.get(material)
        if codepoint is None:
            stats.skipped_unresolved += 1
            if len(unresolved_samples) < 25:
                unresolved_samples.append(f"{sf_name} -> {material}")
            continue

        fill = bool(info.get("fill", False))

        weight = info.get("weight")
        if isinstance(weight, bool):  # JSON true/false is not a weight
            weight = None
        elif isinstance(weight, (int, float)):
            weight = max(WEIGHT_MIN, min(WEIGHT_MAX, int(weight)))
            if weight == 400:  # the default carries no information
                weight = None
        else:
            weight = None

        entries.append(Entry(sf_name, codepoint, fill, weight))
        stats.emitted += 1
        if fill:
            stats.with_fill += 1
        if weight is not None:
            stats.with_weight += 1

    entries.sort(key=lambda e: e.sf_name)
    return entries, stats, unresolved_samples


def parse_aliases(data: bytes) -> dict[str, str]:
    """Parse macOS's name_aliases.strings (a property list of old SF name -> new
    SF name) into a dict. Non-string pairs and keys with capital letters (placeholder
    names for unannounced products) are skipped. Raises ValueError when the data is
    not a property list holding a dictionary. Pure."""
    try:
        plist = plistlib.loads(data)
    except (plistlib.InvalidFileException, xml.parsers.expat.ExpatError) as e:
        raise ValueError(f"not a property list: {e}") from e
    if not isinstance(plist, dict):
        raise ValueError("the property list is not a dictionary")
    return {
        old: new
        for old, new in plist.items()
        if isinstance(old, str) and isinstance(new, str) and old == old.lower()
    }


def add_alias_entries(entries: list[Entry], aliases: dict[str, str]) -> tuple[list[Entry], int]:
    """Add rows across renames, in both directions, with the same codepoint and axes:
      * an old SF name gets its current name's row (the mapping lists current
        names, documents may use old ones);
      * a current name without a row gets its old name's row (macOS can be newer
        than the SF Symbols release the mapping was made from), unless its old
        names have rows that differ.
    A name with its own row keeps it. An alias may name another alias (followed
    until a name with a row, a name without one, or a loop). Returns the sorted
    entries and the number added. Pure."""
    by_name = {e.sf_name: e for e in entries}
    current_of: dict[str, str] = {}
    olds_by_current: dict[str, list[str]] = {}
    for old, new in aliases.items():
        seen = {old}
        while new not in by_name and new in aliases and new not in seen:
            seen.add(new)
            new = aliases[new]
        current_of[old] = new
        olds_by_current.setdefault(new, []).append(old)

    added: list[Entry] = []
    # Current names first, so that an old name without a row can then take a row
    # its current name has only through a sibling old name.
    for current, olds in olds_by_current.items():
        if current in by_name:
            continue
        rows = {(by_name[o].codepoint, by_name[o].fill, by_name[o].weight) for o in olds if o in by_name}
        if len(rows) != 1:
            continue
        codepoint, fill, weight = rows.pop()
        added.append(Entry(current, codepoint, fill, weight))
    by_name.update((e.sf_name, e) for e in added)
    for old, current in current_of.items():
        target = by_name.get(current)
        if old in by_name or target is None:
            continue
        entry = Entry(old, target.codepoint, target.fill, target.weight)
        added.append(entry)
        by_name[old] = entry
    result = entries + added
    result.sort(key=lambda e: e.sf_name)
    return result, len(added)


def format_lines(entries: list[Entry]) -> list[str]:
    """Render [Entry] rows to the embedded table's text lines (no trailing newline).

    Axis overrides are bare integers after the codepoint, disambiguated by range
    (no prefix): FILL is only ever 1, weight is 100..700 - disjoint sets, so the
    reader identifies each by value. Emitted fill-before-weight for stable diffs."""
    lines: list[str] = []
    for e in entries:
        line = f"{e.sf_name} {e.codepoint:x}"
        if e.fill:
            line += " 1"
        if e.weight is not None:
            line += f" {e.weight}"
        lines.append(line)
    return lines


def _report(stats: Stats, unresolved: list[str], min_score: int) -> str:
    lines = [
        "build_sf_material_map:",
        f"  source rows         : {stats.total}",
        f"  emitted             : {stats.emitted}",
        f"    with FILL 1       : {stats.with_fill}",
        f"    with weight       : {stats.with_weight}",
        f"  skipped (no match)  : {stats.skipped_no_material}",
        f"  skipped (score<{min_score:<3}) : {stats.skipped_below_score}",
        f"  skipped (unresolved): {stats.skipped_unresolved}",
    ]
    if unresolved:
        lines.append("  unresolved Material names (font release mismatch?), sample:")
        for s in unresolved:
            lines.append(f"    {s}")
    return "\n".join(lines)


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="Compile the SF->Material embedded map.")
    ap.add_argument("--mapping", required=True, help="sf-symbols-material-map sf_to_material.json (out/sf_to_material.json)")
    ap.add_argument("--codepoints", required=True, help="MaterialSymbolsRounded.codepoints")
    ap.add_argument("--out", required=True, help="output sf_to_material.map")
    ap.add_argument("--aliases", help="macOS name_aliases.strings: add rows for old SF names")
    ap.add_argument("--min-score", type=int, default=DEFAULT_MIN_SCORE,
                    help=f"drop matches scored below this (0-100); default "
                         f"{DEFAULT_MIN_SCORE} (pass 0 to keep all)")
    args = ap.parse_args(argv)

    try:
        with open(args.mapping, encoding="utf-8") as f:
            mapping = json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        print(f"error: cannot read mapping '{args.mapping}': {e}", file=sys.stderr)
        return 2

    try:
        with open(args.codepoints, encoding="utf-8") as f:
            codepoints = parse_codepoints(f.read())
    except OSError as e:
        print(f"error: cannot read codepoints '{args.codepoints}': {e}", file=sys.stderr)
        return 2

    if not codepoints:
        print(f"error: no codepoints parsed from '{args.codepoints}'", file=sys.stderr)
        return 2

    aliases: dict[str, str] = {}
    if args.aliases is not None:
        try:
            with open(args.aliases, "rb") as f:
                aliases = parse_aliases(f.read())
        except (OSError, ValueError) as e:
            print(f"error: cannot read aliases '{args.aliases}': {e}", file=sys.stderr)
            return 2
        if not aliases:
            print(f"error: no aliases parsed from '{args.aliases}'", file=sys.stderr)
            return 2

    entries, stats, unresolved = build_entries(mapping, codepoints, args.min_score)
    entries, alias_rows = add_alias_entries(entries, aliases)

    header = (
        "# SF Symbols -> Material Symbols, compiled by Tools/material_symbols/"
        "build_sf_material_map.py\n"
        "# Format: <sf_name> <codepoint_hex> [<fill>] [<weight>] - trailing integers\n"
        "# are axis overrides by range: 1 => FILL 1, 100..700 => wght.\n"
    )
    if args.aliases is not None:
        header += "# Renamed SF Symbols (macOS name_aliases.strings) have rows for old and new names.\n"
    header += (
        "# Generated artifact - do not edit by hand; regenerate from the sf-symbols-material-map "
        "mapping.\n"
    )
    body = "\n".join(format_lines(entries))
    try:
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(header)
            f.write(body)
            f.write("\n")
    except OSError as e:
        print(f"error: cannot write '{args.out}': {e}", file=sys.stderr)
        return 2

    print(_report(stats, unresolved, args.min_score))
    if args.aliases is not None:
        print(f"  renamed-name rows   : {alias_rows} (from {len(aliases)} aliases)")
    print(f"  wrote               : {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
