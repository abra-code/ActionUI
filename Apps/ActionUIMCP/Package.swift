// swift-tools-version: 6.0
//
// ActionUIMCP - a local MCP (Model Context Protocol) server that lets an AI agent open native
// ActionUI windows on the user's Mac: blocking dialogs that return what the user entered, and
// non-blocking viewer windows. Proof of concept; see Private/2026-09-22-actionui-mcp-server-findings-
// and-design.md for the design.
//
// Two targets:
// - MCPStdio: the protocol layer (JSON-RPC 2.0 over newline-delimited stdio, tools only). One file,
//   Foundation only, no ActionUI imports, so it can be lifted into another server unchanged.
// - ActionUIMCP: the `actionui-mcp` executable. Links core ActionUI and the add-ons like
//   ActionUIViewer does (same aggregator shape, same SDK stamp), runs the AppKit run loop on the main
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

let package = Package(
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
                .product(name: "ActionUIQuickLook", package: "ActionUIQuickLook"),
                .product(name: "ActionUIDiff", package: "ActionUIDiff"),
                .product(name: "ActionUICachedImage", package: "ActionUICachedImage"),
                .product(name: "ActionUIRichText", package: "ActionUIRichText"),
            ],
            path: "Sources/ActionUIMCP",
            linkerSettings: sdkStampLinkerSettings
        ),
        .testTarget(
            name: "MCPStdioTests",
            dependencies: ["MCPStdio"],
            path: "Tests/MCPStdioTests"
        ),
    ]
)
