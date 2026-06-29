# ActionUIQuickLook

An optional ActionUI add-on that provides a native, in-process **Quick Look** preview element
(`QuickLook`) - the embedded "4a" capability from `Private/ActionUI-QuickLook-Design.md` (proposed
there as `QuickLookPreview`; shipped as `QuickLook`, since Quick Look already implies preview),
built as a separately-linkable add-on instead of a core element.

It is the first exercise of ActionUI's public add-on registration API
(`ActionUIRegistry.register(_:as:)`), mirroring the ActionUIAndroid `map-google` / `map-osm`
provider pattern.

## What it adds

A `QuickLook` element, usable from JSON like any built-in:

```json
{ "type": "QuickLook", "id": 70, "properties": {
    "filePath": "/path/to/file.pdf",
    "previewStyle": "normal",
    "valueChangeActionID": "ql.changed" } }
```

- macOS: `QLPreviewView` (NSViewRepresentable).
- iOS / visionOS: `QLPreviewController` (UIViewControllerRepresentable, inline child).
- tvOS / watchOS: a graceful "not available" label.

The element value is the source file path, so the host drives it with the existing
`setElementValue` path; `valueChangeActionID` fires after the previewed item reloads. (Quick Look
previews local files only, so there is no remote `url` property - just `filePath` / the value.)

## Design: compiles against ActionUI, does not link it

This target is a **static library** that depends on ActionUI for its Swift module only
(`link: false` in `project.yml`). It does not embed ActionUI's object code - a static library
never embeds its dependencies, and `link: false` makes that explicit. The **host app links both**
ActionUI and this add-on.

Apple has no guaranteed pre-`main` hook for a statically linked Swift type, so registration is one
explicit call at launch (not automatic on link, unlike Android's manifest ContentProvider):

```swift
import ActionUIQuickLook

// In your App init / applicationDidFinishLaunching, before building any window:
ActionUIQuickLook.register()
```

## Consuming it

`Package.swift` makes this a Swift package (macOS / iOS / visionOS) - the primary way to consume
the add-on. A host adds it as a package dependency and links the `ActionUIQuickLook` product
alongside ActionUI:

```swift
.package(path: "Add-ons/ActionUIQuickLook")
// ...
.product(name: "ActionUIQuickLook", package: "ActionUIQuickLook")
```

SPM builds ActionUI once and the host links it; this product only references ActionUI's symbols,
so the add-on never embeds ActionUI. See `Add-ons/ActionUIAddOnTestApp` for a host that links it.

## Standalone static-library build (optional)

`project.yml` builds the add-on as a standalone static library with [xcodegen](https://github.com/yonaskolb/XcodeGen),
with ActionUI as a `link: false` (compile-only) dependency - the same "compile against, do not
link" relationship the package expresses, useful for inspecting the produced `.a`:

```sh
cd Add-ons/ActionUIQuickLook
xcodegen generate
xcodebuild -project ActionUIQuickLook.xcodeproj -scheme ActionUIQuickLook \
    -destination 'generic/platform=macOS' build
```

The `.xcodeproj` is generated from `project.yml` but committed, so it builds without xcodegen;
regenerate with `xcodegen generate` after editing `project.yml`.

## Documentation and verification

The add-on mirrors core ActionUI's documentation layout so the three doc/tooling systems pick it up
automatically:

- `Sources/QuickLook.swift` opens with a head comment (the `Sample JSON for QuickLook` block), the
  same way core views are documented.
- `Documentation/Schemas/QuickLook.md` is the human-readable element doc derived from that comment;
  `Documentation/Elements/QuickLook.json` is the insert template (most common properties).
- The `ActionUIQuickLookDocumentation` SPM product bundles `Documentation/` as resources, mirroring
  core `ActionUIDocumentation`, so a client that links it gets the docs copied into its app bundle.
- `Schemas/QuickLook.json` is the **verifier** schema. The ActionUI verifier auto-discovers
  `Add-ons/*/Schemas` (in-repo) and its own `schemas/add-ons/` (when packaged), so a document using
  the `QuickLook` element validates with no `--schema-dir` flag:

  ```sh
  python3 Tools/verifier/validate_actionui.py Add-ons/ActionUIQuickLook/Examples/QuickLook.json
  ```

  `Skill/build_skill.py` and OMC's `update_appletbuilder.sh` copy these add-on docs + schemas into
  their packaged outputs.

## Files

- `project.yml` - xcodegen spec (static lib, ActionUI as `link: false` package dep).
- `Sources/ActionUIQuickLook.swift` - Swift `register()` entry point + plain C `ActionUIQuickLook_register()` (for ObjC/C++ hosts).
- `Sources/QuickLook.swift` - the `ActionUIViewConstruction` element type (with the documented head comment).
- `Sources/QuickLookRepresentable.swift` - the macOS / iOS native backings + coordinator.
- `Documentation/Schemas/QuickLook.md` - element schema doc; `Documentation/Elements/QuickLook.json` - insert template.
- `Documentation/ActionUIQuickLookDocumentation.swift` - `Bundle.module` accessor for the docs product.
- `Schemas/QuickLook.json` - verifier schema (auto-discovered).
- `Examples/QuickLook.json` - a sample window using the element.
