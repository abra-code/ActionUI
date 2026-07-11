# ActionUIChat

An optional ActionUI add-on that provides a native **chat** element (`Chat`) - a transcript above a
composer, driven by a pluggable transport. It is the second exercise of ActionUI's public add-on
registration API (after `ActionUIQuickLook`), and follows the same "compile against core, do not link
it; the host links and calls `register()`" pattern.

The element is GENERIC: the same `Chat` backs AI-agent chat and person-to-person chat. The transport
(selected by `protocol` in the element's non-visual `config` block) and the appearance differ, not the
view. See `Private/chat-element-design.md` for the full architecture and the milestone plan (M1-M6).

## Status: M1-M3 + openai-sse

Landed so far:

- **M1** - the `local` transport (a scripted echo backend) and a single-alignment transcript with
  streaming - append, stream deltas, finalize - plus auto-scroll and a config-driven composer submit
  policy.
- **M2** - streaming Markdown message bodies (rendered by the sibling `RichText` component) and
  standalone image items (rendered by the sibling `AsyncImageCache`).
- **M3** - the agentic layer. Transport-agnostic surfaces: streamed reasoning folded behind a
  "Thoughts" disclosure, tool-call cards that mutate in place through their pending / in-progress /
  completed / failed lifecycle, and a permission gate that pins an approval card above the composer
  (routed by the `surfaces` property; the local transport's `"reply": "agentic"` style demos them all
  with no wire protocol). And the **ACP transport** (macOS): the element launches any
  [Agent Client Protocol](https://agentclientprotocol.com) agent as a subprocess (newline-delimited
  JSON-RPC over stdio), negotiates capabilities (advertising no fs / terminal services), opens a
  session, demuxes the `session/update` stream onto those surfaces, wires
  `session/request_permission` to the approval card, and maps Stop to `session/cancel`. Validated
  against OpenCode (`["opencode", "acp"]`).

- **openai-sse transport** (all platforms) - the `ActionUIChatOpenAI` module streams an
  OpenAI-compatible `/v1/chat/completions` endpoint (llama-server, `mlx_lm.server`, or any compatible
  server), so plain streaming chat needs no agent process. Reasoning (`reasoning_content`) folds into
  thoughts, `tool_calls` render as completed cards plus a "not executed here" notice (the tool loop is
  the agent layer's job), and the final `usage` chunk drives the status-bar token count. `model: "auto"`
  resolves the loaded model from `GET {baseURL}/models`.

Later milestones add dual alignment / a real two-party transport (M4) and the advanced agentic side
panels - plans, terminals, diff viewer, slash commands, multi-session (M5).

## What it adds

A `Chat` element, usable from JSON like any built-in:

```json
{ "type": "Chat", "id": 80,
  "config": { "protocol": "local" },
  "properties": {
    "appearance": { "alignment": "single", "showRoleLabels": true },
    "input": { "placeholder": "Message", "submitOn": "return" },
    "sendActionID": "chat.send",
    "messageActionID": "chat.message" } }
```

- `config`: the element's NON-VISUAL operational settings (a sibling of `properties` - properties model
  SwiftUI modifiers, config carries what the element does). Hosts can inject runtime/session-specific
  values with `setElementConfig` between loading a document and showing it (see `DemoApp/`).
- `config.protocol`: the transport. `local` (default) streams a scripted reply (`transport.reply`:
  `echo`, `markdown`, or `agentic`); `acp` launches the ACP agent named by `transport.command` (macOS);
  `openai-sse` / `anthropic-sse` / `custom` arrive in later milestones (and fall back to `local`).
- `appearance.alignment`: `single` (M1 default - leading / full-width, parties by tint + label) or
  `dual` (incoming leading, outgoing trailing - honored in M4).
- `input.submitOn`: `return` (default), `modifier-return` (multiline; Cmd+Return submits), or
  `shift-return-newline`. This solves the Cmd+Return composer gap inside the element.
- Action IDs (`sendActionID`, `stopActionID`, `messageActionID`, `errorActionID`) dispatch host-facing
  events through `ActionUIModel.actionHandler`, exactly like `Button`.

The element manages its own transcript model internally (a `ChatStore`), so it exposes no single scalar
`value`; host interaction is via the action IDs. The session transcript is DATA (a serializable
`ChatTranscript`): a host persists it incrementally as it happens through `entryActionID` (fired per
finalized entry), and restores a saved session at runtime by injecting it into `states["content"]` (via
`setElementState` / `setElementStateFromString`, after the interface is built) - the same place Table /
List keep their content, not a document property. `readOnly` is the read-only viewer mode.

## Internal architecture

Four layers, transport at the bottom, SwiftUI at the top, a router in the middle (the key idea):

- `ChatTransport` (`Sources/Core/ChatTransport.swift`) - speaks one wire protocol, emits a normalized
  `ChatEvent` stream, accepts normalized `ChatCommand`s. `LocalChatTransport` (scripted; also the
  `agentic` demo turn) and `LocalP2PTransport` (the scripted person-to-person / group backend behind
  `local-p2p`) are built in and ship in Core. `ACPChatTransport` lives in its own
  module (`Sources/ACP/`, macOS - `ACPConnection.swift` is the stdio JSON-RPC framing,
  `ACPChatTransport.swift` is the ACP method vocabulary and the `session/update` demux, kept in one file
  on purpose). `OpenAIChatTransport` (`Sources/OpenAI/`) streams an OpenAI-compatible
  `/v1/chat/completions` endpoint (SSE line parser; owns the conversation array since the wire is
  stateless). A transport is built by the factory a module registers for its protocol name (see below).
- `ChatTransportRegistry` (`Sources/Core/ChatTransportRegistry.swift`) - the `@MainActor` table mapping a
  protocol name to its factory. `local` is reserved; the element resolves its transport here when the
  chat starts, degrading an unregistered name to `local` with a logged reason.
- `ChatStore` (`ChatStore.swift`) - the `@MainActor` source of truth. Its `route(_:)` is the
  **pre-filter**: chat text -> transcript, thoughts and tool-call cards -> transcript items styled per
  the `surfaces` config, permission requests -> the pending-approval queue, system / error -> their own
  items. A non-agentic transport never emits the richer events, so the same code renders a plain
  conversation with no special cases.
- `ChatRootView` (`ChatRootView.swift`) - the transcript (`ScrollView` + `LazyVStack`, auto-scroll) and
  the composer.
- `ChatModel.swift` / `ChatConfig.swift` - the transport-agnostic value types and the JSON config.

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

`Package.swift` makes this a Swift package (macOS / iOS / visionOS). Transports are split into modules so
a host links only what it needs:

- `ActionUIChat` - the **umbrella**: the element + every bundled transport, one import, one `register()`.
  This is the default; existing hosts use it unchanged.
- `ActionUIChatCore` - the element + the built-in `local` transport + the registry. Link this plus the
  transport modules you actually want.
- `ActionUIChatACP` - the ACP transport (macOS). Add on top of Core for `"protocol": "acp"`.
- `ActionUIChatOpenAI` - the OpenAI SSE transport (all platforms). Add on top of Core for `"protocol": "openai-sse"`.

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

- `Sources/Chat.swift` opens with a head comment (the `Sample JSON for Chat` block), the same way core
  views are documented.
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

- `project.yml` - xcodegen spec (static libs, ActionUI as `link: false` package dep).
- `Sources/Umbrella/ActionUIChat.swift` - the umbrella `register()` (element + every bundled transport) +
  plain C `ActionUIChat_register()`; re-exports Core.
- `Sources/Core/ActionUIChatCore.swift` - Core `register()` (element + `local`), `registerTransport(_:factory:)`,
  and the C `ActionUIChatCore_register()`.
- `Sources/Core/Chat.swift` - the `ActionUIViewConstruction` element type (with the documented head comment).
- `Sources/Core/ChatModel.swift` - transport-agnostic value types (ChatRole, ChatItem, ChatEvent, ChatCommand);
  the ChatEvent/ChatCommand contract and the types they carry are the frozen public transport API.
- `Sources/Core/ChatConfig.swift` - JSON parsing + validation (visual `properties` and the non-visual `config` block).
- `Sources/Core/ChatTransport.swift` - the `ChatTransport` protocol, `ChatTransportConfig`, `ChatLogger`, the
  factory type, and the built-in `LocalChatTransport`.
- `Sources/Core/ChatTransportRegistry.swift` - the `@MainActor` protocol-name -> factory registry.
- `Sources/ACP/ActionUIChatACP.swift` - the ACP module's `register()` (registers the `acp` factory) + C entry point.
- `Sources/ACP/ACPConnection.swift` - newline-delimited JSON-RPC 2.0 over a subprocess's stdio (macOS).
- `Sources/ACP/ACPChatTransport.swift` - the ACP transport: capability negotiation, session lifecycle,
  the `session/update` -> `ChatEvent` demux, and the permission round-trip.
- `Sources/OpenAI/ActionUIChatOpenAI.swift` - the OpenAI module's `register()` (registers the
  `openai-sse` factory) + C entry point.
- `Sources/OpenAI/OpenAIChatTransport.swift` - the OpenAI SSE transport: the streaming
  `/v1/chat/completions` request, the SSE-chunk demux (content / reasoning / tool_calls / usage), and
  model `auto` resolution.
- `Sources/Core/ChatStore.swift` - the `@MainActor` store + the router (pre-filter).
- `Sources/Core/ChatRootView.swift` - the transcript + composer SwiftUI surface (message, thought, tool-call,
  image rows; the permission approval card).
- `Documentation/Schemas/Chat.md` - element schema doc; `Documentation/Elements/Chat.json` - insert template.
- `Documentation/ActionUIChatDocumentation.swift` - `Bundle.module` accessor for the docs product.
- `Schemas/Chat.json` - verifier schema (auto-discovered).
- `Examples/Chat.json` - a sample view using the element; `Examples/ChatAgentic.json` - the scripted
  agentic demo; `Examples/ChatACP.json` - a live ACP session (OpenCode); `Examples/ChatOpenAI.json` - a
  live openai-sse session (local llama-server).
