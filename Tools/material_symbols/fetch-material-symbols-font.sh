#!/bin/bash
# fetch-material-symbols-font.sh - download the Material Symbols Rounded variable font and its
# codepoints table at one pinned commit of google/material-design-icons, and check both against
# their SHA-256 sums.
#
# The Linux build draws its symbol icons from this font (ActionUISymbolIcons), so the icons depend
# on the font's exact outlines: a pinned commit and checked sums keep every build drawing the same
# icons, where Google's master changes every week or two.
#
# Usage:
#   bash fetch-material-symbols-font.sh [FOLDER]
#
# FOLDER defaults to Tools/material_symbols/font (gitignored). Files already there with the right
# sums are kept. To move to a newer font: change COMMIT and the three sums below and run this
# script; copy its MaterialSymbolsRounded.codepoints over ActionUIAndroid's
# library/src/main/assets/symbols/MaterialSymbolsRounded.codepoints, which regen-symbol-map.sh reads;
# regenerate the map so its codepoints match the font; and check the icons.
#
# License: Apache 2.0 (github.com/google/material-design-icons/blob/master/LICENSE), which is
# downloaded alongside.
#
# Exit codes: 0 the files are in place; 1 a download or check failed.

COMMIT="10ecc14790612ca8fd164e3f4ffe9c16fc50d5b7"   # "Update Symbols", 2026-10-23
FONT_SHA256="7e74e36533ccee12c2b81e75bfcf3ccf123d3bb7e7e46d65d94445f23db0c97c"
CODEPOINTS_SHA256="a7404d9e5a1b63f496cf05ace45d386075886b5a7f123fba9f29527cb6006fde"
LICENSE_SHA256="58d1e17ffe5109a7ae296caafcadfdbe6a7d176f0bc4ab01e12a689b0499d8bd"

BASE_URL="https://raw.githubusercontent.com/google/material-design-icons/$COMMIT"
FONT_PATH="variablefont/MaterialSymbolsRounded%5BFILL,GRAD,opsz,wght%5D"

script_dir="$(cd "$(/usr/bin/dirname "$0")" && pwd)"
dest="${1:-$script_dir/font}"

# The SHA-256 of a file, or nothing when it cannot be read. macOS has shasum, Linux sha256sum.
sha256_of() {
    local _file="$1"
    local _line
    if [ -x /usr/bin/sha256sum ]; then
        _line="$(/usr/bin/sha256sum "$_file" 2>/dev/null)"
    else
        _line="$(/usr/bin/shasum -a 256 "$_file" 2>/dev/null)"
    fi
    printf '%s' "${_line%% *}"
}

# Downloads URL to FOLDER/NAME unless a file with the expected sum is there already.
fetch() {
    local _url="$1"
    local _name="$2"
    local _expected="$3"
    local _target="$dest/$_name"
    local _sum
    _sum="$(sha256_of "$_target")"
    if [ "$_sum" = "$_expected" ]; then
        printf 'kept       %s\n' "$_target"
        return 0
    fi
    local _partial="$_target.partial"
    /usr/bin/curl --fail --silent --show-error --location --output "$_partial" "$_url"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        printf 'error: downloading %s failed (curl exit %d)\n' "$_url" "$_status" >&2
        /bin/rm -f "$_partial"
        return 1
    fi
    _sum="$(sha256_of "$_partial")"
    if [ "$_sum" != "$_expected" ]; then
        printf 'error: %s has SHA-256 %s, expected %s\n' "$_url" "$_sum" "$_expected" >&2
        /bin/rm -f "$_partial"
        return 1
    fi
    /bin/mv -f "$_partial" "$_target"
    _status=$?
    if [ "$_status" -ne 0 ]; then
        printf 'error: cannot move the download to %s\n' "$_target" >&2
        return 1
    fi
    printf 'downloaded %s\n' "$_target"
    return 0
}

/bin/mkdir -p "$dest"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'error: cannot create %s\n' "$dest" >&2
    exit 1
fi

fetch "$BASE_URL/$FONT_PATH.ttf" "MaterialSymbolsRounded.ttf" "$FONT_SHA256" || exit 1
fetch "$BASE_URL/$FONT_PATH.codepoints" "MaterialSymbolsRounded.codepoints" "$CODEPOINTS_SHA256" || exit 1
fetch "$BASE_URL/LICENSE" "LICENSE" "$LICENSE_SHA256" || exit 1
exit 0
