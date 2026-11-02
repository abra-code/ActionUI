// swift-tools-version: 6.0
//
// ActionUIMCP - a local MCP (Model Context Protocol) server that lets an AI agent open native
// ActionUI windows on the user's screen: blocking dialogs that return what the user entered, and
// non-blocking viewer windows.
//
// One package for both platforms: linuxPackage below is the same server on GTK, without the add-ons
// that have no Linux renderer.
//
// Two targets:
// - MCPStdio: the protocol layer (JSON-RPC 2.0 over newline-delimited stdio, tools only). One file,
//   Foundation only, no ActionUI imports, so it can be lifted into another server unchanged.
// - ActionUIMCP: the `actionui-mcp` executable. Links core ActionUI and the add-ons like
//   ActionUIViewer does (same aggregator shape, same SDK stamp), runs the main loop on the main
//   thread and the MCP reader on a background thread.

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

func applePackage() -> Package {
Package(
    name: "ActionUIMCP",
    platforms: [
        .macOS(macOSDeploymentTarget),
    ],
    products: [
        .executable(name: "actionui-mcp", targets: ["ActionUIMCP"]),
    ],
    dependencies: [
        .package(path: "../.."),                            // ActionUI core (Package.swift at the repo root)
        .package(path: "../../Add-ons/ActionUIQuickLook"),
        .package(path: "../../Add-ons/ActionUIDiff"),
        .package(path: "../../Add-ons/ActionUICachedImage"),
        .package(path: "../../Add-ons/ActionUIRichText"),
    ],
    targets: [
        .target(
            name: "MCPStdio",
            path: "Sources/MCPStdio"
        ),
        .executableTarget(
            name: "ActionUIMCP",
            dependencies: [
                "MCPStdio",
                .product(name: "ActionUI", package: "ActionUI"),
                .product(name: "ActionUISwiftAdapter", package: "ActionUI"),
                .product(name: "ActionUIVerifier", package: "ActionUI"),
                .product(name: "ActionUIQuickLook", package: "ActionUIQuickLook"),
                .product(name: "ActionUIDiff", package: "ActionUIDiff"),
                .product(name: "ActionUICachedImage", package: "ActionUICachedImage"),
                .product(name: "ActionUIRichText", package: "ActionUIRichText"),
                // Resource-only documentation bundles, served as MCP resources (DocsResources.swift).
                // Linked only so they are built next to the executable; never imported.
                .product(name: "ActionUIDocumentation", package: "ActionUI"),
                .product(name: "ActionUIQuickLookDocumentation", package: "ActionUIQuickLook"),
                .product(name: "ActionUIDiffDocumentation", package: "ActionUIDiff"),
                .product(name: "ActionUICachedImageDocumentation", package: "ActionUICachedImage"),
                .product(name: "ActionUIRichTextDocumentation", package: "ActionUIRichText"),
            ],
            path: "Sources/ActionUIMCP",
            // The Dock icon (AppKitPlatform), in ActionUIMCP_ActionUIMCP.bundle next to the
            // executable, found by name as the documentation bundles are.
            resources: [.copy("Resources/ActionUIMCP.icns")],
            linkerSettings: sdkStampLinkerSettings
        ),
        .testTarget(
            name: "MCPStdioTests",
            dependencies: ["MCPStdio"],
            path: "Tests/MCPStdioTests"
        ),
        .testTarget(
            name: "ActionUIMCPTests",
            dependencies: ["ActionUIMCP"],
            path: "Tests/ActionUIMCPTests"
        ),
    ]
)
}

// Linux has no JSONSerialization, so the tests parse with ActionUI, as a host there does. Packages
// that Linux does not use stay in the tracked Package.resolved only if a Linux build leaves that
// file alone: build with --only-use-versions-from-resolved-file, and with --manifest-cache none for
// the root package's exclude list.
func linuxPackage() -> Package {
Package(
    name: "ActionUIMCP",
    products: [
        .executable(name: "actionui-mcp", targets: ["ActionUIMCP"]),
    ],
    dependencies: [
        .package(path: "../.."),
        .package(path: "../../Add-ons/ActionUICachedImage"),
        .package(path: "../../Add-ons/ActionUIRichText"),
    ],
    targets: [
        .target(
            name: "MCPStdio",
            path: "Sources/MCPStdio"
        ),
        .executableTarget(
            name: "ActionUIMCP",
            dependencies: [
                "MCPStdio",
                .product(name: "ActionUIStatic", package: "ActionUI"),
                .product(name: "ActionUISwiftAdapter", package: "ActionUI"),
                .product(name: "ActionUIVerifier", package: "ActionUI"),
                .product(name: "ActionUICachedImage", package: "ActionUICachedImage"),
                .product(name: "ActionUIRichText", package: "ActionUIRichText"),
            ],
            path: "Sources/ActionUIMCP",
            // No resource bundles on Linux (they need full Foundation).
            exclude: ["Resources"]
        ),
        .testTarget(
            name: "MCPStdioTests",
            dependencies: ["MCPStdio", .product(name: "ActionUIStatic", package: "ActionUI")],
            path: "Tests/MCPStdioTests"
        ),
        .testTarget(
            name: "ActionUIMCPTests",
            dependencies: ["ActionUIMCP"],
            path: "Tests/ActionUIMCPTests"
        ),
    ]
)
}

// Only the chosen package may be constructed: PackageDescription takes the last Package created as
// the manifest.
#if os(Linux)
let package = linuxPackage()
#else
let package = applePackage()
#endif
