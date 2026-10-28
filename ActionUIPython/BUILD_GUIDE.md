# ActionUI Python Extension — Build Guide

## Architecture

```
Python (actionui.py)
    ↓  json / type dispatch
C Extension (_actionui.so)          ← self-contained; no runtime framework deps
    ↓  C function calls (statically linked)
ActionUI + ActionUICAdapter + ActionUIAppKitApplication   ← baked into the .so at link time
    ↓  Swift API calls
macOS system frameworks                   ← dynamic OS-level deps (Foundation, SwiftUI, AppKit)
```

ActionUI, ActionUICAdapter, and ActionUIAppKitApplication are **static frameworks**.
Their compiled code is embedded directly into `_actionui.so` at link time.  Users of
the extension do not need any ActionUI files installed on their machine at runtime.

---

## Layers

### Layer 1: C Adapters

#### `ActionUICAdapter.framework` — element value / state / action API

**ActionUIC.h** — the C types (enums, callback typedefs) and a plain C prototype for every
function, checked against the code by `Scripts/check-c-prototypes.sh`.

**ActionUIC.swift** — implements the `actionUI*` functions with `@c` (the two Apple-only ones,
which load a native view and measure its content, in `ActionUIC+Apple.swift`).

**Function declarations** are emitted by the Swift compiler into
`ActionUICAdapter-Swift.h` as well, for plain C as for Objective-C.

#### `ActionUIAppKitApplication.framework` — app lifecycle / window API

**ActionUIApp.h** — C callback typedefs (`ActionUIAppLifecycleHandler`,
`ActionUIAppShouldTerminateHandler`, `ActionUIAppWindowHandler`) and a plain C prototype for
every function.

**ActionUIApp.swift** — implements all `actionUIApp*` functions with `@c`:
lifecycle handler registration, `actionUIAppSetName`, `actionUIAppSetIcon`,
`actionUIAppRun` (blocks), `actionUIAppTerminate`,
`actionUIAppLoadAndPresentWindow`, `actionUIAppCloseWindow`,
`actionUIAppRunOpenPanel`, `actionUIAppRunSavePanel`.

**ActionUIAppMenuBar.swift** — programmatic replacement for `MainMenu.nib`.
Builds the default macOS menu bar (App, File, Edit, Window, Help) with standard
first-responder selectors.  Implements `actionUIAppLoadMenuBar` which applies
`CommandMenu` / `CommandGroup` JSON on top of the default menu bar, reusing the
same schema as ActionUI's SwiftUI commands.

Function declarations are emitted into `ActionUIAppKitApplication-Swift.h`.

### Layer 2: C Extension (`_actionui.so`)

**actionui_native.c** is plain C and wraps every C function with a `py_*`
counterpart.  It includes the frameworks' plain C headers:

```c
#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include <ActionUICAdapter/ActionUIC.h>
#include <ActionUIAppKitApplication/ActionUIApp.h>
// … plain C code follows …
```

The Swift-generated headers declare the same functions; the framework build checks that
the two declarations of each function agree.

### Layer 3: Python API (`actionui.py`)

Pythonic wrapper providing `Application`, `Window`, `Logger`, `ActionContext`.
`Application` accepts optional `name` and `icon` parameters.  If `icon` is
omitted, the default `actionui-app-icon.icns` shipped alongside the module is
used automatically.  Exposes `load_menu_bar()` for customising the menu bar
via CommandMenu/CommandGroup JSON.

---

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| macOS 14.6+ | arm64 or x86_64 |
| Xcode 26.4+ + command-line tools | `xcode-select --install`; Swift 6.3 or later |
| Python 3.8+ with dev headers | `python3-config` must work |
| Pre-built static frameworks | `ActionUI.framework` + `ActionUICAdapter.framework` + `ActionUIAppKitApplication.framework` (see below) |

---

## Quick start — build script

The included `build_and_install.sh` automates the entire process:

```bash
cd ActionUIPython
./build_and_install.sh
```

This will:
1. Remove stale `build/` and `actionui.egg-info/` directories
2. Build the `ActionUIAppKitApplication` scheme as Release universal (arm64 + x86_64)
   via xcodebuild, which also builds ActionUI and ActionUICAdapter as dependencies
3. Output frameworks to `ActionUIPython/frameworks/Release/`
4. Run `pip3 install --no-cache-dir --verbose .`

To use a custom output directory for frameworks:

```bash
./build_and_install.sh /path/to/output
```

---

## Manual build

### Step 1 — Obtain the static frameworks

#### Option A: Build from source (Xcode)

Open `ActionUI.xcodeproj` and build the three required targets:
**ActionUI**, **ActionUICAdapter**, and **ActionUIAppKitApplication**.

```bash
for scheme in ActionUI ActionUICAdapter ActionUIAppKitApplication; do
  xcodebuild -project ActionUI.xcodeproj \
             -scheme "$scheme" \
             -configuration Release \
             -destination "generic/platform=macOS" \
             BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
             ONLY_ACTIVE_ARCH=NO \
             SKIP_INSTALL=NO \
             MACH_O_TYPE=staticlib \
             build
done
```

Copy the resulting `.framework` bundles from `DerivedData/.../Products/Release/`
into `ActionUIPython/frameworks/`:

```
ActionUIPython/
└── frameworks/
    ├── ActionUI.framework
    ├── ActionUICAdapter.framework
    └── ActionUIAppKitApplication.framework
```

#### Option B: Download a pre-built release archive (future)

ActionUI releases will publish static framework archives as GitHub Actions
artifacts.  Once available, download and extract:

```bash
cd ActionUIPython
# Example (URL TBD when releases are published):
curl -L https://github.com/abra-code/ActionUI/releases/download/v1.0.0/ActionUI-static-frameworks.zip \
     -o frameworks.zip
unzip frameworks.zip -d frameworks/
```

After extraction the layout should match the one shown in Option A.

### Step 2 — Build the Python extension

```bash
cd ActionUIPython

# Standard install (recommended) — with frameworks/ in place:
pip3 install --no-cache-dir --verbose .

# Or with an explicit path:
ACTIONUI_FRAMEWORKS_DIR=/path/to/frameworks pip3 install --no-cache-dir --verbose .

# In-place dev build (produces _actionui.cpython-<ver>-darwin.so here):
python3 setup.py build_ext --inplace
```

Output: `_actionui.cpython-<ver>-darwin.so`

Verify it is self-contained (no ActionUI dylib references):

```bash
otool -L _actionui.cpython-*.so | grep -v '/usr\|/System\|Python'
# Should print nothing — only system and Python libs appear.
```

---

## Install

```bash
# Standard install:
pip3 install --no-cache-dir --verbose  .

# Editable / development install (rebuild .so on source changes):
pip3 install -e --no-cache-dir --verbose  .
```

---

## Building on Linux

The same `actionui_native.c` and `setup.py` build the extension on Linux, against the
ActionUI library package instead of the static frameworks. No Swift installation is needed.

Prerequisites: Python 3 with its development headers (`Python.h`) and setuptools, a C
compiler (gcc or clang), and at run time GTK 4, libadwaita and libsoup 3.

1. Make the library package on a Linux machine with Swift (see `ActionUIAdwaita/README.md`):

   ```bash
   swift build -c release --static-swift-stdlib --product ActionUI
   Scripts/make-linux-library-package.sh .build/release <output folder>
   ```

   and unpack `actionui-<version>-linux-<arch>.tar.gz` where the Python build can read it.

2. Build or install the extension, pointing `ACTIONUI_LIBRARY_DIR` at the unpacked folder
   (or put its `lib/` and `include/` folders in `./library/` beside `setup.py`):

   ```bash
   ACTIONUI_LIBRARY_DIR=/path/to/actionui-0.9.0-linux-aarch64 pip3 install .
   # or, for development:
   ACTIONUI_LIBRARY_DIR=/path/to/actionui-0.9.0-linux-aarch64 python3 setup.py build_ext --inplace
   ```

The build copies `libActionUI.so` beside `_actionui.*.so`, which finds it through its `$ORIGIN`
rpath, so the installed module carries its own copy of the library.

Differences from macOS:

- `_actionui.load_hosting_controller` and `_actionui.get_content_size_limits` do not exist:
  they hand out and measure a native view for embedding. `Window.from_file`, `Window.from_url`
  and `Window.content_size_limits()`, which call them, raise `AttributeError`. Present
  windows with `Application.load_and_present_window` instead.
- There is no remote server: `start_remote_server()` raises `RuntimeError`.
- Ctrl+C does not stop `app.run()`: Python handles the signal only when the interpreter runs,
  and the GTK main loop holds the main thread.

---

## Manual build (for debugging)

```bash
PYTHON_INC=$(python3-config --includes)
FW_DIR=./frameworks           # or wherever your frameworks live

clang -shared -fPIC \
  $PYTHON_INC \
  -F "$FW_DIR" \
  -framework ActionUI \
  -framework ActionUICAdapter \
  -framework ActionUIAppKitApplication \
  -framework Foundation \
  -framework SwiftUI \
  -framework AppKit \
  -framework AVKit \
  -framework Charts \
  -o _actionui.so \
  actionui_native.c
```

---

## Project structure

```
ActionUI/
├── ActionUI/                              Core SwiftUI component library
├── ActionUICAdapter/
│   ├── ActionUIC.swift                    @c element / value / state API
│   ├── dummy.c                            Forces C-linkage output
│   └── include/
│       ├── ActionUICAdapter.h             Umbrella header
│       └── ActionUIC.h                    C types and function prototypes
├── ActionUIAppKitApplication/
│   ├── ActionUIApp.swift                  @c app lifecycle / window / name API
│   ├── ActionUIAppMenuBar.swift           Default menu bar + CommandMenu/CommandGroup adapter
│   ├── dummy.c                            Forces C-linkage output
│   └── include/
│       ├── ActionUIAppKitApplication.h    Umbrella header
│       └── ActionUIApp.h                  C callback typedefs and function prototypes
└── ActionUIPython/                        ← this directory
    ├── actionui_native.c                  Python C extension
    ├── actionui.py                        Pythonic wrapper
    ├── setup.py                           Build script (extension definition)
    ├── pyproject.toml                     Modern build system declaration
    ├── build_and_install.sh               One-step build + install script
    ├── test_native.py                     API smoke test (no run loop)
    ├── test_app_api.py                    App lifecycle + menu bar API smoke test
    ├── test_app_lifecycle.py              Full lifecycle integration test
    ├── test_menu_bar.py                   Menu bar integration test
    ├── test_file_panels.py                File panel API smoke test
    ├── frameworks/                        Drop pre-built static frameworks here
    │   ├── ActionUI.framework
    │   ├── ActionUICAdapter.framework
    │   └── ActionUIAppKitApplication.framework
    ├── BUILD.md                           This file
    └── README_ADAPTER.md                  API reference
```

---

## Type conversion reference

### Python → C → Swift

| Python | C | Swift |
|--------|---|-------|
| `int` | `int64_t` | `Int` |
| `float` | `double` | `Double` |
| `bool` | `bool` (stdbool.h) | `Bool` / `CBool` |
| `str` | `const char*` | `String` |
| `list` / `dict` | JSON `const char*` | `[Any]` / `[String: Any]` |

### Swift → C → Python

| Swift | C | Python |
|-------|---|--------|
| `Int` | `int64_t` | `int` |
| `Double` | `double` | `float` |
| `Bool` / `CBool` | `bool` (stdbool.h) | `bool` |
| `String` | `char*` (malloc; free with actionUIFreeString) | `str` |
| `[Any]` / `[String: Any]` | JSON `char*` | `list` / `dict` |

---

## Memory management

### Strings

Every function that returns a `char*` heap-allocates it with `strdup(3)`.
The extension copies it into a Python `str` object with `PyUnicode_FromString`,
then immediately frees it with `actionUIFreeString` (which calls `free(3)`).

### GIL

All callbacks (logger, action handlers, app lifecycle, window close) are
invoked from Swift's `@MainActor` context while the Python main thread is
blocked inside `app.run()` with the GIL released (`Py_BEGIN_ALLOW_THREADS`).
`actionui_native.c` uses `PyGILState_Ensure` / `PyGILState_Release` around
every Python call made from a C bridge callback.

---

## Testing

```bash
# API smoke test — no window, no run loop required
python3 test_native.py

# App lifecycle + menu bar API smoke test — no run loop required
python3 test_app_api.py

# Full integration test — opens a real window, requires a graphical environment
python3 test_app_lifecycle.py

# Menu bar integration test — opens a window, loads custom menus,
# tests action dispatch; requires a graphical environment
python3 test_menu_bar.py

# File panel API smoke test — no run loop, no panel display
python3 test_file_panels.py
```

---

## Common issues

### `Error: could not locate all required static frameworks`

All three frameworks must be present.  Set `ACTIONUI_FRAMEWORKS_DIR` or
populate `./frameworks/` with `ActionUI.framework`, `ActionUICAdapter.framework`,
and `ActionUIAppKitApplication.framework`.

---

## Distribution

The extension `.so` produced by the build is self-contained.  Package it as a
wheel in the normal Python way:

```bash
# Build a platform wheel using pypa/build (recommended):
python3 -m build --wheel

# Or with an explicit plat-name:
python3 setup.py bdist_wheel --plat-name macosx_14_6_arm64

pip3 install dist/actionui-*.whl
```

No ActionUI frameworks need to be shipped with or installed alongside the wheel.
