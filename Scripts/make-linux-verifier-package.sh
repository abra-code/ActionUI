#!/bin/bash
#
# Scripts/make-linux-verifier-package.sh - assembles the document verifier for Linux as a folder and a tarball, for
# people who check ActionUI documents without building ActionUI:
#
#   actionui-verify-<version>-linux-<arch>/
#     bin/actionui-verify                  the tool, stripped
#     share/actionui/schemas/              the element schemas, where the tool looks for them
#     share/actionui/schemas/add-ons/<AddOn>/   the add-ons' schemas, each add-on's documents being checkable
#     LICENSE.txt
#   actionui-verify-<version>-linux-<arch>.tar.gz   the folder, packed
#
# The tool is self-contained: it must be built with the Swift runtime linked in, and then needs only the C and C++
# libraries, no older than the build machine's, and no GTK. Unpack it anywhere; it finds the schemas from its own
# place. Build it with
#   swift build -c release --static-swift-stdlib --package-path Apps/ActionUIVerifier
# A tool linked to a toolchain's Swift runtime or to GTK is refused, as is one carrying ICU's data (a file importing
# Foundation).
#
# Usage: Scripts/make-linux-verifier-package.sh <products folder> <output folder>
#   products folder: where swift build put actionui-verify (Linux), such as Apps/ActionUIVerifier/.build/release
#   output folder:   where the folder and the tarball are made; ones already there are replaced
# Exit status: 0 made, 1 a step failed, 64 bad arguments.

script_dir="$(CDPATH= cd "$(/usr/bin/dirname "$0")" && pwd)"
if [ -z "$script_dir" ]; then
    printf 'make-linux-verifier-package: could not find the folder of %s\n' "$0" >&2
    exit 1
fi
repo="$(/usr/bin/dirname "$script_dir")"

if [ "$#" -ne 2 ]; then
    printf 'usage: %s <products folder> <output folder>\n' "$0" >&2
    exit 64
fi
tool="$1/actionui-verify"
output="$2"

if [ ! -x "$tool" ]; then
    printf 'make-linux-verifier-package: no tool at %s; build the package on Linux first\n' "$tool" >&2
    exit 1
fi
if [ ! -d "$output" ]; then
    printf 'make-linux-verifier-package: the output folder %s does not exist\n' "$output" >&2
    exit 1
fi

# The version ActionUI states (ActionUIVersion.string), and the machine.
version="$(/usr/bin/sed -n 's/.*public static let string = "\([^"]*\)".*/\1/p' "$repo/ActionUI/Core/Common/ActionUIVersion.swift")"
if [ -z "$version" ]; then
    printf 'make-linux-verifier-package: could not read the version from ActionUI/Core/Common/ActionUIVersion.swift\n' >&2
    exit 1
fi
arch="$(/usr/bin/uname -m)"
name="actionui-verify-$version-linux-$arch"
package="$output/$name"
tarball="$output/$name.tar.gz"

# Self-contained: no Swift runtime, libdispatch or Foundation library from a toolchain, and no GTK.
linked="$(/usr/bin/ldd "$tool" 2>&1)"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'make-linux-verifier-package: ldd could not read %s: %s\n' "$tool" "$linked" >&2
    exit 1
fi
case "$linked" in
    *libswift*|*libdispatch*|*libFoundation*)
        printf 'make-linux-verifier-package: %s uses the Swift runtime of the toolchain that built it; build it with --static-swift-stdlib\n' "$tool" >&2
        exit 1
        ;;
    *libgtk*|*libadwaita*)
        printf 'make-linux-verifier-package: %s links GTK, which the verifier must not need\n' "$tool" >&2
        exit 1
        ;;
esac

# No ICU data: one file importing Foundation brings it back.
icu_mentions="$(/usr/bin/grep -c icudt "$tool")"
if [ "$icu_mentions" != 0 ]; then
    printf 'make-linux-verifier-package: %s contains ICU data (icudt): a file imports Foundation\n' "$tool" >&2
    exit 1
fi

for old in "$package" "$tarball"; do
    if [ -e "$old" ]; then
        /bin/rm -rf "$old"
        status=$?
        if [ "$status" -ne 0 ]; then
            printf 'make-linux-verifier-package: could not remove the old %s\n' "$old" >&2
            exit 1
        fi
    fi
done
# A step that fails after this leaves no partial folder or tarball behind.
discard_package() {
    /bin/rm -rf "$package" "$tarball"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'make-linux-verifier-package: could not remove the partial %s\n' "$package" >&2
    fi
}

# The parent folder of a copy, then the copy. Prints what failed; returns its status.
copy_into_package() {
    local _folder="$package/$2"
    /bin/mkdir -p "$_folder"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        printf 'make-linux-verifier-package: could not make %s\n' "$_folder" >&2
        discard_package
        return 1
    fi
    /bin/cp "$1" "$_folder/"
    _status=$?
    if [ "$_status" -ne 0 ]; then
        printf 'make-linux-verifier-package: could not copy %s to %s\n' "$1" "$_folder" >&2
        discard_package
        return 1
    fi
    return 0
}

copy_into_package "$tool" bin || exit 1
copy_into_package "$repo/LICENSE.txt" . || exit 1
for schema in "$repo"/ActionUIVerifier/Schemas/*.json; do
    copy_into_package "$schema" share/actionui/schemas || exit 1
done
for folder in "$repo"/Add-ons/*/Schemas; do
    addon="${folder%/Schemas}"
    addon="${addon##*/}"
    for schema in "$folder"/*.json; do
        # An add-on with no schemas leaves the pattern as it is, naming no file.
        if [ ! -e "$schema" ]; then
            continue
        fi
        copy_into_package "$schema" "share/actionui/schemas/add-ons/$addon" || exit 1
    done
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
    "$stripper" --strip-all "$package/bin/actionui-verify"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'make-linux-verifier-package: %s could not strip %s\n' "$stripper" "$package/bin/actionui-verify" >&2
        discard_package
        exit 1
    fi
else
    printf 'make-linux-verifier-package: note: no llvm-objcopy, objcopy or strip found; the tool keeps its symbols\n'
fi

# Owned by root in the archive, whoever packed it (GNU tar).
/usr/bin/tar --owner=0 --group=0 --numeric-owner -czf "$tarball" -C "$output" "$name"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'make-linux-verifier-package: could not pack %s\n' "$tarball" >&2
    discard_package
    exit 1
fi

printf 'make-linux-verifier-package: made %s and %s\n' "$package" "$tarball"
