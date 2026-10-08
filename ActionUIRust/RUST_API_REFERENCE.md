# ActionUI for Rust - API Reference

The `actionui` crate: native macOS windows described in ActionUI JSON, driven from Rust.

For building and packaging see [BUILD_GUIDE.md](BUILD_GUIDE.md). The same text, method by method, is in the crate's doc comments (`cargo doc --open`).

## Contents

- [The model](#the-model)
- [Threads](#threads)
- [Errors](#errors)
- [`App`](#app)
- [`ActionContext`](#actioncontext)
- [`Window`](#window)
- [Dialogs inside a window](#dialogs-inside-a-window)
- [`actionui::panels`](#actionuipanels)
- [`actionui::main_thread`](#actionuimain_thread)
- [`actionui::log`](#actionuilog)
- [Other functions](#other-functions)
- [The raw layer: `actionui-sys`](#the-raw-layer-actionui-sys)

## The model

The interface is JSON: a tree of elements such as `VStack`, `TextField`, `Table` and `Button`. An element the program needs to talk to has a numeric `"id"`. An element that should tell the program something has an `"actionID"`, a name of your choice.

The Rust program does three things:

1. Creates the `App` and opens windows from JSON.
2. Registers a handler for each action name.
3. In the handlers, reads and writes elements through the `Window`, by their IDs.

```rust
use actionui::App;

const NAME_FIELD: i64 = 1;
const GREETING: i64 = 2;

fn main() -> actionui::Result<()> {
    let app = App::new()?;
    if !actionui::running_from_bundle() {
        app.set_name("Greeter")?;
    }
    let window = app.present_window_from_json(include_str!("Greeter.json"), Some("Greeter"))?;

    app.on_action("greet", move |_action| {
        let name = window.get_string(NAME_FIELD).ok().flatten().unwrap_or_default();
        let _ = window.set_string(GREETING, &format!("Hello, {name}!"));
    });

    app.run()
}
```

```json
{
  "type": "VStack",
  "properties": { "padding": 20, "spacing": 12 },
  "children": [
    { "type": "TextField", "id": 1, "properties": { "prompt": "Your name" } },
    { "type": "Button", "properties": { "title": "Greet", "actionID": "greet" } },
    { "type": "Text", "id": 2, "properties": { "text": "" } }
  ]
}
```

The JSON itself is described in [ActionUI-JSON-Guide.md](../Documentation/ActionUI-JSON-Guide.md), with one file for each element type in `Documentation/Schemas`.

## Threads

- `App` exists only on the main thread. It is a small `Copy` value that cannot be sent to another thread, so the compiler keeps handler registration, window creation, panels, the menu bar and the remote server on the main thread.
- `App::run` gives the main thread to the event loop. Every handler runs there.
- `Window` can be cloned and sent to any thread. On a worker thread a setter returns at once and is applied on the main thread a moment later; a getter waits for the main thread and returns the answer.
- Because a getter on a worker waits for the main thread, the main thread must never wait for that worker (no `join`, no blocking channel receive in a handler). The two would wait for each other forever.
- `main_thread::dispatch` runs a closure on the main thread, for work that needs the `App`.

## Errors

Most calls return `actionui::Result<T>`, which is `Result<T, actionui::Error>`.

| `Error` | Meaning |
|---|---|
| `NotMainThread` | `App::new` was called on a thread other than the main one. |
| `AppAlreadyCreated` | `App::new` was called twice. |
| `InteriorNul(what)` | A string argument contains a zero byte and cannot be passed to C. `what` names the argument. |
| `ActionUI(message)` | ActionUI refused the call. The message is ActionUI's own. |
| `Json(error)` | A value could not be written as JSON or read from it. |
| `Io(error)` | A file could not be read. |

Two behaviors to know:

- **Setters are queued.** A setter returns `Ok` before the value is applied. An unknown element ID shows up in ActionUI's log, not as an `Err`.
- **Getters return `Ok(None)` for "no value"**: an unknown element, or an element that has no value yet. They return `Err(Error::ActionUI)` when the value exists but has another type, for example `get_bool` on a text field.

## `App`

### Creating and running

| Method | Description |
|---|---|
| `App::new() -> Result<App>` | Creates the application. Call once, on the main thread, first. |
| `App::get() -> Option<App>` | The application, when it exists and this is the main thread. |
| `set_name(&self, name: &str) -> Result<()>` | Names the application in the menu bar and the Dock. For a bare executable only; see below. Call before `run`. |
| `set_icon(&self, path) -> Result<()>` | Sets the Dock and About-panel icon from an image file (icns, png and others). Call before `run`. |
| `run(self) -> !` | Runs the event loop. Does not return. |
| `terminate(&self)` | Asks the application to quit, as the Quit menu item does, and returns. The should-terminate handler can still refuse. |

`set_name` is for a program run as a bare executable, such as with `cargo run`. Do not call it in a program packaged as an `.app` bundle: the bundle's `Info.plist` names the application, and `set_name` discards everything else that file declares. `actionui::running_from_bundle()` tells the two apart.

`run` never returns, because quitting ends the process from inside the event loop. Code after `run`, and the destructors of values still alive in `main`, do not run. Do final work in the `on_will_terminate` handler.

### Windows

| Method | Description |
|---|---|
| `present_window_from_json(&self, json: &str, title: Option<&str>) -> Result<Window>` | Opens a window from JSON in a string, typically `include_str!`. Without a title the window is named after the application. |
| `present_window_from_file(&self, path, title: Option<&str>) -> Result<Window>` | Opens a window from a JSON file. Without a title the window is named after the file. |
| `present_window_from_url(&self, url: &str, title: Option<&str>) -> Result<Window>` | Opens a window from a `file://`, `http://` or `https://` URL. Content from the network is loaded after the window appears. |

Each call opens a new window and returns its `Window`. JSON that cannot be parsed is reported in ActionUI's log and shown as an error text in the window.

Windows can be opened before `run` or from any handler.

### Actions

| Method | Description |
|---|---|
| `on_action(&self, action_id, handler: impl Fn(&ActionContext) + 'static)` | Runs `handler` for every action with this name: a button, a menu item, a changed value. Replaces an earlier handler for the same name. |
| `remove_action(&self, action_id: &str)` | Removes the handler for one name. |
| `on_any_action(&self, handler: impl Fn(&ActionContext) + 'static)` | Runs `handler` for every action that has no handler of its own. |

Handlers are `Fn`, not `FnMut`: a handler can be entered again while it runs, because one that shows a blocking panel keeps the event loop going. State that changes goes in a `Cell` or `RefCell`, shared between handlers with `Rc`:

```rust
use std::cell::Cell;
use std::rc::Rc;

let count = Rc::new(Cell::new(0));
app.on_action("counter.add", {
    let count = count.clone();
    move |action| {
        count.set(count.get() + 1);
        let _ = action.window.set_int(COUNTER_LABEL, count.get());
    }
});
```

A panic in a handler is caught, written to standard error and to ActionUI's log, and the application keeps running.

### Application and window events

Each takes a closure and replaces the one set before.

| Method | When the handler runs |
|---|---|
| `on_will_finish_launching(impl Fn())` | The application is starting; the standard menu bar is in place. |
| `on_did_finish_launching(impl Fn())` | The application has started. |
| `on_will_become_active(impl Fn())`, `on_did_become_active(impl Fn())` | The application comes to the front. |
| `on_will_resign_active(impl Fn())`, `on_did_resign_active(impl Fn())` | Another application comes to the front. |
| `on_should_terminate(impl Fn() -> bool)` | The user asked to quit. Return false to keep running. |
| `on_will_terminate(impl Fn())` | The last chance to save anything: the process ends when the handler returns. |
| `on_window_will_present(impl Fn(&Window))` | A window's content is loaded and the window is about to be shown. Values set here are in place for the first frame. |
| `on_window_will_close(impl Fn(&Window))` | A window is closing. |

The application keeps running after its last window closes, as document applications do. To quit instead:

```rust
app.on_window_will_close(move |_window| app.terminate());
```

### Menu bar

| Method | Description |
|---|---|
| `load_default_menu_bar(&self)` | Installs the standard menu bar: application, File, Edit, Format, Window, Help. This also happens by itself when the application starts without one. |
| `load_menu_bar(&self, json: &str) -> Result<()>` | Installs the standard menu bar with the changes described in `json`. |
| `load_menu_bar_from_file(&self, path) -> Result<()>` | The same, with the JSON read from a file. |

The JSON is a list of `CommandMenu` elements (a new menu) and `CommandGroup` elements (items added to, replacing, or removed from a standard menu). A menu item's `actionID` arrives through `on_action` like any other action; its `ActionContext` names the frontmost window, and its `view_id` is a number ActionUI gave the menu item (10000 or more), not the ID of an element.

```rust
app.load_menu_bar(r#"[
  { "type": "CommandMenu", "properties": { "name": "Tools" },
    "children": [
      { "type": "Button", "properties": { "title": "Run Report", "actionID": "tools.report",
          "keyboardShortcut": { "key": "r", "modifiers": ["command", "shift"] } } }
    ] }
]"#)?;
```

`load_menu_bar` can be called before `run` or later, and more than once; each call adds to the menu bar. The full syntax is in [ActionUI-MenuBar-JSON-Guide.md](../Documentation/ActionUI-MenuBar-JSON-Guide.md).

### Remote server

Lets other processes of the same user read and drive this application's windows, for example a helper script or a test. The protocol is described in `ActionUIRemote/PROTOCOL.md`.

| Method | Description |
|---|---|
| `start_remote_server(&self, socket_path: Option<&Path>) -> Result<String>` | Starts the server and returns the path of its socket. Without a path it picks one in the temporary directory. |
| `stop_remote_server(&self)` | Stops the server and removes the socket. |
| `remote_server_endpoint(&self) -> Option<String>` | The socket path while the server runs. |
| `remote_server_token(&self) -> Option<String>` | The token a client must present, if any. |

Starting the server exports `ACTIONUI_REMOTE_ENDPOINT` and `ACTIONUI_REMOTE_TOKEN` in this process's environment, so a child process started afterwards finds the server by itself. The server stops when the application terminates.

## `ActionContext`

What a handler is told about the action.

| Field | Type | Description |
|---|---|---|
| `action_id` | `String` | The `actionID` from the JSON. |
| `window` | `Window` | The window the action came from. For a menu item, the frontmost window; its UUID is empty when there is none. |
| `view_id` | `i64` | The `id` of the element. For a menu item, a number ActionUI gave the item (10000 or more), which is not an element ID. |
| `view_part_id` | `i64` | The part of the element, for elements with parts; otherwise 0. |
| `context` | `Option<serde_json::Value>` | Extra data some elements send, such as the row index of a button in a table row. |

| Method | Description |
|---|---|
| `app(&self) -> App` | The application. Panics when called off the main thread. |
| `context_as<T: DeserializeOwned>(&self) -> Result<Option<T>>` | The extra data read into a type of your own. |

`ActionContext` is `Clone`, so a handler can keep it or send it to a worker.

## `Window`

A handle to one open window. Cloning is cheap; clones name the same window. A `Window` stays valid as a value after its window closes, and calls on it then find nothing.

| Method | Description |
|---|---|
| `uuid(&self) -> &str` | The identifier ActionUI knows the window by. |
| `close(&self) -> Result<()>` | Closes the window. The will-close handler runs first. |
| `content_size_limits(&self) -> Result<Option<ContentSizeLimits>>` | The smallest and largest size the content allows (`min_width`, `min_height`, `max_width`, `max_height`). `None` until the content has loaded. |

In every method below, `view_id` is the element's `"id"` from the JSON.

### Values

Each element type has one kind of value. A text field's is a string, a toggle's a bool, a slider's a number, a picker's the tag of the selected option, a table's the selected row.

| Method | Description |
|---|---|
| `set_string(view_id, value: &str) -> Result<()>` | |
| `set_int(view_id, value: i64) -> Result<()>` | |
| `set_double(view_id, value: f64) -> Result<()>` | |
| `set_bool(view_id, value: bool) -> Result<()>` | |
| `get_string(view_id) -> Result<Option<String>>` | |
| `get_int(view_id) -> Result<Option<i64>>` | A number with a fraction is cut toward zero. |
| `get_double(view_id) -> Result<Option<f64>>` | |
| `get_bool(view_id) -> Result<Option<bool>>` | |
| `set_value<T: Serialize>(view_id, value: &T) -> Result<()>` | Any value that serializes to JSON: a list, a `serde_json::Value`, a type of your own. |
| `get_value<T: DeserializeOwned>(view_id) -> Result<Option<T>>` | Reads the value into any type. Ask for `serde_json::Value` when the shape is not known. |
| `set_value_from_string(view_id, value: &str, content_type: Option<&str>) -> Result<()>` | Sets the value from text, converted by the element to its own type. `content_type` names the format for elements that accept more than one. |
| `get_value_as_string(view_id, content_type: Option<&str>) -> Result<Option<String>>` | The value as text, whatever its own type is. |

Setting a value from code fires no action.

Some elements have parts, addressed by a second number. Each method above has a `_part` form that takes `view_part_id` after `view_id`: `set_string_part`, `get_int_part`, `set_value_part`, `get_value_as_string_part`, and so on.

```rust
let amount = window.get_double(AMOUNT)?.unwrap_or(0.0);
window.set_string(TOTAL, &format!("{:.2}", amount * 1.2))?;

// A table's value is its selected row.
let selected: Option<Vec<String>> = window.get_value(TABLE)?;
```

### Rows of a Table or List

| Method | Description |
|---|---|
| `column_count(view_id) -> Result<i64>` | The number of columns; 0 for any other element. |
| `set_rows<T: Serialize>(view_id, rows: &T) -> Result<()>` | Replaces all rows. `rows` is a list of rows, each a list of cells: `&[["a", "b"], ["c", "d"]]`, a `Vec<Vec<String>>`. |
| `append_rows<T: Serialize>(view_id, rows: &T) -> Result<()>` | Adds rows after the existing ones. |
| `get_rows<T: DeserializeOwned>(view_id) -> Result<Option<T>>` | The rows, usually read as `Vec<Vec<String>>`. |
| `clear_rows(view_id) -> Result<()>` | Removes all rows. |
| `select_row(view_id, index: i64) -> Result<bool>` | Selects the row at a 0-based index and returns true. An index outside the rows clears the selection and returns false. |
| `select_row_with_content(view_id, text: &str, column: Option<i64>) -> Result<Option<i64>>` | Selects the first row with a cell equal to `text`, in one 0-based column or in all. Returns the row's index. |
| `clear_selection(view_id) -> Result<()>` | |

Selecting from code fires no action.

A row may hold more cells than the table has columns. The extra cells are not shown, which makes them a place for an identifier that comes back with the selected row.

### Properties

The settings written under `"properties"` in the JSON: `"title"`, `"disabled"`, `"hidden"`, `"text"` and the rest.

| Method | Description |
|---|---|
| `get_property<T: DeserializeOwned>(view_id, name: &str) -> Result<Option<T>>` | |
| `set_property<T: Serialize>(view_id, name: &str, value: &T) -> Result<()>` | The new value is validated the same way as a value in the JSON. |

```rust
window.set_property(SAVE_BUTTON, "disabled", &true)?;
window.set_property(SAVE_BUTTON, "title", "Saving...")?;
```

### State

Run-time state some elements keep beside their value, read and written by key. The keys are listed with each element type.

| Method | Description |
|---|---|
| `get_state<T: DeserializeOwned>(view_id, key: &str) -> Result<Option<T>>` | |
| `get_state_string(view_id, key: &str) -> Result<Option<String>>` | |
| `set_state<T: Serialize>(view_id, key: &str, value: &T) -> Result<()>` | |
| `set_state_from_string(view_id, key: &str, value: &str) -> Result<()>` | |

### Changing the structure

| Method | Description |
|---|---|
| `element_info(&self) -> Result<BTreeMap<i64, String>>` | The elements that have an ID of their own, as a map from the ID to the element type. |
| `insert_element<T: Serialize>(parent_id, element: &T, container: Option<&str>, position: InsertPosition) -> Result<i64>` | Adds an element to a container and returns its ID. |
| `insert_row<T: Serialize>(parent_id, cells: &T, container: Option<&str>, position: InsertPosition) -> Result<Vec<i64>>` | Adds a row of cells to a Grid and returns the cells' IDs. |
| `remove_element(view_id) -> Result<()>` | Removes an element and everything inside it. The window's root element cannot be removed. |

`element` is one element object, written the same way as in the interface JSON. `container` names the container property (`"children"`) when the parent has more than one; `None` picks the only one.

An inserted element without an `"id"` gets a negative one from ActionUI, which `insert_element` returns and `remove_element` accepts.

`InsertPosition`:

| Variant | Where |
|---|---|
| `Append` | After the last existing child. |
| `Prepend` | Before the first. |
| `At(index)` | At a 0-based index. |
| `Before(view_id)` | Before the sibling with this ID. Not for rows. |
| `After(view_id)` | After the sibling with this ID. Not for rows. |

```rust
use actionui::InsertPosition;
use serde_json::json;

let label = json!({ "type": "Text", "id": 50, "properties": { "text": "Added later" } });
window.insert_element(CONTAINER, &label, None, InsertPosition::Append)?;
```

## Dialogs inside a window

These are attached to one window and do not block: each call returns at once, and the user's answer arrives later as an action.

| `Window` method | Description |
|---|---|
| `present_modal(json: &str, style: ModalStyle, on_dismiss_action_id: Option<&str>) -> Result<()>` | Presents ActionUI JSON as a sheet over the window. The dismiss action fires when the sheet goes away, however that happens. |
| `dismiss_modal() -> Result<()>` | |
| `present_alert(title: &str, message: Option<&str>, buttons: &[DialogButton]) -> Result<()>` | An alert attached to the window. Without buttons it has "OK". |
| `present_confirmation_dialog(title: &str, message: Option<&str>, buttons: &[DialogButton]) -> Result<()>` | A list of choices attached to the window. |
| `dismiss_dialog() -> Result<()>` | Dismisses the alert or confirmation dialog with no button chosen. |
| `present_toast(message: &str, duration: Duration, action: Option<(&str, &str)>) -> Result<()>` | A short message over the content that goes away by itself. `action` is an optional button: its title and its action name. |
| `dismiss_toast() -> Result<()>` | |

`ModalStyle` is `Sheet` or `FullScreenCover`; on macOS both are shown as a sheet.

A `DialogButton` has a title, an optional role and an optional action:

```rust
use actionui::{ButtonRole, DialogButton};

window.present_alert(
    "Delete the selected item?",
    Some("This cannot be undone."),
    &[
        DialogButton::new("Delete").role(ButtonRole::Destructive).action("item.delete"),
        DialogButton::new("Cancel").role(ButtonRole::Cancel),
    ],
)?;

app.on_action("item.delete", |action| { /* the user confirmed */ });
```

`ButtonRole` is `Default`, `Cancel` or `Destructive` (shown in red). A button without an action only dismisses the dialog.

Elements inside a sheet are read and written through the same `Window`, by their IDs, so the IDs in a sheet's JSON must differ from those in the window's.

## `actionui::panels`

Panels that belong to the application, not to a window. Each `run` blocks until the user answers and returns the answer. They take the `App`, so they can only be used on the main thread.

The event loop keeps running underneath a blocking panel, so other handlers can run before `run` returns.

### `Alert`

```rust
use actionui::panels::{Alert, AlertStyle};

let answer = Alert::new("Discard the draft?")
    .message("This cannot be undone.")
    .style(AlertStyle::Warning)
    .buttons(["Discard", "Cancel"])
    .run(app)?;
if answer.as_deref() == Some("Discard") {
    // ...
}
```

| Method | Description |
|---|---|
| `Alert::new(title)` | |
| `message(text)` | The smaller text under the title. |
| `style(AlertStyle)` | `Informational`, `Warning` or `Critical`. |
| `buttons(titles)` | Button titles. The first is the default button. Without any, the alert has "OK". |
| `run(self, app: App) -> Result<Option<String>>` | Shows the alert and returns the title of the chosen button. |

### `OpenPanel` and `SavePanel`

```rust
use actionui::panels::{OpenPanel, SavePanel};

if let Some(paths) = OpenPanel::new().allowed_types(["json"]).allows_multiple_selection(true).run(app)? {
    for path in paths { /* ... */ }
}

if let Some(path) = SavePanel::new().file_name("Report.txt").run(app)? {
    std::fs::write(path, report)?;
}
```

Both have these options:

| Method | Description |
|---|---|
| `title(text)` | The panel's window title. |
| `prompt(text)` | The label of the confirming button. |
| `message(text)` | A line of text at the top of the panel. |
| `identifier(text)` | A name under which the system remembers this panel's last folder and size. |
| `allowed_types(types)` | File extensions (`"json"`) or uniform type identifiers (`"public.image"`). |
| `directory(path)` | The folder the panel opens in. |
| `shows_hidden_files(bool)` | |
| `treats_file_packages_as_directories(bool)` | Lets the user look inside packages such as `.app` bundles. |
| `can_create_directories(bool)` | |
| `allows_other_file_types(bool)` | |

`OpenPanel` adds `allows_multiple_selection(bool)`, `can_choose_directories(bool)` and `can_choose_files(bool)`. `OpenPanel::new()` lets the user choose one file. `run(self, app: App)` returns `Result<Option<Vec<PathBuf>>>`.

`SavePanel` adds `file_name(text)`, the name the panel proposes. `run(self, app: App)` returns `Result<Option<PathBuf>>`.

`None` means the user canceled.

## `actionui::main_thread`

| Function | Description |
|---|---|
| `dispatch(work: impl FnOnce() + Send + 'static)` | Runs `work` on the main thread, later, and returns at once. Callable from any thread. Closures run in the order they were dispatched, once the event loop is running. |
| `is_main_thread() -> bool` | |

A worker thread that only updates a window does not need `dispatch`; it uses its `Window` directly. `dispatch` is for work that needs the `App`:

```rust
use std::thread;
use actionui::{App, main_thread};
use actionui::panels::Alert;

let window = window.clone();
thread::spawn(move || {
    let result = long_computation();
    let _ = window.set_string(STATUS, "Done");          // any thread
    main_thread::dispatch(move || {                     // needs the App
        if let Some(app) = App::get() {
            let _ = Alert::new("Finished").message(result).run(app);
        }
    });
});
```

## `actionui::log`

ActionUI reports what it does, and what it refuses, in a log. By default the messages go to standard output.

| Function | Description |
|---|---|
| `set_logger(logger: impl Fn(&str, LogLevel) + Send + Sync + 'static)` | Sends every ActionUI log message to `logger` instead. The logger can be called on any thread. |
| `log(level: LogLevel, message: &str) -> Result<()>` | Writes a message to ActionUI's log, from any thread. |

`LogLevel` is `Error`, `Warning`, `Info`, `Debug` or `Verbose`, in that order.

```rust
use actionui::LogLevel;

actionui::log::set_logger(|message, level| {
    if level <= LogLevel::Warning {
        eprintln!("ActionUI: {message}");
    }
});
```

## Other functions

| Function | Description |
|---|---|
| `actionui::version() -> String` | The version of the ActionUI frameworks linked into the program. |
| `actionui::running_from_bundle() -> bool` | Whether the program was started from inside an `.app` bundle. |

## The raw layer: `actionui-sys`

`actionui-sys` declares every C function of ActionUI's C adapter and application layer, with the same names as in C (`actionUISetStringValue`, `actionUIAppRun`), and nothing else. `actionui` is built on it and covers all of it but one function: `actionUILoadHostingControllerFromURL`, for a program that creates its own AppKit windows and places an ActionUI view in one.

The C functions are documented in [PYTHON_EXTENSION_API_REFERENCE.md](../ActionUIPython/PYTHON_EXTENSION_API_REFERENCE.md), which lists the C surface the Python, Node.js and Rust bindings share.

Using the raw layer means following the C rules by hand: strings returned by ActionUI are released with `actionUIFreeString`, callbacks must not let a panic escape, and `actionUIGetLastError` reports the error of the calling thread's last call.

## See also

- [README.md](README.md) - overview and a first program
- [BUILD_GUIDE.md](BUILD_GUIDE.md) - building, packaging, problems
- [ActionUI-JSON-Guide.md](../Documentation/ActionUI-JSON-Guide.md) - the interface JSON
- [ActionUI-MenuBar-JSON-Guide.md](../Documentation/ActionUI-MenuBar-JSON-Guide.md) - the menu bar JSON
- `ActionUIRemote/PROTOCOL.md` - the remote server's protocol
