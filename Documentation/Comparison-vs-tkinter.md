# ActionUI Python Bridge vs tkinter

> **Scope note:** This comparison covers desktop use on macOS and Linux. tkinter is a
> desktop UI toolkit (macOS, Windows, Linux via Tk) with no mobile or web
> support. ActionUI's Python module runs on macOS (SwiftUI) and on Linux (GTK 4 and
> libadwaita); there is no ActionUI renderer for Windows. ActionUI also targets iOS,
> Android, and the browser (a zero-dependency DOM/CSS renderer) from the same JSON;
> for those platforms, tkinter is not a relevant alternative — see `Comparison-vs-ReactNative.md`
> for the cross-platform perspective.

A comparison of ActionUI's Python module with Python's built-in tkinter for building desktop applications on macOS and Linux.

## Architectural Differences

| Aspect | ActionUI | tkinter |
|--------|----------|---------|
| UI definition | Declarative JSON | Imperative Python code |
| Rendering | Native SwiftUI views (macOS), GTK 4 / libadwaita widgets (Linux) | Tk widgets (non-native look) |
| State model | Set/get values by view ID | Variable tracing (StringVar, IntVar) |
| Event model | Action callbacks by ID | Widget event binding |
| Layout | SwiftUI stacks, grids, modifiers (the same layout rules on Linux) | pack/grid/place geometry managers |
| App structure | JSON defines UI, Python handles logic | Python defines both UI and logic |

## Where ActionUI Excels

### Native Experience
ActionUI renders real SwiftUI views on macOS and real GTK 4 / libadwaita widgets on Linux. Buttons, pickers, toggles, tables — everything looks and behaves like a native macOS app, or a native GNOME app, from the same JSON. tkinter uses Tk widgets that look out of place on both despite theming efforts (ttk).

### Simplicity
A form with text fields, pickers, and buttons is a JSON file. No widget instantiation, no layout manager calls, no variable binding boilerplate. The Python side only handles actions and state — it never constructs UI.

### AI-Friendly
JSON is a format that LLMs generate reliably. Asking an AI to produce a tkinter UI means generating imperative Python code with correct widget hierarchies, geometry management, and callback wiring. ActionUI's JSON schema is regular and predictable.

### Multi-Window
ActionUI has built-in multi-window support with per-window state, window lifecycle callbacks, and menu bar integration. tkinter can do multi-window with Toplevel, but window management, menu bars, and state isolation require manual work.

### Platform Integration
ActionUI provides native file open/save panels, alert dialogs, application menu bar with CommandGroup/CommandMenu, keyboard shortcuts, and proper app lifecycle (will_terminate, should_terminate, etc.). On Linux the same calls give GTK's file dialogs, libadwaita's alert dialog, and the menu commands in each window's primary menu, as GNOME apps have them. tkinter's macOS integration is limited — file dialogs work but menu bars and app lifecycle are basic.

### Dynamic UI
LoadableView allows swapping UI sections at runtime by loading new JSON from files or network — without rebuilding the window. tkinter requires destroying and recreating widgets.

### 60+ Native Components
Table, NavigationSplitView, Map, Chart, VideoPlayer, Canvas, Gauge, DisclosureGroup, ColorPicker, DatePicker — these are SwiftUI components (with GTK counterparts on Linux) with no tkinter equivalent or with significantly inferior tkinter alternatives.

## Where tkinter Has More Features

### Dynamic Widget Construction
tkinter can create and destroy widgets programmatically at any time. ActionUI's UI structure is defined by JSON at window creation. However, LoadableView, property changes (isHidden, items, etc.), and set/get APIs cover most practical cases.

### Rich Text
tkinter's Text widget supports tags, marks, embedded widgets, and per-character styling. ActionUI's TextEditor is plain text; the RichText add-on displays styled Markdown (headings, code blocks, tables, links), selectable but not editable.

### Canvas Drawing (Imperative)
tkinter's Canvas allows imperative drawing — add/remove/move shapes interactively with hit testing and drag support. ActionUI has a Canvas view but it uses declarative drawing operations in JSON properties, which is a different (and arguably cleaner) model for static or data-driven graphics. For drawing that needs its own renderer, the HostSurface add-on gives the program a rectangle to draw into, with pointer and key input.

### Event Granularity
tkinter exposes mouse motion, key press/release, focus, enter/leave, and drag events per widget. ActionUI fires action callbacks — sufficient for app logic but not for building custom interactive controls.

## Features That Seem Missing But Aren't Needed

### Timers
tkinter has `after(ms, callback)` for scheduling. ActionUI doesn't expose a timer API, but Python threads handle periodic work fine, and UI updates are just `set_value()` calls. A timer synchronized to the UI run loop is rarely needed in applet-style apps.

### Clipboard
tkinter provides `clipboard_get()`/`clipboard_append()`. In practice, the system Edit menu handles user-driven copy/paste in text fields automatically. For scripting, macOS `pbcopy`/`pbpaste` (on Linux, `wl-copy`/`wl-paste` or `xclip`) cover programmatic clipboard needs. Clipboard operations should be user-initiated, not app-driven.

### Text Input Dialog
tkinter has `simpledialog.askstring()`. In practice, text input belongs in the UI itself (a TextField in the form), not in a modal dialog. ActionUI supports alert dialogs with custom buttons for confirmations.

### Window Positioning/Resizing
tkinter offers `geometry()`, `minsize()`, `maxsize()`. ActionUI sets window properties at creation via JSON. Programmatic window manipulation is rarely needed for applets — the window manager and user handle this.

## Summary

ActionUI is not a tkinter replacement for all use cases. It targets a specific and common pattern: **macOS and Linux applets and tools where the UI is a form/dashboard that displays data and collects user input**. For this pattern, ActionUI is simpler, produces better-looking results, and integrates deeply with macOS and GNOME.

tkinter remains appropriate when Windows must be covered, for highly dynamic widget construction, or for interactive canvas applications (drawing tools, diagram editors). But on macOS and Linux, tkinter's non-native appearance and limited platform integration make ActionUI the better choice for most applet-style applications.
