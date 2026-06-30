# ActionUIChat

An optional ActionUI add-on that provides a native **chat** element (`Chat`) - a transcript above a
composer, driven by a pluggable transport. It is the second exercise of ActionUI's public add-on
registration API (after `ActionUIQuickLook`), and follows the same "compile against core, do not link
it; the host links and calls `register()`" pattern.

The element is GENERIC: the same `Chat` backs AI-agent chat and person-to-person chat. The transport
(selected by the `protocol` property) and the appearance differ, not the view. See
`Private/chat-element-design.md` for the full architecture and the milestone plan (M1-M6).

## Status: M1

This is **M1** of that plan: the `local` transport (a scripted echo backend) and a single-alignment
transcript with plain-text streaming - append, stream deltas, finalize - plus auto-scroll and a
config-driven composer submit policy. Later milestones add streaming Markdown (M2), the ACP transport
and tool/permission surfaces (M3), dual alignment and a real two-party transport (M4), and the advanced
agentic surfaces (M5).

## What it adds

A `Chat` element, usable from JSON like any built-in:

```json
{ "type": "Chat", "id": 80, "properties": {
    "protocol": "local",
    "appearance": { "alignment": "single", "showRoleLabels": true },
    "input": { "placeholder": "Message", "submitOn": "return" },
    "sendActionID": "chat.send",
    "messageActionID": "chat.message" } }
```

- `protocol`: the transport. `local` (default) echoes a streamed reply; `acp` / `openai-sse` /
  `anthropic-sse` / `custom` arrive in later milestones (and fall back to `local` for now).
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
  stream, accepts normalized `ChatCommand`s. M1 ships `LocalChatTransport`.
- `ChatStore` (`ChatStore.swift`) - the `@MainActor` source of truth. Its `route(_:)` is the
  **pre-filter**: chat text -> transcript, system / error -> their own items, and (later) tool calls /
  plans / permissions -> side surfaces. A non-agentic transport never emits the richer events, so the
  same code renders a plain conversation with no special cases.
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
- `Sources/ChatConfig.swift` - JSON property parsing + validation.
- `Sources/ChatTransport.swift` - the transport protocol + `LocalChatTransport` + the selection factory.
- `Sources/ChatStore.swift` - the `@MainActor` store + the router (pre-filter).
- `Sources/ChatRootView.swift` - the transcript + composer SwiftUI surface.
- `Documentation/Schemas/Chat.md` - element schema doc; `Documentation/Elements/Chat.json` - insert template.
- `Documentation/ActionUIChatDocumentation.swift` - `Bundle.module` accessor for the docs product.
- `Schemas/Chat.json` - verifier schema (auto-discovered).
- `Examples/Chat.json` - a sample view using the element.
