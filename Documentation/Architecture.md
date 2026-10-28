# ActionUI Architecture (Apple Platforms)

> **Scope:** This document describes the **Apple-platform renderer** (SwiftUI on macOS, iOS, iPadOS, watchOS, tvOS, visionOS), which is the reference implementation. ActionUI renders the same JSON on three other platforms - **Android** (Jetpack Compose), the **Web** (DOM/CSS) and **Linux** (GTK 4 and libadwaita, in Swift, sharing the portable core) - through renderers that mirror this architecture. The [Android Architecture](#android-architecture), [Web Architecture](#web-architecture) and [Linux Architecture](#linux-architecture) sections near the end summarize how each maps onto this design and where it differs. The pipeline, model, action system, and language adapters below are Apple-specific unless noted.

## Overview

ActionUI renders SwiftUI views from JSON descriptions. There is no intermediate runtime, virtual DOM, or reconciliation step: each element reads its JSON properties through a typed `Props` value and is constructed directly as a SwiftUI view.

The design goal shared across all three renderers is the same: read a platform-neutral JSON document into typed properties, then construct native views directly in the host UI framework, with no framework-specific markup in the JSON. Each renderer keeps its source tree laid out the same way (one file per element, grouped into `Common` / `Helpers` / `Views`) so the three stay diffable against one another.

## Pipeline

```
┌─────────────────────────────────────────────┐
│           JSON/Plist Description            │
│  { "type": "Button", "id": 1, ... }         │
└─────────────────┬───────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────┐
│           ActionUIRegistry                  │
│  - View type registration                   │
│  - Type lookup and dispatch                 │
└─────────────────┬───────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────┐
│        ActionUIViewConstruction             │
│  - Props (typed properties)                 │
│  - buildView()                              │
│  - applyModifiers()                         │
└─────────────────┬───────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────┐
│           ActionUIModel                     │
│  - State management (@MainActor)            │
│  - Action routing                           │
│  - View value get/set                       │
└─────────────────────────────────────────────┘
```

### ActionUIRegistry
Maps type strings ("Button", "TextField", etc.) to view construction implementations. Extensible — new view types are registered here.

### ActionUIViewConstruction Protocol
Every view type conforms to `ActionUIViewConstruction`, which names two protocols together: `ActionUIElementSpec` (what the element is, shared by every renderer: its value type, initial value and states, string conversions, insertable containers, how it reacts to a property change, and the base properties it applies itself) and `ActionUISwiftUIRenderer` (how it draws on Apple: `buildView` and `applyModifiers`). Each element reads its properties through a nested `Props` value:
- **Props** - the element's typed properties, read from the raw JSON properties on every render. A value of the wrong type is ignored and a missing one gets its default, so an invalid document renders instead of failing. The base View properties (padding, frame, font, actionID, ...) are read the same way by `BaseModifiers`. Checking a document while it is written is the verifier's job (`actionui-verify`).
- **buildView()** - Constructs the SwiftUI view from the element's `Props`
- **applyModifiers()** — Applies styling and behavior modifiers (padding, frame, font, actionID, etc.)

### ActionUIModel
The central state manager. Holds view values, routes action callbacks, and provides the get/set API for client code to read and update view state.

## Supported Components (50+)

**Layout & Containers:**
HStack, VStack, ZStack, LazyHStack, LazyVStack, LazyHGrid, LazyVGrid, Grid, NavigationStack, NavigationSplitView, NavigationLink, TabView, Group, Section, Form, ControlGroup, DisclosureGroup, GroupBox, ScrollView, ScrollViewReader

**Input Controls:**
TextField, SecureField, TextEditor, Picker, DatePicker, ColorPicker, Toggle, Slider, Button, Link, ShareLink, Menu

**Display Elements:**
Text, Label, Image, AsyncImage, ProgressView, Gauge, Table, List, VideoPlayer, Map, Canvas, WebView, Spacer, Divider, EmptyView

**Dynamic Loading:**
LoadableView — Load JSON UI definitions at runtime from files or URLs

## Universal Modifiers

All views inherit modifiers from the base View implementation:
- **Layout:** padding, frame, background, cornerRadius, position, offset
- **Styling:** foregroundStyle, font, opacity, shadow, border
- **Sizing:** controlSize (mini, small, regular, large, extraLarge)
- **Behavior:** hidden, disabled, actionID, keyboardShortcut
- **Accessibility:** accessibilityLabel, accessibilityHint

## State Management

Views with integer IDs have their state tracked by ActionUIModel. Client code can:
- **Get values:** Read the current value of any identified view
- **Set values:** Update view values programmatically
- **Get/set properties:** Read or modify view properties at runtime
- **Get/set state:** Access view-specific state (e.g., scroll position)

## Action System

User interactions fire action callbacks identified by string IDs. The action handler receives:
- **actionID** — The string identifier from the view's JSON
- **windowUUID** — Which window the action originated from
- **viewID** — The integer ID of the view
- **viewPartID** — Sub-component identifier (e.g., column index in a table)
- **context** — Optional contextual data (e.g., button title, row index)

## Language Adapters

ActionUI's core is a Swift framework. Language adapters provide bindings for different programming environments:

- **ActionUISwiftAdapter** — Native Swift integration
- **ActionUIObjCAdapter** — Objective-C bridging
- **ActionUICAdapter** — C function API (foundation for other language bindings)
- **ActionUICppAdapter** — C++ bindings
- **ActionUIJavaScriptCoreAdapter** — JavaScriptCore integration
- **ActionUIWebKitJSAdapter** — WebKit JavaScript bridge
- **ActionUI Python Module** — Full Python package with pip install (see [Python Bridge](#python-bridge))
- **ActionUI Node.js Addon** - Native addon over the same C functions (see `ActionUINodeJS/`)
- **ActionUI Rust Crates** - `actionui-sys` and `actionui` (see [Rust Bridge](#rust-bridge))
- **ActionUIRemote** — Out-of-process binding (see [Remote Binding](#remote-binding))

## Remote Binding

Every adapter above runs inside the process that owns the UI. `ActionUIRemote` (macOS) serves the same verb set to other processes: a host embedding ActionUI starts `ActionUIRemoteServer` on a Unix domain socket, and any process of the same user speaks newline-delimited JSON-RPC 2.0 to it, with the same value encoding as the C adapter and the same `(windowUUID, viewID, viewPartID)` addressing. Requests run on the main actor against `ActionUIModel`; hosts add their own namespaced methods. The wire contract is `ActionUIRemote/PROTOCOL.md`; a stdlib-only Python client ships in `ActionUIRemote/Python/`. This is the path OMC applets use from their out-of-process script handlers.

## Python Bridge

The `actionui` Python module provides a complete API for building macOS applications:

```python
import actionui

app = actionui.Application(name="MyApp")

window = actionui.Window.from_file("ui.json", title="My Window")
app.load_and_present_window(window)

@app.action("buttonClicked")
def on_button(ctx):
    value = window.get_string(view_id=10)
    window.set_string(view_id=20, value=f"You entered: {value}")

app.run()
```

### Application Features
- Multi-window management with per-window state
- Application lifecycle callbacks (will_terminate, should_terminate, etc.)
- Window lifecycle callbacks (window_will_present, window_will_close)
- Native menu bar with CommandGroup and CommandMenu
- File open/save panels with type filtering
- Alert dialogs with custom buttons

### Building
The Python module is built from `ActionUIPython/` using `build_and_install.sh`, which:
1. Builds ActionUI static frameworks via xcodebuild (universal arm64 + x86_64)
2. Compiles the C bridge (`actionui_native.c`) against the frameworks
3. Installs the `actionui` Python package via pip

## Rust Bridge

The `actionui` crate pairs a native macOS interface described in JSON with program logic written in Rust. It is built on the C adapter and on `ActionUIAppKitApplication`, the application layer the Python and Node.js modules also use: that layer creates the windows and the menu bar and runs the event loop, and the Rust code opens windows from JSON and reacts to named actions.

```rust
use actionui::App;

fn main() -> actionui::Result<()> {
    let app = App::new()?;
    let window = app.present_window_from_json(include_str!("ui.json"), Some("My Window"))?;

    app.on_action("buttonClicked", move |_action| {
        let value = window.get_string(10).ok().flatten().unwrap_or_default();
        let _ = window.set_string(20, &format!("You entered: {value}"));
    });

    app.run()
}
```

- Two crates in `ActionUIRust/`: `actionui-sys` (the C declarations and the link setup) and `actionui` (the safe API).
- The ActionUI frameworks are linked statically, so the result is one executable that depends only on macOS itself.
- `App` exists only on the main thread; a `Window` can be used from any thread, so a worker thread updates the interface directly.
- A panic in a handler is caught and logged, and the application keeps running.
- `make_app_bundle.sh` wraps the executable in an `.app` bundle.

See `ActionUIRust/README.md`, `ActionUIRust/RUST_API_REFERENCE.md` and `ActionUIRust/BUILD_GUIDE.md`.

## Platform Support

- macOS 14.6+
- iOS 17.6+
- iPadOS 17.6+
- watchOS 10.6+
- tvOS 17.6+
- visionOS 2.6+
- Linux: GNOME 48 and later (GTK 4.18, libadwaita 1.7); see Linux Architecture below

Platform-specific views (e.g., Table on macOS) are conditionally available. Unsupported features degrade gracefully: they are ignored, never a crash.

## Android Architecture

The Android renderer targets **Android 12.0+** and reproduces this architecture in Kotlin with **Jetpack Compose** as the native UI framework in place of SwiftUI.

**What is the same:**
- The same JSON schema, element names, and property names. A document written for Apple renders on Android with no changes.
- The same pipeline shape: a registry maps type strings to per-element constructors, each element reads its properties and builds a native view, and a central model holds view state and routes action callbacks by string ID.
- The same one-file-per-element source layout, kept parallel to the Swift tree so behavior can be diffed element-for-element.
- The same graceful-degradation contract: unknown types or properties never crash.

**What differs:**
- Views are **Compose composables** rather than SwiftUI views; state flows through Compose's recomposition instead of SwiftUI's, so there is likewise no virtual DOM or manual diffing.
- Platform-native chrome is Material: toolbars and menu icons use the Material Symbols font, the window-level toast is a Material snackbar, and semantic colors resolve to adaptive theme colors.
- Optional capabilities that carry heavy dependencies (notably **Map**) ship as self-registering provider modules — `:map-osm` (Leaflet/OpenStreetMap, no API key) or `:map-google` (maps-compose) — so an app that shows no map links no map engine. This module-registration pattern is the same idea the Apple add-on architecture later adopted.
- Add-ons exist on Android too (`:addon-cachedimage`, `:addon-richtext`), though a few Apple add-ons (e.g. the Chat element) are not yet ported.

## Web Architecture

The Web renderer targets any modern browser and reproduces this architecture in **plain JavaScript**, emitting **real DOM elements styled with CSS** as the native UI layer. It uses ES modules directly — **no build step, no bundler, no framework runtime, no dependencies** — and serves as static files from any URL prefix.

**What is the same:**
- The same JSON schema and the same registry, build and apply-modifiers pipeline (the Web renderer also checks each element's properties before building it), with a central model holding view state and dispatching actions by string ID.
- The same one-file-per-element layout (`Common` / `Helpers` / `Views`), kept parallel to the Swift and Kotlin trees.
- The same runtime surface — `setElementProperty`, structural mutation (`insertElement` / `insertRow` / `removeElement`), programmatic row selection, dialogs/sheets/popovers, toast, lifecycle hooks, and the `animation` modifier.

**What differs:**
- Views are **DOM nodes**; the "no virtual DOM, no reconciliation" property here means the renderer manipulates the real DOM directly rather than diffing a shadow tree, so the `animation` modifier is expressed over armed CSS transitions.
- A dedicated **mobile/touch adaptation layer** presents sheets, popovers, and menus as bottom action sheets on phones, collapses TabView to a bottom tab bar and NavigationSplitView to a stack, and adds left-edge swipe-back, pull-to-refresh, and safe-area handling — behaviors the Apple and Android UI frameworks provide natively.
- SF Symbol names are resolved to Material Symbol glyphs for the web font, and lazy containers use `content-visibility` plus incremental rendering in place of the native lazy stacks.
- There is no compiled language adapter layer; app logic is JavaScript in the page. A [live demo](https://abracode.com/ActionUIWeb/demo/) runs the renderer directly from static files.

## Linux Architecture

The Linux renderer targets **GNOME 48 and later** (GTK 4.18, libadwaita 1.7) and is written in **Swift 6**, with **GTK 4 and libadwaita** as the native UI layer in place of SwiftUI. It is built from the same Swift package as the Apple frameworks.

**What is the same:**
- The same JSON schema, element names and property names. A document written for Apple renders on Linux with no changes; an element the Linux renderer does not have yet shows a placeholder that names its type.
- The same portable core, compiled once for both platforms: the element specs and their typed properties, `ActionUIModel`, the JSON layer and the document loader (`ActionUI/Core`). It uses `FoundationEssentials` only, not full Foundation, so the library carries no ICU data.
- The same C interface: the functions of `ActionUIC.h` and `ActionUIApp.h`, with the same names and signatures. A Python, C, Rust or Node.js host written for macOS runs on Linux with the same calls. The functions Linux does not have yet (the menu bar, alerts, file panels, the remote server) answer as failures and log why.

**What differs:**
- **Retained widgets.** Each element gets one GTK widget for its lifetime. A node per element watches what it read from the model (Observation) and updates its widget when that changes. SwiftUI instead rebuilds views and diffs them.
- **SwiftUI's layout, reproduced.** Stacks offer space the way SwiftUI does: the least flexible child first, Spacers last, frames with minimum, ideal and maximum sizes. The layout parity fixtures (`LayoutParity/`) are documents whose frames were recorded from SwiftUI; both renderers are tested against the same recordings.
- **libadwaita's look:** its controls, header bar, cards and dark style. SF Symbol names map to the Adwaita icon theme; a name with no counterpart shows `image-missing`.
- **Optional libraries loaded at run time.** WebView uses WebKitGTK 6.0 and locale formatting uses the system's ICU, both opened with `dlopen` when first needed rather than linked, as Linux has no weak linking: neither is needed to build or start a program. An app that shows web pages lists `libwebkitgtk-6.0-4` among its own package dependencies; without it a WebView shows a placeholder naming that package.
- **Closing the last window:** when the user closes it, the application ends (after asking the shouldTerminate handler), as GNOME applications do; on macOS an application keeps running without windows, but a Linux application with no window has no Dock icon or menu bar to quit it from. When the host closes it, the application keeps running until the host presents another window or calls terminate, as on macOS, so a host can close one window before it opens the next.
- **One library.** On Apple platforms the application layer (`ActionUIAppKitApplication`) is a framework of its own, apart from `ActionUI` and the C adapter, because it brings an application delegate, a menu bar and the remote server that an app with its own `NSApplication` does not want. On Linux, `libActionUI.so` holds all three: the renderer, the C adapter and the application functions (`AdwaitaApplication` and the `actionUIApp*` functions):
  - The application part is small, does nothing until a host calls it, and needs no library the renderer does not already use (GTK, libadwaita, the Swift runtime, `FoundationEssentials`).
  - The library meant for distribution carries the Swift runtime inside it, so it runs where Swift is not installed. A process can hold only one Swift runtime, so a second ActionUI library carrying its own copy cannot be loaded beside it, and a host that loads one library is the simplest for Python's ctypes and Node.js.

**Swift programs on Linux** use ActionUI as a Swift package dependency: its code is compiled into the program, which uses the toolchain's Swift runtime. They do not load `libActionUI.so`, which would bring a second Swift runtime into the process. `ActionUIAdwaitaViewer` is built this way. `AdwaitaApplication` is the public Swift API for running an application and presenting documents; there is no public API yet for showing ActionUI content in the windows of an application that has its own `GtkApplication`.

## Tools

- **ActionUIViewer** — Preview JSON files, take screenshots for sharing or AI feedback (`--screenshot out.png`; add `--hide-window` to render in-process without showing a window, which also works with the screen locked)
- **ActionUIVerifier** — Validate JSON files before deployment
- **ActionUISwiftTestApp** — Test app with examples of all supported view types
- **ActionUIAdwaitaViewer** (Linux) - Opens a JSON file in a window; `--dark` for the dark style, `--screenshot out.png` to save the window as an image and quit (drawn by the window itself, so no screen capture is needed)
