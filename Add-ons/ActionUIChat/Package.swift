// swift-tools-version: 6.0
//
// ActionUIChat - an optional ActionUI add-on, packaged as a Swift package.
//
// The products are static libraries that compile against ActionUI's public API. They do NOT
// embed ActionUI: SPM builds ActionUI once and the host app links it, so the add-on only
// references ActionUI's symbols (resolved at the host's final link) - the same "compile
// against, do not link" relationship the standalone xcodegen project expresses with
// link: false.
//
// The chat implementation itself lives in the standalone ChatView package (a sibling repo):
// the component owns the transcript, store, transports, and views. This add-on is the thin
// ActionUI wrapper: the `Chat` element (JSON properties -> ChatConfiguration, action-ID
// callbacks via the component's host-event sink, states["content"] / states["config"]
// exposure through ChatContentSource) plus per-transport register shims that preserve the
// established module split:
//   - ActionUIChatCore  - the `Chat` element glue; re-exports ChatView (the component).
//   - ActionUIChatACP   - registers the component's ACP transports: `"protocol": "acp"` (macOS, the
//                         agent is a subprocess) and `"protocol": "acp-remote"` (every platform, the
//                         agent lives on another machine behind a chatview-acp-bridge).
//   - ActionUIChatOpenAI - registers the OpenAI SSE transport: `"protocol": "openai-sse"`.
//   - ActionUIChat      - the umbrella: depends on Core + every bundled transport shim; its
//                         register() wires them all, preserving the single-import experience.
// A host links a transport module and calls its register() to make that protocol available;
// the strong reference from register() is what pulls the module's archive in at link time.

import PackageDescription

let package = Package(
    name: "ActionUIChat",
    platforms: [
        .macOS("14.6"),
        .iOS("17.6"),
        .visionOS("2.6"),
    ],
    products: [
        // The umbrella: element + every bundled transport, one import, one register(). The
        // default product for a host that just wants "everything the add-on ships".
        .library(name: "ActionUIChat", targets: ["ActionUIChat"]),
        // Core only: the element + the component (with its built-in `local` / `local-p2p`
        // transports and the registry). A host links this plus the transport modules it wants.
        .library(name: "ActionUIChatCore", targets: ["ActionUIChatCore"]),
        // The ACP transport shim (add on top of Core for `"protocol": "acp"` / `"acp-remote"`).
        .library(name: "ActionUIChatACP", targets: ["ActionUIChatACP"]),
        // The OpenAI SSE transport shim (add on top of Core for `"protocol": "openai-sse"`).
        .library(name: "ActionUIChatOpenAI", targets: ["ActionUIChatOpenAI"]),
        // Resource-only docs product, mirroring core ActionUIDocumentation. A client that links
        // this gets the add-on's schema doc + insert template copied into its bundle.
        .library(name: "ActionUIChatDocumentation", targets: ["ActionUIChatDocumentation"]),
    ],
    dependencies: [
        .package(path: "../.."),                // the ActionUI package at the repo root
        // The standalone chat component in its own repo (github.com/abra-code), which itself
        // depends on RichText, AsyncImageCache, and DiffView. Consumed as a versioned release.
        // 0.2.6 WAS the floor (see 0.4.0 below, which supersedes it), and it was a hard one: it was
        // the actual fix for the AppKit layout-loop crash that kills the host app mid-answer, after
        // three releases that were not. The cause is a scroller-width loop - a legacy
        // (non-overlay) vertical scroller takes 17pt from the content, so when the transcript's
        // height lands within a line of the viewport's, showing the scroller rewraps the rows enough
        // to make it unnecessary and hiding it makes it necessary again, forever. 0.2.6 reserves the
        // scroller so the content width cannot change. Note that 0.2.1, 0.2.3 and 0.2.5 were each
        // committed as the fix for this same crash and none of them were: they all addressed who
        // issues the scroll, and the loop runs with no scroll in flight at all.
        // Also carries 0.2.4 (the transcript no longer scrolls the reader back) and 0.2.2 (the
        // composer grows with its content under both submit policies).
        //
        // 0.4.5 is now the floor, and 0.4.0 is where the reason for it starts. 0.4.0 is hard for the
        // same reason 0.2.6 was - it undoes a
        // regression 0.2.6 itself introduced. That release replaced the transcript's scroll-to-bottom
        // maximum with `constrainBoundsRect(y: .greatestFiniteMagnitude)`, which does not clamp: it
        // returns the proposed size with the origin zeroed, so the maximum came back 0.0 on every
        // sample and the follow became a no-op that still reported success - suppressing the
        // ScrollViewProxy fallback. Every build from 0.2.6 through 0.3.0 leaves the transcript frozen
        // at the top of a streaming answer. Do not lower this floor to pick up an older fix.
        //
        // 0.4.5 adds the Kotlin/Android side of `acp-remote` plus two Swift fixes in the component's
        // ACP sources, both internal (so the bump is API-compatible with 0.4.0) and both worth having
        // in any host that registers `acp-remote`: the remote socket now installs a delegate that
        // refuses redirects on the WebSocket upgrade - the bridge token rides in the `initialize`
        // params, where no header-stripping rule protects it, so a followed 3xx hands a
        // code-execution credential to the redirect target, in cleartext if it says `ws://` - and the
        // reconnect loop now checks and clears its latch under one lock acquisition, closing a gap
        // where a socket dropping between the two saw the task still latched, declined to schedule a
        // new loop, and left the transport reconnecting forever with nothing running to reconnect it.
        .package(url: "https://github.com/abra-code/ChatView", from: "0.5.2"),
    ],
    targets: [
        // Core: the `Chat` element glue over the ChatView component.
        .target(
            name: "ActionUIChatCore",
            dependencies: [
                .product(name: "ActionUI", package: "ActionUI"),
                .product(name: "ChatView", package: "ChatView"),
            ],
            path: "Sources/Core"
        ),
        // The ACP register shim: forwards to the component's ChatViewACP.register(), which registers
        // `acp` (macOS only, the agent is a subprocess) and `acp-remote` (every platform).
        .target(
            name: "ActionUIChatACP",
            dependencies: [
                "ActionUIChatCore",
                .product(name: "ChatViewACP", package: "ChatView"),
            ],
            path: "Sources/ACP"
        ),
        // The OpenAI SSE register shim: forwards to ChatViewOpenAI.register().
        .target(
            name: "ActionUIChatOpenAI",
            dependencies: [
                "ActionUIChatCore",
                .product(name: "ChatViewOpenAI", package: "ChatView"),
            ],
            path: "Sources/OpenAI"
        ),
        // The umbrella: depends on Core + every bundled transport shim, re-exports Core, and
        // its register() wires them all. Existing hosts link this product unchanged.
        .target(
            name: "ActionUIChat",
            dependencies: [
                "ActionUIChatCore",
                "ActionUIChatACP",
                "ActionUIChatOpenAI",
            ],
            path: "Sources/Umbrella"
        ),
        // Bundles this add-on's Documentation/ (the per-element .md schema doc and .json insert
        // template) as SPM resources, the same way the core ActionUIDocumentation target bundles
        // Documentation/Schemas + Documentation/Elements. Not linked into the add-on libraries.
        .target(
            name: "ActionUIChatDocumentation",
            path: "Documentation",
            sources: ["ActionUIChatDocumentation.swift"],
            resources: [
                .copy("Schemas"),
                .copy("Elements"),
            ]
        ),
        // Add-on tests: the umbrella wiring (element + every bundled transport registered),
        // the ChatConfig action-ID parsing / validate witness, and the host-event ->
        // actionHandler dispatch mapping. The component's own suites live in the ChatView repo.
        .testTarget(
            name: "ActionUIChatTests",
            dependencies: [
                "ActionUIChat",
                "ActionUIChatCore",
                .product(name: "ActionUI", package: "ActionUI"),
                .product(name: "ChatView", package: "ChatView"),
            ],
            path: "Tests"
        ),
    ]
)
