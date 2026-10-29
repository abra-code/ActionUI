# ActionUI on Linux (GTK 4 and libadwaita)

ActionUI renders its JSON documents on Linux as native GNOME interfaces: **GTK 4 and libadwaita widgets**, written in **Swift** and built from the same Swift package as the Apple frameworks. A document written for macOS opens on Linux unchanged, with the same element and property names, the same values and actions, and the same C interface for host programs.

For how the renderer works (retained widgets, SwiftUI's layout reproduced, what is shared with Apple) see the Linux section of [Architecture.md](../Documentation/Architecture.md#linux-architecture).

## Requirements

- **GNOME 48 or later:** GTK 4.18, libadwaita 1.7, GLib 2.84 and libsoup 3. Tested on **Debian 13** (GTK 4.18, libadwaita 1.7) and **Ubuntu 26.04** (GTK 4.22, libadwaita 1.9). Ubuntu 24.04's libadwaita 1.5 is too old.
- To build: a **Swift 6.3** or later toolchain from swift.org, and the development packages (Debian and Ubuntu names):

  ```sh
  sudo apt install libgtk-4-dev libadwaita-1-dev libsoup-3.0-dev pkg-config
  ```

- At run time, besides GTK, libadwaita and libsoup:
  - **glib-networking** for https URLs (installed with GNOME);
  - **WebKitGTK 6.0** (`libwebkitgtk-6.0-4`) for WebView only. It is loaded when a WebView is first shown, so it is a dependency of the app that shows web pages, not of ActionUI; without it a WebView shows a placeholder that names the package. Ubuntu's desktop installs it; Debian's GNOME desktop does not.
  - **GStreamer** for VideoPlayer: built into GTK 4.20 and later, a GTK module before that (`libgtk-4-media-gstreamer`, which Debian's GNOME desktop installs), plus the GStreamer plug-ins for the video's format;
  - **ICU** (any version the system has) for dates and numbers by locale, also loaded when first needed.

## Building and trying it

From the repository root, on Linux:

```sh
swift build                                   # the library, the viewer and the demo
swift run ActionUIAdwaitaViewer ActionUISwiftTestApp/Resources/Form.json
swift run ActionUIAdwaitaDemo --resources ActionUISwiftTestApp/Resources
```

- **ActionUIAdwaitaViewer** opens one document in a window: a path, a file URL or an http(s) URL. `--dark` uses the dark style; `--screenshot out.png` saves the window as an image once it has drawn and quits (drawn by the window itself, so no screen capture is needed); `--rows <id> <rows.json>` fills a List, Table or Chart for a screenshot.
- **ActionUIAdwaitaDemo** is the Linux counterpart of ActionUISwiftTestApp: a launcher of all the test app's documents, with the test app's own action handlers. `--open <Name>` also opens one document at launch, `--screenshot` saves it.

A self-contained demo, which runs where Swift is not installed:

```sh
swift build -c release --static-swift-stdlib --product ActionUIAdwaitaDemo
Scripts/make-linux-demo-bundle.sh .build/release /tmp     # makes /tmp/ActionUIDemo.app
/tmp/ActionUIDemo.app/ActionUIDemo
Scripts/linux-app-entry.py install /tmp/ActionUIDemo.app  # optional: the demo in the desktop's app list
```

`ActionUIDemo.app` is a plain folder: the program, stripped (about 15 MB), beside its documents and images, its `Info.json` and its icon (both from `ActionUIAdwaita/DemoBundle`). The program finds its documents in the folder it runs from.

## Info.json

An app's folder (the program's folder, or for Python and Node.js the main script's, the resource folder) can hold an `Info.json` that names the app, as `Info.plist` does on Apple:

```json
{
  "applicationID": "org.example.MyApp",
  "name": "My App",
  "icon": "MyApp.svg"
}
```

- `applicationID`: the reverse-DNS application ID. The desktop matches the app's windows to its desktop entry, `<applicationID>.desktop`, by it, so the dock shows the entry's name and icon; with no matching entry it shows the raw ID and a generic icon.
- `name`: the application's name, in the About item and dialog of the windows' primary menu, and the title of a window that has none of its own (a document file's window takes the file's name).
- `icon`: the windows' icon, a PNG or SVG file (GTK reads no other formats) by its path relative to the app's folder (`MyApp.svg`, `icons/MyApp.svg`) or an absolute path, else an icon theme name.

All keys are optional; an empty string counts as left out. A value the program sets in code (`actionUIAppSetApplicationID`, `actionUIAppSetName`, `actionUIAppSetIcon` and their Python, Node.js, Rust and Swift counterparts) wins over the file; with neither, the ID is made from the name (`com.abracode.actionui.<name>`). Other keys are left for the tools that install the app. On Apple the file is not read.

### In the desktop's app list

`Scripts/linux-app-entry.py` adds an app folder to the app list of the desktop (GNOME's Apps, KDE Plasma's launcher, Xfce's menu and others that follow the freedesktop.org standards), for the current user, from its `Info.json`:

```sh
Scripts/linux-app-entry.py install /path/to/MyApp.app                                # runs MyApp.app/MyApp
Scripts/linux-app-entry.py install /path/to/MyApp --exec 'python3 MyApp.py'          # a Python or Node.js app
Scripts/linux-app-entry.py uninstall /path/to/MyApp.app                              # or: uninstall org.example.MyApp
```

It writes `~/.local/share/applications/<applicationID>.desktop` and copies the icon into the user's icon theme as `<applicationID>.svg` or `.png` (a square PNG of a standard size: 48, 64, 128, 256, 512 and others; an SVG serves every size). `Info.json` needs `applicationID` for it; two more keys go into the entry:

```json
{
  "applicationID": "org.example.MyApp",
  "name": "My App",
  "icon": "MyApp.svg",
  "summary": "Edits my things",
  "categories": ["Utility"]
}
```

The desktop picks the entry up within seconds. A changed icon is another matter in GNOME: its Apps grid can keep showing the icon it first drew until the next login, even after the entry is uninstalled and installed again, while the dock shows the new icon at once. `--exec` takes the entry's command line, run in the app folder; without it the entry runs the folder's program (the executable named after the folder, else its only executable). macOS `.icns` and Icon Composer files do not work on Linux: export a PNG or an SVG.

## Tests

```sh
swift test
```

The renderer tests open real windows, so they need a graphical session (Wayland or X11); without one they skip themselves. The layout tests compare frames with recordings taken from SwiftUI (`LayoutParity/`).

## Using it from a program

- **Swift:** depend on the ActionUI package. On Linux its `ActionUI` module holds the portable core and the GTK renderer; `AdwaitaApplication` runs an application and presents documents, and the Swift adapter (`ActionUISwiftAdapter`) offers the same calls as on Apple. Swift programs compile ActionUI in and use the toolchain's Swift runtime; they do not load `libActionUI.so`, which carries a second, private Swift runtime and libdispatch (its main queue would not be the program's).
- **C, Python, Node.js, Rust and other languages:** load `libActionUI.so`, which holds the renderer, the C adapter (`ActionUIC.h`) and the application functions (`ActionUIApp.h`), with the same names and signatures as on macOS. Built with the Swift runtime inside it, it needs no Swift installation:

  ```sh
  swift build -c release --static-swift-stdlib --product ActionUI   # .build/release/libActionUI.so
  Scripts/make-linux-library-package.sh .build/release <output folder>
  ```

  The script makes `actionui-<version>-linux-<arch>/` and its `.tar.gz`: the stripped library in `lib/`, a `pkg-config` file (`lib/pkgconfig/actionui.pc`, valid wherever the folder is unpacked), and the headers at the include paths the Apple frameworks use (`<ActionUICAdapter/ActionUIC.h>`, `<ActionUIAppKitApplication/ActionUIApp.h>`, and the remote server's `<ActionUIRemote/ActionUIRemote-Swift.h>`, the one Swift generates). It is a build input, not an installation: each program ships its own copy of `libActionUI.so` beside its binary (for Python and Node.js, beside the compiled extension) and links with `-Wl,-rpath,'$ORIGIN'`, so it stays self-contained, as an app bundle is on macOS. A host that loads the library by path, as `ctypes` does, needs no link flags.

  `Tests/Hosts/temperature_converter.py` is a complete Python host using only `ctypes`. The Python and Node.js packages and the Rust crates build on Linux against the library package (`ActionUIPython/BUILD_GUIDE.md`, `ActionUINodeJS/BUILD_GUIDE.md` and `ActionUIRust/BUILD_GUIDE.md`, "Building on Linux").

## What is there and what is not yet

- **Elements:** every core element type except **Chart and Map**, which show a placeholder naming their type. All but those few of the test app's 108 documents render with nothing missing.
- **ShareLink:** Linux desktops have no share sheet, so its button opens a menu of the ways GNOME shares a link: **Copy Link**, and **Send by Email...**, which opens the user's mail program with the subject, the message and the URL (through the desktop's Email portal, else a `mailto:` link). When no email app can be opened, an alert says so.
- **Application functions** (`actionUIApp*`): windows, the lifecycle handlers, the resource folder and the menu bar's commands (in each window's primary menu) work. The standalone alert and the open and save panels are libadwaita's alert dialog and GTK's file dialog, modal to the active window; each call blocks until the user answers while the main loop keeps running, and takes the macOS configuration keys, ignoring those GTK has no counterpart for (an alert's `style`, a panel's `message`, `showsHiddenFiles`, `treatsFilePackagesAsDirectories`, `canCreateDirectories`; a panel allowing files and folders chooses files). Called before the application runs, they log why and return NULL. **The remote server** (`ActionUIRemote/PROTOCOL.md`) runs as on macOS, its socket by default in `$XDG_RUNTIME_DIR` (else `$TMPDIR`, else `/tmp`); `actionui.contentSizeLimits` measures a window on screen (`ActionUIModel.contentSizeLimits`, null for a window that is only loaded), as do the C function `actionUIGetContentSizeLimits` and the Python, Node.js and Rust `content_size_limits` over it.
- **Add-ons** (Chat, Diff, RichText, QuickLook, CachedImage) are not on Linux yet; their elements show the placeholder.
- **Look:** libadwaita's controls, header bar and dark style. SF Symbol names map to the Adwaita icon theme; a name with no counterpart there shows the missing-icon picture.
- **Closing the last window:** the user's close ends the application (after asking the shouldTerminate handler), as GNOME applications do: with no window, a Linux application has no Dock icon or menu bar to quit it from. The host's close (`closeWindow`) leaves it running, as on macOS, until the host presents another window or calls `terminate`, so a host can close one window before it opens the next.

## Layout of this folder

| Folder | What |
|---|---|
| `Sources/Elements` | one renderer per element type (`Button+Adwaita.swift`, ...) |
| `Sources/Layout` | SwiftUI's layout reproduced: stacks, grids, frames, scroll views, modifier boxes |
| `Sources/Runtime` | the render tree, `AdwaitaApplication`, windows, toolbars, menus, presentations |
| `Sources/Styling`, `Formatting`, `Markdown`, `Drawing` | CSS for colors and fonts, number and date formats, markdown text, shapes |
| `Sources/Interop` | the Swift side of the GTK, GLib and WebKitGTK C APIs |
| `CAdwaita`, `CSoup` | the system libraries' headers, with the version floors |
| `CLinuxSocket` | `accept4`, which Swift's Glibc module leaves out (for the remote server) |
| `Viewer`, `Demo` | ActionUIAdwaitaViewer and ActionUIAdwaitaDemo |
| `Tests` | the renderer, layout and application tests |
