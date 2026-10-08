# ActionUI for Rust

Native macOS user interfaces described in ActionUI JSON, with the program's logic in Rust.

Two crates:

- `actionui-sys` - the raw C declarations and the link setup. No logic.
- `actionui` - the safe API: `App`, `Window`, action and lifecycle handlers, element values.

The Rust program links ActionUI's application layer (`ActionUIAppKitApplication`), the same one the Python and Node.js modules use. That layer creates the windows and the menu bar and runs the event loop; the Rust code describes the interface in JSON and reacts to named actions.

Status: the core is in place (application, windows, actions, lifecycle and window events, typed and JSON element values, log). Table rows, properties, state, structural changes, modal dialogs, file panels and menu bar loading are declared in `actionui-sys` but not yet wrapped in `actionui`.

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
    let window = app.present_window_from_json(include_str!("Greeter.json"), "Greeter")?;

    app.on_action("greet", move |_action| {
        let name = window.get_string(NAME_FIELD).ok().flatten().unwrap_or_default();
        let _ = window.set_string(GREETING, &format!("Hello, {name}!"));
    });

    app.run()
}
```

## Rules to know

- **Main thread.** Every call is made on the main thread, which `App::run` hands to the event loop. A call from another thread returns `Error::NotMainThread`. A worker thread passes its result to the interface with `actionui::main_thread::dispatch(closure)`; a `Window` can be moved into that closure. Never make the main thread wait for a worker.
- **`App::run` does not return.** Quitting ends the process from inside the event loop. Do final work in `App::on_will_terminate`.
- **Handlers are `Fn`.** A handler can be entered again while it runs (one that shows a modal alert keeps the event loop going), so changing state goes in a `Cell` or `RefCell`.
- **Panics.** A panic in a handler is caught, written to standard error and to ActionUI's log, and the application keeps running.
- **Setters are queued.** A setter returns before the value is applied; an unknown element ID is reported in ActionUI's log, not as an error. Getters return `Ok(None)` when an element has no value.
- **JSON from a string.** ActionUI's application layer loads windows from URLs, so `present_window_from_json` writes the text to a file in the temporary directory and removes it at termination.

## Tests

```sh
cargo test                                                         # no window needed
ACTIONUI_GUI_TESTS=1 cargo test -p actionui --test window_lifecycle   # opens a window
```

`actionui-sys/tests/declarations.rs` compares the hand-written declarations with the headers of the frameworks being linked (functions with the generated headers, enums and callback types with the C headers), and fails when one was added, removed or changed on either side. Run it after rebuilding the frameworks.
