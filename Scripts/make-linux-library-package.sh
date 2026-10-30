#!/bin/bash
#
# Scripts/make-linux-library-package.sh - assembles the ActionUI C library for Linux, for programs
# in other languages (the Python, Node.js and Rust packages, or C), as a folder and a tarball:
#
#   actionui-<version>-linux-<arch>/
#     lib/libActionUI.so                         the library, stripped
#     lib/pkgconfig/actionui.pc                  pkg-config file; finds the folder from its own place
#     include/ActionUICAdapter/ActionUIC.h       the C interface
#     include/ActionUIAppKitApplication/ActionUIApp.h   the application functions
#     include/ActionUIRemote/ActionUIRemote-Swift.h      the remote server's functions (generated)
#     LICENSE.txt
#     LICENSE-MaterialSymbols.txt                the license of the symbol icons in the library
#   actionui-<version>-linux-<arch>.tar.gz       the folder, packed
#
# The headers sit at the include paths the Apple frameworks give them (<ActionUICAdapter/ActionUIC.h>,
# <ActionUIAppKitApplication/ActionUIApp.h>, <ActionUIRemote/ActionUIRemote-Swift.h>), so one
# #include line serves both platforms. ActionUIRemote has no hand-written header, as on Apple: its
# header is the one Swift generates, taken from the build that made the library. The
# library is self-contained: it must be built with the Swift runtime linked in, and then needs only
# the system's GTK 4, libadwaita and libsoup 3 (and WebKitGTK 6.0 for WebView, loaded when shown).
# Build it with
#   swift build -c release --static-swift-stdlib --product ActionUI
# A library linked to a toolchain's Swift runtime is refused. The copy is stripped of its symbols
# (llvm-objcopy from the Swift toolchain, else the system's objcopy or strip; left as it is, with a
# note, when none is found).
#
# The folder is a build input, not an installation: unpack it anywhere, and with
# PKG_CONFIG_PATH=<folder>/lib/pkgconfig, `pkg-config --cflags --libs actionui` gives the include
# and link flags. Each program then ships its own copy of libActionUI.so beside its binary (for
# Python and Node.js, beside the compiled extension) and links with -Wl,-rpath,'$ORIGIN', so the
# loader finds that copy; a host that loads the library by path (ctypes) needs no link flags.
# Self-contained, as an app bundle is on macOS, with no system-wide installation and no clash
# between versions. (The library's RUNPATH is $ORIGIN too, so a dependency placed beside it is
# found first; its dependencies are system libraries.)
# Programs written in Swift do not use this library: they depend on the ActionUI package and build
# it with their own toolchain. Loading this library into a Swift program would bring a second,
# private Swift runtime and libdispatch, so the program's main queue and ActionUI's would differ.
#
# Usage: Scripts/make-linux-library-package.sh <products folder> <output folder>
#   products folder: where swift build put libActionUI.so (Linux), such as .build/release
#   output folder:   where the folder and the tarball are made; ones already there are replaced
# Exit status: 0 made, 1 a step failed, 64 bad arguments.

script_dir="$(CDPATH= cd "$(/usr/bin/dirname "$0")" && pwd)"
if [ -z "$script_dir" ]; then
    printf 'make-linux-library-package: could not find the folder of %s\n' "$0" >&2
    exit 1
fi
repo="$(/usr/bin/dirname "$script_dir")"

if [ "$#" -ne 2 ]; then
    printf 'usage: %s <products folder> <output folder>\n' "$0" >&2
    exit 64
fi
library="$1/libActionUI.so"
output="$2"

if [ ! -f "$library" ]; then
    printf 'make-linux-library-package: no library at %s; build the package on Linux first\n' "$library" >&2
    exit 1
fi
if [ ! -d "$output" ]; then
    printf 'make-linux-library-package: the output folder %s does not exist\n' "$output" >&2
    exit 1
fi

# The version ActionUI states (ActionUIVersion.string), and the machine.
version="$(/usr/bin/sed -n 's/.*public static let string = "\([^"]*\)".*/\1/p' "$repo/ActionUI/Core/Common/ActionUIVersion.swift")"
if [ -z "$version" ]; then
    printf 'make-linux-library-package: could not read the version from ActionUI/Core/Common/ActionUIVersion.swift\n' >&2
    exit 1
fi
arch="$(/usr/bin/uname -m)"
name="actionui-$version-linux-$arch"
package="$output/$name"
tarball="$output/$name.tar.gz"

# The generated remote header, beside the build's other generated headers: the products folder is
# <scratch>/out/Products/<configuration>-linux-<arch>, the headers are in
# <scratch>/out/Intermediates.noindex/GeneratedModuleMaps-linux-<arch>.
products="$(/usr/bin/readlink -f "$1")"
intermediates="$(/usr/bin/dirname "$(/usr/bin/dirname "$products")")/Intermediates.noindex"
remote_header="$intermediates/GeneratedModuleMaps-linux-$arch/ActionUIRemote-Swift.h"
if [ ! -f "$remote_header" ]; then
    printf 'make-linux-library-package: no %s; the products folder must be <scratch>/out/Products/<configuration>-linux-%s, from swift build\n' "$remote_header" "$arch" >&2
    exit 1
fi

# Self-contained: no Swift runtime, libdispatch or Foundation library from a toolchain.
linked="$(/usr/bin/ldd "$library" 2>&1)"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'make-linux-library-package: ldd could not read %s: %s\n' "$library" "$linked" >&2
    exit 1
fi
case "$linked" in
    *libswift*|*libdispatch*|*libFoundation*)
        printf 'make-linux-library-package: %s uses the Swift runtime of the toolchain that built it; build it with --static-swift-stdlib\n' "$library" >&2
        exit 1
        ;;
esac

# With its symbol icons: a build without Scripts/prepare-linux-symbols.sh shows none.
if [ ! -x /usr/bin/gresource ]; then
    printf 'make-linux-library-package: no /usr/bin/gresource to check the symbol icons with (install libglib2.0-bin)\n' >&2
    exit 1
fi
sections="$(/usr/bin/gresource sections "$library" 2>&1)"
case "$sections" in
    *actionui_symbols*) ;;
    *)
        printf 'make-linux-library-package: %s has no symbol icons; run Scripts/prepare-linux-symbols.sh, then build it again (gresource: %s)\n' "$library" "$sections" >&2
        exit 1
        ;;
esac

for old in "$package" "$tarball"; do
    if [ -e "$old" ]; then
        /bin/rm -rf "$old"
        status=$?
        if [ "$status" -ne 0 ]; then
            printf 'make-linux-library-package: could not remove the old %s\n' "$old" >&2
            exit 1
        fi
    fi
done
# A step that fails after this leaves no partial folder or tarball behind.
discard_package() {
    /bin/rm -rf "$package" "$tarball"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'make-linux-library-package: could not remove the partial %s\n' "$package" >&2
    fi
}

/bin/mkdir -p "$package/lib/pkgconfig" "$package/include/ActionUICAdapter" "$package/include/ActionUIAppKitApplication" "$package/include/ActionUIRemote"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'make-linux-library-package: could not make the folders of %s\n' "$package" >&2
    discard_package
    exit 1
fi

# Copies file $1 to $2, or reports which one failed and discards the package. Returns 0 when copied.
copy_into_package() {
    /bin/cp "$1" "$2"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        printf 'make-linux-library-package: could not copy %s to %s\n' "$1" "$2" >&2
        discard_package
        return 1
    fi
    return 0
}

copy_into_package "$library" "$package/lib/libActionUI.so" || exit 1
copy_into_package "$repo/ActionUICAdapter/include/ActionUIC.h" "$package/include/ActionUICAdapter/ActionUIC.h" || exit 1
copy_into_package "$repo/ActionUIAppKitApplication/include/ActionUIApp.h" "$package/include/ActionUIAppKitApplication/ActionUIApp.h" || exit 1
copy_into_package "$remote_header" "$package/include/ActionUIRemote/ActionUIRemote-Swift.h" || exit 1
copy_into_package "$repo/LICENSE.txt" "$package/LICENSE.txt" || exit 1

# The library carries the Material Symbols icons (Apache 2.0), whose license goes with it.
/bin/bash "$repo/Tools/material_symbols/write-material-symbols-license.sh" "$package/LICENSE-MaterialSymbols.txt"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'make-linux-library-package: could not write the Material Symbols license notice\n' >&2
    discard_package
    exit 1
fi

# Stripped of symbols: the Swift toolchain's llvm-objcopy (beside swift), else the system's tools.
stripper=""
swift_path="$(/usr/bin/readlink -f /usr/local/bin/swift 2>/dev/null)"
for candidate in "${swift_path%/*}/llvm-objcopy" /usr/bin/llvm-objcopy /usr/bin/objcopy /usr/bin/strip; do
    if [ -x "$candidate" ]; then
        stripper="$candidate"
        break
    fi
done
if [ -n "$stripper" ]; then
    "$stripper" --strip-all "$package/lib/libActionUI.so"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'make-linux-library-package: %s could not strip %s\n' "$stripper" "$package/lib/libActionUI.so" >&2
        discard_package
        exit 1
    fi
else
    printf 'make-linux-library-package: note: no llvm-objcopy, objcopy or strip found; the library keeps its symbols\n'
fi

# pkg-config finds the folder from the file's own place (${pcfiledir}), so the folder can be
# unpacked anywhere. The system libraries the library uses are its own dependencies, not the
# linking program's, so they are not listed.
printf '%s\n' \
    'prefix=${pcfiledir}/../..' \
    'libdir=${prefix}/lib' \
    'includedir=${prefix}/include' \
    '' \
    'Name: ActionUI' \
    'Description: Native GTK 4 and libadwaita windows from ActionUI JSON documents, through a C interface' \
    'URL: https://github.com/abra-code/ActionUI' \
    "Version: $version" \
    'Libs: -L${libdir} -lActionUI' \
    'Cflags: -I${includedir}' \
    > "$package/lib/pkgconfig/actionui.pc"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'make-linux-library-package: could not write %s\n' "$package/lib/pkgconfig/actionui.pc" >&2
    discard_package
    exit 1
fi

# Owned by root in the archive, whoever packed it (GNU tar).
/usr/bin/tar --owner=0 --group=0 --numeric-owner -czf "$tarball" -C "$output" "$name"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'make-linux-library-package: could not pack %s\n' "$tarball" >&2
    discard_package
    exit 1
fi

printf 'make-linux-library-package: made %s and %s\n' "$package" "$tarball"
