// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.
//
// ActionUI SPM Package
// Source distribution for https://github.com/abra-code/ActionUI
//
// Products:
//   • ActionUI                       – Core library (Swift)
//   • ActionUISwiftAdapter           – Swift-friendly static wrapper over ActionUI
//   • ActionUICAdapter               – C adapter (header + Swift glue)
//   • ActionUIObjCAdapter            – Objective-C adapter
//   • ActionUIJavaScriptCoreAdapter  – JavaScriptCore adapter
//   • ActionUIWebKitJSAdapter        – WebKit / WKWebView JS bridge adapter
//
// Excluded adapters:
//   • ActionUICppAdapter             – not included in this distribution

import PackageDescription

let package = Package(
    name: "ActionUI",
    platforms: [
        .macOS("14.6"),    // macOS 14.6+
        .iOS("17.6"),        // iOS 17.6+
        .tvOS("17.6"),       // tvOS 17.6+
        .watchOS("10.6"),    // watchOS 10.6+
        .visionOS("2.6"),    // visionOS 2.6+
    ],
    products: [
        // MARK: - Core library
        .library(
            name: "ActionUI",
            targets: ["ActionUI"]
        ),

        // MARK: - Swift adapter
        // Provides the @MainActor ActionUISwift struct with a simplified static API.
        // Depends on ActionUI. Suitable for Swift-only clients.
        .library(
            name: "ActionUISwiftAdapter",
            targets: ["ActionUISwiftAdapter"]
        ),

        // MARK: - C adapter
        // Exposes a pure-C API surface for embedding ActionUI in C projects or
        // for use as a stable ABI boundary from other languages.
        .library(
            name: "ActionUICAdapter",
            targets: ["ActionUICAdapter"]
        ),

        // MARK: - Objective-C adapter
        // Wraps ActionUI in Objective-C for integration with ObjC or mixed codebases.
        .library(
            name: "ActionUIObjCAdapter",
            targets: ["ActionUIObjCAdapter"]
        ),

        // MARK: - JavaScriptCore adapter
        // Bridges ActionUI to JavaScriptCore for scripting environments.
        .library(
            name: "ActionUIJavaScriptCoreAdapter",
            targets: ["ActionUIJavaScriptCoreAdapter"]
        ),

        // MARK: - WebKit JS adapter
        // Bridges ActionUI to WKWebView / WebKit JavaScript for hybrid web apps.
        .library(
            name: "ActionUIWebKitJSAdapter",
            targets: ["ActionUIWebKitJSAdapter"]
        ),
    ],
    targets: [
        // MARK: - ActionUI (core)
        // Pure Swift target. Contains all view types, ActionUIModel, ActionUIRegistry,
        // ActionUIView, and related infrastructure.
        .target(
            name: "ActionUI",
            path: "ActionUI",
        ),

        // MARK: - ActionUISwiftAdapter
        // Thin Swift wrapper. Public entry point for Swift clients.
        .target(
            name: "ActionUISwiftAdapter",
            dependencies: ["ActionUI"],
            path: "ActionUISwiftAdapter",
        ),

        // MARK: - ActionUICAdapterHeaders
        // Headers-only C target. Owns the public C headers so SPM can build them
        // as a standalone Clang module that ActionUICAdapter (Swift) can import.
        //
        // SPM cannot mix C and Swift in one target Splitting into a dedicated C target
        // sidesteps all bridging-header and module-map issues.
        //
        // Not listed in `products` — internal implementation detail only.
        //
        // Required file layout (no changes to existing files):
        //   ActionUICAdapter/
        //     dummy.c
        //     include/
        //       ActionUICAdapter.h   - umbrella (may keep <ActionUICAdapter/ActionUIC.h>)
        //       ActionUIC.h          - typedefs and public C API
        //     ActionUIC.swift        - compiled by ActionUICAdapter target below
        .target(
            name: "ActionUICAdapterHeaders",
            path: "ActionUICAdapter",
            exclude: [
                "ActionUIC.swift",
            ],
            publicHeadersPath: "include"
        ),

        // MARK: - ActionUICAdapter (Swift)
        // Swift glue layer over the C API.  Depends on ActionUICAdapterHeaders so that
        // all C typedefs (ActionUILoggerCallback, ActionUILogLevel, ...) are visible
        // to ActionUIC.swift via `import ActionUICAdapterHeaders` — no bridging header
        // or unsafe flags required.
        //
        .target(
            name: "ActionUICAdapter",
            dependencies: ["ActionUI", "ActionUICAdapterHeaders"],
            path: "ActionUICAdapter",
            exclude: [
                // Exclude C sources and headers — owned by ActionUICAdapterHeaders
                "dummy.c",
                "include",
            ],
            sources: ["ActionUIC.swift"],
        ),


        // MARK: - ActionUIObjCAdapter (Swift)
        // Pure Swift target containing the @objc implementation.
        //
        // Consumers (ObjC/C++) import via:
        //   @import ActionUIObjCAdapter;
        .target(
            name: "ActionUIObjCAdapter",
            dependencies: ["ActionUI"],
            path: "ActionUIObjCAdapter",
            sources: ["ActionUIObjC.swift"],
        ),

        // MARK: - ActionUIJavaScriptCoreAdapter
        // Swift + JSC target. Bridges JSContext calls to ActionUIModel.
        // JavaScriptCore is a system framework on Apple platforms — no extra dep needed.
        .target(
            name: "ActionUIJavaScriptCoreAdapter",
            dependencies: ["ActionUI"],
            path: "ActionUIJavaScriptCoreAdapter",
        ),

        // MARK: - ActionUIWebKitJSAdapter
        // Swift target bridging WKWebView <-> ActionUI.
        // WebKit is a system framework — available on macOS, iOS, iPadOS, visionOS.
        // Not available on watchOS or tvOS; guard at the call site if needed.
        //
        // ActionUIWebKitJSBridge.js is loaded at runtime via Bundle.module and must
        // be declared as a bundled resource so SPM copies it into the product bundle.
        .target(
            name: "ActionUIWebKitJSAdapter",
            dependencies: ["ActionUI"],
            path: "ActionUIWebKitJSAdapter",
            resources: [
                .process("ActionUIWebKitJSBridge.js"),
            ],
        ),

        // MARK: - Unit tests for ActionUI core
        .testTarget(
            name: "ActionUITests",
            dependencies: ["ActionUI"],
            path: "ActionUITests"
        ),
    ]
)
