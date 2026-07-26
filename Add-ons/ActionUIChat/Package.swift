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
//   - ActionUIChatACP   - registers the component's ACP transport (macOS): `"protocol": "acp"`.
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
        // The ACP transport shim (add on top of Core for `"protocol": "acp"`).
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
        // 0.2.5 is the floor, and it is a hard one: it is the real fix for the AppKit layout-loop
        // crash that kills the host app mid-answer. Every earlier ChatView follows the stream
        // through ScrollViewProxy, whose pending actions SwiftUI applies from inside
        // NSHostingView.layout - which is the crash. 0.2.1 and 0.2.3 only deferred the call, so
        // they lowered the odds and crashed again; 0.2.5 moves the clip view directly instead.
        // Also carries 0.2.4 (the transcript no longer scrolls the reader back) and 0.2.2 (the
        // composer grows with its content under both submit policies).
        .package(url: "https://github.com/abra-code/ChatView", from: "0.2.5"),
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
        // The ACP register shim: forwards to the component's ChatViewACP.register() (macOS).
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
