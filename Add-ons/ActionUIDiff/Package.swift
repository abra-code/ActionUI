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
// The pure diff-viewer component (module DiffView: SwiftUI / Foundation only, no ActionUI) lives in
// its own repo (github.com/abra-code/DiffView) - the same relationship RichText has to the
// ActionUIRichText add-on. This package ships the `Diff` element wrapper on top of it for JSON
// documents; the chat component consumes the DiffView package directly.

import PackageDescription

let package = Package(
    name: "ActionUIDiff",
    platforms: [
        .macOS("14.6"),
        .iOS("17.6"),
        .visionOS("2.6"),
    ],
    products: [
        .library(name: "ActionUIDiff", targets: ["ActionUIDiff"]),
        // Resource-only docs product, mirroring core ActionUIDocumentation. A client that links
        // this gets the add-on's schema doc + insert template copied into its bundle.
        .library(name: "ActionUIDiffDocumentation", targets: ["ActionUIDiffDocumentation"]),
    ],
    dependencies: [
        .package(path: "../.."),   // the ActionUI package at the repo root
        // The standalone diff-viewer component in its own sibling repo. Referenced by local
        // filesystem path while the component repos are developed side by side; switch to the
        // github URL (branch/tag) once the repo is pushed.
        .package(path: "../../../DiffView"),
    ],
    targets: [
        .target(
            name: "ActionUIDiff",
            dependencies: [
                .product(name: "DiffView", package: "DiffView"),
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
        // Element-level tests (ActionUIDiff); the component's own tests live in the DiffView repo.
        .testTarget(
            name: "DiffTests",
            dependencies: [
                "ActionUIDiff",
                .product(name: "DiffView", package: "DiffView"),
            ],
            path: "Tests"
        ),
    ]
)
