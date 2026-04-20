# ActionUINodeJS — Build Guide

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

ActionUI, ActionUICAdapter, and ActionUIAppKitApplication are **static frameworks**.
Their compiled code is embedded directly into `actionui.node` at link time.  Users of
the addon do not need any ActionUI files installed at runtime.

---

## Layers

### Layer 1: C Adapters

Same as ActionUIPython — see that module's BUILD_GUIDE.md for framework details.

### Layer 2: N-API Addon (`actionui.node`)

**`src/actionui_node.m`** is compiled as Objective-C and wraps every C function with
a `node_*` counterpart using raw N-API (`node_api.h`).

#### Why `.m` instead of `.cc`?

The Swift compiler wraps all `@_cdecl` declarations in the auto-generated bridging
headers with `#if defined(__OBJC__)`.  A `.cc` (C++) file cannot include
`Foundation.h` (pulled in transitively) and would not enter the declaration block.
Compiling as `.m` causes clang to define `__OBJC__` automatically.  The code itself
is entirely plain C — only the compilation mode is ObjC.

#### Why raw N-API instead of node-addon-api?

`node-addon-api` is a C++ header-only wrapper.  Since our source is `.m` (ObjC, not
ObjC++), using raw N-API keeps the translation unit simple and avoids `.mm` complexity.
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
| Xcode + command-line tools | `xcode-select --install` |
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
│   └── actionui_node.m        # N-API addon source (ObjC)
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

### `ActionUICAdapter-Swift.h` not found

Build the frameworks with `BUILD_LIBRARY_FOR_DISTRIBUTION=YES` — this causes Xcode
to generate the Swift interface headers required by `actionui_node.m`.

### Linker error: framework not found

Make sure `ACTIONUI_FRAMEWORKS_DIR` points to the directory that directly contains
`ActionUI.framework`, `ActionUICAdapter.framework`, and
`ActionUIAppKitApplication.framework` (not a parent directory).
