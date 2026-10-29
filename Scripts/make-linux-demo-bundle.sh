#!/bin/bash
#
# Scripts/make-linux-demo-bundle.sh - assembles ActionUIDemo.app, the Linux demo app's bundle: a
# folder holding the program and its resources side by side (a simplified iOS-style bundle).
#
#   ActionUIDemo.app/
#     ActionUIDemo        the ActionUIAdwaitaDemo program
#     *.json, *.png ...   ActionUISwiftTestApp/Resources, copied
#     Orb.png ...         the test app's asset images, named after their assets (Image assetName)
#     Info.json           the app's ID, name and icon (ActionUIAdwaita/DemoBundle, copied)
#     ActionUIDemo.svg    the app's icon (ActionUIAdwaita/DemoBundle)
#
# The program finds its documents in the folder it runs from. The bundle is self-contained: the
# program must be built with the Swift runtime linked in, and then needs only the system's GTK 4,
# libadwaita and libsoup 3 (and WebKitGTK 6.0 for its WebView page, loaded when shown). Build it with
#   swift build -c release --static-swift-stdlib --product ActionUIAdwaitaDemo
# A program linked to a toolchain's Swift runtime is refused. The bundle's copy is stripped of its
# symbols (llvm-objcopy from the Swift toolchain, else the system's objcopy or strip; left as it is,
# with a note, when none is found).
#
# Usage: Scripts/make-linux-demo-bundle.sh <products folder> <output folder>
#   products folder: where swift build put ActionUIAdwaitaDemo (Linux), such as .build/release
#   output folder:   where ActionUIDemo.app is made; an ActionUIDemo.app already there is replaced
# Exit status: 0 made, 1 a step failed, 64 bad arguments.

script_dir="$(CDPATH= cd "$(/usr/bin/dirname "$0")" && pwd)"
if [ -z "$script_dir" ]; then
    printf 'make-linux-demo-bundle: could not find the folder of %s\n' "$0" >&2
    exit 1
fi
repo="$(/usr/bin/dirname "$script_dir")"
resources="$repo/ActionUISwiftTestApp/Resources"
assets="$repo/ActionUISwiftTestApp/Assets.xcassets"
demo_bundle_files="$repo/ActionUIAdwaita/DemoBundle"

if [ "$#" -ne 2 ]; then
    printf 'usage: %s <products folder> <output folder>\n' "$0" >&2
    exit 64
fi
program="$1/ActionUIAdwaitaDemo"
bundle="$2/ActionUIDemo.app"

if [ ! -x "$program" ]; then
    printf 'make-linux-demo-bundle: no program at %s; build the package on Linux first\n' "$program" >&2
    exit 1
fi
if [ ! -d "$2" ]; then
    printf 'make-linux-demo-bundle: the output folder %s does not exist\n' "$2" >&2
    exit 1
fi

# Self-contained: no Swift runtime library from a toolchain.
linked="$(/usr/bin/ldd "$program" 2>&1)"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'make-linux-demo-bundle: ldd could not read %s: %s\n' "$program" "$linked" >&2
    exit 1
fi
case "$linked" in
    *libswiftCore*)
        printf 'make-linux-demo-bundle: %s uses the Swift runtime of the toolchain that built it; build it with --static-swift-stdlib\n' "$program" >&2
        exit 1
        ;;
esac

if [ -e "$bundle" ]; then
    /bin/rm -rf "$bundle"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'make-linux-demo-bundle: could not remove the old %s\n' "$bundle" >&2
        exit 1
    fi
fi
# A step that fails after this leaves no partial bundle behind.
discard_bundle() {
    /bin/rm -rf "$bundle"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'make-linux-demo-bundle: could not remove the partial %s\n' "$bundle" >&2
    fi
}

/bin/mkdir "$bundle"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'make-linux-demo-bundle: could not make %s\n' "$bundle" >&2
    exit 1
fi

/bin/cp "$program" "$bundle/ActionUIDemo"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'make-linux-demo-bundle: could not copy the program into %s\n' "$bundle" >&2
    discard_bundle
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
    "$stripper" --strip-all "$bundle/ActionUIDemo"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'make-linux-demo-bundle: %s could not strip the program in %s\n' "$stripper" "$bundle" >&2
        discard_bundle
        exit 1
    fi
else
    printf 'make-linux-demo-bundle: note: no llvm-objcopy, objcopy or strip found; the program keeps its symbols\n'
fi

# The documents and the files they use, flat, as in the iOS bundle.
/bin/cp "$resources"/* "$bundle/"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'make-linux-demo-bundle: could not copy %s\n' "$resources" >&2
    discard_bundle
    exit 1
fi

# Each asset image as a file named after its asset (Orb.imageset/orb.png -> Orb.png).
for imageset in "$assets"/*.imageset; do
    name="$(/usr/bin/basename "$imageset" .imageset)"
    for image in "$imageset"/*; do
        file="$(/usr/bin/basename "$image")"
        if [ "$file" = "Contents.json" ]; then
            continue
        fi
        extension="${file##*.}"
        /bin/cp "$image" "$bundle/$name.$extension"
        status=$?
        if [ "$status" -ne 0 ]; then
            printf 'make-linux-demo-bundle: could not copy the asset image %s\n' "$image" >&2
            discard_bundle
            exit 1
        fi
    done
done

# The app's Info.json (application ID, name, icon) and its icon, for the runtime and for
# Scripts/linux-app-entry.py, which adds the bundle to the desktop's app list.
/bin/cp "$demo_bundle_files"/* "$bundle/"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'make-linux-demo-bundle: could not copy %s\n' "$demo_bundle_files" >&2
    discard_bundle
    exit 1
fi

printf 'make-linux-demo-bundle: made %s; add it to the app list with Scripts/linux-app-entry.py install %s\n' "$bundle" "$bundle"
