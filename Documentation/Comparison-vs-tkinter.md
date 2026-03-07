# ActionUI Python Bridge vs tkinter

A comparison of ActionUI's Python module with Python's built-in tkinter for building desktop applications on macOS.

## Architectural Differences

| Aspect | ActionUI | tkinter |
|--------|----------|---------|
| UI definition | Declarative JSON | Imperative Python code |
| Rendering | Native SwiftUI views | Tk widgets (non-native look) |
| State model | Set/get values by view ID | Variable tracing (StringVar, IntVar) |
| Event model | Action callbacks by ID | Widget event binding |
| Layout | SwiftUI stacks, grids, modifiers | pack/grid/place geometry managers |
| App structure | JSON defines UI, Python handles logic | Python defines both UI and logic |

## Where ActionUI Excels

### Native macOS Experience
ActionUI renders real SwiftUI views. Buttons, pickers, toggles, tables — everything looks and behaves like a native macOS app. tkinter uses Tk widgets that look out of place on macOS despite theming efforts (ttk).

### Simplicity
A form with text fields, pickers, and buttons is a JSON file. No widget instantiation, no layout manager calls, no variable binding boilerplate. The Python side only handles actions and state — it never constructs UI.

### AI-Friendly
JSON is a format that LLMs generate reliably. Asking an AI to produce a tkinter UI means generating imperative Python code with correct widget hierarchies, geometry management, and callback wiring. ActionUI's JSON schema is regular and predictable.

### Multi-Window
ActionUI has built-in multi-window support with per-window state, window lifecycle callbacks, and menu bar integration. tkinter can do multi-window with Toplevel, but window management, menu bars, and state isolation require manual work.

### macOS Integration
ActionUI provides native file open/save panels, alert dialogs, application menu bar with CommandGroup/CommandMenu, keyboard shortcuts, and proper app lifecycle (will_terminate, should_terminate, etc.). tkinter's macOS integration is limited — file dialogs work but menu bars and app lifecycle are basic.

### Dynamic UI
LoadableView allows swapping UI sections at runtime by loading new JSON from files or network — without rebuilding the window. tkinter requires destroying and recreating widgets.

### 50+ Native Components
Table, NavigationSplitView, Map, VideoPlayer, Canvas, Gauge, DisclosureGroup, ColorPicker, DatePicker — these are SwiftUI components with no tkinter equivalent or with significantly inferior tkinter alternatives.

## Where tkinter Has More Features

### Dynamic Widget Construction
tkinter can create and destroy widgets programmatically at any time. ActionUI's UI structure is defined by JSON at window creation. However, LoadableView, property changes (isHidden, items, etc.), and set/get APIs cover most practical cases.

### Rich Text
tkinter's Text widget supports tags, marks, embedded widgets, and per-character styling. ActionUI's TextEditor is plain text.

### Canvas Drawing (Imperative)
tkinter's Canvas allows imperative drawing — add/remove/move shapes interactively with hit testing and drag support. ActionUI has a Canvas view but it uses declarative drawing operations in JSON properties, which is a different (and arguably cleaner) model for static or data-driven graphics.

### Event Granularity
tkinter exposes mouse motion, key press/release, focus, enter/leave, and drag events per widget. ActionUI fires action callbacks — sufficient for app logic but not for building custom interactive controls.

## Features That Seem Missing But Aren't Needed

### Timers
tkinter has `after(ms, callback)` for scheduling. ActionUI doesn't expose a timer API, but Python threads handle periodic work fine, and UI updates are just `set_value()` calls. A timer synchronized to the UI run loop is rarely needed in applet-style apps.

### Clipboard
tkinter provides `clipboard_get()`/`clipboard_append()`. In practice, the system Edit menu handles user-driven copy/paste in text fields automatically. For scripting, macOS `pbcopy`/`pbpaste` command-line tools cover programmatic clipboard needs. Clipboard operations should be user-initiated, not app-driven.

### Text Input Dialog
tkinter has `simpledialog.askstring()`. In practice, text input belongs in the UI itself (a TextField in the form), not in a modal dialog. ActionUI supports alert dialogs with custom buttons for confirmations.

### Window Positioning/Resizing
tkinter offers `geometry()`, `minsize()`, `maxsize()`. ActionUI sets window properties at creation via JSON. Programmatic window manipulation is rarely needed for applets — the window manager and user handle this.

## Summary

ActionUI is not a tkinter replacement for all use cases. It targets a specific and common pattern: **macOS applets and tools where the UI is a form/dashboard that displays data and collects user input**. For this pattern, ActionUI is simpler, produces better-looking results, and integrates deeply with macOS.

tkinter remains appropriate for cross-platform needs, highly dynamic widget construction, or interactive canvas applications (drawing tools, diagram editors). But on macOS, tkinter's non-native appearance and limited platform integration make ActionUI the better choice for most applet-style applications.
