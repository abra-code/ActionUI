#!/bin/bash
# Verify all JSON resource files using ActionUIVerifier during build.
# This is "Run Script" build phase in ActionUISwiftTestApp

VERIFIER="${BUILT_PRODUCTS_DIR}/ActionUIVerifier"

if [ ! -x "$VERIFIER" ]; then
    echo "error: ActionUIVerifier not found at $VERIFIER"
    exit 1
fi

RESOURCES_DIR="${SRCROOT}/ActionUISwiftTestApp/Resources"

if [ ! -d "$RESOURCES_DIR" ]; then
    echo "error: Resources directory not found at $RESOURCES_DIR"
    exit 1
fi

"$VERIFIER" "$RESOURCES_DIR"
