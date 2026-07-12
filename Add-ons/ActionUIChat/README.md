# ActionUIChat

An optional ActionUI add-on that provides a native **chat** element (`Chat`) - a transcript above a
composer, driven by a pluggable transport. It is the second exercise of ActionUI's public add-on
registration API (after `ActionUIQuickLook`), and follows the same "compile against core, do not link
it; the host links and calls `register()`" pattern.

The element is GENERIC: the same `Chat` backs AI-agent chat and person-to-person chat. The transport
(selected by `protocol`, host-injected at runtime into `states["config"]` - see "What it adds" below) and
the appearance differ, not the view.

## What's implemented

- **The `local` transport** (a scripted echo backend) and a single-alignment transcript with streaming -
  append, stream deltas, finalize - plus auto-scroll and a config-driven composer submit policy.
- **Streaming Markdown message bodies** (rendered by the sibling `RichText` component) and standalone
  image items (rendered by the sibling `CachedImage` from `AsyncImageCache`).
- **The agentic surfaces.** Transport-agnostic: streamed reasoning folded behind a "Thoughts" disclosure,
  tool-call cards that mutate in place through their pending / in-progress / completed / failed lifecycle,
  and a permission gate that pins an approval card above the composer (each routed by the `surfaces`
  property; the local transport's `"reply": "agentic"` style demos them all with no wire protocol).
- **Session-status surfaces.** The agent's evolving task plan pinned ABOVE the transcript (routed by
  `surfaces.plan`), plus a status line under the composer showing the session's model / mode and
  token / cost usage. The model / mode entries become MENUS when the agent offers choices: selecting
  sends `session/set_config_option` (with the spec's `session/set_mode` / `set_model` as fallbacks) and
  the display updates only on the agent's confirmation, never optimistically.
- **The composer slash-command menu.** When a transport advertises commands (ACP
  `available_commands_update`), typing `/` lists and filters them and a tap fills the draft; the command
  still sends as ordinary prompt text for the agent to interpret.
- **Agent-proposed file diffs**, rendered inside a tool card's detail as a real line diff - hunks,
  old / new line-number gutters, +/- markers - by the standalone **DiffView** package, which these
  tool cards consume (routed by `surfaces.diffs`; `hidden` drops them).
- **The ACP transport** (macOS): the element launches any [Agent Client Protocol](https://agentclientprotocol.com)
  agent as a subprocess (newline-delimited JSON-RPC over stdio), negotiates capabilities (advertising no
  fs / terminal services), opens a session, demuxes the `session/update` stream onto those surfaces,
  wires `session/request_permission` to the approval card, and maps Stop to `session/cancel`. Validated
  against OpenCode (`["opencode", "acp"]`) and claude-code-acp.
- **The openai-sse transport** (all platforms): the `ActionUIChatOpenAI` module streams an
  OpenAI-compatible `/v1/chat/completions` endpoint (llama-server, `mlx_lm.server`, or any compatible
  server), so plain streaming chat needs no agent process. Reasoning (`reasoning_content`) folds into
  thoughts, `tool_calls` render as completed cards plus a "not executed here" notice (the tool loop is
  the agent layer's job), and the final `usage` chunk drives the status-bar token count. `model: "auto"`
  resolves the loaded model from `GET {baseURL}/models`.
- **Session transcript persistence and restore.** The transcript is DATA (a serializable
  `ChatTranscript`): a host persists it incrementally through `entryActionID` (fired per finalized entry)
  and restores a saved session at runtime by injecting it into `states["content"]`. `readOnly` is a pure
  viewer mode (no composer, no transport).

Still to come: dual alignment / a real two-party transport, and the remaining advanced agentic surfaces
(terminals, multi-session).

## What it adds

A `Chat` element, usable from JSON like any built-in:

```json
{ "type": "Chat", "id": 80,
  "properties": {
    "appearance": { "alignment": "single", "showRoleLabels": true },
    "input": { "placeholder": "Message", "submitOn": "return" },
    "sendActionID": "chat.send",
    "messageActionID": "chat.message" } }
```

The document declares ONLY `properties` (appearance / roles / input / surfaces / action IDs / readOnly) -
there is no element-level config block anymore. The element is built INERT (composer disabled, no
transport) and a HOST injects the non-visual operational settings - `protocol` and `transport` - at
runtime into `states["config"]` via `setElementState`, after the element is built:

```swift
ActionUISwift.setElementState(windowUUID: windowUUID, viewID: 80, key: "config",
                               value: ["protocol": "local", "transport": ["echo": true]])
```

- `states["config"]`: the WHOLE injected object (not split across keys) - `protocol` selects the
  transport, `transport` is its protocol-specific settings. `local` (default) streams a scripted reply
  (`transport.reply`: `echo`, `markdown`, or `agentic`); `acp` launches the ACP agent named by
  `transport.command` (macOS); `openai-sse` streams an OpenAI-compatible endpoint named by
  `transport.baseURL`. A protocol whose module the host did not register degrades to `local` with a
  logged reason.
- The transport is built once a viable config arrives in `states["config"]`, then FROZEN for that
  element's lifetime - a later `states["config"]` update does not rebuild it; use a fresh `Chat` element
  to switch protocol or transport (see `DemoApp/`).
- `appearance.alignment`: `single` (default - leading / full-width, parties by tint + label) or `dual`
  (incoming leading, outgoing trailing - not yet honored).
- `input.submitOn`: `return` (default), `modifier-return` (multiline; Cmd+Return submits), or
  `shift-return-newline`. This solves the Cmd+Return composer gap inside the element.
- `surfaces`: routing for the agentic items - `toolCalls`, `thoughts`, `plan`, and `diffs` (see the
  schema doc for the accepted values of each).
- Action IDs (`sendActionID`, `stopActionID`, `messageActionID`, `errorActionID`, `approveToolActionID`,
  `entryActionID`) dispatch host-facing events through `ActionUIModel.actionHandler`, exactly like
  `Button`.
- `readOnly`: read-only viewer mode - hides the composer and menus and starts no transport (`protocol`
  may be omitted). Pair with a runtime `setElementState("content", ...)` to show a saved session.

The element manages its own transcript model internally (a `ChatStore`), so it exposes no single scalar
`value`; host interaction is via the action IDs. The session transcript is DATA (a serializable
`ChatTranscript`): a host persists it incrementally as it happens through `entryActionID` (fired per
finalized entry), and restores a saved session at runtime by injecting it into `states["content"]` (via
`setElementState` / `setElementStateFromString`, after the interface is built) - the same place Table /
List keep their content, not a document property. `properties.content` pre-populates a transcript for
previews / testing only, not the production restore path.

## Internal architecture

The chat implementation lives in the standalone **ChatView** package (a sibling repo); this add-on is
the thin ActionUI wrapper over it. Inside the component: four layers, transport at the bottom, SwiftUI
at the top, a router in the middle (the key idea):

- `ChatTransport` (ChatView `Sources/ChatView/ChatTransport.swift`) - speaks one wire protocol, emits a
  normalized `ChatEvent` stream, accepts normalized `ChatCommand`s. `LocalChatTransport` (scripted; also
  the `agentic` demo turn) and `LocalP2PTransport` (the scripted person-to-person / group backend behind
  `local-p2p`) are built in. `ACPChatTransport` lives in the component's `ChatViewACP` product (macOS -
  `ACPConnection.swift` is the stdio JSON-RPC framing, `ACPChatTransport.swift` is the ACP method
  vocabulary and the `session/update` demux, kept in one file on purpose). `OpenAIChatTransport`
  (`ChatViewOpenAI`) streams an OpenAI-compatible `/v1/chat/completions` endpoint (SSE line parser; owns
  the conversation array since the wire is stateless). A transport is built by the factory a module
  registers for its protocol name (see below).
- `ChatTransportRegistry` - the `@MainActor` table mapping a protocol name to its factory. `local` is
  reserved; the component resolves its transport here when the chat starts, degrading an unregistered
  name to `local` with a logged reason.
- `ChatStore` - the `@MainActor` source of truth. Its `route(_:)` is the **pre-filter**: chat text ->
  transcript, thoughts and tool-call cards -> transcript items styled per the `surfaces` config, the
  plan -> the pinned panel, permission requests -> the pending-approval queue, system / error -> their
  own items. A non-agentic transport never emits the richer events, so the same code renders a plain
  conversation with no special cases.
- `ChatView` (the component's public SwiftUI entry point) - the pinned plan panel, the transcript
  (`ScrollView` + `LazyVStack`, auto-scroll), and the composer with its slash-command menu and the
  status line (model / mode menus, token / cost usage). Tool-card diffs render through the standalone
  `DiffView` package.

This add-on contributes the element glue only: `Chat` (the `ActionUIViewConstruction` witness) maps the
document's `properties` to the component's typed `ChatConfiguration`, installs the host-event sink that
routes the component's `ChatHostEvent`s to the configured action IDs through `ActionUIModel.actionHandler`,
adapts the logger, and conforms `ViewModel` to the component's `ChatContentSource` so `states["content"]` /
`states["config"]` reach the component.

## Design: compiles against ActionUI, does not link it

Like `ActionUIQuickLook`, these targets are **static libraries** that depend on ActionUI for its Swift
module only (`link: false` in `project.yml`). The **host app links both** ActionUI and this add-on and
calls `register()` once at launch (Apple has no guaranteed pre-`main` hook for a statically linked Swift
type):

```swift
import ActionUIChat

// In your App init / applicationDidFinishLaunching, before building any window:
ActionUIChat.register()
```

A plain C entry point `ActionUIChat_register()` (`@_cdecl`) lets C / C++ / Objective-C hosts (e.g. OMC's
Abracode.framework) register without the Swift runtime; the caller forward-declares it.

## Consuming it

`Package.swift` makes this a Swift package (macOS / iOS / visionOS). It depends on ActionUI and on the
standalone `ChatView` component package, which itself depends on the sibling `RichText`,
`AsyncImageCache`, and `DiffView` components. Transports are split into modules so a host links only
what it needs:

- `ActionUIChat` - the **umbrella**: the element + every bundled transport, one import, one `register()`.
  This is the default; existing hosts use it unchanged.
- `ActionUIChatCore` - the element + the component (with its built-in `local` / `local-p2p` transports
  and the registry). Link this plus the transport modules you actually want.
- `ActionUIChatACP` - the ACP transport shim (macOS). Add on top of Core for `"protocol": "acp"`.
- `ActionUIChatOpenAI` - the OpenAI SSE transport shim (all platforms). Add on top of Core for `"protocol": "openai-sse"`.

The batteries-included path (everything the add-on ships) links the umbrella:

```swift
.package(path: "Add-ons/ActionUIChat")
// ...
.product(name: "ActionUIChat", package: "ActionUIChat")   // then ActionUIChat.register()
```

A la carte - Core plus only ACP, for example - links each module and calls each `register()`:

```swift
.product(name: "ActionUIChatCore", package: "ActionUIChat")   // ActionUIChatCore.register()
.product(name: "ActionUIChatACP",  package: "ActionUIChat")   // ActionUIChatACP.register()
```

A host can add its own protocol without touching the component: implement `ChatTransport` and call
`ActionUIChatCore.registerTransport("my-protocol") { config, logger in try MyTransport(config, logger) }`.

The `Apps/ActionUIViewer` aggregator links the umbrella `ActionUIChat` product and registers it, so the
viewer can preview documents that use `Chat`.

## Standalone static-library build (optional)

`project.yml` builds the add-on as a standalone static library with
[xcodegen](https://github.com/yonaskolb/XcodeGen), with ActionUI as a `link: false` (compile-only)
dependency:

```sh
cd Add-ons/ActionUIChat
xcodegen generate
xcodebuild -project ActionUIChat.xcodeproj -scheme ActionUIChat \
    -destination 'generic/platform=macOS' build
```

The `.xcodeproj` is generated from `project.yml` but committed, so it builds without xcodegen;
regenerate with `xcodegen generate` after editing `project.yml`.

## Documentation and verification

The add-on mirrors core ActionUI's documentation layout so the three doc/tooling systems pick it up
automatically:

- `Sources/Core/Chat.swift` opens with a head comment (the `Sample JSON for Chat` block), the same way
  core views are documented.
- `Documentation/Schemas/Chat.md` is the human-readable element doc derived from that comment;
  `Documentation/Elements/Chat.json` is the insert template (most common properties).
- The `ActionUIChatDocumentation` SPM product bundles `Documentation/` as resources, mirroring core
  `ActionUIDocumentation`, so a client that links it gets the docs copied into its app bundle.
- `Schemas/Chat.json` is the **verifier** schema. The ActionUI verifier auto-discovers `Add-ons/*/Schemas`
  (in-repo) and its own `schemas/add-ons/` (when packaged), so a document using the `Chat` element
  validates with no `--schema-dir` flag:

  ```sh
  python3 Tools/verifier/validate_actionui.py Add-ons/ActionUIChat/Examples/Chat.json
  ```

  `Skill/build_skill.py` and OMC's `update_appletbuilder.sh` copy these add-on docs + schemas into their
  packaged outputs.

## Files

- `project.yml` - xcodegen spec (static libs; ActionUI and ChatView as `link: false` package deps).
- `Sources/Umbrella/ActionUIChat.swift` - the umbrella `register()` (element + every bundled transport) +
  plain C `ActionUIChat_register()`; re-exports Core.
- `Sources/Core/ActionUIChatCore.swift` - Core `register()` (element + registry logger wiring),
  `registerTransport(_:factory:)`, the C `ActionUIChatCore_register()`, and the `@_exported import
  ChatView` that keeps the component's transport contract reachable through this module.
- `Sources/Core/Chat.swift` - the `ActionUIViewConstruction` element type (with the documented head
  comment) and `hostEventSink` (the ChatHostEvent -> actionHandler dispatch mapping).
- `Sources/Core/ChatConfig.swift` - action-ID parsing + `validate()` (the validateProperties witness);
  delegates the visual keys to the component's `ChatConfiguration`. The operational `protocol` +
  `transport` are not document-declared - a host injects them at runtime into `states["config"]`.
- `Sources/Core/ChatActionUIBridge.swift` - the ActionUILogger -> ChatLogger adapter and the `ViewModel`
  conformance to the component's `ChatContentSource`.
- `Sources/ACP/ActionUIChatACP.swift` - the ACP register shim (forwards to `ChatViewACP.register()`) + C entry point.
- `Sources/OpenAI/ActionUIChatOpenAI.swift` - the OpenAI register shim (forwards to
  `ChatViewOpenAI.register()`) + C entry point.

Everything else - the store, views, models, transports, registry, configuration - lives in the ChatView
package (see its own README).
- `Documentation/Schemas/Chat.md` - element schema doc; `Documentation/Elements/Chat.json` - insert template.
- `Documentation/ActionUIChatDocumentation.swift` - `Bundle.module` accessor for the docs product.
- `Schemas/Chat.json` - verifier schema (auto-discovered).
- `Examples/Chat.json` - a sample view using the element; `Examples/ChatAgentic.json` - the scripted
  agentic demo; `Examples/ChatACP.json` - a live ACP session (OpenCode); `Examples/ChatOpenAI.json` - a
  live openai-sse session (local llama-server); `Examples/ChatReadOnly.json` - a `readOnly` viewer over a
  pre-populated transcript.
- `DemoApp/` - a dedicated macOS demo app for the ACP transport (a launcher that resolves an agent
  through the login shell and hosts the session in a `Chat` element).
