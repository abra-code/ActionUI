#!/bin/bash
# Verify the add-on test app's JSON resources during build, like ActionUISwiftTestApp's
# verify_json_resources.sh. Uses the repo's Python validator and passes every add-on's Schemas/
# directory via --schema-dir, so add-on element types (e.g. QuickLook) are recognized.
#
# Errors fail the build; warnings are printed but do not. python3 must be on PATH (a build host
# always has it); if absent, verification is skipped with a warning.
#
# Note: SRCROOT here is Add-ons/ActionUIAddOnTestApp (the .xcodeproj's directory), so the repo root
# is two levels up.

REPO_ROOT="$(cd "${SRCROOT}/../.." && pwd)"
RESOURCES_DIR="${SRCROOT}/Resources"
VALIDATOR="${REPO_ROOT}/Tools/verifier/validate_actionui.py"

if [ ! -d "$RESOURCES_DIR" ]; then
    echo "error: Resources directory not found at $RESOURCES_DIR"
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "warning: python3 not found on PATH - skipping JSON verification"
    exit 0
fi

if [ ! -f "$VALIDATOR" ]; then
    echo "warning: validator not found at $VALIDATOR - skipping JSON verification"
    exit 0
fi

# Pass every add-on's Schemas/ directory so add-on element types validate.
SCHEMA_ARGS=()
for d in "${REPO_ROOT}/Add-ons"/*/Schemas; do
    [ -d "$d" ] && SCHEMA_ARGS+=( --schema-dir "$d" )
done

python3 "$VALIDATOR" "${SCHEMA_ARGS[@]}" "$RESOURCES_DIR"
STATUS=$?

# Validator exit codes: 0 = ok, 2 = warnings (non-fatal), 1 = errors (fail the build).
if [ "$STATUS" -eq 1 ]; then
    exit 1
fi
exit 0
