# actionui-mcp

A local MCP (Model Context Protocol) server that lets an AI agent open native windows through ActionUI, on macOS, on Linux (GTK 4 and libadwaita; see Linux for what differs there) and on Windows (WinUI 3; see Windows). The client starts it and talks JSON-RPC over stdin and stdout; windows live as long as the client session, except those opened with `keep: true` (see Kept windows). On macOS it installs from an installer package into `/usr/local/libexec/actionui-mcp/` (see Build), on Linux from a tarball (see Install on Linux), on Windows from a zip (see Install on Windows); Configure a client shows how to add it to Claude Code, Codex, opencode and others.

Tools:

- `ask_user` - a dialog with a message (Markdown, drawn whole: headings, lists, quotes, code blocks and tables as well as inline styles; remote images in it are not loaded), optional typed fields (text, multiline, number, integer, toggle, choice, multichoice, slider, date), and buttons. Blocks until the user answers and returns `{action, button, values}`, where `action` is `accept`, `cancel`, or `timeout`. Up to 30 fields; when they would not fit, they scroll. Sliders show their current value. A `multichoice` field is a column of checkboxes and answers with an array of the checked option values.
- `notify` - a short notice in a small floating panel at the top right of the screen. Returns at once; the notice takes no focus and goes away after `duration_s` (default 6) or a click. Its message is Markdown, drawn as in `ask_user` (remote images not loaded). At most 4 on screen, fewer when they are tall; a new one replaces the oldest.
- `show` - a non-blocking viewer window for markdown, plain text, a file shown by its type (a Markdown file with the images its relative paths name; markdown text with them too, given the folder in `base`; images go in as `![alt](path)`, and HTML tags such as `<img>` show as plain text), an image, a PDF, a video, a web page, a diff of two texts or files, a table (up to 50000 rows), or a chart. Returns `{window}` at once and does not take keyboard focus. A chart is a Chart element description in `chart`; it gets the checks of `show_ui`, its warnings come back in `warnings`, and its Chart has id 1, so `update_window` can replace the description (`properties`) or stream data (`rows`, `append_rows`). `keep: true` keeps the window open after the session ends. Kind `file` picks the view from the file's extension, then its content: Markdown formatted (RichText), CSV and TSV as a table (first record as the header), images, audio and video in their elements, HTML, XHTML and SVG as a web page (a WebView of the file, which may read the file's folder, so relative images and style sheets load; the page's scripts run and its remote resources load), a `.webloc` or `.url` link file as the page it names (http and https only), any other UTF-8 text as monospaced text (up to 4 MB; Markdown is formatted up to 1 MB and shown as text above that, and its remote images load when clicked), and only the rest (PDF, RTF, binary files, larger text) with Quick Look; the result's `shown_as` names the view. Quick Look draws some types as web pages whose text cannot be selected, and a Markdown preview needs a Quick Look plug-in most Macs do not have, so it is the last resort.
- `pick_path` - the system open or save panel. Blocks and returns `{action, paths}`.
- `show_ui` - opens ActionUI JSON the agent wrote, passed as a nested object in `ui` or as an absolute `.json` path in `path`. In `dialog` mode it adds a footer and a button row, waits, and returns every element's value by id. In `window` mode it returns `{window}` at once and queues the window's actions for `wait`; `keep: true` keeps the window open after the session ends. ActionUI JSON that ActionUI cannot load is not shown; the load errors come back instead. What is refused is listed under Rules for agent-written ActionUI JSON.
- `validate_ui` - checks ActionUI JSON without showing it: first element shape, unique positive ids, container keys placed inside `properties`, and refused elements; when those pass, the ActionUIVerifier library (the Swift twin of the Python verifier) checks element types, property names, value types, enum values, required properties, and platform suffixes; then ActionUI's own load errors. Errors also make `show_ui` refuse it; warnings (usually typos) come back with the result. Validation targets the system the server runs on.
- `wait` - returns the queued actions of live windows (`show_ui` window mode), waiting for at least one or a timeout. Repeated actions on one element are merged; closing a window adds a `window.closed` event.
- `update_window` / `get_values` - write element properties, values and table rows into an open window, and read values back. `properties` (`{"<id>": {"<name>": value}}`, for example a Chart's `chart` description) is applied first, then values, then rows. Each entry gets the rules under Rules for agent-written ActionUI JSON; a refused one comes back in `problems`, and verifier warnings in `warnings`.
- `screenshot` - a PNG of an open window, or of ActionUI JSON rendered in a window that never appears on screen (to check a layout before showing it). Returns an image content block and saves the PNG; captured in-process, so it needs no Screen Recording permission and works with the screen locked. Rendered ActionUI JSON gets `validate_ui`'s checks first; their controls draw in the inactive style.
- `close_window` - closes a window. A session may have 20 windows open at once (dialogs included); a window the user closes frees its place, and opening one more fails with a tool error that says to close one first.
- `actionui_docs` - the ActionUI JSON reference bundled with the server, for an agent without the actionui skill: `topic` `guide` (how ActionUI JSON is written, with a Window Content example to start from), `elements` (the element index), `element` or `template` with `type` (one element's page, or its JSON template). Returns the same text as the resources below. Read-only; it opens no window and works with no graphical session. The server's instructions and the descriptions of `show_ui` and `validate_ui` tell the agent to read the skill if it has it, else this tool, before writing ActionUI JSON.

Resources: the same reference, for clients that read resources: `actionui://docs/guide` (the JSON guide), `actionui://docs/elements` (the element index), `actionui://docs/elements/<Type>` (one element, core and add-ons) and `actionui://docs/templates/<Type>` (a JSON template). On macOS they are read from the documentation bundles that `swift build` places next to the executable; ship those bundles with the binary, or the resources are left out. On Linux they are read from `share/actionui/docs/` beside the server's `bin` folder in the Linux package, else from the ActionUI checkout the server was built from.

Every window's title starts with who asked for it: "<client>: <title>" (for example "claude-code: Build report"), so the Dock, the Window menu and the window switchers, which show only the title and cut a long one at its end, always show the client, and an agent's title cannot pass for another application's window. A yellow and black mark under the title bar shows that an agent asked for the window. On `show` windows it is a bar, black notches along its top edge, holding where the content came from, either the file (with a button that selects it in a Finder window, never opening it) or the web address, when the window was shown, and a Save button; on the other windows it is a 3-point striped line. The server draws it outside the ActionUI JSON, so the agent cannot remove it. It adds its height to the window's, and a screenshot of the window includes it. Save asks where with a save panel and writes a copy there: the file itself, the text (markdown as .md, plain text as .txt, HTML as .html), a table as CSV with its rows as they are at that moment, a chart as PNG, a diff as a unified diff. Content from the network has a Copy URL button instead. The agent cannot press either button. A kept window keeps the bar, its buttons and the time it was first shown, and its title says "(session ended)" after the client.

## Rules for agent-written ActionUI JSON

Everything the user enters in a window goes back to the agent, and the agent, not the person who installed the server, writes the ActionUI JSON. So `show_ui`, `validate_ui` and `screenshot` (of ActionUI JSON) refuse anything that could keep input away from these checks or run code:

- `SecureField` is refused: whatever the user types in it would be sent to the agent. `ACTIONUI_MCP_ALLOW_SECURE_FIELDS=1` allows it.
- `LoadableView` is refused: the ActionUI JSON it loads (from `url`, `filePath`, a bundle `name`, or a new value) would skip every check here. Put its content inline instead.
- `WindowGroup` is refused: it is an application's scene, and its commands would stay in the application's menu after its window closes. Give its content as the root element.
- `popover` is refused on any element: a popover is placed by the system, can open over the window's title bar from an element anywhere, whatever its size, and could show a fake one of its own there, with another "who asked" (on Linux, a "Requested by" line). A sheet keeps the title bar in view.
- A `ToolbarItem` or `ToolbarItemGroup` with placement `secondaryAction` is refused, in the ActionUI JSON and from `update_window`: on Linux its items open in the header bar's "More" popover, which opens over the "Requested by" line when it does not fit below the bar.
- WebView `userScripts` are removed, with a warning: the server injects no user scripts an agent names. A page's own scripts still run, including those in a WebView's `html` (see What these rules do not cover).
- Platform overrides (`"<key>:macos"`, repeated suffixes such as `"type:macos:macos"` included) are resolved before these checks, and the window loads the resolved ActionUI JSON, so a suffixed key cannot carry a refused element past them.
- The rules reach elements nested anywhere, a Chart's annotation views included (the `content` of a mark's `annotation` in its `chart` description).
- The ActionUI JSON is an object in `ui` (never a string) or an absolute `.json` path in `path`, at most 4 MB. Files it names (Image and QuickLook `filePath`, Diff `oldFile` and `newFile`, a Canvas image's `filePath`, and a QuickLook value or an Image value holding a `/` from `update_window`) are given by absolute path, `~` allowed in Diff: the server loads its own copy of the JSON, so a relative path would resolve against the server's working directory, not the JSON file's folder. Ids are unique positive integers, and container keys such as `children` sit next to `properties`, not inside it. Verifier errors and ActionUI load errors also refuse it.

`update_window` applies the same rules to each entry:

- `properties`: no null value, no `userScripts`, no child-element key such as `children` or `content`, no `id` or `type`, and no `:<platform>` suffix (not resolved here); no property of a SecureField or LoadableView. A Chart's `chart` description is resolved and its annotation views checked as other elements are, and the window gets the resolved description. Each entry is then checked by the verifier as a one-element piece of ActionUI JSON.
- `values`: strings, numbers or booleans; a LoadableView's value (its source) cannot be set.

### What these rules do not cover

The rules decide what an agent's ActionUI JSON may contain; they do not make it harmless. A client that asks the user before a tool call should know what a call can still do:

- Read files. `show` (kinds `diff`, `image`, `pdf`, `file`, `video`) and the Diff, Image and QuickLook elements in agent-written ActionUI JSON draw any file the user can read. `screenshot` of ActionUI JSON draws it in a window that never appears on screen and returns the picture, so a file can be read with nothing shown.
- Reach the network. AsyncImage, CachedImage, VideoPlayer and WebView addresses in agent-written ActionUI JSON, and remote images in markdown passed to `show` (in `text`; in a Markdown file shown with kind `file`, only when the user clicks one; never in an `ask_user` or `notify` message), are fetched when the window or the hidden render loads, so the server at that address learns when, and can receive anything the agent puts in the address.
- Run page scripts. A WebView runs the scripts of the page it shows, and of its `html` (as a page at its `baseURL` when one is given); `show` kind `web` runs the scripts of the HTML it is given.
- Open links. A Link, and a link in markdown, opens any URL scheme on one click, a file the agent wrote included.

So `show`, `show_ui`, `screenshot` and `validate_ui` are annotated `openWorldHint: true`. `validate_ui` shows no window, but it loads the ActionUI JSON to measure it, and whether that fetches anything has not been checked.

## Kept windows

A window opened with `keep: true` (`show`, or `show_ui` in window mode) stays on screen when the session ends. The client ends a session by closing the server's stdin, then sends SIGTERM 2 seconds later and SIGKILL 2 seconds after that, so no window of the server process itself can stay. At the end of input (or on SIGTERM, SIGHUP or SIGINT) the server writes each kept window's ActionUI JSON, frame, title, element values, table rows and the properties `update_window` set to a private temporary folder and starts a second copy of itself, `actionui-mcp --rehost <folder>`, in a session of its own, so the client's signals do not reach it. That process shows the same windows at the same places, with "(session ended)" after who asked for them, deletes the folder, and quits when its last window closes. The server waits up to 1.5 seconds for it to report that its windows are up, so the two sets overlap instead of flickering.

The copies are no longer connected to any agent: their buttons do nothing, and `wait`, `update_window` and the other tools cannot reach them. What is not an element value is not carried over: scroll positions, a video's playback position, a web page the user navigated to. A server killed with SIGKILL before its input closes cannot hand anything off.

## Linux

The same server runs on Linux with ActionUI's GTK 4 and libadwaita renderer. It was tested on GNOME 48 on Debian 13 (GTK 4.18, libadwaita 1.7). What differs from macOS:

- The title is in the header bar ("claude-code: Build report"). Where ActionUI JSON takes the title's place (principal toolbar items, or a NavigationStack or NavigationSplitView that brings its own header bars), a "Requested by <client>" line shows above the header bar, and every sheet shows that line too: a sheet covers the whole window there. The yellow and black mark is under the header bar; with a NavigationStack's own header bars, it is above them. In a `show` window's bar, the button beside a file shows it in the file manager (never opening it), and the time is the date and time of the user's locale.
- Every new window takes the keyboard focus: Wayland has no way to open a window and leave the focus where it was. `show` says so in its description.
- The windows show the ActionUI icon once the server's desktop entry is installed (`--install-desktop-entry`, see Install on Linux); on macOS the Dock shows it without a step.
- `show` has no `pdf` kind (Quick Look has no Linux renderer), and the tool's schema leaves it out; kind `file` shows what ActionUI's own views can (Markdown, CSV and TSV, images, audio and video, HTML and SVG, link files, UTF-8 text) and refuses other files. Of the add-ons, RichText, CachedImage and Diff are there.
- `notify` is a desktop notification (org.freedesktop.Notifications): the desktop places and styles it, may hide it sooner, and holds it back in do-not-disturb mode. Its heading is the "Requested by" line; markdown keeps bold and italic. The server closes it after `duration_s` and when the session ends.
- `pick_path` uses the desktop's file chooser (through the portal on GNOME).
- `screenshot` of ActionUI JSON draws it in a window that is never presented, so nothing shows. A WebView's page is not drawn there, and the result says so; screenshot an open window to see the page.
- Kept windows come back at the same size, but where the compositor puts them: Wayland does not tell an application where its windows are.
- With no display at all (over SSH), the server still starts and answers: `validate_ui`, `actionui_docs` and the resources work, and the tools that show a window or a notice, and `screenshot`, say there is no graphical session.

### Install on Linux

The Linux package is a folder and a tarball: `bin/actionui-mcp` (the Swift runtime linked in), the element schemas in `share/actionui/schemas/` and the element reference in `share/actionui/docs/`, which the server finds from its own place, and the licenses. Build it on Linux from the repository root, with the toolchain and development packages that `ActionUIAdwaita/README.md` lists:

```sh
Scripts/prepare-linux-symbols.sh    # the symbol icons; without them SF Symbols show the missing-icon picture
swift build -c release --static-swift-stdlib --package-path Apps/ActionUIMCP \
    --only-use-versions-from-resolved-file --manifest-cache none
mkdir -p .build/linux-package
Scripts/make-linux-mcp-package.sh Apps/ActionUIMCP/.build/release .build/linux-package
```

`--only-use-versions-from-resolved-file` keeps the tracked `Package.resolved` as it is: the Linux manifest has fewer packages, and a resolve there would drop the macOS-only ones.

The machine needs GNOME 48 or later: GTK 4.18, libadwaita 1.7 and libsoup 3 (on Debian and Ubuntu: `libadwaita-1-0`, `libsoup-3.0-0`; Ubuntu 24.04's libadwaita 1.5 is too old), and glibc 2.38 or later for a build made on Debian 13; WebKitGTK 6.0 (`libwebkitgtk-6.0-4`) for web pages and libshumate (`libshumate-1.0-1`) for maps: without one a web page's or a map's place shows the package to install. Unpack the tarball anywhere, for example into `~/.local/opt`, and register the server with its full path:

```sh
mkdir -p ~/.local/opt
tar -xzf .build/linux-package/actionui-mcp-<version>-linux-<arch>.tar.gz -C ~/.local/opt
~/.local/opt/actionui-mcp-<version>-linux-<arch>/bin/actionui-mcp --install-desktop-entry
claude mcp add --scope user actionui -- ~/.local/opt/actionui-mcp-<version>-linux-<arch>/bin/actionui-mcp
```

`--install-desktop-entry` gives the windows the ActionUI icon and the name "ActionUI MCP" in the dock, the window switcher and the overview, and on the desktop notifications. GNOME takes a window's icon and name from the desktop entry named by its application ID (`com.abracode.actionui.mcp`), not from the program or its file name, so without one the windows show a generic icon and the raw ID. An entry written by an older version names the server "ActionUI": run the option again to rename it. The option writes `~/.local/share/applications/com.abracode.actionui.mcp.desktop` (under `$XDG_DATA_HOME` when that is set), hidden from the app list, naming this copy of the server and its icon; run it again after moving the folder, and `--uninstall-desktop-entry` removes it. A window that opens before the entry is written keeps the generic icon.

The client setup below is the same on Linux with that path.

## Windows

The same server runs on Windows 11 with ActionUI's WinUI 3 renderer (`ActionUIWinUI`). What differs from macOS:

- The title and the mark are those of macOS: "<client>: <title>" in the title bar, and under it the yellow bar on `show` windows (its Save uses the Windows save dialog and also answers Ctrl+S wherever the focus is in the window except inside a web page, and its folder button selects the file in File Explorer) or the striped line on the others. The window cannot be made narrower than the bar's row. Nothing in ActionUI JSON takes the title bar's place on Windows: a NavigationStack's header is inside the window's content and a sheet opens within the window, under the title bar, so no "Requested by" line is needed elsewhere.
- Every new window takes the keyboard focus. `show` says so in its description.
- `show` has no `pdf` kind, and kind `file` shows what ActionUI's own views can, as on Linux. Of the add-ons, RichText, CachedImage and Diff are there.
- `notify` shows its notice in a small window of its own at the bottom right of the screen, above the taskbar, where Windows shows its notifications: it stays on top, is not in the taskbar or Alt+Tab, never takes the focus, and goes after `duration_s` or when clicked. It is not a Windows notification: those need an app identity that an unzipped program does not have.
- `pick_path` uses the Windows file dialogs.
- `screenshot` of ActionUI JSON draws it in a window placed past the edge of every monitor and left out of the taskbar and Alt+Tab, so nothing shows and the focus stays where it is. A WebView's page is drawn from WebView2's own capture, in both kinds of screenshot.
- Windows has no SIGTERM, SIGHUP or SIGINT for a program a client starts with pipes: the session ends when the client closes the server's input. A client that ends the process without closing the input first leaves no kept windows.
- Kept windows come back at their places and sizes when the place is still on a monitor, else where Windows puts them. A window that was minimized comes back where Windows puts it, and one that was maximized comes back as a normal window that covers the screen. The kept windows' process is a second `actionui-mcp.exe`, with no console and in a process group of its own; while it runs, its folder's files are in use and cannot be replaced (see Install on Windows).
- Without a desktop session (over SSH), the server still starts and answers: `validate_ui` and the resources work, and the tools that show a window, and `screenshot`, say there is no graphical session.

### Install on Windows

The Windows package is a folder and a zip: `bin\actionui-mcp.exe` with its manifest and the DLLs it needs (the WinUI shim, the Windows App SDK bootstrapper, the Swift runtime and WebView2's component), the element schemas in `share\actionui\schemas\` and the element reference in `share\actionui\docs\`, which the server finds from its own place, and the licenses. Build it on Windows from the repository root, with the tools that `ActionUIWinUI/README.md` lists (Requirements):

```bat
python Scripts\ci-windows.py winui --install-runtime --quick --mcp-package --results ci-results
```

It builds and tests the renderer and the server, builds the server for release, checks the package by starting its server from an empty folder, and writes `.build\ci-windows-package\actionui-mcp-<version>-windows-<arch>.zip` with its `.zip.sha256`. `--install-runtime` is needed once per user.

The machine needs Windows 11 (x64 or Arm64) and the Windows App SDK runtime 2.7 (Microsoft's Windows App SDK runtime installer, or `--install-runtime` above); web pages need the WebView2 runtime, which Windows 11 has. Install per user, with no administrator rights: unpack the zip into `%LOCALAPPDATA%\Programs\ActionUI MCP` and register the server with its full path. In PowerShell:

```powershell
$zip = ".build\ci-windows-package\actionui-mcp-<version>-windows-<arch>.zip"
(Get-FileHash -Algorithm SHA256 $zip).Hash.ToLower()    # compare with the .zip.sha256 file
Expand-Archive $zip -DestinationPath "$env:LOCALAPPDATA\Programs\ActionUI MCP"
claude mcp add --scope user actionui -- "$env:LOCALAPPDATA\Programs\ActionUI MCP\actionui-mcp-<version>-windows-<arch>\bin\actionui-mcp.exe"
```

Each version unpacks into a folder of its own. To update, unpack the new version beside the old one, register the new path (`claude mcp remove --scope user actionui`, then the add command above), and remove the old folder once no kept window of the old version is open: Windows does not let a program's files be deleted while it runs.

The client setup below is the same on Windows with that path.

## Build

```sh
swift build                      # debug; the binary is at "$(swift build --show-bin-path)/actionui-mcp"
swift build -c release
```

Run builds and tests with the sandbox off, as for ActionUIViewer.

The installer package (a notarizable `.pkg` that puts the server and its resource bundles in `/usr/local/libexec/actionui-mcp/`) is built with PackageBuilder.app from `installer/`; see `installer/README.md`.

## Configure a client

The examples use the installed server, `/usr/local/libexec/actionui-mcp/actionui-mcp`; for a build from this checkout, use the absolute path `swift build --show-bin-path` prints. Every client below starts the server itself and reads its server list only when a session starts, so start a new session after adding it.

Each client decides which folders see a server, and the defaults differ:

| Client | The add command writes to | A project's own file | Seen from subfolders | Trust step for a project's file |
|---|---|---|---|---|
| Claude Code | this project only (`local` scope), unless `--scope user` or `--scope project` | `.mcp.json` at the repository root | yes, inside a git repository | each person approves its servers once |
| Codex | always the user file, `~/.codex/config.toml` | `.codex/config.toml` | yes | loaded only for a trusted project |
| opencode 1.18 | asks: the current project or global | `opencode.json` at the repository root | yes, up to the git root | none |

For a server meant for every project, as this one usually is, install it per user: `--scope user` in Claude Code, the default in Codex, Global in opencode.

### Claude Code

```sh
claude mcp add --scope user actionui -- /usr/local/libexec/actionui-mcp/actionui-mcp
```

Without `--scope`, `claude mcp add` uses the `local` scope: the server is stored in `~/.claude.json` under the project the command ran in, and only sessions started there see it. Inside a git repository that project is the repository, subfolders included; outside one it is that exact folder, so a server added from your home folder is not seen in any folder below it. A session started anywhere else lists no `actionui` server in `/mcp` and reports no error.

- `claude mcp get actionui` prints the scope that applies in the current folder (`Local config`, `Project config` or `User config`); `claude mcp list` lists the servers seen there.
- To fix a server added with the default scope, add it again with `--scope user`. The old entry can stay, since it starts the same server; to remove it, run `claude mcp remove actionui --scope local` from the folder it was added in. When one name is in several scopes, `local` wins over `project`, and `project` over `user`.
- `--scope project` writes `.mcp.json` at the repository root for committing, so everyone working in the repository gets the server; Claude Code asks each person to approve it on first use. The path inside is absolute, which suits the installed server, whose path is fixed.
- Environment variables go after the name, since `-e` takes several values and would take the name as one: `claude mcp add --scope user actionui -e ACTIONUI_MCP_LABEL=my-project -- /usr/local/libexec/actionui-mcp/actionui-mcp`.
- Each tool call asks for permission by default. To let a tool run without asking, add its name to `permissions.allow` in `~/.claude/settings.json`, for example `"mcp__actionui__show"` (the name is `mcp__<server>__<tool>`); `"mcp__actionui"` allows every tool of the server.

### Codex

```sh
codex mcp add actionui -- /usr/local/libexec/actionui-mcp/actionui-mcp
```

`codex mcp add` always writes to `~/.codex/config.toml` (`$CODEX_HOME/config.toml` when that is set) and has no option for a project file. The entry it writes, with the timeout this server needs added by hand:

```toml
[mcp_servers.actionui]
command = "/usr/local/libexec/actionui-mcp/actionui-mcp"
tool_timeout_sec = 3600

[mcp_servers.actionui.env]
ACTIONUI_MCP_LABEL = "my-project"
```

- `tool_timeout_sec`: Codex ends a tool call after 60 seconds by default. `ask_user`, `pick_path` and dialog-mode `show_ui` wait for the user (dialogs up to their `timeout_s`, one hour by default), and `wait` waits for its own timeout, so raise the limit or a dialog the user is still reading fails on the Codex side.
- For one project only, put the same table in `.codex/config.toml` in the project (Codex looks in the current folder and the folders above it). Codex reads that file only when the project is trusted, `trust_level = "trusted"` under the project's entry in `[projects]` in `~/.codex/config.toml`; an untrusted project's file is skipped. `codex mcp add` cannot write that file, so edit it by hand.
- `/mcp` in a Codex session lists the servers it started.

### opencode

`opencode mcp add` (1.18) is interactive. It first asks where to write the server, then for its details: `Current project`, which is `opencode.json` at the repository root, or `Global`, `~/.config/opencode/opencode.json` (or `opencode.jsonc`). The entry, written by hand into either file:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "actionui": {
      "type": "local",
      "command": ["/usr/local/libexec/actionui-mcp/actionui-mcp"],
      "enabled": true,
      "environment": { "ACTIONUI_MCP_LABEL": "my-project" }
    }
  }
}
```

- opencode looks for a project's `opencode.json` from the current folder up to the git root, so a project server is seen from every subfolder of the repository and nowhere else. The global and project files are merged, and the project file wins where both set a value.
- There is no trust step: none is documented, and `opencode mcp list` starts a project's servers without asking, so a cloned repository's `opencode.json` runs its servers as soon as opencode runs in it.
- `opencode mcp list` shows the servers seen from the current folder and whether they connected.
- The opencode v2 configuration format puts servers under `mcp.servers` and turns them off with `"disabled": true` instead of `"enabled"`; its `opencode mcp add <name> -- <command>` writes to the project file by default, and `--global` to the global one. Check `opencode --version` and the format its documentation describes before copying the entry above.

### Other clients

Most clients take a JSON entry of this shape, in a file of their own:

```json
{
  "mcpServers": {
    "actionui": {
      "command": "/usr/local/libexec/actionui-mcp/actionui-mcp",
      "env": { "ACTIONUI_MCP_LABEL": "my-project" }
    }
  }
}
```

### Install the skill

An agent writes better ActionUI JSON for `show_ui` with the actionui skill, which teaches the format with examples and patterns; without it, the agent reads the same reference through `actionui_docs`. The skill comes from this checkout in three variants (see `Skill/README.md`): `claude` for Claude Code (`python3 Skill/install_skill.py claude --user`), `capable` for other large models (Codex, Gemini and the like: a SKILL.md to put in the model's instructions, such as an `AGENTS.md`), and `lite` for small local models. A skill installed separately may describe an older or newer ActionUI than the server's; the server's own `actionui_docs` pages and `validate_ui` always match it.

### Environment variables

- `ACTIONUI_MCP_LABEL` - text shown after the client name in every title bar.
- `ACTIONUI_MCP_LOG_LEVEL` - `error`, `warning` (default), `info`, or `debug`; the log goes to stderr.
- `ACTIONUI_MCP_KEEP_JSON_FILES=1` - keep each window's generated ActionUI JSON file in the temporary folder (the path is logged), so it can be inspected or rendered with ActionUIViewer, and keep the folder when the session ends. Without it the session folder, screenshots included, is removed at the end of the session.
- `ACTIONUI_MCP_SCHEMA_DIR` - another element schemas directory to validate against. By default the server uses the schemas in `ActionUI_ActionUIVerifier.bundle` next to the executable (on Linux, `share/actionui/schemas/` in its package, else the checkout's), plus add-on schemas from that folder's `add-ons/<AddOn>/` or the ActionUI checkout. A Linux package reads only the add-on schemas it ships. Without schemas, only the property checks are skipped.
- `ACTIONUI_MCP_ALLOW_SECURE_FIELDS=1` - lets `show_ui` use SecureField. Off by default, because everything the user enters is sent to the agent.
- `ACTIONUI_MCP_TEST_PRESS=<button title>` and `ACTIONUI_MCP_TEST_ACTION=<actionID>@<viewID>` - debug builds only: 1.5 seconds after a window opens, press that dialog button or fire that action. For the live test.
- `ACTIONUI_MCP_TEST_NOTICE_CAPTURE=1` - debug builds only: save a PNG of each `notify` notice and log its path, to check the layout.
- `ACTIONUI_MCP_TEST_SAVE_DIR=<folder>` - debug builds only: 1.5 seconds after a `show` window opens, save its content as the Save button does, into that folder under the name the save panel would offer. For the live test.
- `ACTIONUI_MCP_TEST_REHOST_REPORT=<path>` - debug builds only: the kept-windows process writes what it shows (pid, titles, frames, values, row counts) to that file and closes its windows a second later. For the live test.

## Layout

- `Info.plist` - linked into the macOS executable as its `__TEXT,__info_plist` section, so the menu bar names the server "ActionUI MCP" instead of its file name (the Dock still shows the file name).
- `Sources/MCPStdio/MCPStdio.swift` - the protocol layer in one file: newline-delimited JSON-RPC in both protocol eras (the stateless 2026-07-28 revision with `server/discover` and per-request `_meta`, and the `initialize` handshake of 2025-11-25, 2025-06-18 and 2024-11-05), tools, concurrent calls, cancellation, progress heartbeats, and a stdout guard that points descriptor 1 at stderr so stray prints cannot corrupt the protocol. Foundation only, no ActionUI code.
- `Sources/ActionUIMCP/` - the executable: `main.swift` (setup), `HostLogger.swift` (stderr log with load capture), `DocsResources.swift` (element reference as MCP resources), `WindowHost.swift` (open windows, action routing, event queue, values), `WindowHost+Dialogs.swift` (dialog sessions), `WindowHost+Panels.swift` (`pick_path`), `WindowHost+Capture.swift` (saved screenshots), `WindowPlatform.swift` (what the host needs from the windowing system), `AppKitPlatform.swift` and its extensions (that layer on macOS: windows, the mark under their title bar, on `show` windows a bar with its buttons, capture, the panels, and `notify`), `AdwaitaPlatform.swift` and its extensions (that layer on Linux, with the mark and the bottom bar), `WinUIPlatform.swift` and its extensions (that layer on Windows, with the mark, the bar and `notify`), `KeptWindows.swift` (the hand-off of kept windows), `KeeperLauncher.swift`, `KeptWindowKeeper.swift`, `KeptWindowKeeperLinux.swift` and `KeptWindowKeeper+Windows.swift` (the `--rehost` process; on Windows its launcher too), `CannedUI.swift` (the ActionUI JSON the canned tools generate), `ShowSaving.swift` (what a `show` window's Save writes), `AgentUI.swift` (checks and dialog chrome for agent-written ActionUI JSON), `Verifier.swift` (the ActionUIVerifier setup), `Tools.swift`, `ToolsUI.swift` and `ToolsDocs.swift` (tool definitions and handlers; `actionui_docs` reads the same pages as the resources).

## Tests

```sh
swift test                                                              # protocol layer
/usr/bin/python3 Tests/live_session.py "$(swift build --show-bin-path)/actionui-mcp"   # real windows
```

The live test needs a graphical login session (a locked screen is fine) and a debug build. On Linux, build with `--only-use-versions-from-resolved-file --manifest-cache none` (see Install on Linux) and run the live test from inside the desktop session, or give it that session's `XDG_RUNTIME_DIR`, `WAYLAND_DISPLAY` and `DBUS_SESSION_BUS_ADDRESS`; it skips the checks of what Linux does not have.
