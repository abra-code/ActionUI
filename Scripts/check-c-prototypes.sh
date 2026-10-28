#!/bin/bash
#
# Scripts/check-c-prototypes.sh - checks that every C function the Swift adapters export with
# @c has a prototype in its plain C header, and every prototype there has a function. Fails too
# when a Swift file there still uses @_cdecl, whose declarations plain C cannot see in the
# generated header.
#
# Pairs checked (Swift folder -> header):
#   ActionUICAdapter            -> ActionUICAdapter/include/ActionUIC.h
#   ActionUIAppKitApplication   -> ActionUIAppKitApplication/include/ActionUIApp.h
#   ActionUIAdwaitaApplication  -> ActionUIAppKitApplication/include/ActionUIApp.h (Linux, same header)
#
# With --generated-headers, also compiles the HeaderCheck/*.c files against the Swift-generated
# headers in DIR (a build's folder holding ActionUICAdapter-Swift.h): each file includes a
# hand-written header and the generated one, so a parameter or return type that differs is a
# "conflicting types" error. The Xcode framework targets compile these files in every build; the
# option is for package builds, where SwiftPM does not give a C target a Swift target's header.
# On Linux DIR must hold ActionUIAdwaitaApplication-Swift.h too; on Apple platforms
# ActionUIAppKitApplication-Swift.h is checked when DIR has it (the package does not build it).
#
# Usage: Scripts/check-c-prototypes.sh [--generated-headers DIR]
#   The compiler is xcrun clang on Apple platforms, else $CC (an absolute path), else /usr/bin/cc.
# Exit status: 0 passed, 1 a function and its prototype disagree, 2 a file is missing,
# 64 bad arguments.

script_dir="$(CDPATH= cd "$(/usr/bin/dirname "$0")" && pwd)"
repo="$(/usr/bin/dirname "$script_dir")"

generated=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --generated-headers)
            if [ "$#" -lt 2 ] || [ -z "$2" ]; then
                printf 'check-c-prototypes: --generated-headers needs a folder\n' >&2
                exit 64
            fi
            generated="$2"
            shift 2
            ;;
        *)
            printf 'check-c-prototypes: unknown argument %s\nusage: %s [--generated-headers DIR]\n' "$1" "$0" >&2
            exit 64
            ;;
    esac
done
if [ -n "$generated" ] && [ ! -d "$generated" ]; then
    printf 'check-c-prototypes: no folder %s\n' "$generated" >&2
    exit 2
fi

work="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/check-c-prototypes.XXXXXX")"
status=$?
if [ "$status" -ne 0 ] || [ -z "$work" ]; then
    printf 'check-c-prototypes: could not create a temporary folder\n' >&2
    exit 2
fi

# Compares the @c names in the Swift files of folder $1 with the function names declared in
# header $2. Prints each name found on one side only, and each file still using @_cdecl.
# Returns 0 when the two lists agree.
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
    # One name per line: the name in @c(name), or for a bare @c the name of the function that
    # follows, on the same line or the next. find -exec, not xargs, so a repository path with
    # spaces in it works.
    /usr/bin/find "$_folder" -maxdepth 1 -name '*.swift' -exec /usr/bin/sed -n \
        -e 's/^[[:space:]]*@c(\([A-Za-z0-9_]*\)).*/\1/p' \
        -e 's/^[[:space:]]*@c[[:space:]][^(]*func \([A-Za-z0-9_]*\).*/\1/p' \
        -e '/^[[:space:]]*@c[[:space:]]*$/{n;s/.*func \([A-Za-z0-9_]*\).*/\1/p;}' \
        {} + | /usr/bin/sort -u > "$_exported"
    if [ ! -s "$_exported" ]; then
        printf 'check-c-prototypes: no @c functions found in the Swift files of %s\n' "$_folder" >&2
        return 2
    fi
    # One name per line: the function name of each prototype, a line starting with a return type.
    /usr/bin/sed -n 's/^[a-z][A-Za-z0-9_ *]*[ *]\(actionUI[A-Za-z0-9_]*\)(.*/\1/p' "$_header" | /usr/bin/sort -u > "$_declared"
    local _missing="$(/usr/bin/comm -23 "$_exported" "$_declared")"
    local _extra="$(/usr/bin/comm -13 "$_exported" "$_declared")"
    local _legacy="$(/usr/bin/find "$_folder" -maxdepth 1 -name '*.swift' -exec /usr/bin/grep -l '^[[:space:]]*@_cdecl' {} +)"
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
    if [ -n "$_legacy" ]; then
        printf 'check-c-prototypes: these files export with @_cdecl, which the generated header hides from plain C; use @c:\n%s\n' "$_legacy" >&2
        _status=1
    fi
    if [ "$_status" -eq 0 ]; then
        printf 'check-c-prototypes: %s: %s functions, each with a prototype\n' "$1" "$_count"
    fi
    return "$_status"
}

# Compiles header-check file $1 (relative to the repository) as plain C against the generated
# headers, after checking that generated header $2 declares functions for plain C at all (if it
# declared none, the check file would compile with nothing compared). Prints the compiler's
# output when it fails. Returns 0 when it compiles.
compile_check() {
    local _source="$repo/$1"
    local _includes=(-I "$repo/ActionUICAdapter/include" -I "$repo/ActionUIAppKitApplication/include" -I "$generated")
    # The generated header alone, preprocessed as plain C with the hand-written headers' include
    # guards defined, so every actionUI prototype left is one the generated header declares.
    local _visible="$("${compiler[@]}" -x c -E -P -DActionUIC_h -DActionUIApp_h -DActionUICAdapter_h \
        -DActionUIAppKitApplication_h "${_includes[@]}" "$generated/$2" 2> "$work/preprocess.err" \
        | /usr/bin/grep -o 'actionUI[A-Za-z0-9_]*(' | /usr/bin/sort -u | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
    if [ "${_visible:-0}" -eq 0 ]; then
        printf 'check-c-prototypes: %s declares no functions for plain C (built before the switch to @c?)\n' "$generated/$2" >&2
        /bin/cat "$work/preprocess.err" >&2
        return 1
    fi
    local _output
    _output="$("${compiler[@]}" -x c -std=c17 -Wall -Wextra -fsyntax-only "${_includes[@]}" "$_source" 2>&1)"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        printf 'check-c-prototypes: %s does not compile against %s:\n%s\n' "$1" "$generated" "$_output" >&2
        return 1
    fi
    printf 'check-c-prototypes: %s: %s functions declared in both headers, and the declarations agree\n' "$1" "$_visible"
    return 0
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

if [ -n "$generated" ]; then
    system="$(/usr/bin/uname -s)"
    if [ "$system" = Darwin ]; then
        compiler=(/usr/bin/xcrun clang)
        app_header=ActionUIAppKitApplication-Swift.h
    else
        compiler=("${CC:-/usr/bin/cc}")
        app_header=ActionUIAdwaitaApplication-Swift.h
    fi
    if [ ! -f "$generated/ActionUICAdapter-Swift.h" ]; then
        printf 'check-c-prototypes: no ActionUICAdapter-Swift.h in %s\n' "$generated" >&2
        result=2
    else
        compile_check ActionUICAdapter/HeaderCheck/ActionUICHeaderCheck.c ActionUICAdapter-Swift.h
        status=$?
        if [ "$status" -gt "$result" ]; then
            result=$status
        fi
    fi
    if [ -f "$generated/$app_header" ]; then
        compile_check ActionUIAppKitApplication/HeaderCheck/ActionUIAppHeaderCheck.c "$app_header"
        status=$?
        if [ "$status" -gt "$result" ]; then
            result=$status
        fi
    elif [ "$system" = Darwin ]; then
        printf 'check-c-prototypes: no %s in %s; the Xcode framework target checks ActionUIApp.h\n' "$app_header" "$generated"
    else
        printf 'check-c-prototypes: no %s in %s\n' "$app_header" "$generated" >&2
        result=2
    fi
fi

/bin/rm -rf "${work:?}"
if [ "$result" -ne 0 ]; then
    printf 'check-c-prototypes: FAILED\n' >&2
fi
exit "$result"
