// swift-tools-version: 6.0
//
// ActionUICachedImage - an optional ActionUI add-on, packaged as a Swift package.
//
// It adds a "CachedImage" element that renders AsyncImageCache's cached, off-main image view: bytes
// are fetched / decoded / downscaled OFF the main thread and served from a two-tier (memory + disk)
// cache, and the natural pixel size is known up front so layout reserves the exact box with no
// reflow on hydration - even across relaunch.
//
// Two dependencies, with different linking stories:
//   - ActionUI: the add-on compiles against ActionUI's public API but does NOT embed it. A static
//     library never embeds its dependencies; SPM builds ActionUI once and the HOST app links it, so
//     this product only references ActionUI's symbols (resolved at the host's final link) - the same
//     "compile against, do not link" relationship the standalone xcodegen project expresses with
//     link: false.
//   - AsyncImageCache: a genuine third-party dependency (github.com/abra-code/AsyncImageCache) whose
//     code the element actually uses. SPM pulls it transitively into any host that links this add-on,
//     so the host links AsyncImageCache too - no special handling needed here.
//
// The host links this product (+ ActionUI) and calls ActionUICachedImage.register() at launch.

import PackageDescription

let package = Package(
    name: "ActionUICachedImage",
    platforms: [
        .macOS("14.6"),
        .iOS("17.6"),
        .visionOS("2.6"),
    ],
    products: [
        .library(name: "ActionUICachedImage", targets: ["ActionUICachedImage"]),
        // Resource-only docs product, mirroring core ActionUIDocumentation. A client that links
        // this gets the add-on's schema doc + insert template copied into its bundle.
        .library(name: "ActionUICachedImageDocumentation", targets: ["ActionUICachedImageDocumentation"]),
    ],
    dependencies: [
        .package(path: "../.."),   // the ActionUI package at the repo root
        // AsyncImageCache has no released tags yet, so pin the branch. Switch to `from: "x.y.z"`
        // once the package is tagged.
        .package(url: "https://github.com/abra-code/AsyncImageCache", branch: "main"),
    ],
    targets: [
        .target(
            name: "ActionUICachedImage",
            dependencies: [
                .product(name: "ActionUI", package: "ActionUI"),
                .product(name: "AsyncImageCache", package: "AsyncImageCache"),
            ],
            path: "Sources"
        ),
        // Bundles this add-on's Documentation/ (the per-element .md schema doc and .json insert
        // template) as SPM resources, the same way the core ActionUIDocumentation target bundles
        // Documentation/Schemas + Documentation/Elements. Not linked into the add-on library.
        .target(
            name: "ActionUICachedImageDocumentation",
            path: "Documentation",
            sources: ["ActionUICachedImageDocumentation.swift"],
            resources: [
                .copy("Schemas"),
                .copy("Elements"),
            ]
        ),
    ]
)
