#!/bin/bash
#
# Scripts/prepare-linux-symbols.sh - generates the Material Symbols icons that ActionUI shows for SF
# Symbols on Linux, before `swift build`. They go into ActionUI as a GResource in a section of its
# own (ActionUIAdwaita/CSymbolResource), so libActionUI.so and every Swift program that links
# ActionUI statically carry them. Without this step ActionUI still builds, with no icons: the build
# warns, and SF Symbols show the missing-icon picture.
#
#   1. The font, Tools/material_symbols/font: downloaded by fetch-material-symbols-font.sh when it is
#      missing. A font already there is used as it is; run that script to move to a newer release.
#   2. The generator, Tools/material_symbols/generate-symbol-icons.c, compiled with HarfBuzz.
#   3. The icons, from ActionUIAndroid's sf_to_material.map: one symbolic SVG per distinct glyph,
#      fill and weight, in Tools/material_symbols/build/icons (gitignored, kept for inspection).
#   4. glib-compile-resources --generate-source writes them, with the map, as C source into
#      ActionUIAdwaita/CSymbolResource/generated/symbols-resource.inc (gitignored). The file is
#      replaced only when it changed, and then SymbolResource.c, which includes it, is touched:
#      SwiftPM does not look again for an included file it once found missing.
#
# Usage: Scripts/prepare-linux-symbols.sh
# Needs: a C compiler (the Swift toolchain's clang, else cc, clang or gcc; or CC set to one),
# pkg-config with HarfBuzz's development files, and glib-compile-resources (GLib's development files;
# GTK's pull in both on Debian and Ubuntu).
# Exit status: 0 the icons are ready, 1 a step failed.

script_dir="$(CDPATH= cd "$(/usr/bin/dirname "$0")" && pwd)"
if [ -z "$script_dir" ]; then
    printf 'prepare-linux-symbols: could not find the folder of %s\n' "$0" >&2
    exit 1
fi
repo="$(/usr/bin/dirname "$script_dir")"
tools="$repo/Tools/material_symbols"
font_folder="$tools/font"
build="$tools/build"
map="$repo/ActionUIAndroid/library/src/main/assets/symbols/sf_to_material.map"
resource_folder="$repo/ActionUIAdwaita/CSymbolResource"
generated="$resource_folder/generated"

# 1. The font.
if [ ! -r "$font_folder/MaterialSymbolsRounded.ttf" ] || [ ! -r "$font_folder/COMMIT" ]; then
    printf 'prepare-linux-symbols: no font yet; downloading it\n'
    /bin/bash "$tools/fetch-material-symbols-font.sh"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'prepare-linux-symbols: the font download failed\n' >&2
        exit 1
    fi
fi

# 2. The generator. A C compiler: CC, the clang beside the Swift toolchain, else the system's.
compiler=""
candidates="$CC"
case "$CC" in
    ""|/*) ;;
    *)
        # A name such as CC=gcc: its path on PATH.
        candidates="$(command -v "$CC")"
        if [ -z "$candidates" ]; then
            printf 'prepare-linux-symbols: CC=%s is not a command on PATH\n' "$CC" >&2
            exit 1
        fi
        ;;
esac
for swift in /usr/local/bin/swift /usr/bin/swift; do
    if [ -x "$swift" ]; then
        resolved="$(/usr/bin/readlink -f "$swift")"
        candidates="$candidates ${resolved%/*}/clang"
    fi
done
for candidate in $candidates /usr/bin/cc /usr/bin/clang /usr/bin/gcc; do
    case "$candidate" in
        /*) ;;
        *) continue ;;
    esac
    if [ -x "$candidate" ]; then
        compiler="$candidate"
        break
    fi
done
if [ -z "$compiler" ]; then
    printf 'prepare-linux-symbols: no C compiler found (set CC to one)\n' >&2
    exit 1
fi
for tool in /usr/bin/pkg-config /usr/bin/glib-compile-resources; do
    if [ ! -x "$tool" ]; then
        printf 'prepare-linux-symbols: no %s (install pkg-config and libglib2.0-dev)\n' "$tool" >&2
        exit 1
    fi
done
harfbuzz_flags="$(/usr/bin/pkg-config --cflags --libs harfbuzz)"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'prepare-linux-symbols: pkg-config finds no HarfBuzz (install libharfbuzz-dev)\n' >&2
    exit 1
fi
/bin/mkdir -p "$build" "$generated"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'prepare-linux-symbols: cannot create %s and %s\n' "$build" "$generated" >&2
    exit 1
fi
# harfbuzz_flags is split into words on purpose: it is a list of flags.
"$compiler" -std=c11 -O2 -o "$build/generate-symbol-icons" "$tools/generate-symbol-icons.c" $harfbuzz_flags
status=$?
if [ "$status" -ne 0 ]; then
    printf 'prepare-linux-symbols: %s could not compile the generator\n' "$compiler" >&2
    exit 1
fi

# 3. The icons.
"$build/generate-symbol-icons" "$map" "$font_folder/MaterialSymbolsRounded.ttf" "$build/icons"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'prepare-linux-symbols: the generator failed; the icons were not updated\n' >&2
    exit 1
fi

# 4. The C source, replaced only when it changed.
/usr/bin/glib-compile-resources --sourcedir "$build/icons" --generate-source --manual-register \
    --c-name actionui_symbols --target "$generated/symbols-resource.inc.new" "$build/icons/symbols.gresource.xml"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'prepare-linux-symbols: glib-compile-resources failed (it comes with GLib'"'"'s development files)\n' >&2
    /bin/rm -f "$generated/symbols-resource.inc.new"
    exit 1
fi
changed=yes
if [ -r "$generated/symbols-resource.inc" ]; then
    /usr/bin/cmp -s "$generated/symbols-resource.inc.new" "$generated/symbols-resource.inc"
    status=$?
    if [ "$status" -eq 0 ]; then
        changed=no
    fi
fi
if [ "$changed" = yes ]; then
    /bin/mv -f "$generated/symbols-resource.inc.new" "$generated/symbols-resource.inc"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'prepare-linux-symbols: cannot write %s\n' "$generated/symbols-resource.inc" >&2
        exit 1
    fi
    /usr/bin/touch "$resource_folder/SymbolResource.c"
    status=$?
    if [ "$status" -ne 0 ]; then
        # Without the touch a build that once missed the file keeps an object without it; removing
        # the file makes the next run replace it and touch again.
        /bin/rm -f "$generated/symbols-resource.inc"
        printf 'prepare-linux-symbols: cannot touch %s; run this script again\n' "$resource_folder/SymbolResource.c" >&2
        exit 1
    fi
    printf 'prepare-linux-symbols: updated %s\n' "$generated/symbols-resource.inc"
else
    /bin/rm -f "$generated/symbols-resource.inc.new"
    printf 'prepare-linux-symbols: the icons are unchanged\n'
fi
# The build's check compares this stamp with the map and the font.
/usr/bin/touch "$generated/stamp"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'prepare-linux-symbols: cannot touch %s; the build may warn that the icons are out of date\n' "$generated/stamp" >&2
    exit 1
fi
exit 0
