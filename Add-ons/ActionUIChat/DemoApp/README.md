# ActionUIChatDemo

A dedicated macOS demo app for the ActionUIChat ACP transport: it launches a real
[Agent Client Protocol](https://agentclientprotocol.com) agent (OpenCode,
claude-code-acp, ...) as a subprocess and hosts the session in a `Chat` element -
streamed replies, collapsed thoughts, tool-call cards, and the permission gate.

## Why a dedicated app (and not another ActionUIAddOnTestApp resource)

- An ACP document is machine-specific (which agent binary, which working directory) and
  macOS-only (the agent is a subprocess). The shared test app's demos are committed
  static JSON that must render on macOS and iOS; a hardcoded `["opencode", "acp"]`
  would fail to spawn on most machines and silently degrade to the local transport on iOS.
- GUI apps do not inherit the user's shell PATH (agents typically live in
  `~/.opencode/bin`, `/opt/homebrew/bin`, ...), so a bare command name resolves in a
  terminal but not when the app is launched from Finder or Xcode. This host resolves the
  command through the user's login shell.
- Real ACP testing needs per-run choices - agent, working directory, restart / new
  session - which is a launcher UI, not a static document.

The app demonstrates the embedding story the ActionUI way: the UI is the STATIC bundled
`Resources/ChatDemo.json` (build-verified against the schemas, properties only - no
element-level config block), and the element is built INERT (no transport, disabled
composer) until the host injects the runtime/session-specific parts - `protocol` and the
resolved `transport.command` / `cwd` - into the element's `states["config"]`.
`ActionUISwift.loadView` registers the document's model tree synchronously and the
element's view is built lazily on first render, so calling
`ActionUISwift.setElementState(.. "config" ..)` between the two configures the Chat
element before it exists. No JSON is generated at runtime. The transport is built once
this config arrives and then frozen for that element's lifetime; the chat's action IDs
are observed through a host action handler (shown live in the session footer).

The scripted no-agent demos remain in ActionUIAddOnTestApp (`Chat.agentic.json` fakes a
full agentic turn with the local transport, no install required). From a terminal,
ActionUIViewer can also render `../Examples/ChatACP.json` directly, since a terminal
launch does inherit your PATH.

## Requirements

- macOS 14.6+.
- An ACP agent installed and authenticated, e.g. OpenCode (`opencode auth login`).

## Build

The `.xcodeproj` is generated from `project.yml` but committed, so it builds without
xcodegen:

```
xcodebuild -project ActionUIChatDemo.xcodeproj -scheme ActionUIChatDemo \
    -destination 'generic/platform=macOS' build
```

Regenerate with `xcodegen generate` only after editing `project.yml`.

## Use

1. Pick an agent from Presets (or type any argv; bare names are resolved through your
   login shell's PATH, absolute and `~` paths are used directly).
2. Pick the working directory the agent should operate on (the ACP session `cwd`).
3. Start Chat. Cmd+Return sends (the composer is `submitOn: "modifier-return"`, so
   Return inserts a newline).
4. Ask the agent to read or edit a file in the working directory to see tool-call cards
   stream their status, and the permission card appear for gated tools (approve or
   reject inline; the composer stays disabled while a permission is pending).
5. "New Session" restarts with the same configuration; "Configure..." returns to the
   launcher. Both tear the old chat down, which terminates the agent subprocess.

The footer shows the most recent action ID the chat fired at the host (`chat.send`,
`chat.message`, `chat.tool.approve`, ...) and a running count.
