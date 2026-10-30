# ActionUINodeJS — Build Guide

## Architecture

```
Node.js (index.js)
    ↓  JSON / type dispatch
N-API Addon (actionui_node.c → actionui.node)   ← self-contained; no runtime framework deps
    ↓  C function calls (statically linked)
ActionUI + ActionUICAdapter + ActionUIAppKitApplication   ← baked into .node at link time
    ↓  Swift API calls
macOS system frameworks                   ← dynamic OS-level deps (Foundation, SwiftUI, AppKit)
```

ActionUI, ActionUICAdapter, and ActionUIAppKitApplication are **static frameworks**.
Their compiled code is embedded directly into `actionui.node` at link time.  Users of
the addon do not need any ActionUI files installed at runtime.

---

## Layers

### Layer 1: C Adapters

Same as ActionUIPython — see that module's BUILD_GUIDE.md for framework details.

### Layer 2: N-API Addon (`actionui.node`)

**`src/actionui_node.c`** is plain C and wraps every C function with a `node_*` counterpart
using raw N-API (`node_api.h`). It includes the frameworks' plain C headers, `ActionUIC.h` and
`ActionUIApp.h`; the Swift-generated headers declare the same functions, and the framework
build checks that the two declarations of each function agree.

#### Why raw N-API instead of node-addon-api?

`node-addon-api` is a C++ header-only wrapper.  Since our source is plain C, using raw
N-API keeps the translation unit simple and avoids C++.
Raw N-API is ABI-stable across Node.js major versions, which is the primary N-API benefit.

#### Threading model

`appRun()` blocks the Node.js main thread inside `[NSApp run]`.  AppKit dispatches
callbacks on the `@MainActor` (main thread) — the same thread V8 ran on.  Calling
`napi_call_function` from inside an AppKit callback is therefore safe: we're on the
correct thread with a clean C stack.  No `napi_threadsafe_function` is needed.

JS callbacks are stored as `napi_ref` (strong GC roots) so V8 cannot collect them.

### Layer 3: JS API (`index.js`)

JavaScript wrapper providing `Application`, `Window`, `ActionContext`.

---

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| macOS 14.6+ | arm64 or x86_64 |
| Xcode 26.4+ + command-line tools | `xcode-select --install`; Swift 6.3 or later |
| Node.js 18+ | `node --version` |
| npm 9+ | bundled with Node.js |
| Pre-built static frameworks | built from the ActionUI Xcode project |

---

## Quick Start — build script

```bash
cd ActionUINodeJS
./build_and_install.sh
```

This will:
1. Remove stale `build/` directory
2. Build the `ActionUIAppKitApplication` scheme as Release universal (arm64 + x86_64)
   via xcodebuild, which also builds ActionUI and ActionUICAdapter as dependencies
3. Output frameworks to `ActionUINodeJS/frameworks/Release/`
4. Run `npm install` (triggers `node-gyp rebuild` with `ACTIONUI_FRAMEWORKS_DIR` set)

To use a custom output directory for frameworks:

```bash
./build_and_install.sh /path/to/output
```

---

## Manual Build

### Step 1 — Obtain the static frameworks

Build with xcodebuild (same as Python adapter):

```bash
xcodebuild \
    -project ../ActionUI.xcodeproj \
    -scheme ActionUIAppKitApplication \
    -destination 'platform=macOS' \
    -configuration Release \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    ONLY_ACTIVE_ARCH=NO \
    SYMROOT=./frameworks \
    build
```

The three frameworks will be in `./frameworks/Release/`.

### Step 2 — Build the addon

```bash
ACTIONUI_FRAMEWORKS_DIR=./frameworks/Release npm install
```

Output: `build/Release/actionui.node`

Verify it is self-contained:

```bash
otool -L build/Release/actionui.node | grep -v '/usr\|/System\|node\|libc'
# Should print nothing — only system and Node libs appear.
```

---

## Building on Linux

The same `src/actionui_node.c` and `binding.gyp` build the addon on Linux, against the ActionUI
library package instead of the static frameworks. No Swift installation is needed.

Prerequisites: Node.js 18+ with npm, a C compiler and make (node-gyp's usual tools), `pkg-config`
and the GLib development files (`libglib2.0-dev` on Debian and Ubuntu), and at run time GTK 4,
libadwaita and libsoup 3.

1. Make the library package on a Linux machine with Swift (see `ActionUIAdwaita/README.md`):

   ```bash
   Scripts/prepare-linux-symbols.sh
   swift build -c release --static-swift-stdlib --product ActionUI
   Scripts/make-linux-library-package.sh .build/release <output folder>
   ```

   and unpack `actionui-<version>-linux-<arch>.tar.gz` where the build can read it.

2. Build the addon, pointing `ACTIONUI_LIBRARY_DIR` at the unpacked folder (or put its contents,
   `lib/`, `include/` and the license files, in `./library/` beside `binding.gyp`):

   ```bash
   ACTIONUI_LIBRARY_DIR=/path/to/actionui-0.9.0-linux-aarch64 npm install
   ```

The build copies `libActionUI.so` into `build/Release/` beside `actionui.node`, which finds it
through its `$ORIGIN` rpath, with the library's licenses, `LICENSE.txt` and
`LICENSE-MaterialSymbols.txt` (the Material Symbols icons compiled into the library, Apache 2.0);
a copy of the addon for others to use should keep them.

While `appRun()` blocks in the GTK main loop, a GLib source keeps Node's event loop running: it
watches libuv's backend file descriptor and wakes for libuv's timers, as the CFRunLoop observer,
timer and I/O watcher thread do on macOS.

Differences from macOS:

- Load `actionui` on the main thread before any worker thread loads it (require it at the start of
  the main script). The libdispatch inside `libActionUI.so` takes the thread that loads the library
  for the main thread; loaded first by a worker, the addon refuses to load at all, on the worker and
  on the main thread after it, with an error saying so.
- `loadHostingController` does not exist: it hands out a native view for embedding.
  `Window.fromFile` and `Window.fromURL`, which call it, load nothing (the window they return has
  no view). Present windows with `app.loadAndPresentWindow` instead.
- `contentSizeLimits()` measures a window on screen, where GTK sizes the widgets, and returns null
  for one that is not; its minimum is GTK's, not SwiftUI's for a zero proposal.
- `startRemoteServer()` puts the socket in `$XDG_RUNTIME_DIR` by default (else `$TMPDIR`, else
  `/tmp`).

---

## Usage

```js
const actionui = require('./index.js');

const app = new actionui.Application({ name: 'MyApp' });

app.onDidFinishLaunching(() => {
    const win = app.loadAndPresentWindow('file:///path/to/ui.json', 'main-window');
    win.setString(1, 'Hello from Node.js!');
});

app.action('button.click', (ctx) => {
    console.log('Button clicked, viewId:', ctx.viewId);
    const text = ctx => win.getString(2);
    console.log('TextField value:', text);
});

app.run();  // blocks until app terminates
```

---

## Project Structure

```
ActionUINodeJS/
├── src/
│   └── actionui_node.c        # N-API addon source (C)
├── binding.gyp                # node-gyp build configuration
├── package.json               # npm package definition
├── index.js                   # high-level JS API
├── build_and_install.sh       # one-step build script
├── BUILD_GUIDE.md             # this file
└── frameworks/                # place pre-built static frameworks here
    ├── ActionUI.framework
    ├── ActionUICAdapter.framework
    └── ActionUIAppKitApplication.framework
```

---

## Type Conversion Reference

### JS → N-API → C → Swift

| JavaScript | C | Swift |
|------------|---|-------|
| `number` (integer) | `int64_t` | `Int` |
| `number` (float) | `double` | `Double` |
| `boolean` | `bool` | `Bool` |
| `string` | `const char*` | `String` |
| `object` / `array` | JSON `const char*` | `[Any]` / `[String: Any]` |

### Swift → C → N-API → JS

| Swift | C | JavaScript |
|-------|---|------------|
| `Int` | `int64_t` | `number` (BigInt for pointers) |
| `Double` | `double` | `number` |
| `Bool` | `bool` | `boolean` |
| `String` | `char*` (freed with `actionUIFreeString`) | `string` |
| `[Any]` / `[String: Any]` | JSON `char*` | parsed via `JSON.parse` |

---

## Memory Management

### Strings

Every C function that returns `char*` heap-allocates with `strdup(3)`.
The addon copies the value into a JS string via `napi_create_string_utf8`,
then immediately frees it with `actionUIFreeString` (calls `free(3)`).

### JS Callbacks

Callbacks are stored as `napi_ref` with a reference count of 1, preventing
V8 GC collection.  References are released in the addon state finalizer when
the addon unloads, or when `null`/`undefined` is passed to replace a callback.

---

## Common Issues

### `Error: could not find actionui.node`

Run `npm install` (or `./build_and_install.sh`) first.

### Missing frameworks

Set `ACTIONUI_FRAMEWORKS_DIR` to the directory containing all three `.framework` bundles:

```bash
ACTIONUI_FRAMEWORKS_DIR=/path/to/frameworks npm install
```

### Linker error: framework not found

Make sure `ACTIONUI_FRAMEWORKS_DIR` points to the directory that directly contains
`ActionUI.framework`, `ActionUICAdapter.framework`, and
`ActionUIAppKitApplication.framework` (not a parent directory).
