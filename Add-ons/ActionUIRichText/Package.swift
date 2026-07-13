// swift-tools-version: 6.0
//
// ActionUIRichText - an optional ActionUI add-on, packaged as a Swift package.
//
// It adds a "RichText" element that renders the RichText package's rich-text DISPLAY view: a whole
// Markdown document (headings, code blocks, quotes, lists, GFM tables, inline styling, links) laid
// out into ONE native text view, selectable and copyable as a single unit.
//
// Two dependencies, with different linking stories:
//   - ActionUI: the add-on compiles against ActionUI's public API but does NOT embed it. A static
//     library never embeds its dependencies; SPM builds ActionUI once and the HOST app links it, so
//     this product only references ActionUI's symbols (resolved at the host's final link) - the same
//     "compile against, do not link" relationship the standalone xcodegen project expresses with
//     link: false.
//   - RichText: the first-party remote SPM dependency (github.com/abra-code/RichText) whose view the
//     element uses. SPM pulls it (and its own AsyncImageCache dependency) transitively into any host
//     that links this add-on, so the host links them too - no special handling needed here.
//
// The host links this product (+ ActionUI) and calls ActionUIRichText.register() at launch.

import PackageDescription

let package = Package(
    name: "ActionUIRichText",
    platforms: [
        .macOS("14.6"),
        .iOS("17.6"),
        .visionOS("2.6"),
    ],
    products: [
        .library(name: "ActionUIRichText", targets: ["ActionUIRichText"]),
        // Resource-only docs product, mirroring core ActionUIDocumentation. A client that links
        // this gets the add-on's schema doc + insert template copied into its bundle.
        .library(name: "ActionUIRichTextDocumentation", targets: ["ActionUIRichTextDocumentation"]),
    ],
    dependencies: [
        .package(path: "../.."),   // the ActionUI package at the repo root
        // RichText is consumed as a versioned release. (RichText itself pulls AsyncImageCache;
        // SPM resolves it transitively.)
        .package(url: "https://github.com/abra-code/RichText", from: "0.1.0"),
    ],
    targets: [
        .target(
            name: "ActionUIRichText",
            dependencies: [
                .product(name: "ActionUI", package: "ActionUI"),
                .product(name: "RichText", package: "RichText"),
            ],
            path: "Sources"
        ),
        // Bundles this add-on's Documentation/ (the per-element .md schema doc and .json insert
        // template) as SPM resources, the same way the core ActionUIDocumentation target bundles
        // Documentation/Schemas + Documentation/Elements. Not linked into the add-on library.
        .target(
            name: "ActionUIRichTextDocumentation",
            path: "Documentation",
            sources: ["ActionUIRichTextDocumentation.swift"],
            resources: [
                .copy("Schemas"),
                .copy("Elements"),
            ]
        ),
    ]
)
