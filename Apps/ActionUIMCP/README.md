# actionui-mcp (proof of concept)

A local MCP (Model Context Protocol) server that lets an AI agent open native macOS windows through ActionUI. The client starts it and talks JSON-RPC over stdin and stdout; windows live as long as the client session, except those opened with `keep: true` (see Kept windows).

Tools:

- `ask_user` - a dialog with a message, optional typed fields (text, multiline, number, integer, toggle, choice, multichoice, slider, date), and buttons. Blocks until the user answers and returns `{action, button, values}`, where `action` is `accept`, `cancel`, or `timeout`. Up to 30 fields; when they would not fit, they scroll. Sliders show their current value. A `multichoice` field is a column of checkboxes and answers with an array of the checked option values.
- `notify` - a short notice in a small floating panel at the top right of the screen. Returns at once; the notice takes no focus and goes away after `duration_s` (default 6) or a click. At most 4 on screen, fewer when they are tall; a new one replaces the oldest.
- `show` - a non-blocking viewer window for markdown, plain text, an image, a PDF or any Quick Look file, a video, a web page, a diff of two texts or files, a table (up to 50000 rows), or a chart. Returns `{window}` at once and does not take keyboard focus. A chart is a Chart element description in `chart`; it gets the checks of `show_document`, its warnings come back in `warnings`, and its Chart has id 1, so `update_window` can replace the description (`properties`) or stream data (`rows`, `append_rows`). `keep: true` keeps the window open after the session ends.
- `pick_path` - the system open or save panel. Blocks and returns `{action, paths}`.
- `show_document` - opens an ActionUI document the agent wrote, passed as a nested object or an absolute `.json` path. In `dialog` mode it adds a footer and a button row, waits, and returns every element's value by id. In `window` mode it returns `{window}` at once and queues the window's actions for `wait`; `keep: true` keeps the window open after the session ends. A document ActionUI cannot load is not shown; the load errors come back instead. What is refused is listed under Rules for agent documents.
- `validate_document` - checks a document without showing it: first element shape, unique positive ids, container keys placed inside `properties`, and refused elements; when those pass, the ActionUIVerifier library (the Swift twin of the Python verifier) checks element types, property names, value types, enum values, required properties, and platform suffixes; then ActionUI's own load errors. Errors also make `show_document` refuse the document; warnings (usually typos) come back with the result. Validation targets macOS.
- `wait` - returns the queued actions of live windows (`show_document` window mode), waiting for at least one or a timeout. Repeated actions on one element are merged; closing a window adds a `window.closed` event.
- `update_window` / `get_values` - write element properties, values and table rows into an open window, and read values back. `properties` (`{"<id>": {"<name>": value}}`, for example a Chart's `chart` description) is applied first, then values, then rows. Each entry gets the rules under Rules for agent documents; a refused one comes back in `problems`, and verifier warnings in `warnings`.
- `screenshot` - a PNG of an open window, or of a document rendered in a window that never appears on screen (to check a layout before showing it). Returns an image content block and saves the PNG; captured in-process, so it needs no Screen Recording permission and works with the screen locked. Rendered documents get `validate_document`'s checks first; their controls draw in the inactive style.
- `close_window` - closes a window.

Resources: ActionUI's element reference, for clients without the actionui skill: `actionui://docs/guide` (the JSON guide), `actionui://docs/elements` (the element index), `actionui://docs/elements/<Type>` (one element, core and add-ons) and `actionui://docs/templates/<Type>` (a JSON template). They are read from the documentation bundles that `swift build` places next to the executable; ship those bundles with the binary, or the resources are left out.

Every window shows "Requested by <client>" in its title bar.

## Rules for agent documents

Everything the user enters in a window goes back to the agent, and the agent, not the person who installed the server, writes the documents. So `show_document`, `validate_document` and `screenshot` (of a document) refuse anything that could keep input away from these checks or run code:

- `SecureField` is refused: whatever the user types in it would be sent to the agent. `ACTIONUI_MCP_ALLOW_SECURE_FIELDS=1` allows it.
- `LoadableView` is refused: the document it loads (from `url`, `filePath`, a bundle `name`, or a new value) would skip every check here. Put its content in the document instead.
- WebView `userScripts` are removed, with a warning: scripts from an agent are not run.
- Platform overrides (`"<key>:macos"`, repeated suffixes such as `"type:macos:macos"` included) are resolved before these checks, and the window loads the resolved document, so a suffixed key cannot carry a refused element past them.
- The rules reach elements nested anywhere, a Chart's annotation views included (the `content` of a mark's `annotation` in its `chart` description).
- The document is a JSON object (never a string) or an absolute `.json` path, at most 4 MB. Ids are unique positive integers, and container keys such as `children` sit next to `properties`, not inside it. Verifier errors and ActionUI load errors also refuse the document.

`update_window` applies the same rules to each entry:

- `properties`: no null value, no `userScripts`, no child-element key such as `children` or `content`, no `id` or `type`, and no `:<platform>` suffix (not resolved here); no property of a SecureField or LoadableView. A Chart's `chart` description is resolved and its annotation views checked as a document's elements are, and the window gets the resolved description. Each entry is then checked by the verifier as a one-element document.
- `values`: strings, numbers or booleans; a LoadableView's value (its source) cannot be set.

## Kept windows

A window opened with `keep: true` (`show`, or `show_document` in window mode) stays on screen when the session ends. The client ends a session by closing the server's stdin, then sends SIGTERM 2 seconds later and SIGKILL 2 seconds after that, so no window of the server process itself can stay. At the end of input (or on SIGTERM, SIGHUP or SIGINT) the server writes each kept window's document, frame, title, element values, table rows and the properties `update_window` set to a private temporary folder and starts a second copy of itself, `actionui-mcp --rehost <folder>`, in a session of its own, so the client's signals do not reach it. That process shows the same windows at the same places, with "(session ended)" after the provenance line, deletes the folder, and quits when its last window closes. The server waits up to 1.5 seconds for it to report that its windows are up, so the two sets overlap instead of flickering.

The copies are no longer connected to any agent: their buttons do nothing, and `wait`, `update_window` and the other tools cannot reach them. What is not an element value is not carried over: scroll positions, a video's playback position, a web page the user navigated to. A server killed with SIGKILL before its input closes cannot hand anything off.

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

- `tool_timeout_sec`: Codex ends a tool call after 60 seconds by default. `ask_user`, `pick_path` and dialog-mode `show_document` wait for the user (dialogs up to their `timeout_s`, one hour by default), and `wait` waits for its own timeout, so raise the limit or a dialog the user is still reading fails on the Codex side.
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

### Environment variables

- `ACTIONUI_MCP_LABEL` - text shown after the client name in every title bar.
- `ACTIONUI_MCP_LOG_LEVEL` - `error`, `warning` (default), `info`, or `debug`; the log goes to stderr.
- `ACTIONUI_MCP_KEEP_DOCUMENTS=1` - keep each generated window document in the temporary folder (the path is logged), so it can be inspected or rendered with ActionUIViewer.
- `ACTIONUI_MCP_SCHEMA_DIR` - another element schemas directory to validate against. By default the server uses the schemas in `ActionUI_ActionUIVerifier.bundle` next to the executable, plus add-on schemas from the bundle's `Schemas/add-ons/<AddOn>/` or the ActionUI checkout. Without schemas, only the property checks are skipped.
- `ACTIONUI_MCP_ALLOW_SECURE_FIELDS=1` - lets `show_document` use SecureField. Off by default, because everything the user enters is sent to the agent.
- `ACTIONUI_MCP_TEST_PRESS=<button title>` and `ACTIONUI_MCP_TEST_ACTION=<actionID>@<viewID>` - debug builds only: 1.5 seconds after a window opens, press that dialog button or fire that action. For the live test.
- `ACTIONUI_MCP_TEST_NOTICE_CAPTURE=1` - debug builds only: save a PNG of each `notify` notice and log its path, to check the layout.
- `ACTIONUI_MCP_TEST_REHOST_REPORT=<path>` - debug builds only: the kept-windows process writes what it shows (pid, titles, frames, values, row counts) to that file and closes its windows a second later. For the live test.

## Layout

- `Sources/MCPStdio/MCPStdio.swift` - the protocol layer in one file: newline-delimited JSON-RPC in both protocol eras (the stateless 2026-07-28 revision with `server/discover` and per-request `_meta`, and the `initialize` handshake of 2025-11-25, 2025-06-18 and 2024-11-05), tools, concurrent calls, cancellation, progress heartbeats, and a stdout guard that points descriptor 1 at stderr so stray prints cannot corrupt the protocol. Foundation only, no ActionUI code.
- `Sources/ActionUIMCP/` - the executable: `main.swift` (setup), `HostLogger.swift` (stderr log with load capture), `DocsResources.swift` (element reference as MCP resources), `WindowHost.swift` (windows, action routing, event queue, values), `WindowHost+Dialogs.swift` (dialog sessions), `WindowHost+Panels.swift` (open and save panels), `WindowHost+Capture.swift` (screenshots), `WindowHost+Notices.swift` (`notify`), `KeptWindows.swift` (the hand-off of kept windows and the `--rehost` process), `Documents.swift` (documents the canned tools generate), `AgentDocuments.swift` (checks and dialog chrome for agent documents), `Verifier.swift` (the ActionUIVerifier setup), `Tools.swift` and `ToolsDocuments.swift` (tool definitions and handlers).

## Tests

```sh
swift test                                                              # protocol layer
/usr/bin/python3 Tests/live_session.py "$(swift build --show-bin-path)/actionui-mcp"   # real windows
```

The live test needs a graphical login session (a locked screen is fine) and a debug build.
