#!/bin/sh
# regen-symbol-map.sh - regenerate the SF->Material map from the origin mapping.
#
# This is the UPSTREAM half of the symbol-map pipeline; ActionUIWeb's
# scripts/sync-symbol-map.sh is the downstream half. The full pipeline:
#
#   sf-symbols-material-map/out/sf_to_material.json   (origin: Material names + scores)
#         |  build_sf_material_map.py  (resolve name->codepoint, drop score<min,
#         |                             add rows for old SF names from macOS's aliases)
#         v
#   ActionUIAndroid/.../symbols/sf_to_material.map    (committed: codepoints)
#         |  ActionUIWeb/scripts/sync-symbol-map.sh   (copy + validate)
#         v
#   ActionUIWeb/assets/symbols/sf_to_material.map
#
# build_sf_material_map.py (next to this script) needs three paths: the origin
# JSON, the Material .codepoints table, and the output .map. Remembering all three
# by hand is what this wrapper removes - it fills in the conventional locations
# (origin repo as a sibling of ActionUI; codepoints/out in the Android assets) and
# then refreshes the web copy too, so one command takes a fresh origin JSON all the
# way to both committed maps.
#
# Usage:
#   sh regen-symbol-map.sh                         # sibling sf-symbols-material-map
#   sh regen-symbol-map.sh /path/to/sf_to_material.json
#   SF_MATERIAL_MAP_JSON=/path/to.json sh regen-symbol-map.sh
#   ACTIONUI_ANDROID=/path/to/ActionUIAndroid sh regen-symbol-map.sh
#   sh regen-symbol-map.sh --min-score 0           # keep the full lower-confidence tail
#   sh regen-symbol-map.sh --no-web-sync           # regenerate the Android map only
#
# The old-name rows need macOS's alias table (CoreGlyphs.bundle's
# name_aliases.strings), so a regeneration elsewhere stops unless given --aliases
# PATH (a copy of that file) or --no-aliases (a map without the old names).
#
# Exit codes: 0 success; 2 bad/unreadable input (mirrors the generator).

set -eu

usage() {
    cat <<'EOF'
regen-symbol-map.sh - regenerate the SF->Material symbol map from the origin mapping.

Usage:
  sh regen-symbol-map.sh [OPTIONS] [ORIGIN_JSON]

Arguments:
  ORIGIN_JSON        Path to sf_to_material.json. Defaults to $SF_MATERIAL_MAP_JSON,
                     then the sibling sf-symbols-material-map/out/sf_to_material.json.

Options:
  --min-score N      Drop mappings scoring below N (default: the generator's floor, 60).
                     Use 0 to keep the full lower-confidence tail.
  --no-web-sync      Regenerate the Android map only; skip the ActionUIWeb copy.
  --aliases PATH     macOS's name_aliases.strings (old SF name -> current name).
                     Default: the one in /System/Library/CoreServices/CoreGlyphs.bundle.
  --no-aliases       Leave out the rows for old SF names.
  -h, --help         Show this help.

Environment:
  SF_MATERIAL_MAP_JSON   Origin JSON path (overridden by a positional argument).
  ACTIONUI_ANDROID       ActionUIAndroid checkout (for codepoints + output map).

Exit codes: 0 success; 2 bad/unreadable input.
EOF
}

# Resolve paths relative to this script, so it works from any cwd.
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(cd -- "$script_dir/../.." && pwd)
parent_root=$(cd -- "$repo_root/.." && pwd)

generator="$script_dir/build_sf_material_map.py"
rel_codepoints="library/src/main/assets/symbols/MaterialSymbolsRounded.codepoints"
rel_map="library/src/main/assets/symbols/sf_to_material.map"
web_sync="$repo_root/ActionUIWeb/scripts/sync-symbol-map.sh"

# Defaults; overridable by flags / env (parsed below).
min_score=""        # empty => let the generator apply its default floor (60)
do_web_sync=1
origin=""
aliases="/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/name_aliases.strings"
use_aliases=1

while [ "$#" -ge 1 ]; do
    case "$1" in
        --min-score)
            [ "$#" -ge 2 ] || { echo "error: --min-score needs a value" >&2; exit 2; }
            min_score=$2; shift 2 ;;
        --min-score=*)
            min_score=${1#*=}; shift ;;
        --no-web-sync)
            do_web_sync=0; shift ;;
        --aliases)
            [ "$#" -ge 2 ] || { echo "error: --aliases needs a path" >&2; exit 2; }
            aliases=$2; shift 2 ;;
        --aliases=*)
            aliases=${1#*=}; shift ;;
        --no-aliases)
            use_aliases=0; shift ;;
        -h|--help)
            usage; exit 0 ;;
        --)
            shift; break ;;
        -*)
            echo "error: unknown option '$1'" >&2; exit 2 ;;
        *)
            origin=$1; shift ;;
    esac
done

# Origin JSON source precedence: positional arg, then $SF_MATERIAL_MAP_JSON, then
# the sibling sf-symbols-material-map checkout next to this repo.
if [ -z "$origin" ]; then
    origin=${SF_MATERIAL_MAP_JSON:-"$parent_root/sf-symbols-material-map/out/sf_to_material.json"}
fi

android_root=${ACTIONUI_ANDROID:-"$repo_root/ActionUIAndroid"}
codepoints="$android_root/$rel_codepoints"
out="$android_root/$rel_map"

if [ ! -r "$generator" ]; then
    echo "error: cannot find generator '$generator'" >&2
    exit 2
fi
if [ ! -r "$origin" ]; then
    echo "error: cannot read origin mapping '$origin'" >&2
    echo "  Pass a path argument, set SF_MATERIAL_MAP_JSON, or place the" >&2
    echo "  sf-symbols-material-map repo next to ActionUI." >&2
    exit 2
fi
if [ ! -r "$codepoints" ]; then
    echo "error: cannot read codepoints '$codepoints'" >&2
    echo "  Set ACTIONUI_ANDROID to your ActionUIAndroid checkout." >&2
    exit 2
fi
if [ "$use_aliases" -eq 1 ] && [ ! -r "$aliases" ]; then
    echo "error: cannot read SF name aliases '$aliases'" >&2
    echo "  Regenerate on macOS, pass --aliases with a copy of name_aliases.strings," >&2
    echo "  or --no-aliases to leave out the old SF names." >&2
    exit 2
fi

echo "Regenerating SF->Material map:"
echo "  origin     : $origin"
echo "  codepoints : $codepoints"
if [ "$use_aliases" -eq 1 ]; then
    echo "  aliases    : $aliases"
fi
echo "  out        : $out"
echo

set -- --mapping "$origin" --codepoints "$codepoints" --out "$out"
if [ "$use_aliases" -eq 1 ]; then
    set -- "$@" --aliases "$aliases"
fi
if [ -n "$min_score" ]; then
    set -- "$@" --min-score "$min_score"
fi
python3 "$generator" "$@"

if [ "$do_web_sync" -eq 1 ] && [ -x "$web_sync" ]; then
    echo
    echo "Syncing the regenerated map into ActionUIWeb..."
    sh "$web_sync" "$out"
elif [ "$do_web_sync" -eq 1 ]; then
    echo
    echo "note: web sync skipped ('$web_sync' not found/executable);"
    echo "      run it yourself to refresh ActionUIWeb/assets/symbols/."
fi
