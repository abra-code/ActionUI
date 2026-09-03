# ActionUI Architecture (Apple Platforms)

> **Scope:** This document describes the **Apple-platform renderer** (SwiftUI on macOS, iOS, iPadOS, watchOS, tvOS, visionOS), which is the reference implementation. ActionUI renders the same JSON on two other platforms — **Android** (Jetpack Compose) and the **Web** (DOM/CSS) — through independent renderers that mirror this architecture. The [Android Architecture](#android-architecture) and [Web Architecture](#web-architecture) sections near the end summarize how each maps onto this design and where it differs. The pipeline, model, action system, and language adapters below are Apple-specific unless noted.

## Overview

ActionUI renders SwiftUI views from JSON descriptions. There is no intermediate runtime, virtual DOM, or reconciliation step — JSON is parsed into validated properties and constructed directly as SwiftUI views.

The design goal shared across all three renderers is the same: parse a platform-neutral JSON document into validated properties, then construct native views directly in the host UI framework, with no framework-specific markup in the JSON. Each renderer keeps its source tree laid out the same way (one file per element, grouped into `Common` / `Helpers` / `Views`) so the three stay diffable against one another.

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
│  - validateProperties()                     │
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
Every view type conforms to this protocol, implementing three methods:
- **validateProperties()** — Validates JSON properties, applies defaults, reports errors/warnings
- **buildView()** — Constructs the SwiftUI view from validated properties
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
2. Compiles the C bridge (`actionui_native.m`) against the frameworks
3. Installs the `actionui` Python package via pip

## Platform Support

- macOS 14.6+
- iOS 17.6+
- iPadOS 17.6+
- watchOS 10.6+
- tvOS 17.6+
- visionOS 2.6+

Platform-specific views (e.g., Table on macOS) are conditionally available. Unsupported features degrade gracefully with validation warnings.

## Android Architecture

The Android renderer targets **Android 12.0+** and reproduces this architecture in Kotlin with **Jetpack Compose** as the native UI framework in place of SwiftUI.

**What is the same:**
- The same JSON schema, element names, and property names. A document written for Apple renders on Android with no changes.
- The same pipeline shape: a registry maps type strings to per-element constructors, each element validates its properties and builds a native view, and a central model holds view state and routes action callbacks by string ID.
- The same one-file-per-element source layout, kept parallel to the Swift tree so behavior can be diffed element-for-element.
- The same graceful-degradation contract: unknown types or properties produce validation warnings rather than crashes.

**What differs:**
- Views are **Compose composables** rather than SwiftUI views; state flows through Compose's recomposition instead of SwiftUI's, so there is likewise no virtual DOM or manual diffing.
- Platform-native chrome is Material: toolbars and menu icons use the Material Symbols font, the window-level toast is a Material snackbar, and semantic colors resolve to adaptive theme colors.
- Optional capabilities that carry heavy dependencies (notably **Map**) ship as self-registering provider modules — `:map-osm` (Leaflet/OpenStreetMap, no API key) or `:map-google` (maps-compose) — so an app that shows no map links no map engine. This module-registration pattern is the same idea the Apple add-on architecture later adopted.
- Add-ons exist on Android too (`:addon-cachedimage`, `:addon-richtext`), though a few Apple add-ons (e.g. the Chat element) are not yet ported.

## Web Architecture

The Web renderer targets any modern browser and reproduces this architecture in **plain JavaScript**, emitting **real DOM elements styled with CSS** as the native UI layer. It uses ES modules directly — **no build step, no bundler, no framework runtime, no dependencies** — and serves as static files from any URL prefix.

**What is the same:**
- The same JSON schema and the same registry → validate → build → apply-modifiers pipeline, with a central model holding view state and dispatching actions by string ID.
- The same one-file-per-element layout (`Common` / `Helpers` / `Views`), kept parallel to the Swift and Kotlin trees.
- The same runtime surface — `setElementProperty`, structural mutation (`insertElement` / `insertRow` / `removeElement`), programmatic row selection, dialogs/sheets/popovers, toast, lifecycle hooks, and the `animation` modifier.

**What differs:**
- Views are **DOM nodes**; the "no virtual DOM, no reconciliation" property here means the renderer manipulates the real DOM directly rather than diffing a shadow tree, so the `animation` modifier is expressed over armed CSS transitions.
- A dedicated **mobile/touch adaptation layer** presents sheets, popovers, and menus as bottom action sheets on phones, collapses TabView to a bottom tab bar and NavigationSplitView to a stack, and adds left-edge swipe-back, pull-to-refresh, and safe-area handling — behaviors the Apple and Android UI frameworks provide natively.
- SF Symbol names are resolved to Material Symbol glyphs for the web font, and lazy containers use `content-visibility` plus incremental rendering in place of the native lazy stacks.
- There is no compiled language adapter layer; app logic is JavaScript in the page. A [live demo](https://abracode.com/ActionUIWeb/demo/) runs the renderer directly from static files.

## Tools

- **ActionUIViewer** — Preview JSON files, take screenshots for sharing or AI feedback
- **ActionUIVerifier** — Validate JSON files before deployment
- **ActionUISwiftTestApp** — Test app with examples of all supported view types
