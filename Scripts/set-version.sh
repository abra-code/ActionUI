#!/bin/bash
#
# Scripts/set-version.sh - ActionUI's version in one place: sets it everywhere, or checks that
# every file stating it agrees.
#
# The version is ActionUIVersion.string in ActionUI/Core/Common/ActionUIVersion.swift (what
# actionUIGetVersion returns on every platform). These files state it too and are kept equal to it:
#   ActionUI.xcodeproj/project.pbxproj  MARKETING_VERSION of every target (the frameworks' and the
#                                       apps' CFBundleShortVersionString)
#   ActionUIPython/pyproject.toml       version
#   ActionUINodeJS/package.json         version, and package-lock.json's two copies of it
#   ActionUIRust/Cargo.toml             [workspace.package] version, and Cargo.lock's actionui and
#                                       actionui-sys
#   ActionUIRust/actionui/Cargo.toml    the version its actionui-sys dependency asks for (cargo
#                                       refuses the workspace when it is not met)
#   ActionUIWeb/package.json            version
# A release: Scripts/set-version.sh 0.9.1, commit, then tag the commit v0.9.1.
#
# Usage: Scripts/set-version.sh <major.minor.patch>   writes it into all of them
#        Scripts/set-version.sh --check                 lists every file that differs from
#                                                       ActionUIVersion.swift
# Exit status: 0 written or all agree, 1 a file differs or a write failed, 64 bad arguments.

usage() {
    printf 'usage: %s <major.minor.patch> | --check\n' "$0" >&2
    exit 64
}

script_dir="$(CDPATH= cd "$(/usr/bin/dirname "$0")" && pwd)"
repo="$(/usr/bin/dirname "$script_dir")"

core="$repo/ActionUI/Core/Common/ActionUIVersion.swift"
xcode="$repo/ActionUI.xcodeproj/project.pbxproj"
python="$repo/ActionUIPython/pyproject.toml"
node="$repo/ActionUINodeJS/package.json"
node_lock="$repo/ActionUINodeJS/package-lock.json"
cargo="$repo/ActionUIRust/Cargo.toml"
cargo_lock="$repo/ActionUIRust/Cargo.lock"
cargo_actionui="$repo/ActionUIRust/actionui/Cargo.toml"
web="$repo/ActionUIWeb/package.json"

if [ "$#" -ne 1 ]; then
    usage
fi

# The values each file states, one per line ("" when it states none).
core_version() {
    /usr/bin/sed -n 's/.*public static let string = "\([^"]*\)".*/\1/p' "$core"
}
xcode_versions() {
    /usr/bin/sed -n 's/.*MARKETING_VERSION = \([^;]*\);.*/\1/p' "$xcode" | /usr/bin/sort -u
}
python_version() {
    /usr/bin/sed -n 's/^version = "\([^"]*\)"/\1/p' "$python"
}
node_versions() {
    /usr/bin/jq -r '.version' "$node"
    /usr/bin/jq -r '.version, .packages[""].version' "$node_lock"
}
cargo_versions() {
    /usr/bin/sed -n 's/^version = "\([^"]*\)"/\1/p' "$cargo"
    /usr/bin/sed -n '/^name = "actionui"$/{n;s/^version = "\([^"]*\)"/\1/p;}' "$cargo_lock"
    /usr/bin/sed -n '/^name = "actionui-sys"$/{n;s/^version = "\([^"]*\)"/\1/p;}' "$cargo_lock"
    /usr/bin/sed -n 's/^actionui-sys = {.* version = "\([^"]*\)".*/\1/p' "$cargo_actionui"
}
web_version() {
    /usr/bin/jq -r '.version' "$web"
}

# Compares every value of a file with the expected version; prints the file and its values when
# one differs. Returns 1 then.
compare() {
    local _label="$1"
    local _values="$2"
    local _expected="$3"
    local _differs=0
    local _value
    for _value in $_values; do
        if [ "$_value" != "$_expected" ]; then
            _differs=1
        fi
    done
    if [ -z "$_values" ]; then
        _differs=1
    fi
    if [ "$_differs" -ne 0 ]; then
        printf 'set-version: %s states %s, not %s\n' "$_label" "$(printf '%s' "$_values" | /usr/bin/tr '\n' ' ')" "$_expected" >&2
        return 1
    fi
    return 0
}

check_all() {
    local _expected="$1"
    local _failed=0
    compare "ActionUI.xcodeproj MARKETING_VERSION" "$(xcode_versions)" "$_expected" || _failed=1
    compare "ActionUIPython/pyproject.toml" "$(python_version)" "$_expected" || _failed=1
    compare "ActionUINodeJS/package.json and package-lock.json" "$(node_versions)" "$_expected" || _failed=1
    compare "ActionUIRust/Cargo.toml, Cargo.lock and actionui/Cargo.toml" "$(cargo_versions)" "$_expected" || _failed=1
    compare "ActionUIWeb/package.json" "$(web_version)" "$_expected" || _failed=1
    return "$_failed"
}

# Writes the output of a filter over a file back into it, through a temporary file beside it.
# Usage: rewrite <file> <command> [arguments...]: the command reads the file on its standard input.
rewrite() {
    local _file="$1"
    shift
    local _temporary
    _temporary="$(/usr/bin/mktemp "$_file.XXXXXX")"
    local _status=$?
    if [ "$_status" -ne 0 ] || [ -z "$_temporary" ]; then
        printf 'set-version: cannot create a temporary file beside %s\n' "$_file" >&2
        return 1
    fi
    "$@" < "$_file" > "$_temporary"
    _status=$?
    if [ "$_status" -ne 0 ]; then
        printf 'set-version: could not rewrite %s (%s exit %s)\n' "$_file" "$1" "$_status" >&2
        /bin/rm -f "$_temporary"
        return 1
    fi
    # Written back into the file, which keeps its permissions (mktemp makes the copy 0600).
    /bin/cat "$_temporary" > "$_file"
    _status=$?
    /bin/rm -f "$_temporary"
    if [ "$_status" -ne 0 ]; then
        printf 'set-version: could not write %s\n' "$_file" >&2
        return 1
    fi
    return 0
}

if [ "$1" = "--check" ]; then
    expected="$(core_version)"
    if [ -z "$expected" ]; then
        printf 'set-version: no version found in %s\n' "$core" >&2
        exit 1
    fi
    check_all "$expected"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'set-version: run Scripts/set-version.sh %s to make them agree\n' "$expected" >&2
        exit 1
    fi
    printf 'set-version: every file states %s\n' "$expected"
    exit 0
fi

version="$1"
case "$version" in
    # Not "x.y.z" in digits, or a number with a leading zero (Cargo and npm refuse "01.2.3").
    -*|*[!0-9.]*|.*|*.|*..*|0[0-9]*|*.0[0-9]*)
        usage
        ;;
esac
dots="$(printf '%s' "$version" | /usr/bin/tr -cd '.')"
if [ "${#dots}" -ne 2 ]; then
    usage
fi

failed=0
rewrite "$core" /usr/bin/sed "s/public static let string = \"[^\"]*\"/public static let string = \"$version\"/" || failed=1
rewrite "$xcode" /usr/bin/sed "s/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = $version;/" || failed=1
rewrite "$python" /usr/bin/sed "s/^version = \"[^\"]*\"/version = \"$version\"/" || failed=1
# The JSON files are edited line by line, as written by npm (two-space indents), so nothing else
# in them changes; the check reads them with jq.
rewrite "$node" /usr/bin/sed "s/^  \"version\": \"[^\"]*\"/  \"version\": \"$version\"/" || failed=1
rewrite "$node_lock" /usr/bin/sed -e "s/^  \"version\": \"[^\"]*\"/  \"version\": \"$version\"/" \
    -e "/^    \"\": {\$/,/^    }/s/^      \"version\": \"[^\"]*\"/      \"version\": \"$version\"/" || failed=1
rewrite "$cargo" /usr/bin/sed "s/^version = \"[^\"]*\"/version = \"$version\"/" || failed=1
rewrite "$cargo_lock" /usr/bin/sed -e "/^name = \"actionui\"$/{n;s/^version = \"[^\"]*\"/version = \"$version\"/;}" \
    -e "/^name = \"actionui-sys\"$/{n;s/^version = \"[^\"]*\"/version = \"$version\"/;}" || failed=1
rewrite "$cargo_actionui" /usr/bin/sed "/^actionui-sys = {/s/ version = \"[^\"]*\"/ version = \"$version\"/" || failed=1
rewrite "$web" /usr/bin/sed "s/^  \"version\": \"[^\"]*\"/  \"version\": \"$version\"/" || failed=1
if [ "$failed" -ne 0 ]; then
    exit 1
fi

check_all "$version"
status=$?
if [ "$status" -ne 0 ]; then
    exit 1
fi
printf 'set-version: every file states %s\n' "$version"
