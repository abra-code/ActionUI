#!/bin/bash
# Verify all ActionUI JSON asset files for the Android demo app.
#
# Android counterpart of ActionUISwiftTestApp/Scripts/verify_json_resources.sh.
# Runs the shared Python validator (Tools/verifier/validate_actionui.py) against
# the demoApp assets, filtering platform-suffixed keys for "android".
#
# Invoked automatically by the :demoApp Gradle build (see demoApp/build.gradle.kts,
# task "verifyJsonResources"), and usable standalone / in CI.
#
# python3 must be on PATH; if absent we warn and skip rather than fail the build.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANDROID_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$ANDROID_ROOT/.." && pwd)"

# Allow Gradle (or a caller) to override the assets dir; default to demoApp assets.
ASSETS_DIR="${ACTIONUI_ASSETS_DIR:-$ANDROID_ROOT/demoApp/src/main/assets}"
PYTHON_VALIDATOR="$REPO_ROOT/Tools/verifier/validate_actionui.py"

if [ ! -d "$ASSETS_DIR" ]; then
    echo "error: assets directory not found at $ASSETS_DIR"
    exit 1
fi

if ! command -v python3 &> /dev/null; then
    echo "warning: python3 not found on PATH — skipping ActionUI JSON validation"
    exit 0
fi

if [ ! -f "$PYTHON_VALIDATOR" ]; then
    echo "warning: Python validator not found at $PYTHON_VALIDATOR — skipping"
    exit 0
fi

echo "Validating ActionUI JSON assets in $ASSETS_DIR (platform: android)"
python3 "$PYTHON_VALIDATOR" "$ASSETS_DIR" --recursive --platform android
