#!/bin/bash
# fetch-material-symbols-font.sh - download the Material Symbols Rounded variable font from
# google/material-design-icons: the latest release when it is compatible with the committed
# codepoints table, else the last accepted one.
#
# The committed table, ActionUIAndroid/library/src/main/assets/symbols/MaterialSymbolsRounded.codepoints,
# is what sf_to_material.map was made from (regen-symbol-map.sh reads it) and what Android ships;
# ActionUIAndroid/library/material-symbols-font.commit names the upstream commit it came from.
# A release is compatible when every line of the committed table ("<name> <hex codepoint>") is in
# its table unchanged: names may only be added, so no codepoint the map uses moves or disappears.
#
#   compatible     the latest font is downloaded; when its table has new names, the committed table
#                  and the commit file are updated with them (commit both).
#   not compatible the removed and renumbered names are listed, marking those the map uses, and the
#                  font of the accepted commit is downloaded instead. To move to the new release:
#                  run again with --accept (which overwrites the committed table and the commit
#                  file), then regen-symbol-map.sh, and review the map's diff and the icons.
#
# A glyph Google redraws at the same codepoint passes the check: the check is for the mapping only.
# Android's Gradle build (fetchMaterialSymbols) follows the same rule, without editing the
# committed files.
#
# Usage:
#   bash fetch-material-symbols-font.sh [--accept] [FOLDER]
#
# FOLDER defaults to Tools/material_symbols/font (gitignored). It receives MaterialSymbolsRounded.ttf,
# the release's LICENSE (Apache 2.0), its MaterialSymbolsRounded.codepoints and COMMIT (the upstream
# commit they came from). A font there whose table keeps every line of the committed table is kept
# when it is the latest release, when the latest is not compatible, and when GitHub cannot be reached.
#
# Exit codes: 0 a font is in place (the latest, or the accepted one); 1 a download or check failed.

REPO_RAW="https://raw.githubusercontent.com/google/material-design-icons"
REPO_API="https://api.github.com/repos/google/material-design-icons"
FONT_PATH="variablefont/MaterialSymbolsRounded%5BFILL,GRAD,opsz,wght%5D"

script_dir="$(cd "$(/usr/bin/dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
android_library="$repo_root/ActionUIAndroid/library"
table="$android_library/src/main/assets/symbols/MaterialSymbolsRounded.codepoints"
map="$android_library/src/main/assets/symbols/sf_to_material.map"
accepted_file="$android_library/material-symbols-font.commit"

accept=no
dest=""
for argument in "$@"; do
    case "$argument" in
        --accept) accept=yes ;;
        -h|--help) /usr/bin/sed -n '2,31p' "$0"; exit 0 ;;
        -*) printf 'error: unknown option %s\n' "$argument" >&2; exit 1 ;;
        *)
            if [ -n "$dest" ]; then
                printf 'error: more than one FOLDER (%s, %s)\n' "$dest" "$argument" >&2
                exit 1
            fi
            dest="$argument"
            ;;
    esac
done
if [ -z "$dest" ]; then
    dest="$script_dir/font"
fi

# curl gives up on a connection that does not open in 30 s or stalls below 1 KB/s for a minute.
CURL_LIMITS="--connect-timeout 30 --speed-limit 1024 --speed-time 60"

# 0 when $1 is a full commit hash: 40 lowercase hex digits.
is_commit() {
    case "$1" in
        *[!0-9a-f]*) return 1 ;;
    esac
    [ "${#1}" -eq 40 ]
}

# Downloads URL to TARGET; prints why on failure.
download() {
    local _url="$1"
    local _target="$2"
    /usr/bin/curl --fail --silent --show-error --location $CURL_LIMITS --output "$_target" "$_url"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        printf 'error: downloading %s failed (curl exit %d)\n' "$_url" "$_status" >&2
        return 1
    fi
    return 0
}

# The lines of table OLD missing from table NEW: names removed or renumbered.
missing_lines() {
    LC_ALL=C /usr/bin/comm -23 <(LC_ALL=C /usr/bin/sort -u "$1") <(LC_ALL=C /usr/bin/sort -u "$2")
}

# The number of lines of table NEW missing from table OLD: names added.
added_count() {
    local _count="$(LC_ALL=C /usr/bin/comm -13 <(LC_ALL=C /usr/bin/sort -u "$1") <(LC_ALL=C /usr/bin/sort -u "$2") | /usr/bin/wc -l)"
    printf '%d' "$_count"
}

# Lists LINES (missing_lines output): renumbered or removed, and how many map rows use each.
report_missing() {
    local _lines="$1"
    local _new_table="$2"
    local name
    local hex
    printf '%s\n' "$_lines" | while read -r name hex; do
        if [ -z "$name" ]; then
            continue
        fi
        local _now="$(/usr/bin/grep -m 1 -E "^$name[[:space:]]" "$_new_table")"
        local _change="removed"
        if [ -n "$_now" ]; then
            _change="renumbered to ${_now##* }"
        fi
        local _rows="$(/usr/bin/grep -c -i -E "^[^[:space:]]+[[:space:]]+$hex([[:space:]]|$)" "$map")"
        local _use="not in the map"
        if [ "$_rows" -gt 0 ]; then
            _use="USED BY $_rows map rows"
        fi
        printf '  %s %s: %s, %s\n' "$name" "$hex" "$_change" "$_use"
    done
}

# 0 when a font is installed and its table keeps every line of the committed table.
installed_fits() {
    if [ -z "$installed" ] || [ ! -r "$dest/MaterialSymbolsRounded.codepoints" ]; then
        return 1
    fi
    local _missing="$(missing_lines "$table" "$dest/MaterialSymbolsRounded.codepoints")"
    [ -z "$_missing" ]
}

# Downloads the font and LICENSE of COMMIT into WORK and moves them, with TABLE_FILE (that commit's
# table, already downloaded) and COMMIT last, into dest.
install_commit() {
    local _commit="$1"
    local _work="$2"
    local _table_file="$3"
    download "$REPO_RAW/$_commit/$FONT_PATH.ttf" "$_work/MaterialSymbolsRounded.ttf" || return 1
    download "$REPO_RAW/$_commit/LICENSE" "$_work/LICENSE" || return 1
    /bin/mv -f "$_table_file" "$_work/MaterialSymbolsRounded.codepoints"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        printf 'error: cannot move %s\n' "$_table_file" >&2
        return 1
    fi
    printf '%s\n' "$_commit" > "$_work/COMMIT"
    local _name
    for _name in MaterialSymbolsRounded.ttf LICENSE MaterialSymbolsRounded.codepoints COMMIT; do
        /bin/mv -f "$_work/$_name" "$dest/$_name"
        _status=$?
        if [ "$_status" -ne 0 ]; then
            printf 'error: cannot move %s into %s\n' "$_name" "$dest" >&2
            return 1
        fi
    done
    printf 'installed the font of %s in %s\n' "$_commit" "$dest"
    return 0
}

# Copies TABLE_FILE over the committed table and records COMMIT as accepted.
record_accepted() {
    local _table_file="$1"
    local _commit="$2"
    /bin/cp -f "$_table_file" "$table"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        printf 'error: cannot update %s\n' "$table" >&2
        return 1
    fi
    printf '%s\n' "$_commit" > "$accepted_file"
    _status=$?
    if [ "$_status" -ne 0 ]; then
        printf 'error: cannot update %s\n' "$accepted_file" >&2
        return 1
    fi
    printf 'updated %s and %s: commit both\n' "$table" "$accepted_file"
    return 0
}

if [ ! -r "$table" ] || [ ! -r "$map" ] || [ ! -r "$accepted_file" ]; then
    printf 'error: the committed table, map or commit file is missing under %s\n' "$android_library" >&2
    exit 1
fi
read -r accepted < "$accepted_file"
is_commit "$accepted"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'error: %s does not hold a full commit hash\n' "$accepted_file" >&2
    exit 1
fi

/bin/mkdir -p "$dest"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'error: cannot create %s\n' "$dest" >&2
    exit 1
fi
installed=""
if [ -r "$dest/COMMIT" ] && [ -r "$dest/MaterialSymbolsRounded.ttf" ]; then
    read -r installed < "$dest/COMMIT"
fi
installed_fits
fits=$?

latest="$(/usr/bin/curl --fail --silent --show-error --location $CURL_LIMITS -H 'Accept: application/vnd.github.sha' "$REPO_API/commits/master")"
status=$?
if [ "$status" -eq 0 ]; then
    is_commit "$latest"
    status=$?
fi
if [ "$status" -ne 0 ]; then
    if [ "$fits" -eq 0 ]; then
        printf 'warning: cannot look up the latest release; kept the font of %s in %s\n' "$installed" "$dest" >&2
        exit 0
    fi
    printf 'warning: cannot look up the latest release; using the accepted commit %s\n' "$accepted" >&2
    latest="$accepted"
fi

if [ "$latest" = "$installed" ] && [ "$fits" -eq 0 ] && [ "$accept" = no ]; then
    printf 'up to date: the font of %s is in %s\n' "$installed" "$dest"
    exit 0
fi

work="$(/usr/bin/mktemp -d "$dest/.download.XXXXXX")"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'error: cannot create a download folder in %s\n' "$dest" >&2
    exit 1
fi
# The download folder goes on every exit; an interrupted download (Ctrl-C) would leave 15 MB behind.
trap '/bin/rm -rf "$work"' EXIT
trap 'exit 1' INT TERM HUP

download "$REPO_RAW/$latest/$FONT_PATH.codepoints" "$work/latest.codepoints" || exit 1
missing="$(missing_lines "$table" "$work/latest.codepoints")"
added="$(added_count "$table" "$work/latest.codepoints")"

if [ -z "$missing" ] || [ "$accept" = yes ]; then
    if [ -n "$missing" ]; then
        printf 'accepting %s, which changes these names of the committed table:\n' "$latest"
        report_missing "$missing" "$work/latest.codepoints"
    fi
    # Recorded before the font is installed: should the install fail, the next run sees a font that
    # does not fit the committed table and downloads it again.
    if [ -n "$missing" ] || [ "$added" -gt 0 ]; then
        printf '%s: %d names added\n' "$latest" "$added"
        record_accepted "$work/latest.codepoints" "$latest" || exit 1
        if [ -n "$missing" ]; then
            printf 'next: sh Tools/material_symbols/regen-symbol-map.sh, then review the map and the icons\n'
        fi
    fi
    install_commit "$latest" "$work" "$work/latest.codepoints" || exit 1
    exit 0
fi

printf 'warning: the latest release (%s) is not compatible with the committed table; these names changed:\n' "$latest" >&2
report_missing "$missing" "$work/latest.codepoints" >&2
printf 'warning: after a review, move to it with: bash %s --accept\n' "$0" >&2
if [ "$fits" -eq 0 ]; then
    printf 'kept the font of %s in %s\n' "$installed" "$dest"
    exit 0
fi
printf 'using the accepted commit %s\n' "$accepted"
download "$REPO_RAW/$accepted/$FONT_PATH.codepoints" "$work/accepted.codepoints" || exit 1
/usr/bin/cmp -s "$work/accepted.codepoints" "$table"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'error: the table of the accepted commit %s differs from %s\n' "$accepted" "$table" >&2
    exit 1
fi
install_commit "$accepted" "$work" "$work/accepted.codepoints" || exit 1
exit 0
