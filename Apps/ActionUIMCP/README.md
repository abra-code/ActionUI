# actionui-mcp (proof of concept)

A local MCP (Model Context Protocol) server that lets an AI agent open native macOS windows through ActionUI. The client starts it and talks JSON-RPC over stdin and stdout; windows live as long as the client session.

Tools:

- `ask_user` - a dialog with a message, optional typed fields (text, multiline, number, integer, toggle, choice, slider, date), and buttons. Blocks until the user answers and returns `{action, button, values}`, where `action` is `accept`, `cancel`, or `timeout`. Up to 30 fields; when they would not fit, they scroll. Sliders show their current value.
- `show` - a non-blocking viewer window for markdown, plain text, an image, a PDF or any Quick Look file, a video, a web page, a diff of two texts or files, or a table (up to 50000 rows). Returns `{window}` at once and does not take keyboard focus.
- `pick_path` - the system open or save panel. Blocks and returns `{action, paths}`.
- `show_document` - opens an ActionUI document the agent wrote, passed as a nested object or an absolute `.json` path. In `dialog` mode it adds a footer and a button row, waits, and returns every element's value by id. In `window` mode it returns `{window}` at once and queues the window's actions for `wait`. A document ActionUI cannot load is not shown; the load errors come back instead. SecureField is refused and WebView user scripts are removed.
- `validate_document` - checks a document without showing it: first element shape, unique positive ids, container keys placed inside `properties`, and refused elements; when those pass, the ActionUIVerifier library (the Swift twin of the Python verifier) checks element types, property names, value types, enum values, required properties, and platform suffixes; then ActionUI's own load errors. Errors also make `show_document` refuse the document; warnings (usually typos) come back with the result. Validation targets macOS.
- `wait` - returns the queued actions of live windows (`show_document` window mode), waiting for at least one or a timeout. Repeated actions on one element are merged; closing a window adds a `window.closed` event.
- `update_window` / `get_values` - write values and table rows into an open window, and read values back.
- `close_window` - closes a window.

Resources: ActionUI's element reference, for clients without the actionui skill: `actionui://docs/guide` (the JSON guide), `actionui://docs/elements` (the element index), `actionui://docs/elements/<Type>` (one element, core and add-ons) and `actionui://docs/templates/<Type>` (a JSON template). They are read from the documentation bundles that `swift build` places next to the executable; ship those bundles with the binary, or the resources are left out.

Every window shows "Requested by <client>" in its title bar.

## Build

```sh
swift build                      # debug; the binary is at "$(swift build --show-bin-path)/actionui-mcp"
swift build -c release
```

Run builds and tests with the sandbox off, as for ActionUIViewer.

## Configure a client

```json
{
  "mcpServers": {
    "actionui": {
      "command": "/absolute/path/to/actionui-mcp",
      "env": { "ACTIONUI_MCP_LABEL": "my-project" }
    }
  }
}
```

For Claude Code: `claude mcp add actionui -- /absolute/path/to/actionui-mcp`.

Environment variables:

- `ACTIONUI_MCP_LABEL` - text shown after the client name in every title bar.
- `ACTIONUI_MCP_LOG_LEVEL` - `error`, `warning` (default), `info`, or `debug`; the log goes to stderr.
- `ACTIONUI_MCP_KEEP_DOCUMENTS=1` - keep each generated window document in the temporary folder (the path is logged), so it can be inspected or rendered with ActionUIViewer.
- `ACTIONUI_MCP_SCHEMA_DIR` - another element schemas directory to validate against. By default the server uses the schemas in `ActionUI_ActionUIVerifier.bundle` next to the executable, plus add-on schemas from the bundle's `Schemas/add-ons/<AddOn>/` or the ActionUI checkout. Without schemas, only the property checks are skipped.
- `ACTIONUI_MCP_ALLOW_SECURE_FIELDS=1` - lets `show_document` use SecureField. Off by default, because everything the user enters is sent to the agent.
- `ACTIONUI_MCP_TEST_PRESS=<button title>` and `ACTIONUI_MCP_TEST_ACTION=<actionID>@<viewID>` - debug builds only: 1.5 seconds after a window opens, press that dialog button or fire that action. For the live test.

## Layout

- `Sources/MCPStdio/MCPStdio.swift` - the protocol layer in one file: newline-delimited JSON-RPC in both protocol eras (the stateless 2026-07-28 revision with `server/discover` and per-request `_meta`, and the `initialize` handshake of 2025-11-25, 2025-06-18 and 2024-11-05), tools, concurrent calls, cancellation, progress heartbeats, and a stdout guard that points descriptor 1 at stderr so stray prints cannot corrupt the protocol. Foundation only, no ActionUI code.
- `Sources/ActionUIMCP/` - the executable: `main.swift` (setup), `HostLogger.swift` (stderr log with load capture), `DocsResources.swift` (element reference as MCP resources), `WindowHost.swift` (windows, action routing, event queue, values), `WindowHost+Dialogs.swift` (dialog sessions), `WindowHost+Panels.swift` (open and save panels), `Documents.swift` (documents the canned tools generate), `AgentDocuments.swift` (checks and dialog chrome for agent documents), `Verifier.swift` (the ActionUIVerifier setup), `Tools.swift` and `ToolsDocuments.swift` (tool definitions and handlers).

## Tests

```sh
swift test                                                              # protocol layer
/usr/bin/python3 Tests/live_session.py "$(swift build --show-bin-path)/actionui-mcp"   # real windows
```

The live test needs a graphical login session (a locked screen is fine) and a debug build.
