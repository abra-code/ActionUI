#!/bin/bash
#
# Wraps a built Rust executable in a macOS application bundle, so it has its own
# name, icon and Dock entry and can be opened from the Finder.
#
#   ./make_app_bundle.sh <executable> "<App Name>" [bundle-identifier] [icon.icns]
#
# Example:
#   cargo build --release --example folder_contents
#   ./make_app_bundle.sh target/release/examples/folder_contents "Folder Contents"
#
# The bundle is created beside the executable and signed for this Mac only
# (an ad-hoc signature). To give it to other people, sign it with a
# Developer ID certificate and have Apple notarize it.

# Byte-wise matching: in a UTF-8 locale the ranges below (A-Z, a-z) also match
# accented letters, and a bundle identifier must be plain ASCII.
LC_ALL=C
export LC_ALL

executable="$1"
app_name="$2"
bundle_id="$3"
icon="$4"

if [ -z "$executable" ] || [ -z "$app_name" ]; then
    printf 'usage: %s <executable> "<App Name>" [bundle-identifier] [icon.icns]\n' "$0" >&2
    exit 2
fi

if [ ! -f "$executable" ] || [ ! -x "$executable" ]; then
    printf 'error: %s is not an executable file. Build it first with cargo build.\n' "$executable" >&2
    exit 1
fi

# The name goes into Info.plist, which is XML, and into a folder name.
case "$app_name" in
    *'&'*|*'<'*|*'>'*|*'/'*)
        printf 'error: the application name must not contain & < > or /.\n' >&2
        exit 1
        ;;
esac

if [ -n "$icon" ] && [ ! -f "$icon" ]; then
    printf 'error: the icon file %s does not exist.\n' "$icon" >&2
    exit 1
fi

executable_name="$(/usr/bin/basename "$executable")"
# The file name goes into Info.plist too.
case "$executable_name" in
    *'&'*|*'<'*|*'>'*)
        printf 'error: the name of the executable file must not contain & < or >.\n' >&2
        exit 1
        ;;
esac
output_dir="$(/usr/bin/dirname "$executable")"
app="$output_dir/$app_name.app"

if [ -z "$bundle_id" ]; then
    # Letters, digits, hyphens and periods only.
    bundle_suffix="$(printf '%s' "$executable_name" | /usr/bin/tr -c 'A-Za-z0-9.-' '-')"
    bundle_id="com.example.$bundle_suffix"
fi

case "$bundle_id" in
    *[!A-Za-z0-9.-]*)
        printf 'error: the bundle identifier may contain only letters, digits, hyphens and periods.\n' >&2
        exit 1
        ;;
esac

if [ -e "$app" ]; then
    /bin/rm -rf "$app"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'error: could not remove the previous %s.\n' "$app" >&2
        exit 1
    fi
fi

/bin/mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'error: could not create %s.\n' "$app" >&2
    exit 1
fi

/bin/cp "$executable" "$app/Contents/MacOS/$executable_name"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'error: could not copy %s into the bundle.\n' "$executable" >&2
    exit 1
fi

icon_entry=""
if [ -n "$icon" ]; then
    /bin/cp "$icon" "$app/Contents/Resources/AppIcon.icns"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'error: could not copy %s into the bundle.\n' "$icon" >&2
        exit 1
    fi
    icon_entry='    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
'
fi

# LSMinimumSystemVersion matches the macOS version ActionUI is built for.
printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>'"$executable_name"'</string>
    <key>CFBundleIdentifier</key>
    <string>'"$bundle_id"'</string>
    <key>CFBundleName</key>
    <string>'"$app_name"'</string>
    <key>CFBundleDisplayName</key>
    <string>'"$app_name"'</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
'"$icon_entry"'    <key>LSMinimumSystemVersion</key>
    <string>14.6</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>' > "$app/Contents/Info.plist"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'error: could not write %s.\n' "$app/Contents/Info.plist" >&2
    exit 1
fi

/usr/bin/plutil -lint -s "$app/Contents/Info.plist"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'error: the generated Info.plist is not valid.\n' >&2
    exit 1
fi

/usr/bin/codesign --force --sign - "$app"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'error: codesign could not sign %s.\n' "$app" >&2
    exit 1
fi

printf 'Created %s\n' "$app"
