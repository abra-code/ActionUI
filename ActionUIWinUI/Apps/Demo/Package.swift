// swift-tools-version: 6.3
//
// The Windows demo: ActionUIWinUIDemo, the counterpart of ActionUISwiftTestApp, as ActionUIAdwaitaDemo is on Linux
// (ActionUIAdwaita/Apps). It links the add-ons that build for Windows and registers them at launch.
//
// A package of its own because the add-ons depend on ActionUI, so ActionUI cannot depend on them.
//
// Windows only. Scripts/ci-windows.py builds it with the shim's import library (-Xswiftc -L<folder>).

import PackageDescription

let package = Package(
    name: "ActionUIWinUIApps",
    dependencies: [
        .package(path: "../../.."),   // the ActionUI package at the repo root
        .package(path: "../../../Add-ons/ActionUIDiff"),
        .package(path: "../../../Add-ons/ActionUICachedImage"),
        .package(path: "../../../Add-ons/ActionUIRichText"),
        .package(path: "../../../Add-ons/ActionUIHostSurface"),
    ],
    targets: [
        .executableTarget(
            name: "ActionUIWinUIDemo",
            dependencies: [
                .product(name: "ActionUIStatic", package: "ActionUI"),
                .product(name: "ActionUIWinUIApplication", package: "ActionUI"),
                .product(name: "CWinUI", package: "ActionUI"),
                .product(name: "ActionUISwiftAdapter", package: "ActionUI"),
                .product(name: "ActionUIDemoHandlers", package: "ActionUI"),
                .product(name: "ActionUIDiff", package: "ActionUIDiff"),
                .product(name: "ActionUICachedImage", package: "ActionUICachedImage"),
                .product(name: "ActionUIRichText", package: "ActionUIRichText"),
                .product(name: "ActionUIHostSurface", package: "ActionUIHostSurface"),
            ]
        ),
    ]
)
