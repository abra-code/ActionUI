# ActionUI Add-ons

Optional, separately-linkable ActionUI add-ons - libraries that register their own custom element
types with the ActionUI engine without being part of core. The pattern mirrors the ActionUIAndroid
map providers (`map-google` / `map-osm`): core stays lean, and a host links an add-on only when it
needs that element.

## How an add-on works

- ActionUI exposes a public registration API: `ActionUIRegistry.shared.register(_:as:)` plus the
  public `ActionUIViewConstruction` contract (enabling change, commit 6637c52). An add-on implements
  that contract for its element type and exposes a one-line `register()` entry point.
- The add-on **compiles against ActionUI but does not link it** - the host app links ActionUI + the
  add-on and calls the add-on's `register()` once at launch, before any window that uses the element
  is built. (Apple has no guaranteed pre-`main` auto-registration hook like Android's manifest
  ContentProvider, so registration is this explicit call.)
- The add-on ships its own verifier schema; documents that use the add-on's element are validated by
  pointing the verifier at the add-on's `Schemas/` directory with `--schema-dir`.

## On Linux

The registration is the same call, `ActionUIRegistry.shared.register(_:as:)`, for a different
contract: SwiftUI views do not exist there, so an element type conforms to `ActionUIAdwaitaElement`
instead of `ActionUIViewConstruction`. It shares its spec (`ActionUIElementSpec`: value type, initial
value and states) with Apple and adds two calls:

- `makeWidget(_:)` creates the element's widget, once per instance, and reads nothing from the model.
  The element sets its own expansion on the widget (`gtk_widget_set_hexpand`,
  `gtk_widget_set_vexpand`). Closures it hands to GTK capture the node weakly.
- `update(_:_:)` makes the widget show the model, through the `RenderNode` it receives: its
  `properties`, view `model`, `element` and `windowUUID`. The node's `state` holds what the element keeps
  for this instance, set in `makeWidget` and released with the node. It runs again when a value, state or
  property it read changes, and after `node.setNeedsUpdate()`, for a change the model cannot report
  (an image that arrived).

Widgets are `OpaquePointer`s, as they are in RichText and AsyncImageCache. ModifierBox applies the
base View modifiers around the widget, as it does for a built-in element, less those the element lists
in `handledBaseModifiers`, which it reads in its `properties` and applies itself. The contract covers
elements that display: firing an action from a user's input is not part of it yet.

An add-on's Linux target depends on the `ActionUIStatic` product: one process has one Swift runtime,
so everything written in Swift links into one binary. Programs in other languages cannot call
`register()`, so `libActionUI.so`, built by the package in `ActionUIAdwaita/Library`, links the add-ons
and registers them before the first document loads. To add one there: a dependency in its
`Package.swift` and a line in `Sources/ActionUILibrary/LinkedAddOns.swift`. The Linux viewer and demo, in
`Apps/ActionUIViewer` (its `linuxPackage`) and `ActionUIAdwaita/Apps`, link and register the add-ons themselves:
add it to both `Package.swift` files and to both programs' `main.swift`.
The `CAdwaita` product gives it GTK's and libadwaita's C API
at the versions ActionUI supports. Do not depend on a Documentation target there: `Bundle.module`
needs full Foundation, and with it ICU's data, which the Linux build leaves out.

## Layout

- **`ActionUIQuickLook/`** - the first add-on: a `QuickLook` element (an embedded in-process
  Quick Look pane; `QLPreviewView` on macOS, `QLPreviewController` on iOS/visionOS). Shipped as a
  Swift package (`Package.swift`) and, optionally, a standalone static-library xcodegen project. Owns
  `Schemas/QuickLook.json`.
- **`ActionUICachedImage/`** - a `CachedImage` element, on Linux too: a cached, off-main image view backed by the
  [AsyncImageCache](https://github.com/abra-code/AsyncImageCache) github package (fetch/decode/
  downscale off the main thread, a two-tier memory + on-disk cache, and size-known-upfront layout
  with no reflow on hydration). Owns `Schemas/CachedImage.json`.
- **`ActionUIRichText/`** - a `RichText` element, on Linux too: a rich-text display view backed by the
  [RichText](https://github.com/abra-code/RichText) github package. It renders a whole Markdown
  document (headings, code blocks, quotes, lists, GFM tables, inline styling, links) into one native
  text view, selectable and copyable as a single unit (table-aware copy). RichText pulls AsyncImageCache
  transitively. Owns `Schemas/RichText.json`.
- **`ActionUIDiff/`** - a `Diff` element, on Linux too: a unified line diff of two texts or files, backed by the
  [DiffView](https://github.com/abra-code/DiffView) github package (a SwiftUI view on Apple, GTK widgets on Linux).
  Owns `Schemas/Diff.json`.
- **`ActionUIAddOnTestApp/`** - a multiplatform (macOS + iOS) host app that links ActionUI +
  ActionUISwiftAdapter + the add-on and renders a document using the add-on's element. The add-on
  analogue of `ActionUISwiftTestApp`, and the place to exercise an add-on at runtime.

## Projects (committed, generated by xcodegen)

Each subproject's `.xcodeproj` is generated from its `project.yml` but **committed**, so it builds
without xcodegen installed. `project.yml` is the source of truth - regenerate after editing it:

```sh
cd Add-ons/<dir>
xcodegen generate
```

Only `build/` output and per-user Xcode state (`xcuserdata/`) are git-ignored.

## Build / run the test app

```sh
cd Add-ons/ActionUIAddOnTestApp
xcodebuild -project ActionUIAddOnTestApp.xcodeproj -scheme ActionUIAddOnTestApp \
    -destination 'generic/platform=macOS' build
xcodebuild -project ActionUIAddOnTestApp.xcodeproj -scheme ActionUIAddOnTestApp \
    -destination 'generic/platform=iOS Simulator' build
# Or open the project in Xcode, pick a macOS or iOS destination, and Run.
```

## Verifying JSON that uses an add-on element

The core verifier only knows built-in elements; add the add-on's schema directory:

```sh
python3 Tools/verifier/validate_actionui.py \
    --schema-dir Add-ons/ActionUIQuickLook/Schemas \
    <document.json>
```

## Adding a new add-on

1. Create `Add-ons/<Name>/` with a `Package.swift` that depends on the ActionUI package
   (`.package(path: "../..")`) and a `Sources/` target implementing `ActionUIViewConstruction` for the
   element plus a public `register()` entry point. `buildView` and `applyModifiers` receive the
   properties as the document or `setElementProperty` gave them: read each one with a type check and a
   default, so a value of the wrong type is ignored rather than trusted.
2. Ship `Schemas/<Element>.json` (same format as `ActionUIVerifier/Schemas/`) so documents validate via
   `--schema-dir`.
3. Add the package + product to `ActionUIAddOnTestApp` and call its `register()` in the app's `init`
   to exercise it on macOS and iOS.
