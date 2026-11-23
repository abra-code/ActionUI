// swift-tools-version: 6.3
//
// ActionUI.dll and its import library ActionUI.lib, the library for programs in other languages: Python, Node.js,
// Rust and C load it and call its C functions. It holds ActionUI, the C adapter, the application functions and the
// add-ons (LinkedAddOns.swift). Scripts/ci-windows.py builds it and puts it in the Windows library package.
//
// It is a package of its own because the add-ons depend on ActionUI, so ActionUI cannot depend on them (as
// ActionUIAdwaita/Library on Linux). Its product must be named ActionUI, which names the DLL, so ActionUI's package
// has no product of that name on Windows: a product's name is unique across a build, whatever its type.
//
// The DLL must export the C functions of ActionUIC.h and ActionUIApp.h. On Windows SwiftPM exports the public
// symbols of only the modules the dynamic product lists, and those functions are in ActionUI's package, so the
// linker takes their names from a module-definition file, ActionUI.def. A new C function is a line there;
// Scripts/ci-windows.py checks the file against the headers as MSVC's preprocessor reads them for Windows.
//
// Windows only. Swift programs do not use this library: they depend on the ActionUI package's ActionUIStatic product
// and on the add-ons they want.

import PackageDescription

let package = Package(
    name: "ActionUILibrary",
    products: [
        .library(name: "ActionUI", type: .dynamic, targets: ["ActionUILibrary"]),
    ],
    dependencies: [
        .package(path: "../.."),   // the ActionUI package at the repo root
    ],
    targets: [
        .target(
            name: "ActionUILibrary",
            dependencies: [
                .product(name: "ActionUIStatic", package: "ActionUI"),
                .product(name: "ActionUICAdapter", package: "ActionUI"),
                .product(name: "ActionUIWinUIApplication", package: "ActionUI"),
            ],
            // Allowed here: this package is only ever built as the root package.
            linkerSettings: [.unsafeFlags(["-Xlinker", "/DEF:" + Context.packageDirectory + "/ActionUI.def"])]
        ),
    ]
)
