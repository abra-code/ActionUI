#!/usr/bin/env bash
#
# test-viewer.sh - build (if needed) and exercise ActionUIViewer with and without
# --screenshot, using sample JSONs from ActionUISwiftTestApp/Resources.
#
# The --screenshot path supports three capture methods (ActionUIViewer --method):
#   legacy (default) - CGWindowListCreateImage; no Screen Recording permission required, so it
#                      works out of the box (handy for automated / AI-agent screenshots).
#   sck              - ScreenCaptureKit (SCScreenshotManager); the supported, non-deprecated API,
#                      but it requires Screen Recording permission (System Settings > Privacy &
#                      Security > Screen Recording) even for the app's own window.
#   offscreen        - NSView.cacheDisplay; draws the window in-process instead of reading the
#                      window server, so it works with the screen locked and with -H (hidden
#                      window). Same layout as the other two, minus the window shadow.
# legacy and sck capture the window-server composite; both fall back to offscreen automatically
# when the screen is locked or the window server returns no image.
#
# Usage:
#   Scripts/test-viewer.sh                 Screenshot the default sample set into a temp dir.
#   Scripts/test-viewer.sh Text Slider     Screenshot just these (name with or without .json).
#   Scripts/test-viewer.sh -m sck Slider   Screenshot using ScreenCaptureKit (needs permission).
#   Scripts/test-viewer.sh -H Slider       Screenshot without showing a window on the desktop.
#   Scripts/test-viewer.sh -d 5 WebView    Wait 5s before capture (for WebView / VideoPlayer).
#   Scripts/test-viewer.sh -p              Preview the default set (open live windows, no screenshot).
#   Scripts/test-viewer.sh -p Map List     Preview specific JSONs (close each window to proceed).
#   Scripts/test-viewer.sh -o /tmp/shots   Choose the screenshot output dir.
#   Scripts/test-viewer.sh -r              Use the release binary instead of debug.
#   Scripts/test-viewer.sh -h              This help.
#
# Note: ActionUIViewer is a standalone CLI with no app bundle, so JSONs that reference bundled
# resources render with missing content - Image.json / Canvas.json (bundled abracadabra.png),
# VideoPlayer.json / WebView.json (bundled video + inject JS), AsyncImage.json (remote URLs).
# The default set below avoids these so the screenshots look as intended.

set -eo pipefail

usage() {
    cat <<'EOF'
test-viewer.sh - build (if needed) and exercise ActionUIViewer on sample JSONs.

Usage:
  Scripts/test-viewer.sh [OPTIONS] [NAME ...]

  NAME ...   Sample JSONs to render (with or without .json), from
             ActionUISwiftTestApp/Resources. Defaults to a standalone-friendly set.

Options:
  -p, --preview     Open live windows instead of screenshotting (close each to proceed).
  -o, --out DIR     Screenshot output directory (default: a temp dir).
  -m, --method M    Capture method: 'legacy' (default, no permission needed), 'sck'
                    (ScreenCaptureKit; requires Screen Recording permission) or 'offscreen'
                    (in-process drawing; works with the screen locked, no window shadow).
  -H, --hidden      Keep the viewer window off every screen (implies -m offscreen).
  -d, --delay SECS  Seconds to wait before capture (for WebView / VideoPlayer).
  -r, --release     Use the release binary instead of debug.
  -h, --help        Show this help.

Note: ActionUIViewer is a standalone CLI with no app bundle, so JSONs that reference
bundled resources (Image, Canvas, VideoPlayer, WebView, AsyncImage) render with missing
content; the default set avoids these.
EOF
}

config="debug"
preview=0
outdir=""
method=""
hidden=0
delay=""
args=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--preview) preview=1; shift ;;
        -r|--release) config="release"; shift ;;
        -o|--out)     outdir="$2"; shift 2 ;;
        -m|--method)  method="$2"; shift 2 ;;
        -H|--hidden)  hidden=1; shift ;;
        -d|--delay)   delay="$2"; shift 2 ;;
        -h|--help)    usage; exit 0 ;;
        -*)           echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
        *)            args+=("$1"); shift ;;
    esac
done

# Find the package root (dir containing Package.swift), starting from this script's location.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$script_dir"
while [[ "$repo" != "/" && ! -f "$repo/Package.swift" ]]; do repo="$(dirname "$repo")"; done
[[ -f "$repo/Package.swift" ]] || { echo "Could not find Package.swift above $script_dir" >&2; exit 1; }
res="$repo/ActionUISwiftTestApp/Resources"

# Resolve the binary path (this does not build); whether to build is decided below.
if [[ "$config" == "release" ]]; then
    bindir="$(cd "$repo/Apps/ActionUIViewer" && swift build --product ActionUIViewer -c release --show-bin-path)"
else
    bindir="$(cd "$repo/Apps/ActionUIViewer" && swift build --product ActionUIViewer --show-bin-path)"
fi
bin="$bindir/ActionUIViewer"

# SDK stamp. Under Xcode 27 the default SwiftPM engine (Swift Build) links without SDKROOT in its
# environment, and a binary then records the DEPLOYMENT TARGET as its SDK version ("sdk 14.6"),
# although it is compiled against the current SDK. AppKit picks its design from that stamp, so such
# a viewer runs in the pre-Liquid Glass compatibility layout and its screenshots do not match a
# real app. Apps/ActionUIViewer/Package.swift states both versions to the linker, so a build is
# stamped correctly by itself; all this script does is notice a binary from before that. The probes
# must not end the script (set -e), hence "|| true".
sdk_version="$(/usr/bin/xcrun --sdk macosx --show-sdk-version 2>/dev/null || true)"

# Build when the binary is missing, and relink when it carries the wrong SDK stamp.
needs_build=0
if [[ ! -x "$bin" ]]; then
    needs_build=1
elif [[ -n "$sdk_version" ]]; then
    stamped_sdk="$(/usr/bin/xcrun vtool -show-build "$bin" 2>/dev/null | /usr/bin/awk '$1 == "sdk" { print $2; exit }' || true)"
    if [[ "$stamped_sdk" != "$sdk_version" ]]; then
        echo ">> Existing binary is stamped with SDK '$stamped_sdk', expected '$sdk_version'; relinking."
        # Remove it: SwiftPM relinks only when an input or the command line changed, and neither
        # may have. A missing product always links.
        /bin/rm -f "$bin"
        needs_build=1
    fi
fi
if [[ "$needs_build" -eq 1 ]]; then
    echo ">> Building ActionUIViewer ($config) ..."
    if [[ "$config" == "release" ]]; then
        (cd "$repo/Apps/ActionUIViewer" && swift build --product ActionUIViewer -c release)
    else
        (cd "$repo/Apps/ActionUIViewer" && swift build --product ActionUIViewer)
    fi
    # Say so once if the fresh binary is still stamped wrong, instead of relinking silently forever.
    if [[ -n "$sdk_version" ]]; then
        stamped_sdk="$(/usr/bin/xcrun vtool -show-build "$bin" 2>/dev/null | /usr/bin/awk '$1 == "sdk" { print $2; exit }' || true)"
        if [[ "$stamped_sdk" != "$sdk_version" ]]; then
            echo ">> Warning: the new binary is stamped with SDK '$stamped_sdk', expected '$sdk_version'; it may run" >&2
            echo ">>          without the current system look. The stamp comes from Apps/ActionUIViewer/Package.swift;" >&2
            echo ">>          an exported SDKROOT that names another SDK also causes this." >&2
        fi
    fi
fi
echo ">> Binary: $bin"

# Default standalone-friendly samples (no bundled assets, no network required).
default_set=(Text Button Label Slider Toggle Stepper Picker Gauge ProgressView Form Shapes List)

names=()
[[ ${#args[@]} -gt 0 ]] && names=("${args[@]}")
[[ ${#names[@]} -eq 0 ]] && names=("${default_set[@]}")

resolve_json() {
    local n="$1"
    [[ "$n" == *.json ]] || n="$n.json"
    printf '%s/%s' "$res" "$n"
}

# ---- Preview mode: open live windows, no screenshot (window stays until you close it) ----
if [[ "$preview" -eq 1 ]]; then
    echo ">> Preview mode (no screenshot). Close each window to move on."
    for n in "${names[@]}"; do
        j="$(resolve_json "$n")"
        [[ -f "$j" ]] || { echo "   skip (missing): $j" >&2; continue; }
        echo "   opening: $(basename "$j")  (close the window to continue)"
        "$bin" "$j"
    done
    echo ">> Preview done."
    exit 0
fi

# ---- Screenshot mode: capture each JSON to a PNG ----
# Pass --method / --screenshot-delay through only when given; otherwise the viewer's defaults
# (legacy method, 1.5s delay) are used.
method_args=()
if [[ -n "$method" ]]; then
    case "$(echo "$method" | tr '[:upper:]' '[:lower:]')" in
        legacy|cg)               method_args=(--method legacy) ;;
        sck|screencapturekit)    method_args=(--method sck) ;;
        offscreen|cachedisplay)  method_args=(--method offscreen) ;;
        *) echo "Unknown -m method: $method (use 'legacy', 'sck' or 'offscreen')" >&2; exit 2 ;;
    esac
fi
hidden_label=""
if [[ "$hidden" -eq 1 ]]; then
    method_args+=(--hide-window)
    hidden_label=", hidden window -> offscreen"
fi

delay_args=()
[[ -n "$delay" ]] && delay_args=(--screenshot-delay "$delay")

[[ -n "$outdir" ]] || outdir="$(mktemp -d "${TMPDIR:-/tmp}/actionui-viewer-shots.XXXXXX")"
mkdir -p "$outdir"
echo ">> Screenshot mode (method: ${method:-legacy}${hidden_label}, delay: ${delay:-1.5}s) -> $outdir"
[[ "$method" == "sck" || "$method" == "screencapturekit" ]] && \
    echo ">> (ScreenCaptureKit: first run may require Screen Recording permission)"

fail=0
for n in "${names[@]}"; do
    j="$(resolve_json "$n")"
    base="$(basename "${j%.json}")"
    png="$outdir/$base.png"
    if [[ ! -f "$j" ]]; then
        echo "   skip (missing): $j" >&2
        continue
    fi
    printf '   %-18s -> ' "$base.json"
    if out="$("$bin" "$j" --screenshot "$png" ${method_args[@]+"${method_args[@]}"} ${delay_args[@]+"${delay_args[@]}"} 2>&1)" && [[ -s "$png" ]]; then
        echo "OK ($(du -h "$png" | cut -f1 | tr -d ' '))"
    else
        echo "FAILED"
        [[ -n "$out" ]] && echo "$out" | sed 's/^/        /'
        fail=1
    fi
done

echo ">> Done. Output: $outdir"
if [[ "$fail" -eq 0 ]]; then
    open "$outdir"
else
    echo ">> Some captures failed. With -m sck this is usually a permission issue - grant Screen" >&2
    echo "   Recording to: $bin" >&2
    echo "   (System Settings > Privacy & Security > Screen Recording), or omit -m to use the" >&2
    echo "   no-permission legacy method." >&2
fi
exit "$fail"
