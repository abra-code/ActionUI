# ActionUI for Rust

Native macOS user interfaces described in ActionUI JSON, with the program's logic in Rust.

Two crates:

- `actionui-sys` - the raw C declarations and the link setup. No logic.
- `actionui` - the safe API: `App`, `Window`, action and lifecycle handlers, element values, rows, properties, dialogs, file panels, the menu bar.

The Rust program links ActionUI's application layer (`ActionUIAppKitApplication`), the same one the Python and Node.js modules use. That layer creates the windows and the menu bar and runs the event loop; the Rust code describes the interface in JSON and reacts to named actions.

Status: `actionui` covers everything the C adapter and the application layer offer, the same ground as the Python module. The one function left unwrapped is `actionUILoadHostingControllerFromURL`, for programs that create their own windows; it is declared in `actionui-sys`.

## Requirements

- macOS 14.6 or later, Xcode (to build the ActionUI frameworks), Rust 1.85 or later.

## Build

```sh
cd ActionUIRust
./build_frameworks.sh          # builds the static frameworks into ./frameworks/Release
cargo build
cargo run --example temperature_converter
```

`actionui-sys` looks for the frameworks in `ActionUIRust/frameworks/Release`. To use frameworks built elsewhere, set `ACTIONUI_FRAMEWORKS_DIR` to the directory that contains the `.framework` bundles.

The frameworks are static libraries, so the result is one self-contained executable. It depends only on system frameworks and the Swift runtime that ships with macOS.

## Using the crates from your own project

```toml
[target.'cfg(target_os = "macos")'.dependencies]
actionui = { path = "/path/to/ActionUI/ActionUIRust/actionui" }
```

Add this to your project's `.cargo/config.toml`, or the linker warns about every ActionUI object file being built for a newer macOS than the program:

```toml
[env]
MACOSX_DEPLOYMENT_TARGET = "14.6"
```

## A first program

```rust
use actionui::App;

const NAME_FIELD: i64 = 1;
const GREETING: i64 = 2;

fn main() -> actionui::Result<()> {
    let app = App::new()?;
    app.set_name("Greeter")?;          // only for a program run outside an .app bundle
    let window = app.present_window_from_json(include_str!("Greeter.json"), Some("Greeter"))?;

    app.on_action("greet", move |_action| {
        let name = window.get_string(NAME_FIELD).ok().flatten().unwrap_or_default();
        let _ = window.set_string(GREETING, &format!("Hello, {name}!"));
    });

    app.run()
}
```

## Rules to know

- **Threads.** `App` exists only on the main thread, which `App::run` hands to the event loop, and handlers run there. A `Window` can be moved to any thread and used from it: a setter returns at once and is applied later, a getter waits for the main thread. So never make the main thread wait for a worker that calls into a window; the two would wait for each other forever. `actionui::main_thread::dispatch(closure)` runs a closure on the main thread, for work that needs the `App`.
- **`App::run` does not return.** Quitting ends the process from inside the event loop. Do final work in `App::on_will_terminate`.
- **Handlers are `Fn`.** A handler can be entered again while it runs (one that shows a modal alert keeps the event loop going), so changing state goes in a `Cell` or `RefCell`.
- **Panics.** A panic in a handler is caught, written to standard error and to ActionUI's log, and the application keeps running.
- **Setters are queued.** A setter returns before the value is applied; an unknown element ID is reported in ActionUI's log, not as an error. Getters return `Ok(None)` when an element has no value.

## What is where

| To do this | Use |
|---|---|
| Open a window | `App::present_window_from_json`, `_from_file`, `_from_url` |
| React to a button, menu item or changed value | `App::on_action`, `App::on_any_action` |
| Read and write a control's value | `Window::get_string`, `set_string`, `get_int`, `get_double`, `get_bool`, `get_value`, `set_value` |
| Fill a Table or List, select a row | `Window::set_rows`, `append_rows`, `get_rows`, `select_row`, `select_row_with_content` |
| Change a title, disable or hide a control | `Window::set_property` |
| Add or remove controls while the window is open | `Window::insert_element`, `insert_row`, `remove_element` |
| Show a sheet, an alert, a list of choices or a toast in a window | `Window::present_modal`, `present_alert`, `present_confirmation_dialog`, `present_toast` |
| Ask with a standalone alert, or for files | `actionui::panels::Alert`, `OpenPanel`, `SavePanel` |
| Add menus and menu items | `App::load_menu_bar` |
| Let child processes drive the windows | `App::start_remote_server` |

## Tests

```sh
cargo test                                                         # no window needed
ACTIONUI_GUI_TESTS=1 cargo test -p actionui --test window_lifecycle   # opens a window
```

`actionui-sys/tests/declarations.rs` compares the hand-written declarations with the headers of the frameworks being linked (functions with the generated headers, enums and callback types with the C headers), and fails when one was added, removed or changed on either side. Run it after rebuilding the frameworks.
