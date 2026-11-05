// swift-tools-version: 6.0
//
// ActionUIHostSurface - an optional ActionUI add-on, packaged as a Swift package.
//
// The HostSurface element: a rectangle in an ActionUI layout whose pixels a client program draws with
// its own renderer. On macOS and iOS the client gets a CAMetalLayer.
//
// Two library targets:
// - CActionUIHostSurface: the plain C header (include/ActionUIHostSurface.h) that C, C++ and Rust
//   clients include, and that the Swift target imports for the C types;
// - ActionUIHostSurface: the element and the functions the header declares (Swift, @c).
//
// The ActionUIHostSurface product compiles against ActionUI's public API and does NOT embed ActionUI:
// SPM builds ActionUI once and the host app links it. The host links this product + ActionUI and
// calls ActionUIHostSurface.register() (Swift) or ActionUIHostSurface_register() (C).
//
// Apple platforms only for now; the GTK element (a frame sink and a GL area) is a later step.

import PackageDescription

let package = Package(
    name: "ActionUIHostSurface",
    platforms: [
        .macOS("14.6"),
        .iOS("17.6"),
    ],
    products: [
        .library(name: "ActionUIHostSurface", targets: ["ActionUIHostSurface"]),
        // Resource-only docs product, mirroring core ActionUIDocumentation. A client that links
        // this gets the add-on's schema doc + insert template copied into its bundle.
        .library(name: "ActionUIHostSurfaceDocumentation", targets: ["ActionUIHostSurfaceDocumentation"]),
    ],
    dependencies: [
        .package(path: "../.."),   // the ActionUI package at the repo root
    ],
    targets: [
        .target(
            name: "CActionUIHostSurface",
            path: "Sources/CActionUIHostSurface"
        ),
        .target(
            name: "ActionUIHostSurface",
            dependencies: [
                "CActionUIHostSurface",
                .product(name: "ActionUI", package: "ActionUI"),
            ],
            path: "Sources/ActionUIHostSurface"
        ),
        .target(
            name: "ActionUIHostSurfaceDocumentation",
            path: "Documentation",
            sources: ["ActionUIHostSurfaceDocumentation.swift"],
            resources: [
                .copy("Schemas"),
                .copy("Elements"),
            ]
        ),
        .testTarget(
            name: "HostSurfaceTests",
            dependencies: [
                "ActionUIHostSurface",
                .product(name: "ActionUI", package: "ActionUI"),
            ],
            path: "Tests"
        ),
    ]
)
