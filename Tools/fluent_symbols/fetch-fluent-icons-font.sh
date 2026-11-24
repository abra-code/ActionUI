#!/bin/bash
# fetch-fluent-icons-font.sh - download the Fluent System Icons font (the Resizable family) and its
# license from microsoft/fluentui-system-icons, at the commit in fluent-icons-font.commit: the commit
# sf_to_fluent.map was built for, so every codepoint the map names is the glyph it was chosen for.
# To move to a newer commit, rebuild the map with build_sf_fluent_map.py and update that file.
#
# Usage:
#   bash fetch-fluent-icons-font.sh [FOLDER]
#
# FOLDER defaults to Tools/fluent_symbols/font (gitignored). It receives FluentSystemIcons-Resizable.ttf,
# the repository's LICENSE (MIT) and COMMIT (the commit they came from, written last). A font there
# whose COMMIT is the pinned commit is kept, without a download.
#
# Exit codes: 0 the font of the pinned commit is in place; 1 a download or check failed; 64 bad arguments.

REPO_RAW="https://raw.githubusercontent.com/microsoft/fluentui-system-icons"
FONT_NAME="FluentSystemIcons-Resizable.ttf"

script_dir="$(CDPATH= cd -P -- "$(/usr/bin/dirname "$0")" && pwd)"
if [ -z "$script_dir" ]; then
    printf 'error: could not find the folder of %s\n' "$0" >&2
    exit 1
fi
if [ $# -gt 1 ]; then
    printf 'usage: %s [FOLDER]\n' "$0" >&2
    exit 64
fi
dest="${1:-$script_dir/font}"

# curl gives up on a connection that does not open in 30 s or stalls below 1 KB/s for a minute.
CURL_LIMITS="--connect-timeout 30 --speed-limit 1024 --speed-time 60"

# Prints the commit hash in file $1 when it holds one (40 lowercase hex digits).
read_commit() {
    local _line=""
    if [ -r "$1" ]; then
        read -r _line < "$1"
    fi
    case "$_line" in
        *[!0-9a-f]*|"") return 0 ;;
    esac
    if [ "${#_line}" -eq 40 ]; then
        printf '%s' "$_line"
    fi
    return 0
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

commit="$(read_commit "$script_dir/fluent-icons-font.commit")"
if [ -z "$commit" ]; then
    printf 'error: %s/fluent-icons-font.commit holds no commit hash\n' "$script_dir" >&2
    exit 1
fi
installed="$(read_commit "$dest/COMMIT")"
if [ "$installed" = "$commit" ] && [ -r "$dest/$FONT_NAME" ] && [ -r "$dest/LICENSE" ]; then
    printf 'The Fluent System Icons font of %s is in place.\n' "$commit"
    exit 0
fi

/bin/mkdir -p "$dest"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'error: cannot create %s\n' "$dest" >&2
    exit 1
fi
work="$(/usr/bin/mktemp -d "$dest/.download.XXXXXX")"
status=$?
if [ "$status" -ne 0 ] || [ -z "$work" ]; then
    printf 'error: cannot create a download folder in %s\n' "$dest" >&2
    exit 1
fi
failed=no
download "$REPO_RAW/$commit/fonts/$FONT_NAME" "$work/$FONT_NAME" || failed=yes
if [ "$failed" = no ]; then
    download "$REPO_RAW/$commit/LICENSE" "$work/LICENSE" || failed=yes
fi
if [ "$failed" = no ]; then
    # COMMIT goes first out and last in, so a folder with COMMIT always holds that commit's files.
    /bin/rm -f "$dest/COMMIT"
    /bin/mv -f "$work/$FONT_NAME" "$dest/$FONT_NAME" || failed=yes
fi
if [ "$failed" = no ]; then
    /bin/mv -f "$work/LICENSE" "$dest/LICENSE" || failed=yes
fi
if [ "$failed" = no ]; then
    printf '%s\n' "$commit" > "$dest/COMMIT" || failed=yes
fi
/bin/rm -rf "$work"
if [ "$failed" = yes ]; then
    printf 'error: the Fluent System Icons font of %s was not installed in %s\n' "$commit" "$dest" >&2
    exit 1
fi
printf 'Downloaded the Fluent System Icons font of %s into %s.\n' "$commit" "$dest"
exit 0
