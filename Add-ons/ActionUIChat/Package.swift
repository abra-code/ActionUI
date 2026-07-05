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
// Transport modules are split so a host links only what it needs (P0-6):
//   - ActionUIChatCore  - the `Chat` element, transcript / store / views, the built-in
//                         `local` transport, and the transport registry. `local` is the
//                         only built-in; every other protocol degrades to `local`.
//   - ActionUIChatACP   - the ACP transport (macOS): `"protocol": "acp"`.
//   - ActionUIChatOpenAI - the OpenAI SSE transport (all platforms): `"protocol": "openai-sse"`.
//   - ActionUIChat      - the umbrella: depends on Core + every bundled transport; its
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
        // Core only: the element + the built-in `local` transport + the registry. A host
        // links this plus the transport modules it actually wants.
        .library(name: "ActionUIChatCore", targets: ["ActionUIChatCore"]),
        // The ACP transport module (add on top of Core for `"protocol": "acp"`).
        .library(name: "ActionUIChatACP", targets: ["ActionUIChatACP"]),
        // The OpenAI SSE transport module (add on top of Core for `"protocol": "openai-sse"`).
        .library(name: "ActionUIChatOpenAI", targets: ["ActionUIChatOpenAI"]),
        // Resource-only docs product, mirroring core ActionUIDocumentation. A client that links
        // this gets the add-on's schema doc + insert template copied into its bundle.
        .library(name: "ActionUIChatDocumentation", targets: ["ActionUIChatDocumentation"]),
    ],
    dependencies: [
        .package(path: "../.."),                    // the ActionUI package at the repo root
        .package(path: "../../../RichText"),    // the sibling RichText component (renders message Markdown)
        .package(path: "../ActionUIDiff"),      // the sibling add-on whose DiffView product renders tool-card diffs
        .package(path: "../../../AsyncImageCache"), // the sibling image cache (CachedImage for image items)
    ],
    targets: [
        // Core: the element, transcript / store / views, models, `local` transport, registry.
        .target(
            name: "ActionUIChatCore",
            dependencies: [
                .product(name: "ActionUI", package: "ActionUI"),
                .product(name: "RichText", package: "RichText"),
                .product(name: "DiffView", package: "ActionUIDiff"),
                .product(name: "AsyncImageCache", package: "AsyncImageCache"),  // CachedImage for image items
            ],
            path: "Sources/Core"
        ),
        // The ACP transport: launches an Agent Client Protocol agent as a subprocess (macOS).
        // Depends on Core for the transport contract; registers the `acp` factory.
        .target(
            name: "ActionUIChatACP",
            dependencies: [
                "ActionUIChatCore",
                .product(name: "ActionUI", package: "ActionUI"),
            ],
            path: "Sources/ACP"
        ),
        // The OpenAI SSE transport: streams /v1/chat/completions (llama-server, mlx_lm.server,
        // any OpenAI-compatible endpoint). Cross-platform (URLSession). Registers `openai-sse`.
        .target(
            name: "ActionUIChatOpenAI",
            dependencies: [
                "ActionUIChatCore",
                .product(name: "ActionUI", package: "ActionUI"),
            ],
            path: "Sources/OpenAI"
        ),
        // The umbrella: depends on Core + every bundled transport, re-exports Core, and its
        // register() wires them all. Existing hosts link this product unchanged.
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
        // Core tests: the `local` transport's canned reply content and streaming chunker, the
        // store's router reductions and `surfaces` config, and the transport registry
        // (register / override / reserved / unknown-name degrade). `@testable` reaches internals.
        .testTarget(
            name: "ActionUIChatCoreTests",
            dependencies: [
                "ActionUIChatCore",
                .product(name: "ActionUI", package: "ActionUI"),
            ],
            path: "Tests/Core"
        ),
        // ACP tests: the JSON-RPC framing / correlation, the payload parsers, the
        // session/update demux and message segmentation, and the permission round-trip -
        // all without spawning a real agent. macOS-only content (guarded in the sources).
        .testTarget(
            name: "ActionUIChatACPTests",
            dependencies: [
                "ActionUIChatACP",
                "ActionUIChatCore",
                .product(name: "ActionUI", package: "ActionUI"),
            ],
            path: "Tests/ACP"
        ),
        // OpenAI tests: the pure SSE-chunk / usage / models / request-body parsers, plus
        // end-to-end streaming, non-200, disconnect, and cancel via a URLProtocol stub.
        .testTarget(
            name: "ActionUIChatOpenAITests",
            dependencies: [
                "ActionUIChatOpenAI",
                "ActionUIChatCore",
                .product(name: "ActionUI", package: "ActionUI"),
            ],
            path: "Tests/OpenAI"
        ),
        // Umbrella tests: assert ActionUIChat.register() wires the element + every bundled
        // transport (the single-import contract). `@testable` Core to read the registry.
        .testTarget(
            name: "ActionUIChatTests",
            dependencies: [
                "ActionUIChat",
                "ActionUIChatCore",
            ],
            path: "Tests/Umbrella"
        ),
    ]
)
