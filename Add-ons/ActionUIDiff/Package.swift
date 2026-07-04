// swift-tools-version: 6.0
//
// ActionUIDiff - an optional ActionUI add-on, packaged as a Swift package.
//
// The ActionUIDiff product is a static library that compiles against ActionUI's public API. It does
// NOT embed ActionUI: SPM builds ActionUI once and the host app links it, so the add-on only
// references ActionUI's symbols (resolved at the host's final link) - the same "compile against, do
// not link" relationship the standalone xcodegen project expresses with link: false. The host links
// this product + ActionUI and calls ActionUIDiff.register().
//
// This package ships two consumable libraries: DiffView is the pure diff-viewer component (imports
// SwiftUI / Foundation only, no ActionUI) that ActionUIChat consumes directly for its tool-card
// diffs; ActionUIDiff adds the `Diff` element wrapper on top of it for JSON documents.

import PackageDescription

let package = Package(
    name: "ActionUIDiff",
    platforms: [
        .macOS("14.6"),
        .iOS("17.6"),
        .visionOS("2.6"),
    ],
    products: [
        // The pure component (no ActionUI). Consumed directly by ActionUIChat, like RichText.
        .library(name: "DiffView", targets: ["DiffView"]),
        .library(name: "ActionUIDiff", targets: ["ActionUIDiff"]),
        // Resource-only docs product, mirroring core ActionUIDocumentation. A client that links
        // this gets the add-on's schema doc + insert template copied into its bundle.
        .library(name: "ActionUIDiffDocumentation", targets: ["ActionUIDiffDocumentation"]),
    ],
    dependencies: [
        .package(path: "../.."),   // the ActionUI package at the repo root
    ],
    targets: [
        // The standalone diff-viewer component: SwiftUI / Foundation only, no ActionUI dependency.
        .target(
            name: "DiffView",
            path: "Sources/DiffView"
        ),
        .target(
            name: "ActionUIDiff",
            dependencies: [
                "DiffView",
                .product(name: "ActionUI", package: "ActionUI"),
            ],
            path: "Sources/ActionUIDiff"
        ),
        // Bundles this add-on's Documentation/ (the per-element .md schema doc and .json insert
        // template) as SPM resources, the same way the core ActionUIDocumentation target bundles
        // Documentation/Schemas + Documentation/Elements. Not linked into the add-on library.
        .target(
            name: "ActionUIDiffDocumentation",
            path: "Documentation",
            sources: ["ActionUIDiffDocumentation.swift"],
            resources: [
                .copy("Schemas"),
                .copy("Elements"),
            ]
        ),
        // Component tests (DiffView) plus element-level tests (ActionUIDiff); both reach internals.
        .testTarget(
            name: "DiffTests",
            dependencies: ["DiffView", "ActionUIDiff"],
            path: "Tests"
        ),
    ]
)
