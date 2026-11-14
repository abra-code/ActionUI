# ActionUI on Linux (GTK 4 and libadwaita)

ActionUI renders its JSON documents on Linux as native GNOME interfaces: **GTK 4 and libadwaita widgets**, written in **Swift** and built from the same Swift package as the Apple frameworks. A document written for macOS opens on Linux unchanged, with the same element and property names, the same values and actions, and the same C interface for host programs.

For how the renderer works (retained widgets, SwiftUI's layout reproduced, what is shared with Apple) see the Linux section of [Architecture.md](../Documentation/Architecture.md#linux-architecture).

## Requirements

- **GNOME 48 or later:** GTK 4.18, libadwaita 1.7, GLib 2.84 and libsoup 3. Tested on **Debian 13** (GTK 4.18, libadwaita 1.7) and **Ubuntu 26.04** (GTK 4.22, libadwaita 1.9). Ubuntu 24.04's libadwaita 1.5 is too old.
- To build: a **Swift 6.3** or later toolchain from swift.org, and the development packages (Debian and Ubuntu names):

  ```sh
  sudo apt install libgtk-4-dev libadwaita-1-dev libsoup-3.0-dev pkg-config
  ```

- For a Linux virtual machine on a Mac: [`agent-vm/swift-gtk`](agent-vm/swift-gtk/recipe.json) is an [agent-vm](https://github.com/abra-code/agent-vm) image recipe that installs all of the above on Debian 13 or Ubuntu 26.04 (ARM). It installs swift.org's toolchain for the system it runs on into `/usr`, refusing a download not signed by the Swift 6.x release key; the `swift`, `platform`, `signed_by` and `sha256` parameters choose another release, build or key, or pin the download. Add a desktop recipe (`Recipes/linux-gnome`) to run the apps on the box's screen:

  ```sh
  agent-vm image create swift-gtk --linux ubuntu-26.04 --recipe ActionUIAdwaita/agent-vm/swift-gtk/recipe.json
  agent-vm image create swift-gtk-gnome --from swift-gtk --recipe <agent-vm>/Recipes/linux-gnome/recipe.json
  ```

- At run time, besides GTK, libadwaita and libsoup:
  - **glib-networking** for https URLs (installed with GNOME);
  - **WebKitGTK 6.0** (`libwebkitgtk-6.0-4`) for WebView only. It is loaded when a WebView is first shown, so it is a dependency of the app that shows web pages, not of ActionUI; without it a WebView shows a placeholder that names the package. Ubuntu's desktop installs it; Debian's GNOME desktop does not.
  - **libshumate** (`libshumate-1.0-1`, GNOME's map widget) for Map only, loaded when a Map is first made, so it too is a dependency of the app that shows maps; without it a Map shows a placeholder that names the package. GNOME Maps depends on it, so a desktop with GNOME Maps has it.
  - **GStreamer** for VideoPlayer: built into GTK 4.20 and later, a GTK module before that (`libgtk-4-media-gstreamer`, which Debian's GNOME desktop installs), plus the GStreamer plug-ins for the video's format;
  - **ICU** (any version the system has) for dates and numbers by locale, also loaded when first needed.

## Building and trying it

From the repository root, on Linux:

```sh
Scripts/prepare-linux-symbols.sh              # the symbol icons; again when the map or font changes
swift build                                   # ActionUI
swift run --package-path Apps/ActionUIViewer --only-use-versions-from-resolved-file --manifest-cache none \
    ActionUIViewer ActionUISwiftTestApp/Resources/Form.json
swift run --package-path ActionUIAdwaita/Apps ActionUIAdwaitaDemo --resources ActionUISwiftTestApp/Resources
```

SF Symbols are shown as Material Symbols icons, which `Scripts/prepare-linux-symbols.sh` generates from the Material Symbols font (downloaded on its first run) and compiles into ActionUI, as a GResource in a section of its own: `libActionUI.so` and every Swift program that links ActionUI statically carry it (`gresource list` shows it). Run the script before the first build, and again when `sf_to_material.map` or the font changes; `bash Tools/material_symbols/fetch-material-symbols-font.sh` moves to a newer font release. A build without the icons succeeds but warns at its top on every build, and its SF Symbols show the missing-icon picture. A Swift package that depends on ActionUI runs the script in its ActionUI checkout first (`.build/checkouts/ActionUI`, or the folder of a path dependency).

- **ActionUIViewer** (`Apps/ActionUIViewer`, one package for macOS and Linux) opens one document in a window: a path, a file URL or an http(s) URL. `--dark` uses the dark style; `--screenshot out.png` saves the window as an image once it has drawn and quits (drawn by the window itself, so no screen capture is needed); `--rows <id> <rows.json>` fills a List, Table or Chart for a screenshot. Its package's `Package.resolved` also lists packages only macOS uses: `--only-use-versions-from-resolved-file` keeps a Linux build from dropping them, and `--manifest-cache none` keeps the root package's file list current.
- **ActionUIAdwaitaDemo** is the Linux counterpart of ActionUISwiftTestApp: a launcher of all the test app's documents and the documents of the add-ons that work on Linux, with the test app's own action handlers. `--open <Name>` also opens one document at launch, `--screenshot` saves it.

A self-contained demo, which runs where Swift is not installed:

```sh
swift build -c release --static-swift-stdlib --package-path ActionUIAdwaita/Apps --product ActionUIAdwaitaDemo
Scripts/make-linux-demo-bundle.sh ActionUIAdwaita/Apps/.build/release /tmp     # makes /tmp/ActionUIDemo.app
/tmp/ActionUIDemo.app/ActionUIDemo
Scripts/linux-app-entry.py install /tmp/ActionUIDemo.app  # optional: the demo in the desktop's app list
```

`ActionUIDemo.app` is a plain folder: the program, stripped (about 17 MB), beside its documents and images, its `Info.plist` and its icon (both from `ActionUIAdwaita/DemoBundle`). The program finds its documents in the folder it runs from.

## Info.plist

An app describes itself in an `Info.plist`, the same file and keys as an Apple bundle's. It is at the app folder's top level (the flat layout: the program's folder, or for Python and Node.js the main script's, the resource folder), or in `Contents` when the app has the macOS layout (the program in `Contents/Linux`, its resources in `Contents/Resources`):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key>
	<string>org.example.MyApp</string>
	<key>CFBundleDisplayName</key>
	<string>My App</string>
	<key>CFBundleIconFile</key>
	<string>MyApp</string>
</dict>
</plist>
```

- `CFBundleIdentifier`: the reverse-DNS application ID. The desktop matches the app's windows to its desktop entry, `<CFBundleIdentifier>.desktop`, by it, so the dock shows the entry's name and icon; with no matching entry it shows the raw ID and a generic icon.
- `CFBundleDisplayName`, else `CFBundleName`: the application's name, in the About item and dialog of the windows' primary menu, and the title of a window that has none of its own (a document file's window takes the file's name).
- `CFBundleIconFile`: the windows' icon, a file name in the resources with its extension optional. GTK reads no `.icns`, so on Linux the name is looked for as `MyApp.svg`, then `MyApp.png` (or the file named, when it is an SVG or a PNG): one plist serves both systems, with `MyApp.icns` beside the SVG for macOS.

All keys are optional; an empty string counts as left out. A value the program sets in code (`actionUIAppSetApplicationID`, `actionUIAppSetName`, `actionUIAppSetIcon` and their Python, Node.js, Rust and Swift counterparts) wins over the file; with neither, the ID is made from the name (`com.abracode.actionui.<name>`). Other keys are left for the tools that install the app.

### In the desktop's app list

`Scripts/linux-app-entry.py` adds an app folder to the app list of the desktop (GNOME's Apps, KDE Plasma's launcher, Xfce's menu and others that follow the freedesktop.org standards), for the current user, from its `Info.plist`:

```sh
Scripts/linux-app-entry.py install /path/to/MyApp.app                                # runs MyApp.app/MyApp
Scripts/linux-app-entry.py install /path/to/MyApp --exec 'python3 MyApp.py %U'       # a Python or Node.js app
Scripts/linux-app-entry.py uninstall /path/to/MyApp.app                              # or: uninstall org.example.MyApp
```

It writes `~/.local/share/applications/<CFBundleIdentifier>.desktop` and copies the icon into the user's icon theme as `<CFBundleIdentifier>.svg` or `.png` (a square PNG of a standard size: 48, 64, 128, 256, 512 and others; an SVG serves every size). It needs `CFBundleIdentifier`; the entry runs `CFBundleExecutable` in the program folder (the app folder, or `Contents/Linux`), else the executable named after the app folder. Two keys only Linux reads go into the entry, and macOS ignores them:

```xml
	<key>LinuxDesktopComment</key>
	<string>Edits my things</string>
	<key>LinuxDesktopCategories</key>
	<array>
		<string>Utility</string>
	</array>
```

The files and folders the app opens are its `CFBundleDocumentTypes`, as on macOS: the entry lists them as MIME types (`MimeType`), so the file manager's Open With offers the app for them, and the entry's command line ends in `%U`, which hands the app the chosen files as `file://` URLs. Each document type's `CFBundleTypeMIMETypes` is taken as given; its `LSItemContentTypes` (such as `public.plain-text`, `public.folder`, `com.apple.application-bundle`) and `CFBundleTypeExtensions` (`txt`, `png`) are turned into MIME types; a type whose `CFBundleTypeRole` is `None` is left out, and `CFBundleTypeOSTypes`, legacy Mac OS file types, are not read. `*` (any file) is not listed: as `application/octet-stream` it would make the app the default for every file the desktop cannot type further, so an app that takes any file names the types it should be offered for. The URL schemes in `CFBundleURLTypes` are listed as `x-scheme-handler/<scheme>`, so a link with the scheme opens the app with the URL, as on macOS. A Linux desktop types every folder `inode/directory` whatever its name, so an app that opens bundles is offered for every folder. For what these cannot say, a Linux-only array adds MIME types as given:

```xml
	<key>LinuxMimeTypes</key>
	<array>
		<string>application/x-example</string>
	</array>
```

The desktop picks the entry up within seconds. A changed command line is another matter in GNOME: GNOME Shell can keep starting the program the entry named before, until the entry is uninstalled, some seconds pass, and it is installed again (or the next login). A changed icon is another matter in GNOME: its Apps grid can keep showing the icon it first drew until the next login, even after the entry is uninstalled and installed again, while the dock shows the new icon at once. `--exec` takes the entry's command line, run in the app folder; without it the entry runs the app's program (`CFBundleExecutable`, else the executable named after the app folder, else the only executable in the program folder). macOS `.icns` and Icon Composer files do not work on Linux: export a PNG or an SVG (with neither, the entry gets the desktop's generic icon, and the script says so).

## Checking documents

`actionui-verify` checks ActionUI JSON documents against the element schemas, with the same options, output and exit codes as on macOS and as the Python verifier in `Tools/verifier`. It needs no GTK, so it also runs on a machine with no desktop:

```sh
swift run --package-path Apps/ActionUIVerifier actionui-verify -r ActionUISwiftTestApp/Resources
```

A self-contained copy, which runs where Swift is not installed:

```sh
swift build -c release --static-swift-stdlib --package-path Apps/ActionUIVerifier
Scripts/make-linux-verifier-package.sh Apps/ActionUIVerifier/.build/release <output folder>
```

The script makes `actionui-verify-<version>-linux-<arch>/` and its `.tar.gz`: the stripped tool in `bin/`, the element schemas and the add-ons' in `share/actionui/schemas/`. Unpack it anywhere; it needs only the C and C++ libraries, no older than those of the machine that built it (a build on Debian 13 needs glibc 2.38).

## Tests

```sh
swift test
```

The renderer tests open real windows, so they need a graphical session (Wayland or X11); without one they skip themselves. The layout tests compare frames with recordings taken from SwiftUI (`LayoutParity/`).

The viewer and the demo have tests of their own in their packages, which run the programs themselves:

```sh
swift test --package-path Apps/ActionUIViewer --only-use-versions-from-resolved-file --manifest-cache none
swift test --package-path ActionUIAdwaita/Apps
```

`libActionUI.so` has tests of its own, Python programs run against the built library, in the package that builds it:

```sh
swift build --package-path ActionUIAdwaita/Library
swift test --package-path ActionUIAdwaita/Library
```

## Using it from a program

- **Swift:** depend on the ActionUI package's `ActionUIStatic` product, which links the same `ActionUI` module into the program. That module holds the portable core and the GTK renderer. A program that lets ActionUI run its application also depends on the `ActionUIAdwaitaApplication` product (`import ActionUIAdwaitaApplication`), where `AdwaitaApplication` runs an application and presents documents and `AppPanels` shows the alert and the file panels; a program that runs its own `GtkApplication` leaves it out, as an AppKit host on macOS leaves out `ActionUIAppKitApplication`. The Swift adapter (`ActionUISwiftAdapter`), which offers the same calls as on Apple, is a target of the package, for the programs inside it such as the demo; it is not a product on Linux yet. Swift programs compile ActionUI in and use the toolchain's Swift runtime; they do not load `libActionUI.so`, which carries a second, private Swift runtime and libdispatch (its main queue would not be the program's).
- **C, Python, Node.js, Rust and other languages:** load `libActionUI.so`, which holds the renderer, the add-ons (RichText and CachedImage, registered on first use, so a document just uses them), the C adapter (`ActionUIC.h`) and the application functions (`ActionUIApp.h`), with the same names and signatures as on macOS. Built with the Swift runtime inside it, it needs no Swift installation:

  ```sh
  swift build -c release --static-swift-stdlib --package-path ActionUIAdwaita/Library --product ActionUI
  Scripts/make-linux-library-package.sh ActionUIAdwaita/Library/.build/release <output folder>
  ```

  The script makes `actionui-<version>-linux-<arch>/` and its `.tar.gz`: the stripped library in `lib/`, the licenses (`LICENSE.txt`, `LICENSE-MaterialSymbols.txt` for the symbol icons, and `LICENSE-RichText.txt`, `LICENSE-AsyncImageCache.txt` and `LICENSE-DiffView.txt` for the packages linked in), a `pkg-config` file (`lib/pkgconfig/actionui.pc`, valid wherever the folder is unpacked), and the headers at the include paths the Apple frameworks use (`<ActionUICAdapter/ActionUIC.h>`, `<ActionUIAppKitApplication/ActionUIApp.h>`, and the remote server's `<ActionUIRemote/ActionUIRemote-Swift.h>`, the one Swift generates). It is a build input, not an installation: each program ships its own copy of `libActionUI.so` beside its binary (for Python and Node.js, beside the compiled extension) and links with `-Wl,-rpath,'$ORIGIN'`, so it stays self-contained, as an app bundle is on macOS. A host that loads the library by path, as `ctypes` does, needs no link flags.

  `Library/Tests/ActionUILibraryTests/Hosts/temperature_converter.py` is a complete Python host using only `ctypes`. The Python and Node.js packages and the Rust crates build on Linux against the library package (`ActionUIPython/BUILD_GUIDE.md`, `ActionUINodeJS/BUILD_GUIDE.md` and `ActionUIRust/BUILD_GUIDE.md`, "Building on Linux").

## What is there and what is not yet

- **Elements:** every core element type. All but a few of the test app's 108 documents render with nothing missing.
- **Map:** OpenStreetMap's standard tiles through libshumate, with the attribution OpenStreetMap requires, a scale, zoom buttons and a compass. The value, both actions and `interactionModes` work, and each annotation is a red pin with its title and subtitle under it, and `showsUserLocation` shows the user's location from the desktop's location portal. `Documentation/Schemas/Map.md` lists what differs.
- **Chart:** draws every mark with axes, legends and series colors, comparable to Swift Charts. Selection (by the pointer, as on macOS), scrolling and annotations work; `Documentation/Schemas/Chart.md` lists what differs.
- **ShareLink:** Linux desktops have no share sheet, so its button opens a menu of the ways GNOME shares a link: **Copy Link**, and **Send by Email...**, which opens the user's mail program with the subject, the message and the URL (through the desktop's Email portal, else a `mailto:` link). When no email app can be opened, an alert says so.
- **Application functions** (`actionUIApp*`): windows, the lifecycle handlers, the resource folder and the menu bar's commands (in each window's primary menu) work. The standalone alert and the open and save panels are libadwaita's alert dialog and GTK's file dialog, modal to the active window; each call blocks until the user answers while the main loop keeps running, and takes the macOS configuration keys, ignoring those GTK has no counterpart for (an alert's `style`, a panel's `message`, `showsHiddenFiles`, `treatsFilePackagesAsDirectories`, `canCreateDirectories`; a panel allowing files and folders chooses files). Called before the application runs, they log why and return NULL. **The remote server** (`ActionUIRemote/PROTOCOL.md`) runs as on macOS, its socket by default in `$XDG_RUNTIME_DIR` (else `$TMPDIR`, else `/tmp`); `actionui.contentSizeLimits` measures a window on screen (`ActionUIModel.contentSizeLimits`, null for a window that is only loaded), as do the C function `actionUIGetContentSizeLimits` and the Python, Node.js and Rust `content_size_limits` over it.
- **Add-ons:** RichText, CachedImage and Diff are in `libActionUI.so`, and work in a Swift program that links them and registers them (`Add-ons/README.md`), as the viewer and the demo do. Chat and QuickLook are not on Linux yet. An element without a renderer shows the placeholder.
- **Look:** libadwaita's controls, header bar and dark style. SF Symbols may not be shipped off Apple platforms, so SF Symbol names show the Material Symbols Rounded icons Android and Web show, from the same map (`sf_to_material.map`), at each symbol's fill and weight, in the text color; a name the map lacks shows the missing-icon picture. The icons are compiled into the library; their license (Apache 2.0) is `LICENSE-MaterialSymbols.txt` in the library package and the demo bundle. The controls' own icons (menus, the sidebar button, steppers) stay Adwaita's, as in other GNOME apps.
- **Closing the last window:** the user's close ends the application (after asking the shouldTerminate handler), as GNOME applications do: with no window, a Linux application has no Dock icon or menu bar to quit it from. The host's close (`closeWindow`) leaves it running, as on macOS, until the host presents another window or calls `terminate`, so a host can close one window before it opens the next.

## Layout of this folder

| Folder | What |
|---|---|
| `Sources/Elements` | one renderer per element type (`Button+Adwaita.swift`, ...) |
| `Sources/Layout` | SwiftUI's layout reproduced: stacks, grids, frames, scroll views, modifier boxes |
| `Sources/Runtime` | the render tree, the window registry, toolbars, the primary menu, presentations |
| `../ActionUIAdwaitaApplication` | the optional application module: `AdwaitaApplication`, `AppPanels`, offscreen rendering, and the `actionUIApp*` C functions |
| `Sources/Styling`, `Formatting`, `Markdown`, `Drawing` | CSS for colors and fonts, number and date formats, markdown text, shapes |
| `Sources/Interop` | the Swift side of the GTK, GLib and WebKitGTK C APIs |
| `CAdwaita`, `CSoup` | the system libraries' headers, with the version floors |
| `CLinuxSocket` | `accept4`, which Swift's Glibc module leaves out (for the remote server) |
| `CSymbolResource`, `Plugins/SymbolResourceCheck` | the symbol icons as a GResource section (the C source `Scripts/prepare-linux-symbols.sh` generates, in `generated/`), and the build plugin that warns when they are missing or out of date. The generator, `Tools/material_symbols/generate-symbol-icons.c`, draws Material Symbols Rounded glyphs with HarfBuzz as symbolic SVGs from `ActionUIAndroid`'s `sf_to_material.map`; the SVGs stay in `Tools/material_symbols/build/icons` for inspection |
| `Apps` | ActionUIAdwaitaDemo, a package of its own that links the add-ons, with its tests (the viewer is in `Apps/ActionUIViewer`) |
| `Tests` | the renderer, layout and application tests |
