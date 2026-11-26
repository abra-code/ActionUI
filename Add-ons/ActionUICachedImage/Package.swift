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
//   - AsyncImageCache: the first-party remote SPM dependency (github.com/abra-code/AsyncImageCache) whose
//     code the element actually uses. SPM pulls it transitively into any host that links this add-on,
//     so the host links AsyncImageCache too - no special handling needed here.
//
// The host links this product (+ ActionUI) and calls ActionUICachedImage.register() at launch.
//
// On Linux the add-on is the GTK element (CachedImage+Adwaita.swift) over the same AsyncImageCache package, and
// it links ActionUI's ActionUIStatic product: one process has one Swift runtime. It has no Documentation target
// there: Bundle.module needs full Foundation, and with it ICU's data, which the Linux build leaves out.
//
// On Windows the add-on is the WinUI element (CachedImage+WinUI.swift), drawn through the shim's C functions
// (ActionUI's CWinUI product) from AsyncImageCache's Windows engine, and it links ActionUIStatic as on Linux.
// ActionUI.dll links it (ActionUIWinUI/Library). No test or Documentation target there yet.

import PackageDescription

#if os(Linux)
let package = Package(
    name: "ActionUICachedImage",
    products: [
        .library(name: "ActionUICachedImage", targets: ["ActionUICachedImage"]),
    ],
    dependencies: [
        .package(path: "../.."),   // the ActionUI package at the repo root
        // 0.2.0 is its first version with the Linux port; 0.2.1 keeps local images out of the disk cache;
        // 0.2.3 refuses an image that declares too large a size; 0.2.6 caps each download (32 MB by
        // default, ImageStore.downloadByteLimit).
        .package(url: "https://github.com/abra-code/AsyncImageCache", from: "0.2.6"),
    ],
    targets: [
        .target(
            name: "ActionUICachedImage",
            dependencies: [
                .product(name: "ActionUIStatic", package: "ActionUI"),
                .product(name: "CAdwaita", package: "ActionUI"),
                .product(name: "AsyncImageCache", package: "AsyncImageCache"),
            ],
            path: "Sources",
            // The SwiftUI element.
            exclude: ["CachedImage.swift"]
        ),
        .testTarget(
            name: "CachedImageTests",
            dependencies: [
                "ActionUICachedImage",
                .product(name: "ActionUIAdwaitaApplication", package: "ActionUI"),
                .product(name: "CAdwaita", package: "ActionUI"),
                .product(name: "AsyncImageCache", package: "AsyncImageCache"),
            ],
            path: "Tests"
        ),
    ]
)
#elseif os(Windows)
let package = Package(
    name: "ActionUICachedImage",
    products: [
        .library(name: "ActionUICachedImage", targets: ["ActionUICachedImage"]),
    ],
    dependencies: [
        .package(path: "../.."),   // the ActionUI package at the repo root
        // 0.2.7 is its first version with the Windows engine (WIC, WinHTTP, and a WinUI image source shared by every
        // element that shows the image). 0.2.8 changes Windows only (WinUI decodes an image without corners itself,
        // keeping one copy of its pixels instead of two); the Windows build pins it in its Package.resolved.
        .package(url: "https://github.com/abra-code/AsyncImageCache", from: "0.2.7"),
    ],
    targets: [
        .target(
            name: "ActionUICachedImage",
            dependencies: [
                .product(name: "ActionUIStatic", package: "ActionUI"),
                .product(name: "CWinUI", package: "ActionUI"),
                .product(name: "AsyncImageCache", package: "AsyncImageCache"),
            ],
            path: "Sources",
            // The SwiftUI element and the GTK one.
            exclude: ["CachedImage.swift", "CachedImage+Adwaita.swift"]
        ),
    ]
)
#else
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
        // AsyncImageCache is consumed as a versioned release.
        // 0.2.3 refuses an image that declares too large a size; 0.2.6 caps each download (32 MB by
        // default, ImageStore.downloadByteLimit).
        .package(url: "https://github.com/abra-code/AsyncImageCache", from: "0.2.6"),
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
#endif
