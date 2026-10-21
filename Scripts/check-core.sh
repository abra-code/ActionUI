#!/bin/bash
#
# Scripts/check-core.sh - checks that the portable code in ActionUI/Core builds for Linux.
#
# 1. Imports: every import line under ActionUI/Core follows the rule in check-core-imports.awk.
# 2. Cross-build: builds ActionUI/Core alone (ACTIONUI_CORE_ONLY=1 selects that package) with a
#    Swift toolchain's static Linux SDK, so anything that needs full Foundation, SwiftUI, AppKit,
#    UIKit, CoreGraphics or CoreFoundation fails to compile here, on the Mac.
#
# Usage: Scripts/check-core.sh
# Environment:
#   ACTIONUI_LINUX_SWIFT   the swift to use for step 2; default: the newest Swift toolchain in
#                          ~/Library/Developer/Toolchains with a static Linux SDK of its version
# Exit status: 0 passed, 1 a check failed, 2 no usable toolchain, 64 bad arguments.

script_dir="$(CDPATH= cd "$(/usr/bin/dirname "$0")" && pwd)"
repo="$(/usr/bin/dirname "$script_dir")"
linux_sdk="aarch64-swift-linux-musl"

if [ "$#" -ne 0 ]; then
    printf 'check-core: unknown argument %s\nusage: %s\n' "$1" "$0" >&2
    exit 64
fi

# Prints the swift of a toolchain that can build for Linux: one that has a static Linux SDK of
# its own version. Nothing when there is none.
find_linux_swift() {
    local _candidate
    local _version
    local _sdks
    if [ -n "$ACTIONUI_LINUX_SWIFT" ]; then
        printf '%s\n' "$ACTIONUI_LINUX_SWIFT"
        return 0
    fi
    # Newest first, by version number (6.10 after 6.9).
    local _toolchains="$(/bin/ls -1d "$HOME"/Library/Developer/Toolchains/swift-*-RELEASE.xctoolchain 2>/dev/null | /usr/bin/sort -rV)"
    local _toolchain
    while IFS= read -r _toolchain; do
        [ -n "$_toolchain" ] || continue
        _candidate="$_toolchain/usr/bin/swift"
        [ -x "$_candidate" ] || continue
        _version="$(/usr/bin/basename "$_toolchain" .xctoolchain)"
        _sdks="$("$_candidate" sdk list 2>/dev/null)"
        case "$_sdks" in
            *"${_version}_static-linux"*)
                printf '%s\n' "$_candidate"
                return 0
                ;;
        esac
    done <<EOF_TOOLCHAINS
$_toolchains
EOF_TOOLCHAINS
    _candidate="$HOME/.swiftly/bin/swift"
    if [ -x "$_candidate" ]; then
        _sdks="$("$_candidate" sdk list 2>/dev/null)"
        case "$_sdks" in
            *static-linux*)
                printf '%s\n' "$_candidate"
                return 0
                ;;
        esac
    fi
    return 0
}

# Step 1: imports.
core_files="$(/usr/bin/find "$repo/ActionUI/Core" -name '*.swift' -type f | /usr/bin/sort)"
if [ -z "$core_files" ]; then
    printf 'check-core: no Swift files under %s\n' "$repo/ActionUI/Core" >&2
    exit 1
fi
printf '%s\n' "$core_files" | /usr/bin/tr '\n' '\0' | /usr/bin/xargs -0 /usr/bin/awk -f "$script_dir/check-core-imports.awk"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'check-core: imports FAILED (see above)\n' >&2
    exit 1
fi
printf 'check-core: imports passed\n'

# Step 2: cross-build for Linux.
linux_swift="$(find_linux_swift)"
if [ -z "$linux_swift" ] || [ ! -x "$linux_swift" ]; then
    printf 'check-core: no Swift toolchain with a static Linux SDK was found. Install one\n' >&2
    printf '  (versions, address and checksum: https://www.swift.org/install/macos/):\n' >&2
    printf '    swiftly install <version>\n' >&2
    printf '    swift sdk install <static Linux SDK address> --checksum <checksum>\n' >&2
    printf '  or set ACTIONUI_LINUX_SWIFT to such a swift.\n' >&2
    exit 2
fi
scratch="${TMPDIR:-/tmp}/actionui-core-check"
printf 'check-core: cross-building ActionUI/Core with %s (%s)\n' "$linux_swift" "$linux_sdk"
# --manifest-cache none: the check package's exclude list comes from the folder listing, and a
# cached manifest would keep an old list (SwiftPM keys its cache on the manifest's text).
ACTIONUI_CORE_ONLY=1 "$linux_swift" build --swift-sdk "$linux_sdk" --package-path "$repo" --scratch-path "$scratch" --manifest-cache none
status=$?
if [ "$status" -ne 0 ]; then
    printf 'check-core: cross-build FAILED (status %s)\n' "$status" >&2
    exit 1
fi
printf 'check-core: cross-build passed\n'
exit 0
