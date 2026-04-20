# ActionUI Node.js Addon — API Reference

## Architecture

```
Node.js (index.js)
    ↓  JSON / type dispatch
N-API Addon (actionui_node.m → actionui.node)   ← self-contained; no runtime framework deps
    ↓  C function calls (statically linked)
ActionUI + ActionUICAdapter + ActionUIAppKitApplication   ← baked into .node at link time
    ↓  Swift API calls
macOS system frameworks                   ← dynamic OS-level deps (Foundation, SwiftUI, AppKit)
```

The compiled code for ActionUI, ActionUICAdapter, and ActionUIAppKitApplication is
embedded directly into `actionui.node` at link time.  No ActionUI files are required
at runtime beyond the addon itself.

For build instructions see **BUILD_GUIDE.md**.

---

## Threading model

`app.run()` calls `[NSApp run]` and **blocks the Node.js main thread** for the lifetime
of the application.  AppKit dispatches all callbacks (lifecycle, window, action) on the
`@MainActor` — the same thread V8 was running on — so `napi_call_function` is safe
inside every callback without a `napi_threadsafe_function`.

Background work (closing windows, triggering termination) must be done from a worker
thread that loads the native addon separately via `require('node-gyp-build')(__dirname)`.
Because the addon is registered with `NAPI_MODULE` (non-context-aware), it is loaded
once per process; subsequent `require` calls in workers return the same exported
functions.  Functions that only call through to C (`appCloseWindow`, `appTerminate`,
etc.) are safe to call from any thread; they dispatch to the main queue internally.

---

## Installation

```js
const actionui = require('actionui');            // JS wrapper (recommended)
const native   = require('actionui')._native;   // raw N-API surface (advanced)
```

---

## JS API (`index.js`)

### `Application`

```js
// Singleton — throws Error on a second call in the same process.
const app = new actionui.Application();
const app = new actionui.Application({ name: 'My App' });
const app = new actionui.Application({ name: 'My App', icon: 'icon.icns' });

// If icon is omitted, the default ActionUI icon (shipped with the addon) is used.

// Retrieve the existing instance from anywhere:
const app = actionui.Application.instance();
```

#### Lifecycle callbacks

All lifecycle setters return `app` for chaining.

```js
app.onWillFinishLaunching(fn)   // fn()
app.onDidFinishLaunching(fn)    // fn()
app.onWillBecomeActive(fn)      // fn()
app.onDidBecomeActive(fn)       // fn()
app.onWillResignActive(fn)      // fn()
app.onDidResignActive(fn)       // fn()
app.onWillTerminate(fn)         // fn()
app.onShouldTerminate(fn)       // fn() → boolean; return false to cancel quit
app.onWindowWillClose(fn)       // fn(window: Window)
app.onWindowWillPresent(fn)     // fn(window: Window)
// windowWillPresent fires synchronously before makeKeyAndOrderFront.
// Values/states set here appear before the first frame renders.
// Pass null to any setter to deregister.
```

> **Important — register all callbacks before `app.run()`**
>
> All lifecycle handlers must be registered before calling `app.run()`.
> Registration order among the handlers does not matter — each setter is
> independent and simply stores the callback for the next run-loop cycle.
>
> ```js
> app.onWillFinishLaunching(() => { /* ... */ });
> app.onDidFinishLaunching(() => { /* open window, load menus, etc. */ });
> app.run();  // blocks; handlers fire from within [NSApp run]
> ```
>
> **Worker thread gotcha — `g_state` overwrite.**
> The native module uses a process-wide `g_state` pointer that is set once in
> `Init()`.  When a worker thread loads the same native addon, Node.js calls
> `Init()` again for that worker's V8 environment.  If `g_state` were
> reassigned unconditionally, the worker's blank state would overwrite the main
> thread's registered callbacks, silently preventing all lifecycle events from
> firing.  The addon guards against this with `if (g_state == NULL) g_state = state;`
> in `Init()` — do not regress that guard.

#### App control

```js
app.run()          // start NSApplication run loop; blocks — never returns
app.terminate()    // request graceful termination (async, safe from any thread)
```

#### Window management

```js
// Load JSON and present a window.  Returns a Window object.
const window = app.loadAndPresentWindow(url, uuid, title);
// url   — file path (auto-converted to file://), file://, http://, or https://
// uuid  — caller-supplied UUID string; auto-generated if null/undefined
// title — window title string; derived from the URL filename if null/undefined
console.log(window.uuid);

app.closeWindow(window.uuid);   // close by UUID
```

#### Menu bar

```js
app.loadMenuBar();              // install default menu bar only
app.loadMenuBar('menus.json');  // load from a JSON file
app.loadMenuBar('[...]');       // load from an inline JSON string
```

See the [Menu bar JSON schema](#menu-bar-json-schema) section below.

#### File panels

```js
// Open panel — returns array of paths or null if cancelled
const paths = app.openPanel({
    title:                          'Select Files',
    prompt:                         'Open',
    message:                        'Choose files to import',
    identifier:                     'com.myapp.openImages',
    allowedTypes:                   ['json', 'txt', 'public.image'],
    allowsMultiple:                 true,
    canChooseFiles:                 true,   // default true
    canChooseDirectories:           false,  // default false
    directory:                      '/Users/foo/Documents',
    showsHiddenFiles:               false,
    treatsFilePackagesAsDirectories: false,
    canCreateDirectories:           true,
    allowsOtherFileTypes:           false,
});

// Save panel — returns file path string or null if cancelled
const filePath = app.savePanel({
    title:                          'Save Document',
    prompt:                         'Save',
    message:                        'Choose a location',
    identifier:                     'com.myapp.saveDoc',
    allowedTypes:                   ['json'],
    filename:                       'untitled.json',
    directory:                      '/Users/foo/Documents',
    showsHiddenFiles:               false,
    treatsFilePackagesAsDirectories: false,
    canCreateDirectories:           true,
    allowsOtherFileTypes:           false,
});

// Alert — returns the button title clicked
const clicked = app.alert({
    title:   'Confirm',
    message: 'Are you sure?',
    style:   'informational', // 'informational' | 'warning' | 'critical'
    buttons: ['OK', 'Cancel'],
});
```

All parameters are optional.  `allowedTypes` accepts file extensions (`'json'`) and
UTI strings (`'public.image'`).  All three methods block inside `runModal()` and return
synchronously — call them from action handlers or lifecycle callbacks.

#### Action handlers

```js
// Register (chainable):
app.action('button.click', (ctx) => {
    console.log(ctx.actionId, ctx.windowUuid, ctx.viewId, ctx.context);
});

// Equivalent explicit form:
app.registerHandler('button.click', fn);
app.unregisterHandler('button.click');
app.setDefaultHandler(fn);   // called when no specific handler is registered
app.setDefaultHandler(null); // clear the default handler
```

### `Window`

```js
// Obtain a Window from app.loadAndPresentWindow(), or construct directly:
const win = new actionui.Window();           // auto-generated UUID
const win = new actionui.Window(uuidString); // explicit UUID

// Construct from a file path (uses loadHostingController, not the app window manager):
const win = actionui.Window.fromFile('/path/to/view.json', uuid, isContentView);
const win = actionui.Window.fromURL('file:///path/to/view.json', uuid, isContentView);

win.uuid      // string — the window's UUID
win.viewPtr   // pointer returned by loadHostingController, or null
```

#### Type-specific setters / getters

```js
win.setInt(viewId, 42)
win.setDouble(viewId, 3.14)
win.setBool(viewId, true)
win.setString(viewId, 'Hello')

const n = win.getInt(viewId)      // number or null
const d = win.getDouble(viewId)   // number or null
const b = win.getBool(viewId)     // boolean or null
const s = win.getString(viewId)   // string or null

// Optional partId (default 0):
win.setInt(viewId, 42, partId)
win.getInt(viewId, partId)
```

#### Generic value access

```js
// Auto-dispatches by JS type (boolean → bool, integer → int, float → double,
// string → string, object/array → JSON)
win.setValue(viewId, { key: 'val' })
const val = win.getValue(viewId)   // parsed from JSON; null if not set
```

#### Element rows

```js
win.setRows(viewId, [['Alice', '30'], ['Bob', '25']])
const rows = win.getRows(viewId)               // [['Alice','30'],['Bob','25']] or null
win.appendRows(viewId, [['Carol', '28']])
const count = win.getColumnCount(viewId)       // number or null
win.clearRows(viewId)
```

#### Element properties

```js
win.setProperty(viewId, 'disabled', true)
const val = win.getProperty(viewId, 'columns')   // parsed from JSON; null if absent
```

#### Element state

```js
win.setState(viewId, 'isLoading', true)
const loading = win.getState(viewId, 'isLoading')         // parsed from JSON; null if absent
const url     = win.getStateString(viewId, 'url')         // raw string or null
win.setStateFromString(viewId, 'progress', '0.75')
```

#### Element info

```js
const info = win.getElementInfo()
// { 2: 'TextField', 3: 'Button', ... }  — positive view IDs only
```

#### Modal dialogs

```js
win.presentModal(jsonString, format, style, onDismissActionId)
// format            — 'json' (default) | 'url'
// style             — actionui.ModalStyle.SHEET | actionui.ModalStyle.FULL_SCREEN_COVER
// onDismissActionId — actionID fired when the modal is dismissed (string or null)
win.dismissModal()

win.presentAlert(title, message, buttons)
// buttons — array of { title, role?, actionId? }
win.presentConfirmationDialog(title, message, buttons)
win.dismissDialog()
```

### `ActionContext`

Passed to every action handler.

```js
ctx.actionId    // string  — the registered actionID
ctx.windowUuid  // string  — UUID of the window that triggered the action
ctx.viewId      // BigInt  — view element ID
ctx.viewPartId  // BigInt  — sub-element part ID (0 for most elements)
ctx.context     // parsed JSON object, raw string, or null
```

### Constants

```js
actionui.LogLevel.ERROR    // 0
actionui.LogLevel.WARNING  // 1
actionui.LogLevel.INFO     // 2
actionui.LogLevel.DEBUG    // 3
actionui.LogLevel.VERBOSE  // 4

actionui.ModalStyle.SHEET              // 'sheet'
actionui.ModalStyle.FULL_SCREEN_COVER  // 'fullScreenCover'

actionui.ButtonRole.DEFAULT      // 'default'
actionui.ButtonRole.CANCEL       // 'cancel'
actionui.ButtonRole.DESTRUCTIVE  // 'destructive'
```

### Module-level helpers

```js
actionui.getVersion()    // '1.0.0'
actionui.getLastError()  // string or null
actionui.clearError()
```

---

## Raw N-API surface (`actionui._native`)

The `_native` object exposes every C function directly for advanced use.  Prefer the
JS wrapper classes above; use `_native` only when the wrapper doesn't expose what you
need.

```js
const native = actionui._native;

// Version / errors
native.getVersion()
native.getLastError()
native.clearError()

// Logging
native.setLogger((msg, level) => console.log(`[${level}] ${msg}`))
native.setLogger(null)   // clear
native.log(message, native.LOG_INFO)

// Action handlers
native.registerActionHandler(actionId, callback)
native.unregisterActionHandler(actionId)
native.setDefaultActionHandler(callback)

// Type-specific setters (windowUuid, viewId, value, partId)
native.setIntValue(uuid, viewId, value, partId)
native.setDoubleValue(uuid, viewId, value, partId)
native.setBoolValue(uuid, viewId, value, partId)
native.setStringValue(uuid, viewId, value, partId)

// Type-specific getters → value or null
native.getIntValue(uuid, viewId, partId)
native.getDoubleValue(uuid, viewId, partId)
native.getBoolValue(uuid, viewId, partId)
native.getStringValue(uuid, viewId, partId)

// Generic JSON access
native.setValueFromJSON(uuid, viewId, jsonString, partId)
native.getValueAsJSON(uuid, viewId, partId)          // JSON string or null
native.setValueFromString(uuid, viewId, string, partId)
native.getValueAsString(uuid, viewId, partId)        // string or null

// Element column count
native.getElementColumnCount(uuid, viewId)

// Element rows (JSON strings)
native.getElementRowsJSON(uuid, viewId)
native.clearElementRows(uuid, viewId)
native.setElementRowsJSON(uuid, viewId, rowsJSON)
native.appendElementRowsJSON(uuid, viewId, rowsJSON)

// Element properties (JSON strings)
native.getElementPropertyJSON(uuid, viewId, name)
native.setElementPropertyJSON(uuid, viewId, name, valueJSON)

// Element state (JSON strings)
native.getElementStateJSON(uuid, viewId, key)
native.getElementStateString(uuid, viewId, key)
native.setElementStateJSON(uuid, viewId, key, valueJSON)
native.setElementStateFromString(uuid, viewId, key, value)

// Element info
native.getElementInfoJSON(uuid)   // JSON string: '{"2":"TextField","3":"Button"}'

// Modal
native.presentModal(uuid, jsonString, format, style, onDismissActionId)
native.dismissModal(uuid)
native.presentAlert(uuid, title, message, buttonsJSON)
native.presentConfirmationDialog(uuid, title, message, buttonsJSON)
native.dismissDialog(uuid)

// UI loading (returns viewPtr or null)
native.loadHostingController(url, uuid, isContentView)

// Lifecycle setters (pass null to deregister)
native.appSetWillFinishLaunching(fn)
native.appSetDidFinishLaunching(fn)
native.appSetWillBecomeActive(fn)
native.appSetDidBecomeActive(fn)
native.appSetWillResignActive(fn)
native.appSetDidResignActive(fn)
native.appSetWillTerminate(fn)
native.appSetShouldTerminate(fn)   // fn() → boolean
native.appSetWindowWillClose(fn)   // fn(windowUuid: string)
native.appSetWindowWillPresent(fn) // fn(windowUuid: string)

// App control
native.appSetName(name)
native.appSetIcon(absolutePath)
native.appRun()
native.appTerminate()
native.appLoadAndPresentWindow(url, uuid, title)
native.appCloseWindow(uuid)
native.appLoadMenuBar(jsonString)  // jsonString or null/undefined

// File panels (return JSON string or null)
native.appRunOpenPanel(configJSON)
native.appRunSavePanel(configJSON)
native.appRunAlert(configJSON)

// Log level constants
native.LOG_ERROR    // 0
native.LOG_WARNING  // 1
native.LOG_INFO     // 2
native.LOG_DEBUG    // 3
native.LOG_VERBOSE  // 4
```

---

## Menu bar JSON schema

`app.loadMenuBar(json)` (or `native.appLoadMenuBar(jsonString)`) accepts a JSON array
of `CommandMenu` and `CommandGroup` elements.  The schema is identical to the C API
`actionUIAppLoadMenuBar` described in `PYTHON_EXTENSION_API_REFERENCE.md`.

**CommandMenu** — adds a new top-level menu (inserted before Window and Help):

```json
{
  "type": "CommandMenu",
  "id": 100,
  "properties": { "name": "Tools" },
  "children": [
    {
      "type": "Button",
      "id": 101,
      "properties": {
        "title": "Run Script",
        "actionID": "tools.run",
        "keyboardShortcut": { "key": "r", "modifiers": ["command"] }
      }
    },
    { "type": "Divider", "id": 102 }
  ]
}
```

**CommandGroup** — inserts items into an existing default menu:

```json
{
  "type": "CommandGroup",
  "id": 200,
  "properties": {
    "placement": "after",
    "placementTarget": "help"
  },
  "children": [
    { "type": "Button", "id": 201, "properties": { "title": "About My App", "actionID": "app.about" } }
  ]
}
```

Supported `placementTarget` values:

| Menu | Targets |
|------|---------|
| App | `appInfo`, `appSettings`, `systemServices`, `appVisibility`, `appTermination` |
| File | `newItem`, `saveItem`, `importExport`, `printItem` |
| Edit | `undoRedo`, `pasteboard`, `textEditing`, `textFormatting` |
| View | `toolbar`, `sidebar` |
| Window | `windowSize`, `windowList`, `singleWindowList`, `windowArrangement` |
| Help | `help` |

`placement` values: `"before"`, `"after"`, `"replacing"`.

Button actions are dispatched through the same handler system as UI element actions:

```js
app.loadMenuBar(JSON.stringify([{
    type: 'CommandMenu', id: 1,
    properties: { name: 'Tools' },
    children: [{ type: 'Button', id: 2, properties: {
        title: 'Run', actionID: 'tools.run',
        keyboardShortcut: { key: 'r', modifiers: ['command'] }
    }}]
}]));

app.action('tools.run', (ctx) => console.log('Run clicked!'));
```

---

## Exit handling

`NSApplication.terminate()` calls C `exit()` directly — `app.run()` never returns.
Register assertions and cleanup using `process.on('exit', fn)`, which fires via
Node.js's C-level `atexit` handler even during a native `exit()` call.  This is the
same mechanism as Python's `atexit` module.

```js
process.on('exit', () => {
    // report results, set process.exitCode = 1 on failure
});

app.run();
// never reached
```

---

## Background threads

The main thread is blocked inside `[NSApp run]`.  Use worker threads for any delayed
or background operations (window close sequences, safety timers, etc.).

```js
const { Worker, isMainThread, workerData } = require('worker_threads');

if (!isMainThread) {
    // Worker branch — runs when this file is loaded as a worker
    const native = require('node-gyp-build')(__dirname);

    function sleep(ms) {
        Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
    }

    sleep(workerData.delayMs);
    native.appCloseWindow(workerData.uuid);
    sleep(500);
    native.appTerminate();
    return;
}

// Main thread
const app = new actionui.Application({ name: 'My App' });
app.onDidFinishLaunching(() => {
    const win = app.loadAndPresentWindow('./view.json', null, 'My Window');

    new Worker(__filename, {
        workerData: { uuid: win.uuid, delayMs: 2000 }
    });
});

app.run();
```

`appCloseWindow` and `appTerminate` in the native layer dispatch to the main queue
internally, so calling them from a worker thread is safe.

---

## Naming conventions

### N-API (`_native`) layer

| Element | Convention | Example |
|---------|-----------|---------|
| Functions | camelCase, no prefix | `setIntValue`, `appRun` |
| App-control functions | `app` prefix + PascalCase | `appLoadAndPresentWindow` |
| Log level constants | `LOG_` prefix + UPPER_SNAKE | `LOG_INFO` |

### JS wrapper layer

| Element | Convention | Example |
|---------|-----------|---------|
| Classes | PascalCase | `Application`, `Window`, `ActionContext` |
| Methods | camelCase | `loadAndPresentWindow`, `getState` |
| Constants (objects) | PascalCase keys | `LogLevel.INFO`, `ModalStyle.SHEET` |

---

## See Also

- **BUILD_GUIDE.md** — build instructions, architecture, framework setup
- **PYTHON_EXTENSION_API_REFERENCE.md** (ActionUIPython) — C API reference and menu bar schema
- **test_native.js** — N-API surface reachability smoke test (no run loop)
- **test_app_api.js** — JS wrapper API surface and lifecycle registration smoke test
- **test_app_lifecycle.js** — full lifecycle integration test (real NSApplication run loop)
- **test_menu_bar.js** — menu bar integration test (custom menus, action dispatch)
