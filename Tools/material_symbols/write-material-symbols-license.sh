#!/bin/bash
# write-material-symbols-license.sh - write the license notice for the Material Symbols icons that
# a Linux build of ActionUI carries (Scripts/prepare-linux-symbols.sh generates them into ActionUI,
# and so into every program that links ActionUI): a paragraph saying what the icons are,
# from which release, and that they were converted, then the Apache License 2.0 text of that
# release, which fetch-material-symbols-font.sh downloads with the font.
#
# Usage:
#   bash write-material-symbols-license.sh OUTPUT [FONT FOLDER]
#
# FONT FOLDER defaults to Tools/material_symbols/font, the folder the build draws the icons from.
# Exit codes: 0 written; 1 the font folder lacks its LICENSE or COMMIT, or OUTPUT cannot be written;
# 64 bad arguments.

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    printf 'usage: %s OUTPUT [FONT FOLDER]\n' "$0" >&2
    exit 64
fi
output="$1"
script_dir="$(cd "$(/usr/bin/dirname "$0")" && pwd)"
font_folder="${2:-$script_dir/font}"

if [ ! -r "$font_folder/LICENSE" ] || [ ! -r "$font_folder/COMMIT" ]; then
    printf 'error: %s has no LICENSE or COMMIT; run bash %s/fetch-material-symbols-font.sh %s\n' "$font_folder" "$script_dir" "$font_folder" >&2
    exit 1
fi
read -r commit < "$font_folder/COMMIT"
case "$commit" in
    *[!0-9a-f]*|"")
        printf 'error: %s/COMMIT does not hold a commit hash\n' "$font_folder" >&2
        exit 1
        ;;
esac

{
    printf 'Material Symbols\n\n'
    printf 'The symbol icons in this software are glyphs of the Material Symbols Rounded font by Google\n'
    printf '(https://github.com/google/material-design-icons, commit %s),\n' "$commit"
    printf 'converted to SVG icons when the software was built. They are used under the Apache License 2.0:\n\n'
    /bin/cat "$font_folder/LICENSE"
} > "$output"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'error: cannot write %s\n' "$output" >&2
    exit 1
fi
exit 0
