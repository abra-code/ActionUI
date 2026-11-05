# ActionUIHostSurface

An optional ActionUI add-on that adds the `HostSurface` element: a rectangle in an ActionUI layout
whose pixels the client program draws with its own renderer - Metal, wgpu, MoltenVK, ANGLE or a CPU
rasterizer - while ActionUI does everything around it (layout, controls, menus, dialogs). On macOS and
iOS the client gets a `CAMetalLayer`, frame ticks, and pointer, touch, pen, scroll, gesture and key
input.

```json
{ "type": "HostSurface", "id": 5, "properties": { "surfaceName": "viewport", "continuous": true } }
```

## Two library targets

- **`CActionUIHostSurface`** - the plain C header `include/ActionUIHostSurface.h`, for C, C++ and Rust
  clients. The Swift target imports it for the C types and re-exports it.
- **`ActionUIHostSurface`** - the element, and the functions the header declares (Swift, `@c`).

Plus `ActionUIHostSurfaceDocumentation`, a resource-only product with the element documentation.

## Using it

Register the element once at launch, before any window that uses it, then bind a client to a surface
name:

```swift
import ActionUIHostSurface

ActionUIHostSurface.register()
ActionUIHostSurface.setDelegate(myClient, forSurfaceName: "viewport")   // a HostSurfaceDelegate
```

```c
#include <ActionUIHostSurface.h>

ActionUIHostSurface_register();
AUIHostSurfaceDelegate delegate = { .structSize = sizeof delegate, .surface = on_surface, .frame = on_frame };
actionUIHostSurfaceSetDelegate("viewport", &delegate, my_state);
```

The client contract (events, threads, the frame callback) is in `Documentation/Schemas/HostSurface.md`
and in the header. `Add-ons/ActionUIAddOnTestApp` has a Swift client that draws with Metal
(`Sources/HostSurfaceDemoClient.swift`, demo `HostSurface`): drag to draw, scroll to shift the color.

## Design: one surface per element, outside SwiftUI

SwiftUI rebuilds a representable when a modifier that ActionUI applies conditionally appears or goes
away (the first `padding`, for example), and it makes the new view before it dismantles the old one.
An element that owned its Metal layer would destroy the client's swapchain on such a change. Here the
add-on owns one surface view per (window, element), and the representable is a thin container that
adopts it; a rebuild moves the same view, and its layer, into the new container. The element applies
`hidden` itself (`handledBaseModifiers`) for the same reason.

The surface view decides the events from what it observes: a window, a size, a live container,
`hidden`, the window's occlusion, the scene's state. Teardown waits one main-loop turn after its
container is dismantled, in case a new container adopts it, except when its window closes (closing a
window does not detach its views) or its scene disconnects, which tear down at once.

## Consuming it

`Package.swift` makes this a Swift package (macOS 14.6, iOS 17.6). A host adds it as a dependency and
links the `ActionUIHostSurface` product alongside ActionUI:

```swift
.package(path: "Add-ons/ActionUIHostSurface")
// ...
.product(name: "ActionUIHostSurface", package: "ActionUIHostSurface")
```

The product compiles against ActionUI's public API and does not embed it; the host links ActionUI.

## Documentation and verification

- `Sources/ActionUIHostSurface/HostSurface.swift` opens with the `Sample JSON for HostSurface` comment,
  the same way core views are documented; `Documentation/Schemas/HostSurface.md` is the element doc
  built from it, and `Documentation/Elements/HostSurface.json` the insert template.
- `Schemas/HostSurface.json` is the verifier schema. The verifier finds `Add-ons/*/Schemas` by itself:

  ```sh
  python3 Tools/verifier/validate_actionui.py Add-ons/ActionUIHostSurface/Examples/HostSurface.json
  ```

## Tests

```sh
cd Add-ons/ActionUIHostSurface
swift test
xcodebuild test -scheme ActionUIHostSurface-Package -destination 'platform=iOS Simulator,name=iPhone 17'
```

They need the sandbox off (SwiftPM, windows). `HostSurfaceLifecycleTests` drives the binding and
lifecycle rules with real surface views in windows that are never shown; `HostSurfaceInputTests`
drives input and the focus rules (on macOS with NSEvents); `HostSurfaceDocumentTests`
hosts real ActionUI documents and checks the event sequence for `hidden`, `padding` (which rebuilds the
SwiftUI view), element removal and window close.

## Files

- `Package.swift` - the package (Apple platforms).
- `Sources/CActionUIHostSurface/include/ActionUIHostSurface.h` - the C interface.
- `Sources/ActionUIHostSurface/ActionUIHostSurface.swift` - registration, the Swift API, the C functions.
- `Sources/ActionUIHostSurface/HostSurface.swift` - the element, the representable and the container.
- `Sources/ActionUIHostSurface/HostSurfaceView.swift` - the Metal-layer view and its lifecycle.
- `Sources/ActionUIHostSurface/HostSurfaceView+Input.swift` - input and focus, macOS and iOS.
- `Sources/ActionUIHostSurface/HostSurfaceKeyCodes.swift` - key codes to W3C key names.
- `Sources/ActionUIHostSurface/HostSurfaceRegistry.swift` - clients, surface views, live surfaces.
- `Sources/ActionUIHostSurface/HostSurfaceProperties.swift` - the element's properties.
- `Schemas/`, `Documentation/`, `Examples/` - verifier schema, element docs, an example document.
- `Tests/` - the tests above.
