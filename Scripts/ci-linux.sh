#!/bin/bash
#
# Scripts/ci-linux.sh - the Linux continuous-integration steps, run by .github/workflows/linux.yml
# in an ubuntu:26.04 container; also usable by hand on Debian 13 or Ubuntu 26.04.
#
# Usage: Scripts/ci-linux.sh <step>
#   install  (as root) the packages ActionUI's Linux build and tests need, then swift.org's Swift
#            toolchain into /usr, checked against the Swift release signing key
#            (ActionUIAdwaita/agent-vm/swift-gtk/files/install-swift.sh)
#   build    the symbol icons (Scripts/prepare-linux-symbols.sh), then the root package: the core,
#            the GTK renderer, the C adapter, the application functions, the remote server and the
#            verifier
#   test     the root package's tests with no display: the Core, verifier and remote server tests
#            run; the renderer tests skip themselves, since GTK cannot open a display
#
# Environment:
#   ACTIONUI_CI_SWIFT         the Swift release to install (default 6.4.2; ActionUI needs 6.3 or later)
#   ACTIONUI_CI_SWIFT_SHA256  optional SHA-256 of the toolchain download, to pin it
#
# Exit status: 0 the step passed, 1 it failed, 64 bad arguments.

script_dir="$(CDPATH= cd -P -- "$(/usr/bin/dirname -- "$0")" && pwd)"
if [ -z "$script_dir" ]; then
    printf 'ci-linux: could not find the folder of %s\n' "$0" >&2
    exit 1
fi
repo="$(/usr/bin/dirname -- "$script_dir")"

# The Swift 6.x Release Signing Key, as swift.org's install page lists it (the swift-gtk recipe's
# default too).
swift_key="52BB7E3DE28A71BE22EC05FFEF80A866B47A981F"
swift_version="${ACTIONUI_CI_SWIFT:-6.4.2}"
swift_sha256="${ACTIONUI_CI_SWIFT_SHA256:-}"

# What the Swift toolchain links against, gpg and curl for its download, and the GTK 4, libadwaita
# and libsoup development packages; HarfBuzz and glib-compile-resources for the symbol icons;
# python3 for the remote server's Python client tests. The same list as the swift-gtk recipe
# (ActionUIAdwaita/agent-vm/swift-gtk/recipe.json), plus python3.
packages="binutils libc6-dev g++ libcurl4-openssl-dev libedit2 libpython3-dev libsqlite3-0 libxml2-dev libncurses-dev libz3-dev pkg-config tzdata zlib1g-dev unzip gnupg git ca-certificates curl libgtk-4-dev libadwaita-1-dev libsoup-3.0-dev libharfbuzz-dev libglib2.0-dev-bin glib-networking python3"

usage() {
    printf 'usage: %s install|build|test\n' "$0" >&2
}

step_install() {
    local _uid="$(/usr/bin/id -u)"
    if [ "$_uid" != 0 ]; then
        printf 'ci-linux: install needs root (apt-get and /usr); run it as root\n' >&2
        return 1
    fi
    export DEBIAN_FRONTEND=noninteractive
    /usr/bin/apt-get -q -y -o Dpkg::Use-Pty=0 update
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        printf 'ci-linux: apt-get update failed (status %s)\n' "$_status" >&2
        return 1
    fi
    # $packages is a word list on purpose.
    /usr/bin/apt-get -q -y -o Dpkg::Use-Pty=0 install --no-install-recommends $packages
    _status=$?
    if [ "$_status" -ne 0 ]; then
        printf 'ci-linux: installing the development packages failed (apt-get status %s)\n' "$_status" >&2
        return 1
    fi
    /bin/bash "$repo/ActionUIAdwaita/agent-vm/swift-gtk/files/install-swift.sh" \
        "$swift_version" auto "$swift_key" $swift_sha256
    _status=$?
    if [ "$_status" -ne 0 ]; then
        printf 'ci-linux: installing Swift %s failed (status %s)\n' "$swift_version" "$_status" >&2
        return 1
    fi
    /usr/bin/swift --version
    _status=$?
    if [ "$_status" -ne 0 ]; then
        printf 'ci-linux: the installed swift does not run (status %s)\n' "$_status" >&2
        return 1
    fi
    local _versions
    _versions="$(/usr/bin/pkg-config --modversion gtk4 libadwaita-1 libsoup-3.0 harfbuzz)"
    _status=$?
    if [ "$_status" -ne 0 ]; then
        printf 'ci-linux: pkg-config does not find gtk4, libadwaita-1, libsoup-3.0 or harfbuzz (status %s)\n' "$_status" >&2
        return 1
    fi
    printf 'ci-linux: GTK, libadwaita, libsoup, HarfBuzz: %s\n' "$(printf '%s' "$_versions" | /usr/bin/tr '\n' ' ')"
    return 0
}

step_build() {
    # Without the icons the build still succeeds, with a warning, and SF Symbols show the
    # missing-icon picture; CI builds what ships, so a failure here fails the step.
    /bin/bash "$repo/Scripts/prepare-linux-symbols.sh"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        printf 'ci-linux: generating the symbol icons failed (status %s)\n' "$_status" >&2
        return 1
    fi
    # --manifest-cache none: the manifest's file lists come from the folder listing, which SwiftPM's
    # manifest cache does not see (Package.swift, excludingAllBut).
    /usr/bin/swift build --package-path "$repo" --manifest-cache none
    _status=$?
    if [ "$_status" -ne 0 ]; then
        printf 'ci-linux: swift build failed (status %s)\n' "$_status" >&2
        return 1
    fi
    return 0
}

step_test() {
    # No display, even when the caller has one: the renderer tests skip themselves, so this step
    # gives the same result in CI and by hand.
    /usr/bin/env -u DISPLAY -u WAYLAND_DISPLAY \
        /usr/bin/swift test --package-path "$repo" --manifest-cache none
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        printf 'ci-linux: swift test failed (status %s)\n' "$_status" >&2
        return 1
    fi
    return 0
}

if [ "$#" -ne 1 ]; then
    usage
    exit 64
fi
case "$1" in
    install) step_install ;;
    build) step_build ;;
    test) step_test ;;
    -h|--help) /usr/bin/sed -n '2,21p' "$0"; exit 0 ;;
    *)
        printf 'ci-linux: unknown step %s\n' "$1" >&2
        usage
        exit 64
        ;;
esac
status=$?
if [ "$status" -ne 0 ]; then
    exit 1
fi
exit 0
