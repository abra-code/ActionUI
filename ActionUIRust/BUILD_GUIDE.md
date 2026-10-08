# ActionUI for Rust - Build Guide

## How the parts fit

```
Your Rust program
    |  safe Rust API
actionui crate            App, Window, handlers, panels
    |  unsafe extern "C" calls
actionui-sys crate        declarations and link setup, no logic
    |  C functions, statically linked
ActionUICAdapter + ActionUIAppKitApplication + ActionUIMenuBar + ActionUIRemote + ActionUI
    |  Swift
macOS system frameworks   Foundation, AppKit, SwiftUI (dynamic, part of macOS)
```

The five ActionUI frameworks are static libraries. Their code is copied into your executable when it is linked, so the result is one file that needs nothing from ActionUI installed on the Mac that runs it. It depends only on system frameworks and on the Swift runtime in `/usr/lib/swift`, both part of macOS.

`ActionUIAppKitApplication` is the application layer shared with the Python and Node.js modules. It creates the windows and the menu bar and runs the event loop. Rust code never creates a window itself.

## Requirements

- macOS 14.6 or later.
- Xcode, to build the ActionUI frameworks. The Command Line Tools alone are not enough.
- Rust 1.85 or later (the crates use the 2024 edition).

## Build

```sh
cd ActionUIRust
./build_frameworks.sh
cargo build
cargo run --example temperature_converter
cargo run --example folder_contents
```

### Step 1 - the frameworks

`build_frameworks.sh` runs `xcodebuild` on the `ActionUIAppKitApplication` scheme: Release, for both Apple silicon and Intel. That one scheme also builds the four frameworks it depends on. The output goes to `ActionUIRust/frameworks/Release`; pass a directory to the script to put it in that directory's `Release` folder instead. The full `xcodebuild` output is kept in `xcodebuild.log` in the output directory.

Run the script again after any change to ActionUI's Swift sources. Cargo notices that the libraries changed and links again.

### Step 2 - the crates

`actionui-sys/build.rs` tells the linker where the frameworks are and which system frameworks and Swift library directories they need. It looks in `ActionUIRust/frameworks/Release`. To link frameworks built somewhere else, set `ACTIONUI_FRAMEWORKS_DIR` to the directory that holds the `.framework` bundles:

```sh
ACTIONUI_FRAMEWORKS_DIR=/path/to/Release cargo build
```

## Using the crates in your own project

```toml
# Cargo.toml
[target.'cfg(target_os = "macos")'.dependencies]
actionui = { path = "/path/to/ActionUI/ActionUIRust/actionui" }
serde_json = "1"        # optional, for the json! macro
```

```toml
# .cargo/config.toml
[env]
MACOSX_DEPLOYMENT_TARGET = "14.6"
```

Without the deployment target the linker prints a warning for every ActionUI object file, because the frameworks are built for macOS 14.6 and Rust's default target is older.

If a release build fails on macOS 27 with "mis-aligned LINKEDIT string pool" while compiling `serde`, add this to your `Cargo.toml` (the workspace in `ActionUIRust` has it):

```toml
[profile.release.build-override]
strip = "none"
```

Cargo strips the build tools of a release build, such as serde's derive macro, and the loader of macOS 27 refuses a library stripped by the `strip` tool of Xcode 27. The setting leaves those tools unstripped. It does not change your program.

## Where the interface JSON lives

Three ways, each with its own `App` call:

| Where | Call | Notes |
|---|---|---|
| Compiled into the program | `present_window_from_json(include_str!("ui.json"), ...)` | One file to ship. A change needs a rebuild. |
| A file on disk | `present_window_from_file(path, ...)` | Can be edited without a rebuild. The program has to find the file. |
| A web server | `present_window_from_url("https://...", ...)` | Loaded after the window appears. |

`include_str!` resolves its path against the source file that contains it.

## Packaging as an application

`cargo build` produces a bare executable. It runs, but its name and icon come from `App::set_name` and `App::set_icon`, and the Finder shows it as a command-line tool. `make_app_bundle.sh` wraps it in an application bundle:

```sh
cargo build --release --example folder_contents
./make_app_bundle.sh target/release/examples/folder_contents "Folder Contents"
open "target/release/examples/Folder Contents.app"
```

```
./make_app_bundle.sh <executable> "<App Name>" [bundle-identifier] [icon.icns]
```

The script creates `<App Name>.app` beside the executable, writes an `Info.plist`, copies the icon if one is given, and signs the bundle for this Mac only (an ad-hoc signature). To give the application to other people, sign it with a Developer ID certificate and have Apple notarize it.

Two things change for a program that runs from a bundle:

- Do not call `App::set_name`. The bundle's `Info.plist` names the application, and `set_name` discards everything else that file declares. A program that runs both ways checks first:

  ```rust
  if !actionui::running_from_bundle() {
      app.set_name("Folder Contents")?;
  }
  ```

- Files the program reads at run time belong in `Contents/Resources`. Find them from `std::env::current_exe()`: the executable is in `Contents/MacOS`, so the resources are at `../Resources` from it. JSON compiled in with `include_str!` needs none of this.

The default build is for the Mac's own processor. For an application that runs on both Apple silicon and Intel, build each target and join them with `lipo` before bundling:

```sh
rustup target add aarch64-apple-darwin x86_64-apple-darwin
cargo build --release --target aarch64-apple-darwin
cargo build --release --target x86_64-apple-darwin
lipo -create -output my_app target/aarch64-apple-darwin/release/my_app target/x86_64-apple-darwin/release/my_app
```

## Size

A release build of the `folder_contents` example is about 4 MB for one processor type, most of it ActionUI. The linker leaves out the ActionUI and Rust code the program cannot reach.

## Project layout

```
ActionUIRust/
  build_frameworks.sh       builds the static frameworks
  make_app_bundle.sh        wraps an executable in an .app bundle
  Cargo.toml                the workspace
  .cargo/config.toml        the deployment target
  actionui-sys/
    build.rs                link setup
    src/lib.rs              the C declarations
    tests/declarations.rs   compares the declarations with the framework headers
    tests/link.rs           links and calls one function
  actionui/
    src/                    the safe API
    examples/               temperature_converter, folder_contents
    tests/window_lifecycle.rs   a real window, run on request
  frameworks/               build output, not in the repository
```

## How values cross the boundary

| Rust | C | Swift |
|---|---|---|
| `&str` | `const char*`, copied into a `CString` for the call | `String` |
| `i64`, `f64`, `bool` | `int64_t`, `double`, `bool` | `Int`, `Double`, `Bool` |
| anything `Serialize` | JSON text as `const char*` | decoded with `JSONSerialization` |
| `String` returned | `char*` owned by the caller, released with `actionUIFreeString` | `strdup` of a `String` |
| `Option<T>` returned | a `bool` result plus an out-parameter, or `NULL` | `nil` |

A string with a zero byte inside cannot become a C string. Such a call returns `Error::InteriorNul` and does nothing.

Handlers are Rust closures kept in a table on the main thread. The C API takes plain function pointers with no extra argument, so the crate registers one fixed function for each kind of event, and that function looks the closure up. A panic inside a closure is caught there and logged; it never crosses into Swift.

## Tests

```sh
cargo test
ACTIONUI_GUI_TESTS=1 cargo test -p actionui --test window_lifecycle
```

The first command needs no window. It includes `actionui-sys/tests/declarations.rs`, which compares the hand-written declarations with the headers of the frameworks being linked and fails when a function, enum or callback type was added, removed or changed on either side. Run it after rebuilding the frameworks.

The second opens a window for a few seconds and quits by itself. It needs a logged-in session with the display awake. Do not type while it runs: its text field has keyboard focus.

## Common problems

**`The ActionUI frameworks were not found in ...`** from the `actionui-sys` build script. Run `./build_frameworks.sh`, or point `ACTIONUI_FRAMEWORKS_DIR` at the directory with the `.framework` bundles.

**`ld: warning: object file ... was built for newer macOS version`**, many times. Set `MACOSX_DEPLOYMENT_TARGET = "14.6"` as shown above.

**`missing in src/lib.rs: actionUI...`** from the declarations test. A C function was added to ActionUI after the declarations were written. Add it to `actionui-sys/src/lib.rs`.

**`Undefined symbols ... _actionUI...`** at link time. The frameworks are older than the crates. Rebuild them.

**`mis-aligned LINKEDIT string pool`** in a release build. See "Using the crates in your own project".

**The program starts but no window appears.** `App::run` was not reached, or `App::new` failed because it was not called on the main thread. Check the result of each call before `run`.

**The window shows an error text in place of the interface.** The JSON could not be parsed. The reason is in ActionUI's log, which goes to standard output unless `actionui::log::set_logger` redirects it.

## See also

- [RUST_API_REFERENCE.md](RUST_API_REFERENCE.md) - every type and method
- [../Documentation/ActionUI-JSON-Guide.md](../Documentation/ActionUI-JSON-Guide.md) - the interface JSON
- [../Documentation/ActionUI-MenuBar-JSON-Guide.md](../Documentation/ActionUI-MenuBar-JSON-Guide.md) - the menu bar JSON
