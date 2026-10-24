#!/bin/bash
#
# Scripts/make-linux-demo-bundle.sh - assembles ActionUIDemo.app, the Linux demo app's bundle: a
# folder holding the program and its resources side by side (a simplified iOS-style bundle).
#
#   ActionUIDemo.app/
#     ActionUIDemo        the ActionUIAdwaitaDemo program
#     *.json, *.png ...   ActionUISwiftTestApp/Resources, copied
#     Orb.png ...         the test app's asset images, named after their assets (Image assetName)
#
# The program finds its documents in the folder it runs from. It is linked to the Swift runtime of
# the toolchain that built it, so the bundle runs where that toolchain is (the development box).
#
# Usage: Scripts/make-linux-demo-bundle.sh <products folder> <output folder>
#   products folder: where swift build put ActionUIAdwaitaDemo (Linux)
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

if [ -e "$bundle" ]; then
    /bin/rm -rf "$bundle"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'make-linux-demo-bundle: could not remove the old %s\n' "$bundle" >&2
        exit 1
    fi
fi
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
    exit 1
fi

# The documents and the files they use, flat, as in the iOS bundle.
/bin/cp "$resources"/* "$bundle/"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'make-linux-demo-bundle: could not copy %s\n' "$resources" >&2
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
            exit 1
        fi
    done
done

printf 'make-linux-demo-bundle: made %s\n' "$bundle"
