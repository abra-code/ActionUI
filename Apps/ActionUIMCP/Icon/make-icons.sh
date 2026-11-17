#!/bin/bash
# make-icons.sh - writes the ActionUI MCP server's two icons from the sources in this folder:
#   ../Sources/ActionUIMCP/Resources/ActionUIMCP.svg   Linux (the desktop entry, the windows' icon)
#   ../Sources/ActionUIMCP/Resources/ActionUIMCP.icns  macOS (the Dock, set by AppKitPlatform.swift)
# make_icon_svg.py draws each as an SVG; macOS's sips renders the macOS one at every icns size and
# iconutil packs them. Run it on macOS after changing a source (the glyphs, circle-tile.svg or the
# colors and placement in make_icon_svg.py), and commit the two icons with the change.
#
# sips draws SVG through the window server: run this outside any shell sandbox.
#
# Usage:
#   bash Apps/ActionUIMCP/Icon/make-icons.sh
#
# Exit codes: 0 both icons written; 1 a step failed (named on standard error).

script_dir="$(CDPATH= cd -P -- "$(/usr/bin/dirname -- "$0")" && pwd)"
resources="$script_dir/../Sources/ActionUIMCP/Resources"

fail() {
    printf 'make-icons.sh: %s\n' "$1" >&2
    exit 1
}

work_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/actionui-mcp-icon.XXXXXX")"
if [ -z "$work_dir" ] || [ ! -d "$work_dir" ]; then
    fail "cannot make a temporary folder"
fi
trap '/bin/rm -rf "$work_dir"' EXIT

/usr/bin/python3 "$script_dir/make_icon_svg.py" linux "$work_dir/linux.svg"
status=$?
if [ "$status" -ne 0 ]; then
    fail "the Linux SVG was not drawn"
fi
/usr/bin/python3 "$script_dir/make_icon_svg.py" macos "$work_dir/macos.svg"
status=$?
if [ "$status" -ne 0 ]; then
    fail "the macOS SVG was not drawn"
fi

# The largest image, from which sips makes the smaller ones
/usr/bin/sips -s format png "$work_dir/macos.svg" --out "$work_dir/macos-1024.png" > /dev/null
status=$?
if [ "$status" -ne 0 ] || [ ! -s "$work_dir/macos-1024.png" ]; then
    fail "sips could not render the macOS SVG (outside a shell sandbox?)"
fi

iconset="$work_dir/ActionUIMCP.iconset"
/bin/mkdir "$iconset"
status=$?
if [ "$status" -ne 0 ]; then
    fail "cannot make $iconset"
fi
# Up to 256 at 2x: the Dock's largest magnification is 128 points; a Finder preview, which would use
# 512, never shows this icon (it is not an app bundle's)
for size in 16 32 128 256; do
    for scale in 1 2; do
        pixels=$((size * scale))
        name="icon_${size}x${size}.png"
        if [ "$scale" -eq 2 ]; then
            name="icon_${size}x${size}@2x.png"
        fi
        /usr/bin/sips -z "$pixels" "$pixels" "$work_dir/macos-1024.png" --out "$iconset/$name" > /dev/null
        status=$?
        if [ "$status" -ne 0 ]; then
            fail "sips could not make $name"
        fi
    done
done

/usr/bin/iconutil -c icns "$iconset" -o "$work_dir/ActionUIMCP.icns"
status=$?
if [ "$status" -ne 0 ]; then
    fail "iconutil could not pack the icns"
fi

/bin/cp "$work_dir/linux.svg" "$resources/ActionUIMCP.svg"
status=$?
if [ "$status" -ne 0 ]; then
    fail "cannot write $resources/ActionUIMCP.svg"
fi
/bin/cp "$work_dir/ActionUIMCP.icns" "$resources/ActionUIMCP.icns"
status=$?
if [ "$status" -ne 0 ]; then
    fail "cannot write $resources/ActionUIMCP.icns"
fi
printf 'Wrote %s and %s\n' "$resources/ActionUIMCP.svg" "$resources/ActionUIMCP.icns"
exit 0
