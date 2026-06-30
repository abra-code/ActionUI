// swift-tools-version: 6.0
//
// ActionUIViewer - the add-on-aware preview tool (aggregator package).
//
// Lives in the ActionUI repo but is a SEPARATE package from core: it depends on core ActionUI AND
// the optional add-on packages, links them, and calls each add-on's register() at launch, so it can
// preview JSON documents that use add-on element types (e.g. the "QuickLook" element). A core-package
// target cannot do this - the add-ons depend on core, so linking them back from a core target would
// be a circular package dependency. OMC builds this package's ActionUIViewer product.
//
// The executable also depends on the resource-only documentation products (core + each add-on). That
// is deliberate: one `swift build` of ActionUIViewer then also builds every documentation bundle, so
// OMC's update_appletbuilder.sh gets the viewer and all docs from a single build. Add a new add-on by
// adding its package dependency, its product + its Documentation product below, and an import +
// register() line in ActionUIViewer.swift.

import PackageDescription

let package = Package(
    name: "ActionUIViewer",
    platforms: [
        .macOS("14.6"),
    ],
    dependencies: [
        .package(path: "../.."),                            // ActionUI core (Package.swift at the repo root)
        .package(path: "../../Add-ons/ActionUIQuickLook"),  // add-on(s)
        .package(path: "../../Add-ons/ActionUIChat"),
    ],
    targets: [
        .executableTarget(
            name: "ActionUIViewer",
            dependencies: [
                .product(name: "ActionUI", package: "ActionUI"),
                .product(name: "ActionUISwiftAdapter", package: "ActionUI"),
                .product(name: "ActionUIQuickLook", package: "ActionUIQuickLook"),
                .product(name: "ActionUIChat", package: "ActionUIChat"),
                // Resource-only doc bundles: depending on them makes one viewer build also build the
                // core + add-on documentation bundles, harvested by OMC's update_appletbuilder.sh.
                .product(name: "ActionUIDocumentation", package: "ActionUI"),
                .product(name: "ActionUIQuickLookDocumentation", package: "ActionUIQuickLook"),
                .product(name: "ActionUIChatDocumentation", package: "ActionUIChat"),
            ],
            path: "Sources/ActionUIViewer"
        ),
    ]
)
