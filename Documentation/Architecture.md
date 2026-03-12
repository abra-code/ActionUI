# ActionUI Architecture

## Overview

ActionUI renders SwiftUI views from JSON descriptions. There is no intermediate runtime, virtual DOM, or reconciliation step — JSON is parsed into validated properties and constructed directly as SwiftUI views.

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
- **Styling:** foregroundColor, font, opacity, shadow, border
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

## Tools

- **ActionUIViewer** — Preview JSON files, take screenshots for sharing or AI feedback
- **ActionUIVerifier** — Validate JSON files before deployment
- **ActionUISwiftTestApp** — Test app with examples of all supported view types
