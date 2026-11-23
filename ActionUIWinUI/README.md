# ActionUI on Windows (WinUI 3)

ActionUI renders its JSON documents on Windows as native **WinUI 3** interfaces (the Windows App SDK's UI framework), written in **Swift** and built from the same Swift package as the Apple frameworks and the Linux renderer. A document written for macOS opens on Windows unchanged, with the same element and property names, the same values and actions. Where Windows has a control of its own (a ListView, a NavigationView's pane toggle, the share sheet, WebView2), the renderer uses it, so a document looks like a Windows app rather than a copy of macOS.

The renderer has two parts:

- **The shim** (`Shim`), a small DLL in C++ with Microsoft's C++/WinRT projection, puts the parts of WinUI 3 that ActionUI uses behind plain C functions (`Shim/include/ActionUIWinUIShim.h`).
- **The renderer** (`Sources`), in Swift, calls the shim as the Linux renderer calls GTK: one retained WinUI object per element, SwiftUI's layout reproduced in ActionUI's own panels, and the portable core (`ActionUI/Core`) shared with every platform.

## Requirements

- **Windows 11**, x64 or Arm64.
- **Windows App SDK runtime 2.7** on the machine that runs the program (Microsoft's Windows App SDK runtime installer installs it; `Scripts/ci-windows.py --install-runtime` installs it for the current user from the NuGet package's MSIX files).
- To build:
  - a **Swift 6.4** toolchain for Windows from swift.org;
  - **Visual Studio or its Build Tools** with the C++ workload (MSVC and a Windows SDK), for the shim; the build script takes the newest installation `vswhere` finds;
  - **Python 3**, which runs the build script (it installs `fonttools` with pip for the symbol outlines).

  The build script downloads the NuGet packages it needs itself (the Windows App SDK 2.7.0 packages, C++/WinRT and WebView2), at the versions pinned in `WINUI_PACKAGES` in `Scripts/ci-windows.py`.

## Building and trying it

From the repository root, on Windows:

```bat
python Scripts\ci-windows.py winui --install-runtime --results ci-results
```

It builds the shim (`.build\winui-shim\<arch>\ActionUIWinUIShim.dll`), compiles the SF Symbols' Material Symbols outlines, and Fluent System Icons outlines for the names Material lacks, into it (`Scripts/prepare-windows-symbols.py`), runs the shim's C smoke test, builds the Swift package for Windows (`windowsPackage()` in `Package.swift`) in `.build\ci-windows-winui`, runs its smoke test, then renders every document in `Apps/Preview/Documents` with **ActionUIWinUIPreview** into `ci-results\preview-<name>.png`, printing where each element was placed. `--install-runtime` is needed once per user (and on CI machines, which do not have the runtime). `python Scripts\ci-windows.py shim` builds and tests the shim alone.

ActionUIWinUIPreview renders one document into a PNG of the window's content: `ActionUIWinUIPreview DOCUMENT.json OUT.png [WIDTH HEIGHT] [options]`. Its options operate elements as a user or an accessibility tool would (invoke, toggle, select, type, scroll, drag with the real mouse), change the model as a host does (rows, values, properties), wait for network loads, and check what must follow (actions fired, widths, states); `Apps/Preview/main.swift` lists them. The GitHub workflow `.github/workflows/windows.yml` runs the same script on GitHub's x64 and Arm64 Windows runners.

## What a program ships

An unpackaged Windows program that shows ActionUI documents carries, beside its `.exe`:

| File | Where it comes from | Needed |
|---|---|---|
| `ActionUIWinUIShim.dll` | built by `Scripts/ci-windows.py` | always |
| `Microsoft.WindowsAppRuntime.Bootstrap.dll` | NuGet `microsoft.windowsappsdk.foundation`, `runtimes/win-<arch>/native/` | always: it attaches the Windows App SDK runtime (`actionUIWinUIInitialize`) |
| `<program>.exe.manifest` | as `Apps/Smoke/ActionUIWinUISmoke.exe.manifest` | always: the Windows versions tested and per-monitor DPI awareness |
| `Microsoft.Web.WebView2.Core.dll` | NuGet `microsoft.web.webview2`, `runtimes/win-<arch>/native_uap/` | only when a document shows a WebView (below) |

And on the machine: the Windows App SDK runtime 2.7, and for WebView the WebView2 runtime.

## WebView and its DLL

A WebView is WinUI's **WebView2** control. It needs two things, which are different:

- **The WebView2 runtime**: the browser engine itself, shared by every app on the machine and kept up to date by Microsoft (the "Evergreen" runtime). Windows 11 ships it. Windows Server, and some older or locked-down machines, may not have it: Microsoft's WebView2 runtime installer (the "Evergreen Bootstrapper") installs it. A program does not ship it.
- **`Microsoft.Web.WebView2.Core.dll`**: the WebView2 SDK's Windows Runtime component, through which WinUI starts and talks to that runtime (the SDK's loader is linked into it). It belongs to the app, not to Windows: neither Windows nor the Windows App SDK runtime provides it, and each program carries its own copy beside its `.exe`, or beside `ActionUIWinUIShim.dll` (x64 about 0.8 MB, Arm64 about 1.1 MB): the shim loads it from its own folder before the first WebView, so a host whose `.exe` is elsewhere (python.exe, node.exe) finds it in the library package's folder. A WinUI app built in Visual Studio gets it copied into its output by the NuGet package's build rules without noticing; a program built another way copies it itself.

Without the DLL a WebView stays empty and logs "the browser failed: The specified module could not be found"; without the runtime it logs why the browser failed, or that it has not started after 5 seconds.

### Where to get it

The DLL comes from the **`microsoft.web.webview2`** NuGet package, at `runtimes/win-x64/native_uap/Microsoft.Web.WebView2.Core.dll` or `runtimes/win-arm64/native_uap/Microsoft.Web.WebView2.Core.dll` (a `.nupkg` is a ZIP archive):

- **With the Windows App SDK in Visual Studio**: referencing the Windows App SDK brings the matching WebView2 package with it, and the build copies the DLL. Nothing more to do.
- **Built with `Scripts/ci-windows.py`**: the script downloads the package into `.build\winui-shim\packages\microsoft.web.webview2\` and copies the DLL beside the smoke test and the preview. Copy it from there into your program's folder.
- **Downloaded by hand**: `https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/<version>/microsoft.web.webview2.<version>.nupkg`, at the version below.

### Which version

Use the WebView2 SDK version that the shim was built with. It is the one the Windows App SDK's WinUI package depends on: `Microsoft.WindowsAppSDK.WinUI` 2.7.0 depends on `Microsoft.Web.WebView2` **1.0.3719.77**, the version pinned in `WINUI_PACKAGES` in `Scripts/ci-windows.py`. For another Windows App SDK version, its WinUI package's `.nuspec` names the matching one:

```
https://api.nuget.org/v3-flatcontainer/microsoft.windowsappsdk.winui/<version>/microsoft.windowsappsdk.winui.nuspec
```

Look for `<dependency id="Microsoft.Web.WebView2" version="..." />` and use that version (a NuGet dependency names the lowest version that works, and the Windows App SDK is built and tested against it). Any newer WebView2 runtime works with it: the runtime keeps working with older SDKs.

### Its data, and its license

- The browser keeps its data (cookies, cache) in `%LOCALAPPDATA%\<program name>\WebView2`, unless the host sets `WEBVIEW2_USER_DATA_FOLDER` before the first WebView is made. By default WebView2 would put it beside the program, where an installed program cannot write.
- `Microsoft.Web.WebView2.Core.dll` is under the WebView2 SDK's license (the package's `LICENSE.txt`), a BSD-style license from Microsoft: it may be redistributed in binary form provided the copyright notice ("Copyright (C) Microsoft Corporation. All rights reserved."), the license's conditions and its disclaimer are reproduced in the documentation or other materials that ship with it (a third-party notices file is the usual place), and Microsoft's name is not used to endorse or promote the product. A program that ships the DLL, and a distribution of ActionUI that includes it, carries that notice. The WebView2 runtime is not redistributed this way: the program uses the one on the machine.

## Symbols and their licenses

SF Symbols (Apple's) may not be shipped, so `ActionUIWinUIShim.dll` draws other glyphs for their names, compiled into it as outlines by `Scripts/prepare-windows-symbols.py` (no font ships):

- Google's **Material Symbols** (Rounded), through ActionUI's SF Symbols -> Material map (`ActionUIAndroid/library/src/main/assets/symbols/sf_to_material.map`, shared with Android and Linux), at each row's fill and weight, but at most weight 300: Windows' own icons are thinner than SF Symbols, which the map's weights match. Apache License 2.0.
- Microsoft's **Fluent System Icons** (the Resizable family), for the SF names the Material map has no usable glyph for, through ActionUI's SF Symbols -> Fluent map (`Tools/fluent_symbols/sf_to_fluent.map`), drawn as Fluent draws them, Windows' own thinner look. MIT License (Copyright (c) 2020 Microsoft Corporation): the copyright notice and the license's permission notice go with copies of the outlines.

A program that ships the shim, and a distribution of ActionUI that includes it, carries both licenses' notices (a third-party notices file is the usual place). Each font is downloaded at a pinned commit, `ActionUIAndroid/library/material-symbols-font.commit` and `Tools/fluent_symbols/fluent-icons-font.commit`, the commit each map was made for.

## Layout of this folder

- `Shim/`: the C++/WinRT shim. `include/ActionUIWinUIShim.h` is its C interface, `src/` its implementation, `Tests/` its C smoke test.
- `CWinUI/`: the module map through which Swift sees the shim's header.
- `Sources/`: the Swift renderer: `Elements/` (one file per element type), `Layout/` (stacks, grids, the modifier box), `Runtime/` (render nodes, syncing, toolbars, the registry), `Interop/` (the shim's objects and events in Swift), `Styling/`.
- `Apps/Smoke/`: the Swift smoke test (`ActionUIWinUISmoke`) and the program manifest it and the preview use.
- `Apps/Preview/`: ActionUIWinUIPreview, and in `Documents/` the documents CI renders and checks.
