// swift-tools-version: 6.0
//
// ActionUIVerifier - the command-line document verifier (actionui-verify).
//
// A thin front end over the ActionUIVerifier library of the root package (the Swift twin of the
// Python verifier in Tools/verifier), with the Python verifier's options, output and exit codes.
// A package of its own, like Apps/ActionUIViewer, so the root package gains no executable product.
//
//   swift build --package-path Apps/ActionUIVerifier -c release
//   "$(swift build --package-path Apps/ActionUIVerifier -c release --show-bin-path)/actionui-verify" -r Examples
//
// The built-in schemas come from the library's resource bundle (ActionUI_ActionUIVerifier.bundle),
// which must stay next to the binary when it is copied elsewhere.

import PackageDescription

let package = Package(
    name: "ActionUIVerifier",
    platforms: [
        .macOS("14.6"),
    ],
    products: [
        .executable(name: "actionui-verify", targets: ["ActionUIVerifierTool"]),
    ],
    dependencies: [
        .package(path: "../.."),  // ActionUI (Package.swift at the repo root)
    ],
    targets: [
        .executableTarget(
            name: "ActionUIVerifierTool",
            dependencies: [
                .product(name: "ActionUIVerifier", package: "ActionUI"),
            ],
            path: "Sources/ActionUIVerifierTool"
        ),
    ]
)
