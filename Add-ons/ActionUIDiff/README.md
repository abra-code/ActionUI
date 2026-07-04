# ActionUIDiff

An optional ActionUI add-on that provides an embedded unified line-diff element (`Diff`) - a
review surface that renders the difference between two texts (inline strings or files read from
disk) as hunks with old/new line-number gutters, `+`/`-` markers, tinted rows, and collapsed
unchanged runs. It is built as a separately-linkable add-on, mirroring `ActionUIQuickLook`.

The diff rendering lives in a **standalone component** (`DiffView`) promoted out of `ActionUIChat`,
where it renders tool-call diffs in the agentic transcript. This package ships that component as its
own product and adds the `Diff` element on top - so both the Chat add-on and JSON documents render
identical diffs from the same code.

## Two consumable products

- **`DiffView`** - the pure component: `DiffComputer` (the Myers line-diff model) + `DiffView` (its
  SwiftUI renderer). Imports SwiftUI / Foundation only, **no ActionUI**. This is what `ActionUIChat`
  consumes (a filesystem path dependency, like `RichText`).
- **`ActionUIDiff`** - the `Diff` element wrapper + `register()` + the plain C
  `ActionUIDiff_register()` entry point. Depends on `DiffView` and compiles against ActionUI. Hosts
  that want the element link this.
- **`ActionUIDiffDocumentation`** - a resource-only docs bundle (schema doc + insert template),
  mirroring core `ActionUIDocumentation`.

## What it adds

A `Diff` element, usable from JSON like any built-in:

```json
{ "type": "Diff", "id": 80, "properties": {
    "oldText": "func f() {}",
    "newText": "func f() { g() }" } }
```

Each side is either an inline string (`oldText` / `newText`) or a file read from disk (`oldFile` /
`newFile`, absolute path, tilde-expanded, UTF-8). The text property wins over the file property for a
side; a missing / oversized (over 4 MB) / non-UTF-8 file renders an inline "Cannot read <path>" note
instead of a misleading diff; a side with neither is an empty side (a new-file or deleted-file diff).
`contextLines` (default 3) and `maxRenderedLines` (default 300) tune the rendering.

The element is **display-only** (void value): there is nothing to read back with `getElementValue`.
It is **stateless** - it builds from its current properties on every render - so a host can drive it
at runtime with `setElementProperty` (e.g. inject `oldFile` / `newFile` paths) and the view updates.

## Design: compiles against ActionUI, does not link it

The `ActionUIDiff` target is a **static library** that depends on ActionUI for its Swift module only
(`link: false` in `project.yml`). It does not embed ActionUI's object code - a static library never
embeds its dependencies, and `link: false` makes that explicit. The **host app links both** ActionUI
and this add-on.

Apple has no guaranteed pre-`main` hook for a statically linked Swift type, so registration is one
explicit call at launch:

```swift
import ActionUIDiff

// In your App init / applicationDidFinishLaunching, before building any window:
ActionUIDiff.register()
```

## Consuming it

`Package.swift` makes this a Swift package (macOS / iOS / visionOS) - the primary way to consume the
add-on. A host adds it as a package dependency and links the `ActionUIDiff` product alongside
ActionUI:

```swift
.package(path: "Add-ons/ActionUIDiff")
// ...
.product(name: "ActionUIDiff", package: "ActionUIDiff")
```

`ActionUIChat` instead depends only on the `DiffView` product (the pure component). See
`Add-ons/ActionUIAddOnTestApp` for a host that links the `Diff` element.

## Standalone static-library build (optional)

`project.yml` builds the add-on as two standalone static libraries (`DiffView` and `ActionUIDiff`)
with [xcodegen](https://github.com/yonaskolb/XcodeGen), with ActionUI as a `link: false`
(compile-only) dependency:

```sh
cd Add-ons/ActionUIDiff
xcodegen generate
xcodebuild -project ActionUIDiff.xcodeproj -scheme ActionUIDiff \
    -destination 'generic/platform=macOS' build
```

The `.xcodeproj` is generated from `project.yml` but committed, so it builds without xcodegen;
regenerate with `xcodegen generate` after editing `project.yml`.

## Documentation and verification

The add-on mirrors core ActionUI's documentation layout so the three doc/tooling systems pick it up
automatically:

- `Sources/ActionUIDiff/Diff.swift` opens with a head comment (the `Sample JSON for Diff` block), the
  same way core views are documented.
- `Documentation/Schemas/Diff.md` is the human-readable element doc derived from that comment;
  `Documentation/Elements/Diff.json` is the insert template (most common properties).
- The `ActionUIDiffDocumentation` SPM product bundles `Documentation/` as resources, mirroring core
  `ActionUIDocumentation`, so a client that links it gets the docs copied into its app bundle.
- `Schemas/Diff.json` is the **verifier** schema. The ActionUI verifier auto-discovers
  `Add-ons/*/Schemas` (in-repo) and its own `schemas/add-ons/` (when packaged), so a document using
  the `Diff` element validates with no `--schema-dir` flag:

  ```sh
  python3 Tools/verifier/validate_actionui.py Add-ons/ActionUIDiff/Examples/Diff.json
  ```

  `Skill/build_skill.py` and OMC's `update_appletbuilder.sh` copy these add-on docs + schemas into
  their packaged outputs.

## Files

- `project.yml` - xcodegen spec (two static libs; ActionUI as `link: false` package dep).
- `Sources/DiffView/DiffModel.swift` + `DiffView.swift` - the standalone diff-viewer component (public API).
- `Sources/ActionUIDiff/ActionUIDiff.swift` - Swift `register()` entry point + plain C `ActionUIDiff_register()` (for ObjC/C++ hosts).
- `Sources/ActionUIDiff/Diff.swift` - the `ActionUIViewConstruction` element type (with the documented head comment).
- `Documentation/Schemas/Diff.md` - element schema doc; `Documentation/Elements/Diff.json` - insert template.
- `Documentation/ActionUIDiffDocumentation.swift` - `Bundle.module` accessor for the docs product.
- `Schemas/Diff.json` - verifier schema (auto-discovered).
- `Examples/Diff.json` - a sample document using the element.
