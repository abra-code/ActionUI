// swift-tools-version: 6.3
//
// libActionUI.so, the library for programs in other languages: Python, Node.js, Rust and C load it and call its C
// functions. It holds ActionUI, the C adapter, the application functions, the remote server and the add-ons, with
// the Swift runtime linked in (Scripts/make-linux-library-package.sh).
//
// It is a package of its own because the add-ons depend on ActionUI, so ActionUI cannot depend on them. Its product
// must be named ActionUI, which names the file and the name stamped in it (its SONAME), so ActionUI's package has no
// product of that name on Linux: a product's name is unique across a build, whatever its type.
//
// Linux only. Swift programs do not use this library: they depend on the ActionUI package's ActionUIStatic product
// and on the add-ons they want.

import PackageDescription

let package = Package(
    name: "ActionUILibrary",
    products: [
        .library(name: "ActionUI", type: .dynamic, targets: ["ActionUILibrary"]),
    ],
    dependencies: [
        .package(path: "../.."),   // the ActionUI package at the repo root
        .package(path: "../../Add-ons/ActionUIRichText"),
        .package(path: "../../Add-ons/ActionUICachedImage"),
        .package(path: "../../Add-ons/ActionUIDiff"),
    ],
    targets: [
        .target(
            name: "ActionUILibrary",
            dependencies: [
                .product(name: "ActionUIStatic", package: "ActionUI"),
                .product(name: "ActionUIStaticHosts", package: "ActionUI"),
                .product(name: "ActionUIRichText", package: "ActionUIRichText"),
                .product(name: "ActionUICachedImage", package: "ActionUICachedImage"),
                .product(name: "ActionUIDiff", package: "ActionUIDiff"),
            ]
        ),
        // Programs in other languages, run against the built library.
        .testTarget(
            name: "ActionUILibraryTests",
            exclude: ["Hosts"]
        ),
    ]
)
