# ActionUICachedImage

An optional ActionUI add-on that provides a **cached, off-main image** element (`CachedImage`),
backed by the [AsyncImageCache](https://github.com/abra-code/AsyncImageCache) package. It is the
second ActionUI add-on (after `ActionUIQuickLook`), and the first to depend on a third-party github
package.

## What it adds

A `CachedImage` element, usable from JSON like any built-in:

```json
{ "type": "CachedImage", "id": 80, "properties": {
    "url": "https://example.com/photo.jpg",
    "intrinsicSize": { "width": 1024, "height": 768 },
    "contentMode": "fill",
    "maxPixelWidth": 840 } }
```

- macOS / iOS / visionOS: `AsyncImageCache.CachedImage` (a SwiftUI view).

Why not the core `AsyncImage` element? Core `AsyncImage` wraps SwiftUI's `AsyncImage`: it decodes on
whatever thread SwiftUI picks, keeps no cross-launch cache, and reflows layout when the picture
arrives. `CachedImage` instead:

- fetches / decodes / downscales / rounds **off the main thread** - only the final hand-off touches
  the main thread, so image-heavy scrolling stays smooth;
- serves from a **two-tier cache** (an in-memory `NSCache` of ready-to-draw variants + originals, and
  the original transport bytes on disk under `<Caches>/AsyncImageCache/`), so a second view of the
  same URL is instant and survives relaunch;
- knows the natural pixel size **up front** (persisted as a file extended attribute), so with
  `intrinsicSize` - or once an image is cached - layout reserves the exact box and the picture
  hydrates with **zero reflow**, even on the first frame after a relaunch.

The element value is the image URL string, so the host drives it with the existing `setElementValue`
path, exactly like the core `AsyncImage` element.

### Properties

| Property | Type | Notes |
|---|---|---|
| `url` | string | Web / file / data URL; seeds the element value. Nil or invalid shows the placeholder. |
| `intrinsicSize` | `{ width, height }` | The source's natural size, if known ahead of load. Reserves the exact box up front (zero reflow). |
| `contentMode` | `"fit"` \| `"fill"` | How the image fills the reserved box. Default `"fill"` (CachedImage's own default). |
| `maxPixelWidth` | number | Cap the decoded width in pixels (downscaled off-main) to bound memory. Omit for natural resolution. |
| `cornerRadius` | number | Rounds the image with a continuous-corner clip applied by CachedImage itself. |

`cornerRadius` uses the standard View property name, but this element rounds the image **itself**
rather than via the baseline `cornerRadius` modifier: CachedImage draws the image as an aspect-fit
overlay on a transparent box, so with a filling `frame` the baseline modifier would round only the
transparent outer frame, leaving the centered image square. The element therefore consumes
`cornerRadius` in `validateProperties` and passes it to the wrapped view's own (continuous-corner)
parameter. Sizing still uses the baseline `frame` modifier.

## Design: compiles against ActionUI, links AsyncImageCache transitively

This target is a **static library**. It has two dependencies with different linking stories:

- **ActionUI** - the add-on compiles against ActionUI's public API but does **not** embed it
  (`link: false` in `project.yml`). A static library never embeds its dependencies; the host app
  links ActionUI and this add-on, and ActionUI's symbols resolve at the host's final link.
- **AsyncImageCache** - a genuine third-party dependency whose code the element actually uses. With
  the Swift package, SPM pulls it in transitively, so any host that links `ActionUICachedImage` also
  links `AsyncImageCache` automatically - no extra step.

Apple has no guaranteed pre-`main` hook for a statically linked Swift type, so registration is one
explicit call at launch (not automatic on link, unlike Android's manifest ContentProvider):

```swift
import ActionUICachedImage

// In your App init / applicationDidFinishLaunching, before building any window:
ActionUICachedImage.register()
```

## Consuming it

`Package.swift` makes this a Swift package (macOS / iOS / visionOS) - the primary way to consume the
add-on. It declares the AsyncImageCache github dependency for you:

```swift
.package(path: "Add-ons/ActionUICachedImage")
// ...
.product(name: "ActionUICachedImage", package: "ActionUICachedImage")
```

The AsyncImageCache dependency is pinned to the package's `main` branch (it has no released tags
yet); switch to `from: "x.y.z"` in `Package.swift` once it is tagged.

SPM builds ActionUI once and the host links it; this product references ActionUI's symbols and pulls
AsyncImageCache in transitively. See `Add-ons/ActionUIAddOnTestApp` for a host that links it.

## Standalone static-library build (optional)

`project.yml` builds the add-on as a standalone static library with [xcodegen](https://github.com/yonaskolb/XcodeGen),
with ActionUI and AsyncImageCache as `link: false` (compile-only) dependencies. Unlike `Package.swift`,
the xcodegen spec references AsyncImageCache by a **local checkout path** (`../../../AsyncImageCache`,
a sibling of the ActionUI repo) so xcodegen resolves offline; adjust the path to your checkout if
needed.

```sh
cd Add-ons/ActionUICachedImage
xcodegen generate
xcodebuild -project ActionUICachedImage.xcodeproj -scheme ActionUICachedImage \
    -destination 'generic/platform=macOS' build
```

The `.xcodeproj` is generated from `project.yml` but committed, so it builds without xcodegen;
regenerate with `xcodegen generate` after editing `project.yml`.

## Documentation and verification

The add-on mirrors core ActionUI's documentation layout so the doc/tooling systems pick it up
automatically:

- `Sources/CachedImage.swift` opens with a head comment (the `Sample JSON for CachedImage` block),
  the same way core views are documented.
- `Documentation/Schemas/CachedImage.md` is the human-readable element doc; `Documentation/Elements/CachedImage.json`
  is the insert template.
- The `ActionUICachedImageDocumentation` SPM product bundles `Documentation/` as resources, mirroring
  core `ActionUIDocumentation`.
- `Schemas/CachedImage.json` is the **verifier** schema. The ActionUI verifier auto-discovers
  `Add-ons/*/Schemas` (in-repo) and its own `schemas/add-ons/` (when packaged), so a document using
  the `CachedImage` element validates with no `--schema-dir` flag:

  ```sh
  python3 Tools/verifier/validate_actionui.py Add-ons/ActionUICachedImage/Examples/CachedImage.json
  ```

## Files

- `project.yml` - xcodegen spec (static lib; ActionUI + AsyncImageCache as `link: false` deps).
- `Sources/ActionUICachedImage.swift` - Swift `register()` entry point + plain C `ActionUICachedImage_register()` (for ObjC/C++ hosts).
- `Sources/CachedImage.swift` - the `ActionUIViewConstruction` element type (with the documented head comment).
- `Documentation/Schemas/CachedImage.md` - element schema doc; `Documentation/Elements/CachedImage.json` - insert template.
- `Documentation/ActionUICachedImageDocumentation.swift` - `Bundle.module` accessor for the docs product.
- `Schemas/CachedImage.json` - verifier schema (auto-discovered).
- `Examples/CachedImage.json` - a sample window using the element.
