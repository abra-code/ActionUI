#!/bin/bash
# Verify all JSON resource files during build.
# Primary:  Python validator (Skill/scripts/validate_actionui.py)
# Fallback: ActionUIVerifier binary (macOS only)
#
# python3 must be on PATH; warn and fall back to the binary verifier if absent.

RESOURCES_DIR="${SRCROOT}/ActionUISwiftTestApp/Resources"
PYTHON_VALIDATOR="${SRCROOT}/Tools/verifier/validate_actionui.py"

if [ ! -d "$RESOURCES_DIR" ]; then
    echo "error: Resources directory not found at $RESOURCES_DIR"
    exit 1
fi

# ── Try Python validator ──────────────────────────────────────────────────────
if command -v python3 &> /dev/null; then
    if [ ! -f "$PYTHON_VALIDATOR" ]; then
        echo "warning: Python validator not found at $PYTHON_VALIDATOR"
    else
        python3 "$PYTHON_VALIDATOR" "$RESOURCES_DIR"
        PY_EXIT=$?
        if [ $PY_EXIT -ne 0 ]; then
            exit $PY_EXIT
        fi
        exit 0
    fi
else
    echo "warning: python3 not found on PATH — falling back to ActionUIVerifier binary"
fi

# ── Fallback: ActionUIVerifier binary (macOS only) ───────────────────────────
VERIFIER="${BUILT_PRODUCTS_DIR}/ActionUIVerifier"

if [ ! -x "$VERIFIER" ]; then
    if [ "${PLATFORM_FAMILY_NAME}" = "macOS" ]; then
        echo "error: ActionUIVerifier not found at $VERIFIER (and python3 unavailable)"
        exit 1
    else
        echo "warning: ActionUIVerifier runs only on macOS and python3 was not found"
        exit 0
    fi
fi

"$VERIFIER" "$RESOURCES_DIR"
