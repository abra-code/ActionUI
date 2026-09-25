# actionui-mcp installer

Builds an installer package for the ActionUI MCP server with PackageBuilder.app. It installs the server and the resource bundles it reads at run time into one folder:

- `/usr/local/libexec/actionui-mcp/actionui-mcp` - the server (arm64 and x86_64, macOS 14.6 or later)
- `/usr/local/libexec/actionui-mcp/*.bundle` - the element schemas (`ActionUI_ActionUIVerifier.bundle`) and the documentation served as MCP resources (core and one per add-on)

The server finds the bundles next to its own executable, following symlinks, so the folder must stay together. Clients are configured with the full path:

```sh
claude mcp add actionui -- /usr/local/libexec/actionui-mcp/actionui-mcp
```

There is no link in `/usr/local/bin`. A payload entry must exist on the build machine, and a link to the installed location does not; adding one would take a postinstall script. MCP clients need an absolute path anyway.

This folder is tracked; `artifacts/` and `dist/` are gitignored.

## Two documents, on purpose

| File | Signing | Payload verify (the executable) | Use |
|---|---|---|---|
| `actionui-mcp.pkgbld` | on, installer identity given at build time | arm64 and x86_64, version 0.1.0 from `--version`, Developer ID, hardened runtime, secure timestamp | the distribution build, on the signing machine |
| `actionui-mcp-local.pkgbld` | off | arm64 and x86_64, version only | a local smoke build on a machine with no Developer ID |

`--unsigned` skips only the installer signature; the payload assertions still run, so the distribution document cannot be smoke-built with ad-hoc signed artifacts. Keep the two in step: a change to payload, destinations or presentation belongs in both. The resource bundles hold no code and assert nothing.

`PROJECT.VERSION` must match what `actionui-mcp --version` prints (`serverVersion` in `Sources/ActionUIMCP/main.swift`); the verify stage refuses a stale artifacts folder otherwise. Bump both together.

## Stage the artifacts

```sh
Apps/ActionUIMCP/installer/stage-artifacts.sh                     # ad-hoc signed, for the local document
Apps/ActionUIMCP/installer/stage-artifacts.sh --identity "Developer ID Application: <name> (<TEAMID>)"
```

It builds the release configuration for arm64 and x86_64, copies the executable and the six bundles into `artifacts/`, copies each linked add-on's element schemas (`Add-ons/<AddOn>/Schemas/*.json`) into the verifier bundle's `Schemas/add-ons/<AddOn>/`, and signs. The schema copy is what lets an installed server validate add-on elements: a build run from the checkout finds them in `Add-ons/` itself, an installed copy has no checkout. With `--identity` the executable gets the hardened runtime and a secure timestamp, and the bundles are re-signed with the same identity; without it the executable is re-signed ad hoc (the universal release build carries at most the linker's ad-hoc signature). A bundle the build makes that is not in the script's `BUNDLES` list is reported, so a new add-on's documentation is not silently left out: add it to the list and to both documents. SwiftPM needs the tool sandbox off.

## Build

```sh
PB="/Applications/PackageBuilder.app/Contents/Resources/Agents/pkgbuilder"
ID="Developer ID Installer: <name> (<TEAMID>)"

cd Apps/ActionUIMCP/installer
"$PB" build actionui-mcp.pkgbld --dry-run --identity "$ID"
"$PB" build actionui-mcp.pkgbld --identity "$ID"
```

Run `pkgbuilder` from this folder, or pass the document as an absolute path: given a relative path with folders in it (`Apps/ActionUIMCP/installer/actionui-mcp.pkgbld`), it resolves `${PROJECT_DIR}` wrongly and reports every payload item and resource as "not there". The `dist/` paths below are relative to this folder.

The identity is not stored in the document, so every command needs it, `--dry-run` included; without one the build stops at the preconditions and never reaches the payload verify.

Local smoke build, no identity:

```sh
"$PB" build actionui-mcp-local.pkgbld
```

It lands `dist/actionui-mcp-unsigned.pkg`. Test only: macOS will not install it on another Mac.

Then notarize the signed package with Notarize.app (Sign before submitting off, so it keeps the installer signature), or:

```sh
xcrun notarytool submit dist/actionui-mcp_0.1.0.pkg --keychain-profile <profile> --wait
xcrun stapler staple dist/actionui-mcp_0.1.0.pkg
```

## Checking a package without installing it

```sh
"$PB" inspect dist/actionui-mcp-unsigned.pkg
pkgutil --expand-full dist/actionui-mcp-unsigned.pkg /tmp/actionui-mcp-pkg
/tmp/actionui-mcp-pkg/actionui-mcp.pkg/Payload/usr/local/libexec/actionui-mcp/actionui-mcp --version
```

The expanded payload runs as installed: the server finds its bundles beside it.

## Known gaps

- `pkgbuilder build` given a relative path to a document in another folder resolves `${PROJECT_DIR}` wrongly and reports every payload item as not there; run it from this folder, or give an absolute path.

- No exported `makepkg.sh`: the script PackageBuilder's `export-script` writes fails on this payload with "Could not mark bundle 0 non-relocatable". `pkgbuild --analyze` writes no `BundleIsRelocatable` key for these resource bundles, and the exported script sets the key with PlistBuddy `Set`, which needs it to exist; PackageBuilder's own build adds it. Export again once PackageBuilder is fixed.
- The resource bundles have no `CFBundleVersion`, and pkgbuild marks them version-checked. Whether an upgrade install replaces them (as it must, or the schemas and docs go stale) is untested; check it with the first upgrade.
