#!/usr/bin/env bash
#
# test-viewer.sh - build (if needed) and exercise ActionUIViewer with and without
# --screenshot, using sample JSONs from ActionUISwiftTestApp/Resources.
#
# The --screenshot path supports two capture methods (ActionUIViewer --method):
#   legacy (default) - CGWindowListCreateImage; no Screen Recording permission required, so it
#                      works out of the box (handy for automated / AI-agent screenshots).
#   sck              - ScreenCaptureKit (SCScreenshotManager); the supported, non-deprecated API,
#                      but it requires Screen Recording permission (System Settings > Privacy &
#                      Security > Screen Recording) even for the app's own window.
# Both capture the window-server composite, so WebView / VideoPlayer content is included either way.
#
# Usage:
#   Scripts/test-viewer.sh                 Screenshot the default sample set into a temp dir.
#   Scripts/test-viewer.sh Text Slider     Screenshot just these (name with or without .json).
#   Scripts/test-viewer.sh -m sck Slider   Screenshot using ScreenCaptureKit (needs permission).
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

usage() { sed -n '2,/^$/p' "$0" | sed 's/^#\{0,1\} \{0,1\}//'; }

config="debug"
preview=0
outdir=""
method=""
delay=""
args=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--preview) preview=1; shift ;;
        -r|--release) config="release"; shift ;;
        -o|--out)     outdir="$2"; shift 2 ;;
        -m|--method)  method="$2"; shift 2 ;;
        -d|--delay)   delay="$2"; shift 2 ;;
        -h|--help)    usage; exit 0 ;;
        -*)           echo "Unknown option: $1" >&2; usage; exit 2 ;;
        *)            args+=("$1"); shift ;;
    esac
done

# Find the package root (dir containing Package.swift), starting from this script's location.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$script_dir"
while [[ "$repo" != "/" && ! -f "$repo/Package.swift" ]]; do repo="$(dirname "$repo")"; done
[[ -f "$repo/Package.swift" ]] || { echo "Could not find Package.swift above $script_dir" >&2; exit 1; }
res="$repo/ActionUISwiftTestApp/Resources"

# Resolve the binary path (this does not build), then build only if it is missing.
if [[ "$config" == "release" ]]; then
    bindir="$(cd "$repo" && swift build --product ActionUIViewer -c release --show-bin-path)"
else
    bindir="$(cd "$repo" && swift build --product ActionUIViewer --show-bin-path)"
fi
bin="$bindir/ActionUIViewer"
if [[ ! -x "$bin" ]]; then
    echo ">> Building ActionUIViewer ($config) ..."
    if [[ "$config" == "release" ]]; then
        (cd "$repo" && swift build --product ActionUIViewer -c release)
    else
        (cd "$repo" && swift build --product ActionUIViewer)
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
        *) echo "Unknown -m method: $method (use 'legacy' or 'sck')" >&2; exit 2 ;;
    esac
fi

delay_args=()
[[ -n "$delay" ]] && delay_args=(--screenshot-delay "$delay")

[[ -n "$outdir" ]] || outdir="$(mktemp -d "${TMPDIR:-/tmp}/actionui-viewer-shots.XXXXXX")"
mkdir -p "$outdir"
echo ">> Screenshot mode (method: ${method:-legacy}, delay: ${delay:-1.5}s) -> $outdir"
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
