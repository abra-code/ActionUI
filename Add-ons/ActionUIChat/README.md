# ActionUIChat

An optional ActionUI add-on that provides a native **chat** element (`Chat`) - a transcript above a
composer, driven by a pluggable transport. It is the second exercise of ActionUI's public add-on
registration API (after `ActionUIQuickLook`), and follows the same "compile against core, do not link
it; the host links and calls `register()`" pattern.

The element is GENERIC: the same `Chat` backs AI-agent chat and person-to-person chat. The transport
(selected by `protocol` in the element's non-visual `config` block) and the appearance differ, not the
view. See `Private/chat-element-design.md` for the full architecture and the milestone plan (M1-M6).

## Status: M1-M3

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

Later milestones add the SSE transports and dual alignment / a real two-party transport (M4), and the
advanced agentic side panels - plans, terminals, diff viewer, slash commands, multi-session (M5).

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

The element manages its own transcript model internally (a `ChatStore`), so M1 does not expose a single
scalar `value`; host interaction is via the action IDs.

## Internal architecture

Four layers, transport at the bottom, SwiftUI at the top, a router in the middle (the key idea):

- `ChatTransport` (`ChatTransport.swift`) - speaks one wire protocol, emits a normalized `ChatEvent`
  stream, accepts normalized `ChatCommand`s. Shipped: `LocalChatTransport` (scripted; also the
  `agentic` demo turn) and `ACPChatTransport` (`Sources/ACP/`, macOS - `ACPConnection.swift` is the
  stdio JSON-RPC framing, `ACPChatTransport.swift` is the ACP method vocabulary and the
  `session/update` demux, kept in one file on purpose).
- `ChatStore` (`ChatStore.swift`) - the `@MainActor` source of truth. Its `route(_:)` is the
  **pre-filter**: chat text -> transcript, thoughts and tool-call cards -> transcript items styled per
  the `surfaces` config, permission requests -> the pending-approval queue, system / error -> their own
  items. A non-agentic transport never emits the richer events, so the same code renders a plain
  conversation with no special cases.
- `ChatRootView` (`ChatRootView.swift`) - the transcript (`ScrollView` + `LazyVStack`, auto-scroll) and
  the composer.
- `ChatModel.swift` / `ChatConfig.swift` - the transport-agnostic value types and the JSON config.

## Design: compiles against ActionUI, does not link it

Like `ActionUIQuickLook`, this target is a **static library** that depends on ActionUI for its Swift
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

`Package.swift` makes this a Swift package (macOS / iOS / visionOS). A host adds it as a package
dependency and links the `ActionUIChat` product alongside ActionUI:

```swift
.package(path: "Add-ons/ActionUIChat")
// ...
.product(name: "ActionUIChat", package: "ActionUIChat")
```

The `Apps/ActionUIViewer` aggregator links this add-on and registers it, so the viewer can preview
documents that use `Chat`.

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

- `project.yml` - xcodegen spec (static lib, ActionUI as `link: false` package dep).
- `Sources/ActionUIChat.swift` - Swift `register()` entry point + plain C `ActionUIChat_register()`.
- `Sources/Chat.swift` - the `ActionUIViewConstruction` element type (with the documented head comment).
- `Sources/ChatModel.swift` - transport-agnostic value types (ChatRole, ChatItem, ChatEvent, ChatCommand).
- `Sources/ChatConfig.swift` - JSON parsing + validation (visual `properties` and the non-visual `config` block).
- `Sources/ChatTransport.swift` - the transport protocol + `LocalChatTransport` + the selection factory.
- `Sources/ACP/ACPConnection.swift` - newline-delimited JSON-RPC 2.0 over a subprocess's stdio (macOS).
- `Sources/ACP/ACPChatTransport.swift` - the ACP transport: capability negotiation, session lifecycle,
  the `session/update` -> `ChatEvent` demux, and the permission round-trip.
- `Sources/ChatStore.swift` - the `@MainActor` store + the router (pre-filter).
- `Sources/ChatRootView.swift` - the transcript + composer SwiftUI surface (message, thought, tool-call,
  image rows; the permission approval card).
- `Documentation/Schemas/Chat.md` - element schema doc; `Documentation/Elements/Chat.json` - insert template.
- `Documentation/ActionUIChatDocumentation.swift` - `Bundle.module` accessor for the docs product.
- `Schemas/Chat.json` - verifier schema (auto-discovered).
- `Examples/Chat.json` - a sample view using the element; `Examples/ChatAgentic.json` - the scripted
  agentic demo; `Examples/ChatACP.json` - a live ACP session (OpenCode).
