#!/bin/bash
#
# Scripts/ci-macos.sh - the macOS continuous-integration steps, run by .github/workflows/macos.yml;
# also usable by hand on a Mac with Xcode.
#
# Usage: Scripts/ci-macos.sh <step>
#   build     the root package (ActionUI, the menu bar builder, the language adapters, the remote
#             server and the verifier) with its tests
#   test      the root package's tests
#   xcode     the Xcode project's "Build All" scheme (the frameworks, the adapters, the test apps
#             and the test bundles), without code signing
#   packages  each package in Apps (the viewer, the MCP server, the verifier tool) and Add-ons: its
#             tests when it has a test target, else its build. They name the root package
#             "ActionUI", which SwiftPM takes from the folder's name, so the repository must be in a
#             folder named ActionUI.
#
# build and test build in .build/ci-macos, xcode in .build/ci-macos-xcode, packages in
# .build/ci-macos-packages, so a run by hand leaves the usual .build folder alone. Each step writes
# its full logs to <results>/<step>.log (packages: <results>/<package>.log) and adds its result to
# <results>/summary.md; on GitHub Actions the summary also goes to the run page.
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

# The lines of a log that name an error: the compiler's and xcodebuild's "<file>:<line>:<column>:
# error: ...", XCTest's failed assertions "<file>:<line>: error: ...", xcodebuild's project errors
# "<path>.xcodeproj: error: ..." and its own "xcodebuild: error: ...", the linker driver's
# "clang: error: ...", SwiftPM's "error: ..." (a test process that crashed: "error: Exited with
# unexpected signal code ..."), Swift's own "Fatal error: ..." and Swift Testing's "Test <name>
# recorded an issue at <file>:...". Not any "<name>: error: ": the tests' processes log framework
# noise such as "CoreData: error: ..." (Contacts), over 100 lines in a passing run.
error_pattern='[0-9]: error: |\.xcodeproj: error: |^(xcodebuild|clang|ld): error: |^error: |Fatal error: |recorded an issue'
# The escape character that starts the compiler's color codes, which it writes even into a pipe.
esc="$(printf '\033')"

usage() {
    printf 'usage: %s build|test|xcode|packages\n' "$0" >&2
}

# Adds a line to the results summary.
summary_line() {
    printf '%s\n' "$1" >> "$results/summary.md"
}

# Adds the text $2 to the summary as a fenced block under the line $1; nothing when $2 is empty.
summary_block() {
    if [ -z "$2" ]; then
        return 0
    fi
    summary_line ""
    summary_line "$1"
    summary_line ""
    summary_line '```'
    summary_line "$2"
    summary_line '```'
    summary_line ""
}

# Adds the first 50 error lines of the log $1 to the summary (error_pattern): without color codes
# or the symbols Swift Testing prints in front of its lines, each line once (xcodebuild repeats
# them), cut at 300 characters (SwiftPM's lines carry the whole compiler command).
summary_errors() {
    local _errors
    _errors="$(LC_ALL=C /usr/bin/sed -E "s/${esc}\[[0-9;]*m//g" "$1" | /usr/bin/grep -E "$error_pattern" | LC_ALL=C /usr/bin/sed -E 's/^[^A-Za-z/]+//' | /usr/bin/awk '!seen[$0]++' | /usr/bin/cut -c 1-300 | /usr/bin/head -n 50)"
    summary_block "Errors in $(/usr/bin/basename -- "$1") (the first 50):" "$_errors"
}

# Adds the test totals of the log $1 to the summary: each XCTest bundle's total ("Test Suite
# 'X.xctest' passed", then its "Executed" line), and Swift Testing's totals for runs that had tests,
# without the symbol it prints in front.
summary_totals() {
    local _totals
    _totals="$(/usr/bin/grep -A 1 -E "^Test Suite '[^']+\.xctest' (passed|failed)" "$1" | /usr/bin/grep -v '^--$')"
    local _swift_testing
    _swift_testing="$(/usr/bin/grep -E 'Test run with [1-9][0-9]* tests?' "$1" | LC_ALL=C /usr/bin/sed -E 's/^[^A-Za-z]+//')"
    if [ -n "$_totals" ] && [ -n "$_swift_testing" ]; then
        _totals="$_totals
$_swift_testing"
    elif [ -n "$_swift_testing" ]; then
        _totals="$_swift_testing"
    fi
    summary_block "Totals:" "$_totals"
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
        summary_errors "$_log"
        return 1
    fi
    summary_line "- Build: passed"
    return 0
}

step_test() {
    local _log="$results/test.log"
    run_logged "$_log" /usr/bin/swift test --package-path "$repo" --scratch-path "$scratch"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        printf 'ci-macos: swift test failed (status %s); the log is %s\n' "$_status" "$_log" >&2
        summary_line "- Tests: failed (swift test status $_status)"
    else
        summary_line "- Tests: passed"
    fi
    summary_totals "$_log"
    if [ "$_status" -ne 0 ]; then
        summary_errors "$_log"
        return 1
    fi
    return 0
}

step_xcode() {
    local _log="$results/xcode.log"
    # Code signing off: the targets sign automatically with a development team, which a CI machine
    # does not have.
    run_logged "$_log" /usr/bin/xcodebuild -project "$repo/ActionUI.xcodeproj" -scheme "Build All" \
        -destination 'platform=macOS' -derivedDataPath "$repo/.build/ci-macos-xcode" \
        build CODE_SIGNING_ALLOWED=NO
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        printf 'ci-macos: xcodebuild failed (status %s); the log is %s\n' "$_status" "$_log" >&2
        summary_line "- Xcode project (Build All): failed (xcodebuild status $_status)"
        summary_errors "$_log"
        return 1
    fi
    summary_line "- Xcode project (Build All): passed"
    return 0
}

# Tests the package in the folder $1 (relative to the repository) when it has a test target, else
# builds it. Returns 1 when that failed.
check_package() {
    local _path="$1"
    local _name="$(/usr/bin/basename -- "$_path")"
    local _log="$results/$_name.log"
    local _package_scratch="$repo/.build/ci-macos-packages/$_name"
    local _manifest
    _manifest="$(/usr/bin/swift package --package-path "$repo/$_path" --scratch-path "$_package_scratch" dump-package 2>"$_log")"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        /bin/cat "$_log" >&2
        printf 'ci-macos: reading the manifest of %s failed (status %s)\n' "$_path" "$_status" >&2
        summary_line "- $_path: failed, its manifest could not be read"
        summary_errors "$_log"
        return 1
    fi
    local _tests
    _tests="$(printf '%s' "$_manifest" | /usr/bin/jq '[.targets[] | select(.type == "test")] | length')"
    _status=$?
    if [ "$_status" -ne 0 ] || [ -z "$_tests" ]; then
        printf 'ci-macos: counting the test targets of %s failed (jq status %s)\n' "$_path" "$_status" >&2
        summary_line "- $_path: failed, its test targets could not be counted"
        return 1
    fi
    if [ "$_tests" -gt 0 ]; then
        run_logged "$_log" /usr/bin/swift test --package-path "$repo/$_path" --scratch-path "$_package_scratch"
        _status=$?
        if [ "$_status" -ne 0 ]; then
            printf 'ci-macos: swift test of %s failed (status %s); the log is %s\n' "$_path" "$_status" "$_log" >&2
            summary_line "- $_path: tests failed (swift test status $_status)"
            summary_totals "$_log"
            summary_errors "$_log"
            return 1
        fi
        summary_line "- $_path: tests passed"
        summary_totals "$_log"
        return 0
    fi
    run_logged "$_log" /usr/bin/swift build --package-path "$repo/$_path" --scratch-path "$_package_scratch"
    _status=$?
    if [ "$_status" -ne 0 ]; then
        printf 'ci-macos: swift build of %s failed (status %s); the log is %s\n' "$_path" "$_status" "$_log" >&2
        summary_line "- $_path: build failed (swift build status $_status)"
        summary_errors "$_log"
        return 1
    fi
    summary_line "- $_path: built (no tests on macOS)"
    return 0
}

step_packages() {
    local _folder="$(/usr/bin/basename -- "$repo")"
    if [ "$_folder" != ActionUI ]; then
        printf 'ci-macos: the packages in Apps and Add-ons need the repository in a folder named ActionUI (SwiftPM names a package after its folder); this one is %s\n' "$_folder" >&2
        summary_line "- Packages: not checked, the repository's folder is not named ActionUI"
        return 1
    fi
    local _failed=0
    local _manifest
    for _manifest in "$repo"/Apps/*/Package.swift "$repo"/Add-ons/*/Package.swift; do
        [ -f "$_manifest" ] || continue
        local _dir="$(/usr/bin/dirname -- "$_manifest")"
        check_package "${_dir#"$repo"/}" || _failed=1
    done
    if [ "$_failed" -ne 0 ]; then
        return 1
    fi
    return 0
}

if [ "$#" -ne 1 ]; then
    usage
    exit 64
fi
case "$1" in
    build|test|xcode|packages) ;;
    -h|--help) /usr/bin/sed -n '2,27p' "$0"; exit 0 ;;
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
# The build step starts a new summary; the others add to it. summary_start is where this step's
# part begins.
summary_start=0
if [ "$1" = build ]; then
    printf '# macOS\n\n' > "$results/summary.md"
elif [ -f "$results/summary.md" ]; then
    summary_start="$(/usr/bin/wc -c < "$results/summary.md")"
fi
case "$1" in
    build) step_build ;;
    test) step_test ;;
    xcode) step_xcode ;;
    packages) step_packages ;;
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
