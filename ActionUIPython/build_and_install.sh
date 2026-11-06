#!/bin/bash
# Build ActionUI frameworks and install the actionui Python module.
#
# Usage:
#   ./build_and_install.sh
#   ./build_and_install.sh /path/to/frameworks   # custom output dir
#
# What it does:
#   1. Removes stale build/ and actionui.egg-info/ directories
#   2. Builds the ActionUIAppKitApplication scheme as Release universal
#      (arm64 + x86_64), which also builds ActionUI and ActionUICAdapter
#      as dependencies
#   3. Exports ACTIONUI_FRAMEWORKS_DIR and runs pip3 install

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# --- Determine frameworks output directory ---
if [ -n "${1:-}" ]; then
    FRAMEWORKS_DIR="$(cd "$1" 2>/dev/null && pwd || mkdir -p "$1" && cd "$1" && pwd)"
else
    FRAMEWORKS_DIR="$SCRIPT_DIR/frameworks"
    mkdir -p "$FRAMEWORKS_DIR"
fi

# --- Clean stale build artifacts ---
echo "Cleaning stale build artifacts..."
rm -rf "$SCRIPT_DIR/build" "$SCRIPT_DIR/actionui.egg-info"

# --- Build frameworks with xcodebuild ---
echo "Building ActionUIAppKitApplication Release universal (arm64 + x86_64)..."
xcodebuild \
    -project "$PROJECT_DIR/ActionUI.xcodeproj" \
    -scheme ActionUIAppKitApplication \
    -destination 'platform=macOS' \
    -configuration Release \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    ONLY_ACTIVE_ARCH=NO \
    SYMROOT="$FRAMEWORKS_DIR" \
    build 2>&1 | tail -3

if [ $? -ne 0 ]; then
    echo "Error: xcodebuild failed" >&2
    exit 1
fi

# xcodebuild places output under SYMROOT/Release/
BUILT_DIR="$FRAMEWORKS_DIR/Release"

# The HostSurface add-on, against the ActionUI framework just built (same SYMROOT). Its intermediates
# are its own: two projects sharing one OBJROOT delete each other's files as stale, and every run
# then recompiles all of ActionUI.
echo "Building the ActionUIHostSurface add-on..."
# The script runs with set -e: the status is captured with || so a failure reaches the message below.
status=0
xcodebuild \
    -project "$PROJECT_DIR/Add-ons/ActionUIHostSurface/Framework/ActionUIHostSurface.xcodeproj" \
    -scheme ActionUIHostSurface \
    -destination 'generic/platform=macOS' \
    -configuration Release \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    ONLY_ACTIVE_ARCH=NO \
    SYMROOT="$FRAMEWORKS_DIR" \
    OBJROOT="$FRAMEWORKS_DIR/Intermediates-HostSurface" \
    build > "$FRAMEWORKS_DIR/xcodebuild-hostsurface.log" 2>&1 || status=$?
if [ "$status" -ne 0 ]; then
    echo "Error: xcodebuild failed for the HostSurface add-on (status $status); see $FRAMEWORKS_DIR/xcodebuild-hostsurface.log" >&2
    exit 1
fi

# Verify all the frameworks exist
for fw in ActionUI ActionUICAdapter ActionUIAppKitApplication ActionUIRemote ActionUIHostSurface; do
    if [ ! -d "$BUILT_DIR/${fw}.framework" ]; then
        echo "Error: ${fw}.framework not found in $BUILT_DIR" >&2
        exit 1
    fi
done

echo "Frameworks directory: $BUILT_DIR"

# --- Install Python module ---
echo "Installing actionui Python module..."
cd "$SCRIPT_DIR"
ACTIONUI_FRAMEWORKS_DIR="$BUILT_DIR" pip3 install --no-cache-dir --verbose .

echo ""
echo "Done. You can now 'import actionui' in Python."
