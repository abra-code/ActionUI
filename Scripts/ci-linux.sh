#!/bin/bash
#
# Scripts/ci-linux.sh - the Linux continuous-integration steps, run by .github/workflows/linux.yml
# in an ubuntu:26.04 container; also usable by hand on Debian 13 or Ubuntu 26.04.
#
# Usage: Scripts/ci-linux.sh <step>
#   install      (as root) the packages ActionUI's Linux build and tests need, then swift.org's
#                Swift toolchain into /usr, checked against the Swift release signing key
#                (ActionUIAdwaita/agent-vm/swift-gtk/files/install-swift.sh)
#   build        the symbol icons (Scripts/prepare-linux-symbols.sh), then the root package: the
#                core, the GTK renderer, the C adapter, the application functions, the remote server
#                and the verifier
#   test         the root package's tests with no display: the Core, verifier and remote server
#                tests run; the renderer tests skip themselves, since GTK cannot open a display
#   install-gui  (as root) what the renderer tests need besides the build's packages: GNOME's
#                compositor (Mutter), a session bus, GNOME's fonts and settings schemas, Mesa's
#                software renderer, and GStreamer with an H.264 decoder for the VideoPlayer tests
#   test-gui     the renderer tests (ActionUIAdwaitaTests) on a headless GNOME display: Mutter with
#                a virtual monitor, in a session bus of its own, with GNOME's default font
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

# The renderer tests' display and media: Mutter (the compositor the tests are measured against;
# Weston and Xvfb lay windows out and deliver their first frames differently), dbus for
# dbus-run-session, GNOME's settings schemas, fonts and icons, Mesa's software renderer for a machine
# without a GPU, and GStreamer's base and good plug-ins with libav's H.264 decoder for
# ActionUIAdwaita/Tests/Media/one-second.mp4 (without them GStreamer aborts the test process).
gui_packages="mutter dbus gsettings-desktop-schemas fonts-adwaita adwaita-icon-theme libgl1-mesa-dri libegl-mesa0 gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-libav"

# GNOME's default interface font (org.gnome.desktop.interface font-name). With no desktop portal GTK
# does not read it and falls back to a smaller font, and the tests that size icons and fields from
# the font fail.
gui_font="Adwaita Sans 11"

usage() {
    printf 'usage: %s install|build|test|install-gui|test-gui\n' "$0" >&2
}

# Installs the packages named in $1 (a word list) with apt-get, as root.
apt_install() {
    local _list="$1"
    local _uid="$(/usr/bin/id -u)"
    if [ "$_uid" != 0 ]; then
        printf 'ci-linux: installing packages needs root (apt-get); run this step as root\n' >&2
        return 1
    fi
    export DEBIAN_FRONTEND=noninteractive
    /usr/bin/apt-get -q -y -o Dpkg::Use-Pty=0 update
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        printf 'ci-linux: apt-get update failed (status %s)\n' "$_status" >&2
        return 1
    fi
    # $_list is a word list on purpose.
    /usr/bin/apt-get -q -y -o Dpkg::Use-Pty=0 install --no-install-recommends $_list
    _status=$?
    if [ "$_status" -ne 0 ]; then
        printf 'ci-linux: installing the packages failed (apt-get status %s)\n' "$_status" >&2
        return 1
    fi
    return 0
}

step_install() {
    apt_install "$packages" || return 1
    # $swift_sha256 unquoted: an empty value passes no argument.
    /bin/bash "$repo/ActionUIAdwaita/agent-vm/swift-gtk/files/install-swift.sh" \
        "$swift_version" auto "$swift_key" $swift_sha256
    local _status=$?
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

step_install_gui() {
    apt_install "$gui_packages" || return 1
    return 0
}

# A runtime folder (Mutter's socket) and a settings folder (GNOME's font) of their own, then the
# session: this script again, as step gui-session, inside dbus-run-session.
step_test_gui() {
    local _work
    _work="$(/usr/bin/mktemp -d)"
    local _status=$?
    if [ "$_status" -ne 0 ] || [ -z "$_work" ]; then
        printf 'ci-linux: could not make a work folder\n' >&2
        return 1
    fi
    /bin/mkdir -m 700 "$_work/runtime"
    _status=$?
    if [ "$_status" -ne 0 ]; then
        printf 'ci-linux: could not make %s\n' "$_work/runtime" >&2
        /bin/rm -rf "$_work"
        return 1
    fi
    /bin/mkdir -p "$_work/config/gtk-4.0"
    _status=$?
    if [ "$_status" -ne 0 ]; then
        printf 'ci-linux: could not make %s\n' "$_work/config/gtk-4.0" >&2
        /bin/rm -rf "$_work"
        return 1
    fi
    printf '[Settings]\ngtk-font-name=%s\n' "$gui_font" > "$_work/config/gtk-4.0/settings.ini"
    _status=$?
    if [ "$_status" -ne 0 ]; then
        printf 'ci-linux: could not write %s\n' "$_work/config/gtk-4.0/settings.ini" >&2
        /bin/rm -rf "$_work"
        return 1
    fi
    XDG_RUNTIME_DIR="$_work/runtime" XDG_CONFIG_HOME="$_work/config" CI_LINUX_WORK="$_work" \
        /usr/bin/dbus-run-session -- /bin/bash "$script_dir/ci-linux.sh" gui-session
    _status=$?
    /bin/rm -rf "$_work"
    if [ "$_status" -ne 0 ]; then
        printf 'ci-linux: the renderer tests failed (status %s)\n' "$_status" >&2
        return 1
    fi
    return 0
}

# Inside dbus-run-session: Mutter headless with a virtual monitor, then the renderer tests on it.
step_gui_session() {
    local _socket="actionui-ci"
    local _log="$CI_LINUX_WORK/mutter.log"
    /usr/bin/mutter --headless --wayland --no-x11 --virtual-monitor 1920x1080 \
        --wayland-display "$_socket" > "$_log" 2>&1 &
    local _mutter=$!
    local _tries=0
    while [ ! -S "$XDG_RUNTIME_DIR/$_socket" ] && [ "$_tries" -lt 100 ]; do
        kill -0 "$_mutter" 2>/dev/null || break
        /usr/bin/sleep 0.2
        _tries=$((_tries + 1))
    done
    if [ ! -S "$XDG_RUNTIME_DIR/$_socket" ]; then
        printf 'ci-linux: Mutter did not open its Wayland socket; its output:\n' >&2
        /usr/bin/cat "$_log" >&2
        kill "$_mutter" 2>/dev/null
        return 1
    fi
    /usr/bin/env -u DISPLAY WAYLAND_DISPLAY="$_socket" GDK_BACKEND=wayland \
        /usr/bin/swift test --package-path "$repo" --manifest-cache none \
        --filter ActionUIAdwaitaTests
    local _status=$?
    kill "$_mutter" 2>/dev/null
    wait "$_mutter" 2>/dev/null
    if [ "$_status" -ne 0 ]; then
        printf "ci-linux: swift test failed (status %s); Mutter's output:\n" "$_status" >&2
        /usr/bin/cat "$_log" >&2
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
    install-gui) step_install_gui ;;
    test-gui) step_test_gui ;;
    gui-session)
        if [ -z "$CI_LINUX_WORK" ] || [ -z "$XDG_RUNTIME_DIR" ]; then
            printf 'ci-linux: gui-session is run by test-gui\n' >&2
            exit 64
        fi
        step_gui_session
        ;;
    -h|--help) /usr/bin/sed -n '2,25p' "$0"; exit 0 ;;
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
