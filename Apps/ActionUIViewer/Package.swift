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
import Foundation

// One source of truth for the deployment target: `platforms` below and the linker flag both use it.
let macOSDeploymentTarget = "14.6"

// SDK stamp. Under Xcode 27 the default SwiftPM engine (Swift Build) runs the link step without
// SDKROOT in its environment, and swiftc then records the DEPLOYMENT TARGET as the SDK version in the
// binary (LC_BUILD_VERSION says "sdk 14.6"), although the code is compiled against the current SDK.
// AppKit picks its design from that stamp, so such a viewer runs in the pre-Liquid Glass compatibility
// layout and its previews do not match a real app. Exporting SDKROOT, `xcrun swift build` and --sdk do
// not reach the link step; stating both versions to the linker does. Done here rather than on the
// `swift build` command line so that every way of building this package gets it.
//
// The SDK version is whatever SDK this build uses: SwiftPM sets SDKROOT while it evaluates a manifest
// through the /usr/bin/swift shim; a toolchain binary called directly does not, hence the xcrun
// fallback. If neither answers, the flag is left out and the build behaves as it did before.
let macOSSDKVersion: String? = {
    if let root = ProcessInfo.processInfo.environment["SDKROOT"],
       let data = try? Data(contentsOf: URL(fileURLWithPath: root).appendingPathComponent("SDKSettings.json")),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let version = json["Version"] as? String, !version.isEmpty {
        return version
    }
    let xcrun = Process()
    xcrun.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    xcrun.arguments = ["--sdk", "macosx", "--show-sdk-version"]
    let pipe = Pipe()
    xcrun.standardOutput = pipe
    xcrun.standardError = FileHandle.nullDevice
    guard (try? xcrun.run()) != nil else { return nil }
    // Read to the end before waiting, so a full pipe can never block the child.
    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    xcrun.waitUntilExit()
    let text = String(data: output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    return (text?.isEmpty == false) ? text : nil
}()

// unsafeFlags keeps a package from being used as a versioned dependency. That is fine here: this is a
// root package that builds a tool, never a dependency. Do not copy this into the ActionUI core package.
let sdkStampLinkerSettings: [LinkerSetting] = macOSSDKVersion.map { sdkVersion in
    [.unsafeFlags(["-Xlinker", "-platform_version", "-Xlinker", "macos",
                   "-Xlinker", macOSDeploymentTarget, "-Xlinker", sdkVersion],
                  .when(platforms: [.macOS]))]
} ?? []

let package = Package(
    name: "ActionUIViewer",
    platforms: [
        .macOS(macOSDeploymentTarget),
    ],
    dependencies: [
        .package(path: "../.."),                            // ActionUI core (Package.swift at the repo root)
        .package(path: "../../Add-ons/ActionUIQuickLook"),  // add-on(s)
        .package(path: "../../Add-ons/ActionUIChat"),
        .package(path: "../../Add-ons/ActionUIDiff"),
        .package(path: "../../Add-ons/ActionUICachedImage"),
        .package(path: "../../Add-ons/ActionUIRichText"),
    ],
    targets: [
        .executableTarget(
            name: "ActionUIViewer",
            dependencies: [
                .product(name: "ActionUI", package: "ActionUI"),
                .product(name: "ActionUISwiftAdapter", package: "ActionUI"),
                .product(name: "ActionUIQuickLook", package: "ActionUIQuickLook"),
                .product(name: "ActionUIChat", package: "ActionUIChat"),
                .product(name: "ActionUIDiff", package: "ActionUIDiff"),
                .product(name: "ActionUICachedImage", package: "ActionUICachedImage"),
                .product(name: "ActionUIRichText", package: "ActionUIRichText"),
                // Resource-only doc bundles: depending on them makes one viewer build also build the
                // core + add-on documentation bundles, harvested by OMC's update_appletbuilder.sh.
                .product(name: "ActionUIDocumentation", package: "ActionUI"),
                .product(name: "ActionUIQuickLookDocumentation", package: "ActionUIQuickLook"),
                .product(name: "ActionUIChatDocumentation", package: "ActionUIChat"),
                .product(name: "ActionUIDiffDocumentation", package: "ActionUIDiff"),
                .product(name: "ActionUICachedImageDocumentation", package: "ActionUICachedImage"),
                .product(name: "ActionUIRichTextDocumentation", package: "ActionUIRichText"),
            ],
            path: "Sources/ActionUIViewer",
            linkerSettings: sdkStampLinkerSettings
        ),
    ]
)
