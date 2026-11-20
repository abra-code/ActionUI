#!/bin/bash
#
# Scripts/ci-macos.sh - the macOS continuous-integration steps, run by .github/workflows/macos.yml;
# also usable by hand on a Mac with Xcode.
#
# Usage: Scripts/ci-macos.sh <step>
#   build   the root package (ActionUI, the menu bar builder, the language adapters, the remote
#           server and the verifier) with its tests
#   test    the root package's tests
#
# Both steps build in .build/ci-macos, so a run by hand leaves the usual .build folder alone. Each
# step writes its full log to <results>/<step>.log and adds its result to <results>/summary.md; on
# GitHub Actions the summary also goes to the run page.
#
# Environment:
#   ACTIONUI_CI_RESULTS  the results folder (default: .build/ci-macos-results in the repository)
#   DEVELOPER_DIR        the Xcode to build with (default: the one xcode-select chose)
#
# Exit status: 0 the step passed, 1 it failed, 64 bad arguments.

script_dir="$(CDPATH= cd -P -- "$(/usr/bin/dirname -- "$0")" && pwd)"
if [ -z "$script_dir" ]; then
    printf 'ci-macos: could not find the folder of %s\n' "$0" >&2
    exit 1
fi
repo="$(/usr/bin/dirname -- "$script_dir")"
scratch="$repo/.build/ci-macos"
results="${ACTIONUI_CI_RESULTS:-$repo/.build/ci-macos-results}"

usage() {
    printf 'usage: %s build|test\n' "$0" >&2
}

# Adds a line to the results summary.
summary_line() {
    printf '%s\n' "$1" >> "$results/summary.md"
}

# Runs a command, its output to the terminal and to the log $1; returns the command's status.
run_logged() {
    local _log="$1"
    shift
    "$@" 2>&1 | /usr/bin/tee "$_log"
    return "${PIPESTATUS[0]}"
}

step_build() {
    local _log="$results/build.log"
    local _xcode
    _xcode="$(/usr/bin/xcodebuild -version)"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        printf 'ci-macos: xcodebuild -version failed (status %s); is Xcode installed and selected?\n' "$_status" >&2
        summary_line "- Build: failed, no usable Xcode"
        return 1
    fi
    local _swift
    # The first line, without the driver's version in front: "Apple Swift version ...".
    _swift="$(/usr/bin/swift --version 2>&1 | /usr/bin/head -n 1 | /usr/bin/sed -E 's/^swift-driver version: [^ ]+ //')"
    printf 'ci-macos: %s; %s\n' "$(printf '%s' "$_xcode" | /usr/bin/tr '\n' ' ')" "$_swift"
    summary_line "- Xcode: $(printf '%s' "$_xcode" | /usr/bin/tr '\n' ' ')"
    summary_line "- Swift: $_swift"
    run_logged "$_log" /usr/bin/swift build --package-path "$repo" --scratch-path "$scratch" --build-tests
    _status=$?
    if [ "$_status" -ne 0 ]; then
        printf 'ci-macos: swift build failed (status %s); the log is %s\n' "$_status" "$_log" >&2
        summary_line "- Build: failed (swift build status $_status)"
        return 1
    fi
    summary_line "- Build: passed"
    return 0
}

step_test() {
    local _log="$results/test.log"
    run_logged "$_log" /usr/bin/swift test --package-path "$repo" --scratch-path "$scratch"
    local _status=$?
    # Each XCTest bundle's total ("Test Suite 'X.xctest' passed", then its "Executed" line), and
    # Swift Testing's totals for runs that had tests, without the symbol it prints in front.
    local _totals
    _totals="$(/usr/bin/grep -A 1 -E "^Test Suite '[^']+\.xctest' (passed|failed)" "$_log" | /usr/bin/grep -v '^--$')"
    local _swift_testing
    _swift_testing="$(/usr/bin/grep -E 'Test run with [1-9][0-9]* tests?' "$_log" | LC_ALL=C /usr/bin/sed -E 's/^[^A-Za-z]+//')"
    if [ "$_status" -ne 0 ]; then
        printf 'ci-macos: swift test failed (status %s); the log is %s\n' "$_status" "$_log" >&2
        summary_line "- Tests: failed (swift test status $_status)"
    else
        summary_line "- Tests: passed"
    fi
    if [ -n "$_totals$_swift_testing" ]; then
        summary_line ""
        summary_line '```'
        [ -n "$_totals" ] && summary_line "$_totals"
        [ -n "$_swift_testing" ] && summary_line "$_swift_testing"
        summary_line '```'
    fi
    if [ "$_status" -ne 0 ]; then
        # The failed assertions, the first 50: XCTest prints them as "<file>:<line>: error: ...",
        # Swift Testing as "Test <name> recorded an issue at <file>:<line>:<column>: ...".
        local _failures
        _failures="$(/usr/bin/grep -E ':[0-9]+: error: |recorded an issue' "$_log" | LC_ALL=C /usr/bin/sed -E 's/^[^A-Za-z/]+//' | /usr/bin/head -n 50)"
        if [ -n "$_failures" ]; then
            summary_line ""
            summary_line "Failures (the first 50):"
            summary_line ""
            summary_line '```'
            summary_line "$_failures"
            summary_line '```'
        fi
        return 1
    fi
    return 0
}

if [ "$#" -ne 1 ]; then
    usage
    exit 64
fi
case "$1" in
    build|test) ;;
    -h|--help) /usr/bin/sed -n '2,19p' "$0"; exit 0 ;;
    *)
        printf 'ci-macos: unknown step %s\n' "$1" >&2
        usage
        exit 64
        ;;
esac

/bin/mkdir -p "$results"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'ci-macos: could not create the results folder %s\n' "$results" >&2
    exit 1
fi
# The build step starts a new summary; the test step adds to it. summary_start is where this
# step's part begins.
summary_start=0
if [ "$1" = build ]; then
    printf '# macOS\n\n' > "$results/summary.md"
elif [ -f "$results/summary.md" ]; then
    summary_start="$(/usr/bin/wc -c < "$results/summary.md")"
fi
case "$1" in
    build) step_build ;;
    test) step_test ;;
esac
status=$?
# This step's part of the summary, on the run page.
if [ -n "$GITHUB_STEP_SUMMARY" ]; then
    /usr/bin/tail -c "+$((summary_start + 1))" "$results/summary.md" >> "$GITHUB_STEP_SUMMARY"
fi
if [ "$status" -ne 0 ]; then
    exit 1
fi
exit 0
