// swift-tools-version:5.9
//
// ConvertC - the shared C brain, packaged for Apple as an importable Clang module.
//
// This is the Apple half of UnitConverter's "one C file, every platform" story.
// The single C target below compiles shared/c/convert.c (reached by symlink, so it
// is the SAME bytes Android's NDK build compiles) and exposes shared/c/convert.h
// through publicHeadersPath. SPM auto-generates the module map, so the Clang module
// name == the target name (`ConvertC`); the Swift host just writes `import ConvertC`
// and calls `aui_convert(...)`. No bridging header, no hand-written module.modulemap.
//
// (Section 7 of Private/Example_Host_Patterns.md describes the two-target C+Swift
// split for adding C to an existing Swift package. Here the Swift side is the app
// target itself, so a single pure-C library target is all that is needed.)

import PackageDescription

let package = Package(
    name: "ConvertC",
    products: [
        .library(name: "ConvertC", targets: ["ConvertC"]),
    ],
    targets: [
        .target(
            name: "ConvertC",
            path: "Sources/ConvertC",
            sources: ["convert.c"],
            publicHeadersPath: "include"
        ),
    ]
)
