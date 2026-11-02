#!/bin/bash
#
# Scripts/make-linux-mcp-package.sh - assembles the ActionUI MCP server for Linux as a folder and a tarball:
#
#   actionui-mcp-<version>-linux-<arch>/
#     bin/actionui-mcp                          the server, stripped
#     share/actionui/schemas/                   the element schemas the server checks documents with
#     share/actionui/schemas/add-ons/<AddOn>/   the schemas of the add-ons the Linux server has
#     share/actionui/docs/<Name>/               the element reference it serves as MCP resources
#     share/actionui/ActionUIMCP.svg            the windows' icon (actionui-mcp --install-desktop-entry)
#     LICENSE.txt
#     LICENSE-MaterialSymbols.txt               the license of the symbol icons in the server
#     LICENSE-RichText.txt, LICENSE-AsyncImageCache.txt   the licenses of the packages the add-ons link
#   actionui-mcp-<version>-linux-<arch>.tar.gz  the folder, packed
#
# The server finds the schemas and the documentation from its own place, so the folder stays together; unpack it
# anywhere. It needs GTK 4, libadwaita and libsoup 3 on the machine (WebKitGTK 6.0 for web pages, optional), and
# must be built with the Swift runtime linked in:
#   swift build -c release --static-swift-stdlib --package-path Apps/ActionUIMCP \
#       --only-use-versions-from-resolved-file --manifest-cache none
# A server linked to a toolchain's Swift runtime is refused, as is one carrying ICU's data (a file importing
# Foundation).
#
# Usage: Scripts/make-linux-mcp-package.sh <products folder> <output folder>
#   products folder: where swift build put actionui-mcp (Linux), such as Apps/ActionUIMCP/.build/release
#   output folder:   where the folder and the tarball are made; ones already there are replaced
# Exit status: 0 made, 1 a step failed, 64 bad arguments.

script_dir="$(CDPATH= cd "$(/usr/bin/dirname "$0")" && pwd)"
if [ -z "$script_dir" ]; then
    printf 'make-linux-mcp-package: could not find the folder of %s\n' "$0" >&2
    exit 1
fi
repo="$(/usr/bin/dirname "$script_dir")"

if [ "$#" -ne 2 ]; then
    printf 'usage: %s <products folder> <output folder>\n' "$0" >&2
    exit 64
fi
server="$1/actionui-mcp"
output="$2"

if [ ! -x "$server" ]; then
    printf 'make-linux-mcp-package: no server at %s; build the package on Linux first\n' "$server" >&2
    exit 1
fi
if [ ! -d "$output" ]; then
    printf 'make-linux-mcp-package: the output folder %s does not exist\n' "$output" >&2
    exit 1
fi

# The add-ons the Linux server links (Apps/ActionUIMCP/Package.swift, linuxPackage): their schemas and pages go in.
addons="ActionUICachedImage ActionUIRichText"

# The version the server states ("actionui-mcp 0.2.1"), and the machine.
stated="$("$server" --version 2>&1)"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'make-linux-mcp-package: %s --version failed: %s\n' "$server" "$stated" >&2
    exit 1
fi
version="${stated#actionui-mcp }"
if [ -z "$version" ] || [ "$version" = "$stated" ]; then
    printf 'make-linux-mcp-package: could not read the version from "%s"\n' "$stated" >&2
    exit 1
fi
arch="$(/usr/bin/uname -m)"
name="actionui-mcp-$version-linux-$arch"
package="$output/$name"
tarball="$output/$name.tar.gz"

# The Swift runtime linked in: no Swift runtime, libdispatch or Foundation library from a toolchain.
linked="$(/usr/bin/ldd "$server" 2>&1)"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'make-linux-mcp-package: ldd could not read %s: %s\n' "$server" "$linked" >&2
    exit 1
fi
case "$linked" in
    *libswift*|*libdispatch*|*libFoundation*)
        printf 'make-linux-mcp-package: %s uses the Swift runtime of the toolchain that built it; build it with --static-swift-stdlib\n' "$server" >&2
        exit 1
        ;;
esac

# No ICU data: one file importing Foundation brings it back.
icu_mentions="$(/usr/bin/grep -c icudt "$server")"
if [ "$icu_mentions" != 0 ]; then
    printf 'make-linux-mcp-package: %s contains ICU data (icudt): a file imports Foundation\n' "$server" >&2
    exit 1
fi

# With its symbol icons: a build without Scripts/prepare-linux-symbols.sh shows none.
if [ ! -x /usr/bin/gresource ]; then
    printf 'make-linux-mcp-package: no /usr/bin/gresource to check the symbol icons with (install libglib2.0-bin)\n' >&2
    exit 1
fi
sections="$(/usr/bin/gresource sections "$server" 2>&1)"
case "$sections" in
    *actionui_symbols*) ;;
    *)
        printf 'make-linux-mcp-package: %s has no symbol icons; run Scripts/prepare-linux-symbols.sh, then build it again (gresource: %s)\n' "$server" "$sections" >&2
        exit 1
        ;;
esac

# The packages the add-ons link (Apache 2.0), as checked out for this build: <scratch>/checkouts. The products folder
# is <scratch>/out/Products/<configuration>-linux-<arch>, or <scratch>/<triple>/<configuration> with SwiftPM's native
# build system.
dependencies="RichText AsyncImageCache"
products="$(/usr/bin/readlink -f "$1")"
scratch="$(/usr/bin/dirname "$(/usr/bin/dirname "$products")")"
if [ ! -d "$scratch/checkouts" ]; then
    scratch="$(/usr/bin/dirname "$scratch")"
fi
checkouts="$scratch/checkouts"
for dependency in $dependencies; do
    if [ ! -f "$checkouts/$dependency/LICENSE" ]; then
        printf 'make-linux-mcp-package: no license of %s in %s; give the products folder swift build made, so that the packages it checked out are found\n' "$dependency" "$checkouts" >&2
        exit 1
    fi
done

for old in "$package" "$tarball"; do
    if [ -e "$old" ]; then
        /bin/rm -rf "$old"
        status=$?
        if [ "$status" -ne 0 ]; then
            printf 'make-linux-mcp-package: could not remove the old %s\n' "$old" >&2
            exit 1
        fi
    fi
done
# A step that fails after this leaves no partial folder or tarball behind.
discard_package() {
    /bin/rm -rf "$package" "$tarball"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        printf 'make-linux-mcp-package: could not remove the partial %s\n' "$package" >&2
    fi
}

# Copies a file or a folder ($1) into the package folder $2, making that first. Prints what failed; returns its status.
copy_into_package() {
    local _folder="$package/$2"
    /bin/mkdir -p "$_folder"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        printf 'make-linux-mcp-package: could not make %s\n' "$_folder" >&2
        discard_package
        return 1
    fi
    /bin/cp -R "$1" "$_folder/"
    _status=$?
    if [ "$_status" -ne 0 ]; then
        printf 'make-linux-mcp-package: could not copy %s to %s\n' "$1" "$_folder" >&2
        discard_package
        return 1
    fi
    return 0
}

# The JSON files of a schemas folder ($1) into the package folder $2. A folder with none names no file.
copy_schemas() {
    local schema
    for schema in "$1"/*.json; do
        if [ ! -e "$schema" ]; then
            continue
        fi
        copy_into_package "$schema" "$2" || return 1
    done
    return 0
}

# A documentation folder ($1) as the server serves it, into share/actionui/docs/$2: the element pages and templates,
# and for the core the guide and the element index.
copy_docs() {
    local _target="share/actionui/docs/$2"
    copy_into_package "$1/Schemas" "$_target" || return 1
    copy_into_package "$1/Elements" "$_target" || return 1
    local page
    for page in ActionUI-JSON-Guide.md ActionUI-Elements.md; do
        if [ -e "$1/$page" ]; then
            copy_into_package "$1/$page" "$_target" || return 1
        fi
    done
    return 0
}

copy_into_package "$server" bin || exit 1
copy_into_package "$repo/LICENSE.txt" . || exit 1
# The add-ons' packages and the Material Symbols icons are in the server (Apache 2.0): their licenses go with it.
for dependency in $dependencies; do
    /bin/cp "$checkouts/$dependency/LICENSE" "$package/LICENSE-$dependency.txt"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'make-linux-mcp-package: could not copy the license of %s from %s\n' "$dependency" "$checkouts" >&2
        discard_package
        exit 1
    fi
done
/bin/bash "$repo/Tools/material_symbols/write-material-symbols-license.sh" "$package/LICENSE-MaterialSymbols.txt"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'make-linux-mcp-package: could not write the Material Symbols license notice\n' >&2
    discard_package
    exit 1
fi
copy_schemas "$repo/ActionUIVerifier/Schemas" share/actionui/schemas || exit 1
copy_into_package "$repo/Apps/ActionUIMCP/Sources/ActionUIMCP/Resources/ActionUIMCP.svg" share/actionui || exit 1
copy_docs "$repo/Documentation" ActionUI || exit 1
for addon in $addons; do
    copy_schemas "$repo/Add-ons/$addon/Schemas" "share/actionui/schemas/add-ons/$addon" || exit 1
    copy_docs "$repo/Add-ons/$addon/Documentation" "$addon" || exit 1
done

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
    "$stripper" --strip-all "$package/bin/actionui-mcp"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'make-linux-mcp-package: %s could not strip %s\n' "$stripper" "$package/bin/actionui-mcp" >&2
        discard_package
        exit 1
    fi
else
    printf 'make-linux-mcp-package: note: no llvm-objcopy, objcopy or strip found; the server keeps its symbols\n'
fi

# Owned by root in the archive, whoever packed it, and readable by all whatever the umask was (GNU tar).
/usr/bin/tar --owner=0 --group=0 --numeric-owner --mode='u+rwX,go+rX,go-w' -czf "$tarball" -C "$output" "$name"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'make-linux-mcp-package: could not pack %s\n' "$tarball" >&2
    discard_package
    exit 1
fi

printf 'make-linux-mcp-package: made %s and %s\n' "$package" "$tarball"
