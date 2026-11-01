// swift-tools-version: 6.3
//
// The Linux programs: ActionUIAdwaitaViewer, which opens a document in a window, and ActionUIAdwaitaDemo, the
// counterpart of ActionUISwiftTestApp (Scripts/make-linux-demo-bundle.sh makes its bundle). Both link the add-ons and
// register them at launch, as Apple's ActionUIViewer does.
//
// They are a package of their own because the add-ons depend on ActionUI, so ActionUI cannot depend on them. They are
// not a Linux branch of Apps/ActionUIViewer because a package has one Package.resolved: Apple's lists packages Linux
// does not use, and SwiftPM drops them from the file on the first Linux build.
//
// Linux only.

import PackageDescription

let package = Package(
    name: "ActionUIAdwaitaApps",
    dependencies: [
        .package(path: "../.."),   // the ActionUI package at the repo root
        .package(path: "../../Add-ons/ActionUIRichText"),
        .package(path: "../../Add-ons/ActionUICachedImage"),
    ],
    targets: [
        .executableTarget(
            name: "ActionUIAdwaitaViewer",
            dependencies: [
                .product(name: "ActionUIStatic", package: "ActionUI"),
                .product(name: "CAdwaita", package: "ActionUI"),
                .product(name: "ActionUIRichText", package: "ActionUIRichText"),
                .product(name: "ActionUICachedImage", package: "ActionUICachedImage"),
            ]
        ),
        .executableTarget(
            name: "ActionUIAdwaitaDemo",
            dependencies: [
                .product(name: "ActionUIStatic", package: "ActionUI"),
                .product(name: "CAdwaita", package: "ActionUI"),
                .product(name: "ActionUISwiftAdapter", package: "ActionUI"),
                .product(name: "ActionUIDemoHandlers", package: "ActionUI"),
                .product(name: "ActionUIRichText", package: "ActionUIRichText"),
                .product(name: "ActionUICachedImage", package: "ActionUICachedImage"),
            ]
        ),
        // The programs, run as they are, built next to the test program. They need a display and skip themselves
        // without one.
        .testTarget(
            name: "ActionUIAdwaitaAppsTests",
            dependencies: [
                "ActionUIAdwaitaViewer",
                "ActionUIAdwaitaDemo",
                .product(name: "CAdwaita", package: "ActionUI"),
            ]
        ),
    ]
)
