// swift-tools-version: 6.0
//
// ActionUIChat - an optional ActionUI add-on, packaged as a Swift package.
//
// The product is a static library that compiles against ActionUI's public API. It does NOT
// embed ActionUI: SPM builds ActionUI once and the host app links it, so the add-on only
// references ActionUI's symbols (resolved at the host's final link) - the same "compile
// against, do not link" relationship the standalone xcodegen project expresses with
// link: false. The host links this product + ActionUI and calls ActionUIChat.register().

import PackageDescription

let package = Package(
    name: "ActionUIChat",
    platforms: [
        .macOS("14.6"),
        .iOS("17.6"),
        .visionOS("2.6"),
    ],
    products: [
        .library(name: "ActionUIChat", targets: ["ActionUIChat"]),
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
        .target(
            name: "ActionUIChat",
            dependencies: [
                .product(name: "ActionUI", package: "ActionUI"),
                .product(name: "RichText", package: "RichText"),
                .product(name: "DiffView", package: "ActionUIDiff"),
                .product(name: "AsyncImageCache", package: "AsyncImageCache"),  // CachedImage for image items
            ],
            path: "Sources"
        ),
        // Bundles this add-on's Documentation/ (the per-element .md schema doc and .json insert
        // template) as SPM resources, the same way the core ActionUIDocumentation target bundles
        // Documentation/Schemas + Documentation/Elements. Not linked into the add-on library.
        .target(
            name: "ActionUIChatDocumentation",
            path: "Documentation",
            sources: ["ActionUIChatDocumentation.swift"],
            resources: [
                .copy("Schemas"),
                .copy("Elements"),
            ]
        ),
        // Unit tests for the `local` transport's canned reply content (the reply styles and the
        // word-preserving streaming chunker). Message Markdown rendering is provided by the
        // RichText dependency and covered by its own test suite. `@testable` reaches internals.
        .testTarget(
            name: "ActionUIChatTests",
            dependencies: ["ActionUIChat"],
            path: "Tests"
        ),
    ]
)
