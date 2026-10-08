#!/bin/bash
# Build the ActionUI static frameworks that the Rust crates link against.
#
# Usage:
#   ./build_frameworks.sh                 # output in ./frameworks/Release
#   ./build_frameworks.sh /path/to/dir    # output in /path/to/dir/Release
#
# Builds the ActionUIAppKitApplication scheme as Release universal (arm64 + x86_64),
# which also builds ActionUI, ActionUICAdapter, ActionUIMenuBar and ActionUIRemote.
# The actionui-sys build script finds the result in ./frameworks/Release on its own;
# for any other location set ACTIONUI_FRAMEWORKS_DIR to the Release directory.

script_dir="$(cd "$(/usr/bin/dirname "$0")" && pwd)"
if [ -z "$script_dir" ]; then
    printf 'Error: cannot resolve the directory of %s\n' "$0" >&2
    exit 1
fi
project_dir="$(/usr/bin/dirname "$script_dir")"

frameworks_dir="$script_dir/frameworks"
if [ -n "$1" ]; then
    frameworks_dir="$1"
fi

/bin/mkdir -p "$frameworks_dir"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Error: cannot create the output directory %s\n' "$frameworks_dir" >&2
    exit 1
fi
resolved_dir="$(cd "$frameworks_dir" && pwd)"
if [ -z "$resolved_dir" ]; then
    printf 'Error: cannot enter the output directory %s\n' "$frameworks_dir" >&2
    exit 1
fi
frameworks_dir="$resolved_dir"

log_file="$frameworks_dir/xcodebuild.log"
printf 'Building ActionUIAppKitApplication, Release, arm64 + x86_64...\n'

# Intermediates go next to the products (OBJROOT) so the build writes nothing
# outside the output directory.
/usr/bin/xcodebuild \
    -project "$project_dir/ActionUI.xcodeproj" \
    -scheme ActionUIAppKitApplication \
    -destination 'generic/platform=macOS' \
    -configuration Release \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    ONLY_ACTIVE_ARCH=NO \
    SYMROOT="$frameworks_dir" \
    OBJROOT="$frameworks_dir/Intermediates" \
    build > "$log_file" 2>&1
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Error: xcodebuild failed with status %s. Last lines of %s:\n' "$status" "$log_file" >&2
    /usr/bin/tail -n 30 "$log_file" >&2
    exit 1
fi

built_dir="$frameworks_dir/Release"
for framework in ActionUI ActionUICAdapter ActionUIAppKitApplication ActionUIMenuBar ActionUIRemote; do
    if [ ! -d "$built_dir/$framework.framework" ]; then
        printf 'Error: %s.framework is missing from %s. See %s\n' "$framework" "$built_dir" "$log_file" >&2
        exit 1
    fi
done

printf 'Frameworks are in %s\n' "$built_dir"
