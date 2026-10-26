#!/bin/bash
# Copies RichText's markdown parser into the Linux renderer, or checks that the copy is current.
#
# The Linux renderer shows a Text's markdown with the parser of the RichText package
# (github.com/abra-code/RichText): its document model, its parser and its URL autolinker, which use
# the Swift standard library only. They are copied rather than depended on, so the Linux build has no
# package dependency and builds offline. The copies differ from RichText's files only in a first line
# naming this script and in having no `public`, so the types stay internal to ActionUI.
#
# Usage: Scripts/sync-richtext-markdown.sh [--check] [RICHTEXT_DIR]
#   RICHTEXT_DIR  the RichText checkout; default: RichText beside this repository
#   --check       compare only; exit 1 and name the stale files when a copy differs
# Edit the parser in RichText, then run this script; never edit the copies.

script_dir="$(cd "$(/usr/bin/dirname "$0")" && pwd)"
repo="$(/usr/bin/dirname "$script_dir")"
destination="$repo/ActionUIAdwaita/Sources/Markdown/RichText"

check=0
richtext=""
for argument in "$@"; do
    case "$argument" in
        --check) check=1 ;;
        -h|--help)
            /usr/bin/sed -n '2,13p' "$0"
            exit 0
            ;;
        *) richtext="$argument" ;;
    esac
done
if [ -z "$richtext" ]; then
    richtext="$(/usr/bin/dirname "$repo")/RichText"
fi
if [ ! -d "$richtext/Sources/RichText" ]; then
    printf 'error: no RichText checkout at %s; pass its path as an argument\n' "$richtext" >&2
    exit 2
fi

files="Markdown/RichTextMarkdownParser.swift Markdown/RichTextAutolinker.swift Model/RichTextModel.swift"

work="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/sync-richtext-markdown.XXXXXX")"
status=$?
if [ "$status" -ne 0 ] || [ -z "$work" ]; then
    printf 'error: cannot create a temporary folder\n' >&2
    exit 2
fi

stale=0
for file in $files; do
    name="$(/usr/bin/basename "$file")"
    source="$richtext/Sources/RichText/$file"
    if [ ! -f "$source" ]; then
        printf 'error: %s is missing\n' "$source" >&2
        /bin/rm -rf "$work"
        exit 2
    fi
    {
        printf '// Copied from the RichText package by Scripts/sync-richtext-markdown.sh: edit it there.\n'
        /usr/bin/sed -E 's/^([[:space:]]*)public /\1/' "$source"
    } > "$work/$name"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'error: cannot convert %s\n' "$source" >&2
        /bin/rm -rf "$work"
        exit 2
    fi
    /usr/bin/cmp -s "$work/$name" "$destination/$name"
    same=$?
    if [ "$same" -eq 0 ]; then
        continue
    fi
    if [ "$check" -eq 1 ]; then
        printf 'stale: %s differs from %s\n' "$destination/$name" "$source"
        stale=1
        continue
    fi
    /bin/mkdir -p "$destination"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'error: cannot create %s\n' "$destination" >&2
        /bin/rm -rf "$work"
        exit 2
    fi
    /bin/cp "$work/$name" "$destination/$name"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'error: cannot write %s\n' "$destination/$name" >&2
        /bin/rm -rf "$work"
        exit 2
    fi
    printf 'updated: %s\n' "$destination/$name"
done
/bin/rm -rf "$work"

if [ "$stale" -eq 1 ]; then
    printf 'Run Scripts/sync-richtext-markdown.sh to update the copies.\n'
    exit 1
fi
exit 0
