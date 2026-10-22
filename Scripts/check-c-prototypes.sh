#!/bin/bash
#
# Scripts/check-c-prototypes.sh - checks that every C function the Swift adapters export with
# @_cdecl has a prototype in its plain C header, and every prototype there has a function.
#
# Pairs checked (Swift folder -> header):
#   ActionUICAdapter            -> ActionUICAdapter/include/ActionUIC.h
#   ActionUIAppKitApplication   -> ActionUIAppKitApplication/include/ActionUIApp.h
#   ActionUIAdwaitaApplication  -> ActionUIAppKitApplication/include/ActionUIApp.h (Linux, same header)
#
# Usage: Scripts/check-c-prototypes.sh
# Exit status: 0 passed, 1 a function and its prototype disagree, 2 a file is missing,
# 64 bad arguments.

script_dir="$(CDPATH= cd "$(/usr/bin/dirname "$0")" && pwd)"
repo="$(/usr/bin/dirname "$script_dir")"

if [ "$#" -ne 0 ]; then
    printf 'check-c-prototypes: unknown argument %s\nusage: %s\n' "$1" "$0" >&2
    exit 64
fi

work="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/check-c-prototypes.XXXXXX")"
status=$?
if [ "$status" -ne 0 ] || [ -z "$work" ]; then
    printf 'check-c-prototypes: could not create a temporary folder\n' >&2
    exit 2
fi

# Compares the @_cdecl names in the Swift files of folder $1 with the function names declared in
# header $2. Prints each name found on one side only. Returns 0 when the two lists agree.
check_pair() {
    local _folder="$repo/$1"
    local _header="$repo/$2"
    local _label="$1"
    if [ ! -d "$_folder" ] || [ ! -f "$_header" ]; then
        printf 'check-c-prototypes: missing %s or %s\n' "$_folder" "$_header" >&2
        return 2
    fi
    local _exported="$work/$_label.exported"
    local _declared="$work/$_label.declared"
    # One name per line: the "name" of each @_cdecl("name") that starts a line, indented or not.
    # find -exec, not xargs, so a repository path with spaces in it works.
    /usr/bin/find "$_folder" -maxdepth 1 -name '*.swift' -exec /usr/bin/sed -n 's/^[[:space:]]*@_cdecl("\([A-Za-z0-9_]*\)").*/\1/p' {} + | /usr/bin/sort -u > "$_exported"
    if [ ! -s "$_exported" ]; then
        printf 'check-c-prototypes: no @_cdecl functions found in the Swift files of %s\n' "$_folder" >&2
        return 2
    fi
    # One name per line: the function name of each prototype, a line starting with a return type.
    /usr/bin/sed -n 's/^[a-z][A-Za-z0-9_ *]*[ *]\(actionUI[A-Za-z0-9_]*\)(.*/\1/p' "$_header" | /usr/bin/sort -u > "$_declared"
    local _missing="$(/usr/bin/comm -23 "$_exported" "$_declared")"
    local _extra="$(/usr/bin/comm -13 "$_exported" "$_declared")"
    local _count="$(/usr/bin/wc -l < "$_exported" | /usr/bin/tr -d ' ')"
    local _status=0
    if [ -n "$_missing" ]; then
        printf 'check-c-prototypes: %s exports functions with no prototype in %s:\n%s\n' "$1" "$2" "$_missing" >&2
        _status=1
    fi
    if [ -n "$_extra" ]; then
        printf 'check-c-prototypes: %s declares functions that %s does not export:\n%s\n' "$2" "$1" "$_extra" >&2
        _status=1
    fi
    if [ "$_status" -eq 0 ]; then
        printf 'check-c-prototypes: %s: %s functions, each with a prototype\n' "$1" "$_count"
    fi
    return "$_status"
}

result=0
check_pair ActionUICAdapter ActionUICAdapter/include/ActionUIC.h
status=$?
if [ "$status" -gt "$result" ]; then
    result=$status
fi
check_pair ActionUIAppKitApplication ActionUIAppKitApplication/include/ActionUIApp.h
status=$?
if [ "$status" -gt "$result" ]; then
    result=$status
fi
check_pair ActionUIAdwaitaApplication ActionUIAppKitApplication/include/ActionUIApp.h
status=$?
if [ "$status" -gt "$result" ]; then
    result=$status
fi

/bin/rm -rf "${work:?}"
if [ "$result" -ne 0 ]; then
    printf 'check-c-prototypes: FAILED\n' >&2
fi
exit "$result"
