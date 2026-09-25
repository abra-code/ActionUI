#!/bin/bash
# stage-artifacts.sh - build actionui-mcp for release (arm64 and x86_64) and copy the executable
# and its resource bundles into installer/artifacts, the payload folder of both installer
# documents in this directory.
#
# Usage: stage-artifacts.sh [--identity "Developer ID Application: <name> (<TEAMID>)"]
#
# With --identity the executable is signed with the hardened runtime and a secure timestamp, and
# the resource bundles are re-signed with the same identity, which is what actionui-mcp.pkgbld
# asserts. Without it the executable is re-signed ad hoc (the universal release build carries at
# most the linker's ad-hoc signature), which only actionui-mcp-local.pkgbld accepts. Needs the
# tool sandbox off (SwiftPM).

usage() {
    printf 'usage: %s [--identity "Developer ID Application: <name> (<TEAMID>)"]\n' "$0" >&2
}

identity=""
while [ $# -gt 0 ]; do
    case "$1" in
        --identity)
            if [ $# -lt 2 ] || [ -z "$2" ]; then
                printf 'error: --identity needs a signing identity\n' >&2
                usage
                exit 2
            fi
            identity="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'error: unknown argument: %s\n' "$1" >&2
            usage
            exit 2
            ;;
    esac
done

# The resource bundles the server reads at run time (Verifier.swift, DocsResources.swift). A
# bundle the build makes that is not listed here is reported below, so a new add-on's
# documentation is not left out of the package silently.
BUNDLES="ActionUI_ActionUIVerifier.bundle
ActionUI_ActionUIDocumentation.bundle
ActionUIQuickLook_ActionUIQuickLookDocumentation.bundle
ActionUIDiff_ActionUIDiffDocumentation.bundle
ActionUICachedImage_ActionUICachedImageDocumentation.bundle
ActionUIRichText_ActionUIRichTextDocumentation.bundle"

installer_dir="$(CDPATH= cd -P -- "$(/usr/bin/dirname -- "$0")" && pwd)"
if [ -z "$installer_dir" ]; then
    printf 'error: cannot resolve the folder of %s\n' "$0" >&2
    exit 1
fi
package_dir="$(/usr/bin/dirname -- "$installer_dir")"
repo_dir="$(/usr/bin/dirname -- "$(/usr/bin/dirname -- "$package_dir")")"
artifacts_dir="$installer_dir/artifacts"

printf 'Building actionui-mcp (release, arm64 and x86_64)...\n' >&2
/usr/bin/xcrun swift build -c release --arch arm64 --arch x86_64 --package-path "$package_dir"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'error: swift build failed (exit %s); see the output above\n' "$status" >&2
    exit 1
fi
bin_dir="$(/usr/bin/xcrun swift build -c release --arch arm64 --arch x86_64 --package-path "$package_dir" --show-bin-path)"
if [ -z "$bin_dir" ] || [ ! -x "$bin_dir/actionui-mcp" ]; then
    printf 'error: no actionui-mcp executable in the build products folder "%s"\n' "$bin_dir" >&2
    exit 1
fi

/bin/rm -rf "$artifacts_dir"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'error: cannot remove the previous %s\n' "$artifacts_dir" >&2
    exit 1
fi
/bin/mkdir -p "$artifacts_dir"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'error: cannot create %s\n' "$artifacts_dir" >&2
    exit 1
fi

/usr/bin/ditto "$bin_dir/actionui-mcp" "$artifacts_dir/actionui-mcp"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'error: cannot copy actionui-mcp into %s\n' "$artifacts_dir" >&2
    exit 1
fi
missing=0
for bundle in $BUNDLES; do
    if [ ! -d "$bin_dir/$bundle" ]; then
        printf 'error: the build made no %s; update BUNDLES in this script and the installer documents\n' "$bundle" >&2
        missing=1
        continue
    fi
    /usr/bin/ditto "$bin_dir/$bundle" "$artifacts_dir/$bundle"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'error: cannot copy %s into %s\n' "$bundle" "$artifacts_dir" >&2
        missing=1
    fi
done
if [ "$missing" -ne 0 ]; then
    exit 1
fi

# Add-on element schemas. The verifier reads them from its bundle's Schemas/add-ons/<AddOn>/, or
# from the checkout it was built from (SchemaSet.discoverAddOnDirectories), which an installed copy
# does not have: without this copy, documents with add-on elements fail validation as unknown
# types. Same layout as Skill/build_skill.py makes for the Python verifier. Only the add-ons whose
# documentation bundle is staged, that is the ones the server links.
addons_dest="$artifacts_dir/ActionUI_ActionUIVerifier.bundle/Contents/Resources/Schemas/add-ons"
for bundle in $BUNDLES; do
    case "$bundle" in
        ActionUI_*) continue ;;
    esac
    addon="${bundle%%_*}"
    schema_src="$repo_dir/Add-ons/$addon/Schemas"
    if [ ! -d "$schema_src" ]; then
        printf 'error: no add-on schemas folder %s for %s\n' "$schema_src" "$bundle" >&2
        exit 1
    fi
    /bin/mkdir -p "$addons_dest/$addon"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'error: cannot create %s\n' "$addons_dest/$addon" >&2
        exit 1
    fi
    /bin/cp "$schema_src"/*.json "$addons_dest/$addon/"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'error: cannot copy the schemas in %s into the verifier bundle\n' "$schema_src" >&2
        exit 1
    fi
done

# Bundles the build made that the package would not install.
for path in "$bin_dir"/*.bundle; do
    [ -d "$path" ] || continue
    name="$(/usr/bin/basename "$path")"
    listed=0
    for bundle in $BUNDLES; do
        if [ "$bundle" = "$name" ]; then
            listed=1
        fi
    done
    if [ "$listed" -eq 0 ]; then
        printf 'warning: %s is not staged; if the server needs it, add it to BUNDLES and to both installer documents\n' "$name" >&2
    fi
done

if [ -n "$identity" ]; then
    /usr/bin/codesign --force --options runtime --timestamp --sign "$identity" "$artifacts_dir/actionui-mcp"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'error: codesign failed for actionui-mcp with identity "%s"\n' "$identity" >&2
        exit 1
    fi
    for bundle in $BUNDLES; do
        /usr/bin/codesign --force --timestamp --sign "$identity" "$artifacts_dir/$bundle"
        status=$?
        if [ "$status" -ne 0 ]; then
            printf 'error: codesign failed for %s with identity "%s"\n' "$bundle" "$identity" >&2
            exit 1
        fi
    done
else
    /usr/bin/codesign --force --sign - "$artifacts_dir/actionui-mcp"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'error: ad-hoc codesign failed for actionui-mcp\n' >&2
        exit 1
    fi
fi

/usr/bin/codesign --verify --strict "$artifacts_dir/actionui-mcp"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'error: the staged actionui-mcp signature does not verify\n' >&2
    exit 1
fi

version="$("$artifacts_dir/actionui-mcp" --version </dev/null)"
status=$?
if [ "$status" -ne 0 ] || [ -z "$version" ]; then
    printf 'error: the staged actionui-mcp --version failed (exit %s)\n' "$status" >&2
    exit 1
fi
printf 'Staged %s in %s\n' "$version" "$artifacts_dir" >&2
