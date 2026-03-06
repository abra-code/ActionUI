#!/bin/bash
# Verify all JSON resource files using ActionUIVerifier during build.
# Add this as a "Run Script" build phase in ActionUISwiftTestApp,
# after the "Copy Bundle Resources" phase.
# Ensure ActionUIVerifier is listed as a target dependency.

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
