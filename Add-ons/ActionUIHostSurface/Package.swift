// swift-tools-version: 6.0
//
// ActionUIHostSurface - an optional ActionUI add-on, packaged as a Swift package.
//
// The HostSurface element: a rectangle in an ActionUI layout whose pixels a client program draws with
// its own renderer. On macOS and iOS the client gets a CAMetalLayer; on Linux the element is a frame sink
// that shows the frames the client presents.
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
// On Linux the add-on is the GTK element (HostSurfaceView+Adwaita.swift) and links ActionUI's ActionUIStatic
// product: one process has one Swift runtime. It has no Documentation target there: Bundle.module needs full
// Foundation, and with it ICU's data, which the Linux build leaves out. libActionUI.so links it
// (ActionUIAdwaita/Library), so programs in other languages get the element without a register call.

import PackageDescription

#if os(Linux)
let package = Package(
    name: "ActionUIHostSurface",
    products: [
        .library(name: "ActionUIHostSurface", targets: ["ActionUIHostSurface"]),
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
                .product(name: "ActionUIStatic", package: "ActionUI"),
                .product(name: "CAdwaita", package: "ActionUI"),
            ],
            path: "Sources/ActionUIHostSurface",
            // The SwiftUI element, the AppKit and UIKit view, and its input.
            exclude: ["HostSurface.swift", "HostSurfaceView.swift", "HostSurfaceView+Input.swift", "HostSurfaceKeyCodes.swift"]
        ),
        .testTarget(
            name: "HostSurfaceTests",
            dependencies: [
                "ActionUIHostSurface",
                .product(name: "CAdwaita", package: "ActionUI"),
            ],
            path: "Tests",
            // The AppKit and UIKit tests.
            exclude: ["HostSurfaceDocumentTests.swift", "HostSurfaceInputTests.swift", "HostSurfaceLifecycleTests.swift",
                      "HostSurfaceTestSupport.swift"]
        ),
    ]
)
#else
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
#endif
