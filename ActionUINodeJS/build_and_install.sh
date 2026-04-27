#!/bin/bash
# Build ActionUI frameworks and produce universal prebuilt binaries for
# actionui Node.js addon.
#
# Usage:
#   ./build_and_install.sh
#   ./build_and_install.sh /path/to/frameworks   # custom frameworks output dir
#   ./build_and_install.sh /path/to/frameworks Release
#   ./build_and_install.sh /path/to/frameworks Debug
#
# What it does:
#   1. Removes stale build/ and prebuilds/ directories
#   2. Builds the ActionUIAppKitApplication scheme as Release (or Debug) universal
#      (arm64 + x86_64), which also builds ActionUI and ActionUICAdapter
#      as dependencies
#   3. Runs prebuildify for arm64 and x64, producing:
#        prebuilds/darwin-arm64/node.napi.node
#        prebuilds/darwin-x64/node.napi.node
#   4. Installs node_modules so the package is usable locally
#      (node-gyp-build picks the prebuilt automatically)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# --- Determine frameworks output directory and configuration ---
CONFIG="${2:-Release}"
if [ -n "${1:-}" ]; then
    FRAMEWORKS_DIR="$(mkdir -p "$1" && cd "$1" && pwd)"
else
    FRAMEWORKS_DIR="$SCRIPT_DIR/frameworks"
    mkdir -p "$FRAMEWORKS_DIR"
fi

# Prebuildify flag for debug builds
PREBUILDIFY_CONFIG=""
if [ "$CONFIG" = "Debug" ]; then
    PREBUILDIFY_CONFIG="--debug"
fi

# --- Clean stale artifacts ---
echo "Cleaning stale build artifacts..."
rm -rf "$SCRIPT_DIR/build" "$SCRIPT_DIR/prebuilds"

# --- Build frameworks with xcodebuild ---
echo "Building ActionUIAppKitApplication $CONFIG universal (arm64 + x86_64)..."
xcodebuild \
    -project "$PROJECT_DIR/ActionUI.xcodeproj" \
    -scheme ActionUIAppKitApplication \
    -destination 'platform=macOS' \
    -configuration "$CONFIG" \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    ONLY_ACTIVE_ARCH=NO \
    SYMROOT="$FRAMEWORKS_DIR" \
    build 2>&1 | tail -3

# xcodebuild places output under SYMROOT/$CONFIG/
BUILT_DIR="$FRAMEWORKS_DIR/$CONFIG"

for fw in ActionUI ActionUICAdapter ActionUIAppKitApplication; do
    if [ ! -d "$BUILT_DIR/${fw}.framework" ]; then
        echo "Error: ${fw}.framework not found in $BUILT_DIR" >&2
        exit 1
    fi
done

echo "Frameworks directory: $BUILT_DIR"

# --- Ensure devDependencies (prebuildify) are installed ---
cd "$SCRIPT_DIR"
if [ ! -f node_modules/.bin/prebuildify ]; then
    echo "Installing devDependencies (prebuildify)..."
    npm install --include=dev
fi

# --- Build prebuilt binaries for both architectures ---
# The static frameworks are universal fat binaries, so the linker automatically
# pulls the correct slice for each target architecture.

echo "Building prebuilt: arm64..."
ACTIONUI_FRAMEWORKS_DIR="$BUILT_DIR" \
    node_modules/.bin/prebuildify --napi --arch arm64 --strip $PREBUILDIFY_CONFIG

echo "Building prebuilt: x64..."
ACTIONUI_FRAMEWORKS_DIR="$BUILT_DIR" \
    node_modules/.bin/prebuildify --napi --arch x64 --strip $PREBUILDIFY_CONFIG

echo ""
echo "Prebuilt binaries:"
find prebuilds -name '*.node' | while read f; do
    echo "  $f  $(lipo -info "$f" 2>/dev/null | grep -o 'architecture:.*' || true)"
done

echo ""
echo "Done. node-gyp-build will auto-select the correct binary at runtime."
echo ""
echo "  const actionui = require('./index.js');"
echo "  const app = new actionui.Application({ name: 'MyApp' });"
