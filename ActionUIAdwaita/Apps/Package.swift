// swift-tools-version: 6.3
//
// The Linux demo: ActionUIAdwaitaDemo, the counterpart of ActionUISwiftTestApp (Scripts/make-linux-demo-bundle.sh
// makes its bundle). It links the add-ons and registers them at launch, as the viewer does. The viewer itself is in
// Apps/ActionUIViewer, one package for both platforms.
//
// A package of its own because the add-ons depend on ActionUI, so ActionUI cannot depend on them.
//
// Linux only.

import PackageDescription

let package = Package(
    name: "ActionUIAdwaitaApps",
    dependencies: [
        .package(path: "../.."),   // the ActionUI package at the repo root
        .package(path: "../../Add-ons/ActionUIRichText"),
        .package(path: "../../Add-ons/ActionUICachedImage"),
        .package(path: "../../Add-ons/ActionUIDiff"),
    ],
    targets: [
        .executableTarget(
            name: "ActionUIAdwaitaDemo",
            dependencies: [
                .product(name: "ActionUIStatic", package: "ActionUI"),
                .product(name: "ActionUIAdwaitaApplication", package: "ActionUI"),
                .product(name: "CAdwaita", package: "ActionUI"),
                .product(name: "ActionUISwiftAdapter", package: "ActionUI"),
                .product(name: "ActionUIDemoHandlers", package: "ActionUI"),
                .product(name: "ActionUIRichText", package: "ActionUIRichText"),
                .product(name: "ActionUICachedImage", package: "ActionUICachedImage"),
                .product(name: "ActionUIDiff", package: "ActionUIDiff"),
            ]
        ),
        // The program, run as it is, built next to the test program. The tests need a display and skip themselves
        // without one.
        .testTarget(
            name: "ActionUIAdwaitaAppsTests",
            dependencies: [
                "ActionUIAdwaitaDemo",
                .product(name: "CAdwaita", package: "ActionUI"),
            ]
        ),
    ]
)
