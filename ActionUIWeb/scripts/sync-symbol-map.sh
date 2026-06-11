#!/bin/sh
# sync-symbol-map.sh — place the SF→Material map into ActionUIWeb/assets/.
#
# The map (sf_to_material.map) is a generated artifact, not authored by hand.
# Its generator, Tools/material_symbols/build_sf_material_map.py, needs two
# inputs that do not live in this repo (the external sf-symbols-material-map
# repo's sf_to_material.json, plus the Material Symbols .codepoints table that
# Android fetches at build time). So rather than regenerate here, the web port
# reuses the already-generated map that ActionUIAndroid commits — both platforms
# then resolve `systemName` against an identical table.
#
# This copies that canonical Android map into ActionUIWeb/assets/symbols/,
# validating it first. Plain POSIX sh on purpose: a one-file copy should not add
# a Node/Python runtime dependency to a project that otherwise has none.
#
# Usage:
#   sh scripts/sync-symbol-map.sh                 # copy from the sibling ActionUIAndroid
#   sh scripts/sync-symbol-map.sh /path/to/sf_to_material.map
#   ACTIONUI_ANDROID=/path/to/ActionUIAndroid sh scripts/sync-symbol-map.sh
#
# Exit codes: 0 success; 2 bad/unreadable source (mirrors the generator).

set -eu

# Resolve paths relative to this script, so it works from any cwd.
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
web_root=$(cd -- "$script_dir/.." && pwd)
repo_root=$(cd -- "$web_root/.." && pwd)

rel_map="library/src/main/assets/symbols/sf_to_material.map"
dest="$web_root/assets/symbols/sf_to_material.map"
header_marker="# SF Symbols -> Material Symbols" # first line of the generated map

# Source precedence: positional arg, then $ACTIONUI_ANDROID, then the sibling
# ActionUIAndroid checkout next to this repo's ActionUIWeb.
if [ "$#" -ge 1 ]; then
    source=$1
else
    android_root=${ACTIONUI_ANDROID:-"$repo_root/ActionUIAndroid"}
    source="$android_root/$rel_map"
fi

if [ ! -r "$source" ]; then
    echo "error: cannot read source map '$source'" >&2
    echo "  Pass a path argument or set ACTIONUI_ANDROID to your ActionUIAndroid checkout." >&2
    exit 2
fi

# Sanity-check it really is the generated map, not some other file.
first_line=$(head -n 1 "$source")
case "$first_line" in
    "$header_marker"*) : ;;
    *)
        echo "error: '$source' does not look like the generated SF→Material map" >&2
        echo "  (expected first line to start with \"$header_marker\")." >&2
        exit 2
        ;;
esac

rows=$(grep -cv '^[[:space:]]*\(#.*\)\?$' "$source" || true)
if [ "$rows" -eq 0 ]; then
    echo "error: '$source' contains no symbol rows." >&2
    exit 2
fi

mkdir -p "$(dirname -- "$dest")"
cp -- "$source" "$dest"

echo "Placed SF→Material map:"
echo "  source : $source"
echo "  dest   : $dest"
echo "  rows   : $rows symbols ($(wc -c < "$dest" | tr -d ' ') bytes)"
