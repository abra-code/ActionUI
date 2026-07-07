# ActionUIRichText

An optional ActionUI add-on that provides a **rich-text display** element (`RichText`), backed by
the [RichText](https://github.com/abra-code/RichText) package. It is the third ActionUI add-on
(after `ActionUIQuickLook` and `ActionUICachedImage`).

## What it adds

A `RichText` element, usable from JSON like any built-in:

```json
{ "type": "RichText", "id": 90, "properties": {
    "markdown": "# Title\n\nA **bold** word and a `code` span.",
    "syntaxHighlighting": true } }
```

- macOS / iOS / visionOS: `RichText.RichText` (a SwiftUI view).

The RichText package renders a whole Markdown document - headings, paragraphs, code blocks, block
quotes, lists, GFM tables, inline styling, links - into **one native text view**, so the entire
document is **selectable and copyable as a single unit** (copy is table-aware: RTF / HTML / Markdown,
so a copied table pastes as a real table into TextEdit / Notes / Word). The view is read-only but
selectable, self-sizes to its content for the proposed width, and handles its own links
(http/https/mailto/tel only, per RichText's URL policy).

The element value is the Markdown source string, so the host drives it with the existing
`setElementValue` path, exactly like the core `AsyncImage` element and the `CachedImage` add-on.

### Properties

| Property | Type | Notes |
|---|---|---|
| `markdown` | string | Markdown source; seeds the element value. Empty or nil renders an empty document. |
| `baseFontSize` | number | Base font point size. Omit for Dynamic Type body. |
| `syntaxHighlighting` | boolean | Color fenced code blocks by language. Default from the RichText theme. |

`baseFontSize` and `syntaxHighlighting` override those knobs on RichText's default theme; the rest of
the theme keeps its defaults. Sizing / padding / background use the baseline View modifiers.

The TextKit substrate is intentionally not exposed. The element uses RichText's default (TextKit 1),
which gives the best table fidelity - native wrapping-cell `NSTextTable` on macOS (TextKit 2 draws
single-line grid tables on every platform, losing that; on iOS both are single-line anyway). RichText
picks the engine at construction, so there is nothing runtime to switch.

## Design: compiles against ActionUI, links RichText transitively

This target is a **static library**. It has two dependencies with different linking stories:

- **ActionUI** - the add-on compiles against ActionUI's public API but does **not** embed it
  (`link: false` in `project.yml`). A static library never embeds its dependencies; the host app
  links ActionUI and this add-on, and ActionUI's symbols resolve at the host's final link.
- **RichText** - the first-party remote SPM dependency whose view the element uses. With the Swift
  package, SPM pulls it (and RichText's own AsyncImageCache dependency) in transitively, so any host
  that links `ActionUIRichText` also links `RichText` + `AsyncImageCache` automatically.

Apple has no guaranteed pre-`main` hook for a statically linked Swift type, so registration is one
explicit call at launch (not automatic on link, unlike Android's manifest ContentProvider):

```swift
import ActionUIRichText

// In your App init / applicationDidFinishLaunching, before building any window:
ActionUIRichText.register()
```

## Consuming it

`Package.swift` makes this a Swift package (macOS / iOS / visionOS) - the primary way to consume the
add-on. It declares the RichText github dependency for you:

```swift
.package(path: "Add-ons/ActionUIRichText")
// ...
.product(name: "ActionUIRichText", package: "ActionUIRichText")
```

The RichText dependency is pinned to the package's `main` branch (it has no released tags yet); switch
to `from: "x.y.z"` in `Package.swift` once it is tagged.

SPM builds ActionUI once and the host links it; this product references ActionUI's symbols and pulls
RichText (and AsyncImageCache) in transitively. See `Add-ons/ActionUIAddOnTestApp` for a host that
links it.

## Standalone static-library build (optional)

`project.yml` builds the add-on as a standalone static library with [xcodegen](https://github.com/yonaskolb/XcodeGen),
with ActionUI and RichText as `link: false` (compile-only) dependencies. Unlike `Package.swift`, the
xcodegen spec references RichText - and AsyncImageCache (RichText's own dependency) - by **local
checkout paths** (siblings of the ActionUI repo) so xcodegen resolves offline; listing AsyncImageCache
locally overrides RichText's github reference to it (same package identity). Adjust the paths to your
checkouts if needed.

```sh
cd Add-ons/ActionUIRichText
xcodegen generate
xcodebuild -project ActionUIRichText.xcodeproj -scheme ActionUIRichText \
    -destination 'generic/platform=macOS' build
```

The `.xcodeproj` is generated from `project.yml` but committed, so it builds without xcodegen;
regenerate with `xcodegen generate` after editing `project.yml`.

## Documentation and verification

The add-on mirrors core ActionUI's documentation layout so the doc/tooling systems pick it up
automatically:

- `Sources/RichText.swift` opens with a head comment (the `Sample JSON for RichText` block), the same
  way core views are documented.
- `Documentation/Schemas/RichText.md` is the human-readable element doc; `Documentation/Elements/RichText.json`
  is the insert template.
- The `ActionUIRichTextDocumentation` SPM product bundles `Documentation/` as resources, mirroring
  core `ActionUIDocumentation`.
- `Schemas/RichText.json` is the **verifier** schema. The ActionUI verifier auto-discovers
  `Add-ons/*/Schemas` (in-repo) and its own `schemas/add-ons/` (when packaged), so a document using
  the `RichText` element validates with no `--schema-dir` flag:

  ```sh
  python3 Tools/verifier/validate_actionui.py Add-ons/ActionUIRichText/Examples/RichText.json
  ```

## Files

- `project.yml` - xcodegen spec (static lib; ActionUI + RichText as `link: false` deps).
- `Sources/ActionUIRichText.swift` - Swift `register()` entry point + plain C `ActionUIRichText_register()` (for ObjC/C++ hosts).
- `Sources/RichText.swift` - the `ActionUIViewConstruction` element type (with the documented head comment).
- `Documentation/Schemas/RichText.md` - element schema doc; `Documentation/Elements/RichText.json` - insert template.
- `Documentation/ActionUIRichTextDocumentation.swift` - `Bundle.module` accessor for the docs product.
- `Schemas/RichText.json` - verifier schema (auto-discovered).
- `Examples/RichText.json` - a sample window using the element.
