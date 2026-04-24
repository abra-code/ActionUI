# ActionUI Python Extension — API Reference

## Adapters

Two static frameworks expose ActionUI to non-Swift callers via C-linkage
(`@_cdecl`) functions.

**ActionUICAdapter** — element value, state, action handler, and UI-loading
API.  `ActionUIC.h` defines types only (enums, callback typedefs); function
declarations are auto-generated into `ActionUICAdapter-Swift.h`.

**ActionUIAppKitApplication** — NSApplication lifecycle, window management, and
menu bar construction.  `ActionUIApp.h` defines the three callback typedefs;
function declarations are auto-generated into `ActionUIAppKitApplication-Swift.h`.

Both headers are guarded with `#if defined(__OBJC__)`, so callers must compile
as Objective-C (`.m`).  See `BUILD.md §Why .m instead of .c` for the rationale.

For build instructions see **BUILD.md**.

---

## C API — ActionUICAdapter

### Version

```c
char* actionUIGetVersion(void);
// Returns heap string "1.0.0".  Free with actionUIFreeString().
```

### Logging

```c
void actionUISetLogger(ActionUILoggerCallback callback);
void actionUILog(const char* message, ActionUILogLevel level);
```

### String memory management

```c
void actionUIFreeString(char* str);
// Free a heap string returned by any actionUI getter. Backed by free(3).
```

### Error handling

```c
char* actionUIGetLastError(void);   // NULL if no error; free with actionUIFreeString
void  actionUIClearError(void);
```

### Action handlers

```c
bool actionUIRegisterActionHandler(const char* actionID,
                                   ActionUIActionHandler handler);
bool actionUIUnregisterActionHandler(const char* actionID);
void actionUISetDefaultActionHandler(ActionUIActionHandler handler);
void actionUIRemoveDefaultActionHandler(void);
```

### Element value — JSON

```c
bool  actionUISetElementValueJSON(const char* windowUUID, int64_t viewID,  int64_t viewPartID
                                  const char* valueJSON);
char* actionUIGetElementValueJSON(const char* windowUUID, int64_t viewID,
                                  int64_t viewPartID);
```

### Element value — string

```c
bool  actionUISetElementValueString(const char* windowUUID, int64_t viewID,
                                    const char* valueString, int64_t viewPartID);
char* actionUIGetElementValueString(const char* windowUUID, int64_t viewID,
                                    int64_t viewPartID);
```

### Element value — type-specific

```c
bool actionUISetIntValue   (const char* windowUUID, int64_t viewID, int64_t value, int64_t viewPartID);
bool actionUISetDoubleValue(const char* windowUUID, int64_t viewID, double  value, int64_t viewPartID);
bool actionUISetBoolValue  (const char* windowUUID, int64_t viewID, bool    value, int64_t viewPartID);
bool actionUISetStringValue(const char* windowUUID, int64_t viewID, const char* value, int64_t viewPartID);

bool  actionUIGetIntValue   (const char* windowUUID, int64_t viewID, int64_t viewPartID, int64_t* out);
bool  actionUIGetDoubleValue(const char* windowUUID, int64_t viewID, int64_t viewPartID, double*  out);
bool  actionUIGetBoolValue  (const char* windowUUID, int64_t viewID, int64_t viewPartID, bool*    out);
char* actionUIGetStringValue(const char* windowUUID, int64_t viewID, int64_t viewPartID);
```

### Element column count

```c
int64_t actionUIGetElementColumnCount(const char* windowUUID, int64_t viewID);
```

### Element rows

```c
char* actionUIGetElementRowsJSON   (const char* windowUUID, int64_t viewID);
void  actionUIClearElementRows     (const char* windowUUID, int64_t viewID);
bool  actionUISetElementRowsJSON   (const char* windowUUID, int64_t viewID, const char* rowsJSON);
bool  actionUIAppendElementRowsJSON(const char* windowUUID, int64_t viewID, const char* rowsJSON);
// JSON format: [["cell1","cell2"],["cell3","cell4"],...]
```

### Element properties

```c
char* actionUIGetElementPropertyJSON(const char* windowUUID, int64_t viewID,
                                     const char* propertyName);
bool  actionUISetElementPropertyJSON(const char* windowUUID, int64_t viewID,
                                     const char* propertyName, const char* valueJSON);
```

### Element state

```c
char* actionUIGetElementStateJSON     (const char* windowUUID, int64_t viewID, const char* key);
char* actionUIGetElementStateString   (const char* windowUUID, int64_t viewID, const char* key);
bool  actionUISetElementStateJSON     (const char* windowUUID, int64_t viewID, const char* key, const char* valueJSON);
bool  actionUISetElementStateFromString(const char* windowUUID, int64_t viewID, const char* key, const char* value);
```

### Element info

```c
char* actionUIGetElementInfoJSON(const char* windowUUID);
// JSON format: {"2":"TextField","3":"Button",...}  (positive view IDs only)
```

### UI loading

```c
void* actionUILoadHostingControllerFromURL(const char* urlString,
                                           const char* windowUUID,
                                           bool        isContentView);
// Accepts file:// (local) and http(s):// (remote) URLs.
// Returns retained NSHostingController on macOS.  Caller owns the object.
```

---

## C API — ActionUIAppKitApplication

### Callback types (`ActionUIApp.h`)

```c
// No-argument void callback for simple lifecycle events.
typedef void (*ActionUIAppLifecycleHandler)(void);

// Return true to allow termination, false to cancel.
typedef bool (*ActionUIAppShouldTerminateHandler)(void);

// Fired when a tracked window is about to close.
// windowUUID — the UUID passed to actionUIAppLoadAndPresentWindow.
typedef void (*ActionUIAppWindowHandler)(const char* windowUUID);
```

### Lifecycle handler registration

```c
void actionUIAppSetWillFinishLaunchingHandler(ActionUIAppLifecycleHandler handler);
void actionUIAppSetDidFinishLaunchingHandler (ActionUIAppLifecycleHandler handler);
void actionUIAppSetWillBecomeActiveHandler   (ActionUIAppLifecycleHandler handler);
void actionUIAppSetDidBecomeActiveHandler    (ActionUIAppLifecycleHandler handler);
void actionUIAppSetWillResignActiveHandler   (ActionUIAppLifecycleHandler handler);
void actionUIAppSetDidResignActiveHandler    (ActionUIAppLifecycleHandler handler);
void actionUIAppSetWillTerminateHandler      (ActionUIAppLifecycleHandler handler);
void actionUIAppSetShouldTerminateHandler    (ActionUIAppShouldTerminateHandler handler);
void actionUIAppSetWindowWillCloseHandler    (ActionUIAppWindowHandler handler);
void actionUIAppSetWindowWillPresentHandler  (ActionUIAppWindowHandler handler);
// windowUUID — same UUID passed to actionUIAppLoadAndPresentWindow.
// Fires synchronously before makeKeyAndOrderFront; values set here appear
// before the first frame renders.  Pass NULL to deregister.
// Pass NULL to any setter to deregister.
```

### App name

```c
void actionUIAppSetName(const char* name);
// Set the application name shown in the menu bar (About, Hide, Quit).
// Also patches Bundle.main CFBundleName so macOS displays the correct
// bold title in the app menu (works around Python.app bundle identity).
// Must be called before actionUIAppRun().
```

### App icon

```c
void actionUIAppSetIcon(const char* path);
// Set the application icon (Dock + About panel).
// path — filesystem path to an image file (PNG, ICNS, TIFF, etc.).
// Loads the image via NSImage(contentsOfFile:) and sets
// NSApplication.shared.applicationIconImage.
// Must be called before actionUIAppRun() for the icon to appear on launch.
```

### App control

```c
void actionUIAppRun(void);
// Start the NSApplication run loop.  Blocks until the app terminates.
// Must be called from the main thread.
// Installs the default menu bar (App, File, Edit, Window, Help) automatically
// in applicationWillFinishLaunching if no menu bar has been loaded.
// Activates the app and brings windows to front in applicationDidFinishLaunching.

void actionUIAppTerminate(void);
// Request graceful termination (equivalent to Cmd-Q).
// Dispatches asynchronously to the main thread; safe to call from any thread.
```

### Window operations

```c
void actionUIAppLoadAndPresentWindow(const char* urlString,
                                     const char* windowUUID,
                                     const char* title);
// Load an ActionUI JSON view and present it in a new window.
// urlString  — file:// or http(s):// URL of the ActionUI JSON definition.
// windowUUID — caller-supplied UUID for all subsequent value/state operations.
// title      — window title; pass NULL to derive from the URL filename.

void actionUIAppCloseWindow(const char* windowUUID);
// Close the window identified by windowUUID.
// windowWillClose handler fires before the window is removed from the registry.
```

### Menu bar

```c
void actionUIAppLoadMenuBar(const char* jsonString);
// Install the default menu bar and optionally apply custom commands from JSON.
// Pass NULL to install only the default menu bar (App, File, Edit, Window, Help).
//
// jsonString is a JSON array of CommandMenu and/or CommandGroup elements:
//
//   CommandMenu — adds a new top-level menu (inserted before Window and Help):
//   {
//     "type": "CommandMenu",
//     "id": 100,
//     "properties": { "name": "Tools" },
//     "children": [
//       { "type": "Button", "id": 101, "properties": {
//           "title": "Run Script", "actionID": "tools.run",
//           "keyboardShortcut": { "key": "r", "modifiers": ["command"] }
//       }},
//       { "type": "Divider", "id": 102 }
//     ]
//   }
//
//   CommandGroup — inserts/replaces items in an existing default menu:
//   {
//     "type": "CommandGroup",
//     "id": 200,
//     "properties": {
//       "placement": "after",          // "before", "after", or "replacing"
//       "placementTarget": "newItem"   // see placement targets below
//     },
//     "children": [...]
//   }
//
// Supported placementTarget values:
//   App menu:    appInfo, appSettings, systemServices, appVisibility, appTermination
//   File menu:   newItem, saveItem, importExport, printItem
//   Edit menu:   undoRedo, pasteboard, textEditing, textFormatting
//   View menu:   toolbar, sidebar
//   Window menu: windowSize, windowList, singleWindowList, windowArrangement
//   Help menu:   help
//
// Button children support:
//   "title"            — menu item title (required)
//   "actionID"         — dispatched through ActionUIModel action handlers
//   "keyboardShortcut" — { "key": "t", "modifiers": ["command", "shift"] }
//
// Uses the same schema as ActionUI's SwiftUI CommandMenu/CommandGroup.
```

### File panels

```c
char* actionUIAppRunOpenPanel(const char* configJSON);
// Run an NSOpenPanel with optional JSON configuration.
// Returns a JSON array of selected file paths: ["/path/a.json","/path/b.json"]
// Returns NULL if the user cancelled.  Free result with actionUIFreeString().
//
// configJSON is a JSON object (all fields optional):
// {
//   "title": "Select Files",
//   "prompt": "Open",
//   "message": "Choose files to import",
//   "identifier": "com.myapp.openImages",
//   "allowedContentTypes": ["json", "txt", "public.image"],
//   "allowsMultipleSelection": true,
//   "canChooseDirectories": false,
//   "canChooseFiles": true,
//   "directoryURL": "/Users/foo/Documents",
//   "showsHiddenFiles": false,
//   "treatsFilePackagesAsDirectories": false,
//   "canCreateDirectories": true,
//   "allowsOtherFileTypes": false
// }
// Pass NULL for default configuration.

char* actionUIAppRunSavePanel(const char* configJSON);
// Run an NSSavePanel with optional JSON configuration.
// Returns the chosen file path as a string, or NULL if cancelled.
// Free result with actionUIFreeString().
//
// Accepts the same config keys as actionUIAppRunOpenPanel, plus:
//   "nameFieldStringValue": "untitled.json"  — default filename
// (allowsMultipleSelection, canChooseDirectories, canChooseFiles are ignored)
```

---

## Python API (`actionui.py`)

### Application

```python
import actionui

app = actionui.Application()                  # singleton — raises RuntimeError on second call
app = actionui.Application(name="My App")     # set the app name in the menu bar
app = actionui.Application(icon="icon.png")   # custom icon (Dock + About panel)
app = actionui.Application(name="My App", icon="icon.png")  # both
# If icon is omitted, the default ActionUI icon (shipped with the module) is used.
```

#### Lifecycle decorators

```python
@app.will_finish_launching
def _(): ...

@app.did_finish_launching
def _(): ...

@app.will_become_active
def _(): ...

@app.did_become_active
def _(): ...

@app.will_resign_active
def _(): ...

@app.did_resign_active
def _(): ...

@app.will_terminate
def _(): ...

@app.should_terminate
def _() -> bool:
    return True   # return False to cancel

@app.window_will_close
def _(window: Window): ...

@app.window_will_present
def _(window: Window): ...
# Fires synchronously before makeKeyAndOrderFront.
# Values/states set here are applied before the first frame renders.
```

#### App control

```python
app.run()          # start NSApplication run loop; blocks — never returns
app.terminate()    # request graceful termination (async, any thread)
```

#### Menu bar

```python
# Install default menu bar only (also happens automatically on app.run()):
app.load_menu_bar()

# Load custom commands from a JSON file:
app.load_menu_bar("menus.json")

# Load custom commands from an inline JSON string:
app.load_menu_bar('[{"type": "CommandMenu", "id": 100, ...}]')
```

The JSON uses the same `CommandMenu` / `CommandGroup` schema as SwiftUI
commands.  `CommandMenu` adds a new top-level menu; `CommandGroup` inserts
items into existing default menus using `placement` + `placementTarget`.

Button children with `actionID` are dispatched through the same action handler
system as UI button clicks:

```python
app.load_menu_bar('[{"type":"CommandMenu","id":1,"properties":{"name":"Tools"},'
                   '"children":[{"type":"Button","id":2,"properties":'
                   '{"title":"Run","actionID":"tools.run",'
                   '"keyboardShortcut":{"key":"r","modifiers":["command"]}}}]}]')

@app.action("tools.run")
def on_run(ctx):
    print("Run clicked!")
```

#### File panels

```python
# Open panel — returns list of paths or None if cancelled
paths = app.open_panel(
    title="Select Files",
    prompt="Open",
    message="Choose files to import",
    identifier="com.myapp.openImages",
    allowed_types=["json", "txt", "public.image"],
    allows_multiple=True,
    can_choose_files=True,         # default True
    can_choose_directories=False,  # default False
    directory="/Users/foo/Documents",
    shows_hidden_files=False,
    treats_file_packages_as_directories=False,
    can_create_directories=True,
    allows_other_file_types=False,
)

# Save panel — returns file path or None if cancelled
path = app.save_panel(
    title="Save Document",
    prompt="Save",
    message="Choose a location",
    identifier="com.myapp.saveDoc",
    allowed_types=["json"],
    filename="untitled.json",
    directory="/Users/foo/Documents",
    shows_hidden_files=False,
    treats_file_packages_as_directories=False,
    can_create_directories=True,
    allows_other_file_types=False,
)
```

All parameters are keyword-only and optional.  `allowed_types` accepts file
extensions (`"json"`) and UTI strings (`"public.image"`).  Both methods block
inside `runModal()` and return results synchronously — call them from action
handlers or lifecycle callbacks while the run loop is active.

#### Window management

```python
# Load JSON and present a window.  Returns a Window object.
window = app.load_and_present_window(
    url,              # file path, file://, http://, or https://
    window_uuid=None, # auto-generated UUID if omitted
    title=None,       # window title; derived from filename if omitted
)
print(window.uuid)

app.close_window(window.uuid)  # close by UUID
```

### Logger

```python
app.logger.set_callback(lambda msg, lvl: print(f"[{lvl.name}] {msg}"))
```

### Action handlers

```python
@app.action("button.click")
def on_click(ctx: actionui.ActionContext):
    print(f"view {ctx.view_id}  window {ctx.window_uuid}  value {ctx.value}")
```

### Window — element API

```python
# Obtain a Window from app.load_and_present_window(), or directly:
window = actionui.Window(uuid_string)

# Type-specific values
window.set_int(view_id, 42)
value = window.get_int(view_id)          # -> int

window.set_double(view_id, 3.14)
value = window.get_double(view_id)       # -> float

window.set_bool(view_id, True)
value = window.get_bool(view_id)         # -> bool

window.set_string(view_id, "Hello")
value = window.get_string(view_id)       # -> str

# Generic (auto-dispatch by Python type)
window.set_value(view_id, 0, {"key": "val"})
value = window.get_value(view_id)        # -> dict / list / str / int / float / bool

# Table rows
window.set_rows(view_id, [["Alice", "30"], ["Bob", "25"]])
rows = window.get_rows(view_id)          # -> [["Alice", "30"], ["Bob", "25"]]
window.append_rows(view_id, [["Carol", "28"]])
count = window.get_column_count(view_id) # -> int
window.clear_rows(view_id)

# Structural properties
window.set_property(view_id, "disabled", True)
val = window.get_property(view_id, "columns")

# Runtime state
window.set_state(view_id, "isLoading", True)
loading = window.get_state(view_id, "isLoading")       # -> bool
url_str = window.get_state_string(view_id, "url")      # -> str or None
window.set_state_from_string(view_id, "progress", "0.75")

# Element info
info = window.get_element_info()   # -> {2: "TextField", 3: "Button", ...}
```

### Module-level helpers

```python
print(actionui.get_version())
err = actionui.get_last_error()
actionui.clear_error()
```

---

## Naming Conventions

### C layer

| Element | Convention | Example |
|---------|-----------|---------|
| Functions (element API) | `actionUI` prefix + camelCase | `actionUISetIntValue` |
| Functions (app API) | `actionUIApp` prefix + camelCase | `actionUIAppLoadAndPresentWindow` |
| Types | `ActionUI` prefix + PascalCase | `ActionUILogLevel` |
| Callback typedefs | `ActionUI` prefix + PascalCase + `Handler`/`Callback` | `ActionUIAppLifecycleHandler` |
| Enum values | `ActionUI` prefix + PascalCase | `ActionUILogLevelDebug` |

### Python layer

| Element | Convention | Example |
|---------|-----------|---------|
| Public classes | PascalCase | `Window`, `Application` |
| Public methods / functions | snake_case | `get_state`, `load_and_present_window` |
| Native module functions (`_actionui`) | snake_case | `get_element_state_json` |
| Internal C bridge functions | `py_` prefix + snake_case | `py_get_element_state_json` |

---

## See Also

- **BUILD.md** — build instructions, framework setup, architecture, type conversions, distribution
- **test_native.py** — element API smoke test
- **test_app_api.py** — app lifecycle and menu bar API smoke test
- **test_app_lifecycle.py** — full lifecycle integration test (real NSApplication run loop)
- **test_menu_bar.py** — menu bar integration test (custom menus, action dispatch, app naming)
- **test_file_panels.py** — file panel API surface and edge case smoke test
- **ActionUIC.h** — C type definitions (element API)
- **ActionUIApp.h** — C callback typedef definitions (app lifecycle API)
