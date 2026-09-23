# actionui-mcp (proof of concept)

A local MCP (Model Context Protocol) server that lets an AI agent open native macOS windows through ActionUI. The client starts it and talks JSON-RPC over stdin and stdout; windows live as long as the client session.

Tools:

- `ask_user` - a dialog with a message, optional typed fields (text, multiline, number, integer, toggle, choice, slider, date), and buttons. Blocks until the user answers and returns `{action, button, values}`, where `action` is `accept`, `cancel`, or `timeout`.
- `show` - a non-blocking viewer window for markdown, plain text, an image, a PDF or any Quick Look file, a video, or a web page. Returns `{window}` at once and does not take keyboard focus.
- `close_window` - closes a window opened by `show`.

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
- `ACTIONUI_MCP_TEST_PRESS=<button title>` - debug builds only: presses that dialog button 1.5 seconds after the dialog opens. For the live test.

## Layout

- `Sources/MCPStdio/MCPStdio.swift` - the protocol layer in one file: newline-delimited JSON-RPC, `initialize` negotiation (2025-11-25, 2025-06-18, 2024-11-05), tools, concurrent calls, cancellation, progress heartbeats, and a stdout guard that points descriptor 1 at stderr so stray prints cannot corrupt the protocol. Foundation only, no ActionUI code.
- `Sources/ActionUIMCP/` - the executable: `main.swift` (setup), `WindowHost.swift` (windows, dialog sessions, value snapshots), `Documents.swift` (the ActionUI documents the tools generate), `Tools.swift` (tool definitions and handlers).

## Tests

```sh
swift test                                                              # protocol layer
/usr/bin/python3 Tests/live_session.py "$(swift build --show-bin-path)/actionui-mcp"   # real windows
```

The live test needs a graphical login session (a locked screen is fine) and a debug build.
