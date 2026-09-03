// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.
// Tools-version 6.0 selects the Swift 6 language mode by default for every target in this package.
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
//   • ActionUIRemote                 – Out-of-process binding: Unix socket + JSON-RPC 2.0 server (macOS)
//   • ActionUIDocumentation          – Resource-only bundle (schemas, templates, index)
//
// The ActionUIViewer preview tool moved to its own aggregator package at Apps/ActionUIViewer so it
// can link the optional add-ons and register their element types (a core target cannot depend on the
// add-ons, which depend on core - that would be circular).
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

        // MARK: - Menu bar
        // Lifecycle-free JSON->NSMenu builder (default macOS menu bar plus
        // CommandMenu / CommandGroup items).  Shared by ActionUIAppKitApplication
        // and external hosts.  Depends only on ActionUI core.
        .library(
            name: "ActionUIMenuBar",
            targets: ["ActionUIMenuBar"]
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

        // MARK: - Remote binding
        // Out-of-process access to ActionUI windows: a Unix domain socket server speaking
        // newline-delimited JSON-RPC 2.0, mirroring the C adapter's verb set. Hosts that
        // embed ActionUI start it so that child processes (Python scripts, tools, tests)
        // can read and mutate window state. macOS only. See ActionUIRemote/PROTOCOL.md.
        .library(
            name: "ActionUIRemote",
            targets: ["ActionUIRemote"]
        ),

        // MARK: - Documentation bundle
        // Resource-only bundle containing element schemas (.md), JSON templates,
        // and the element index. No code dependencies — consumers access the
        // bundle at runtime via ActionUIDocumentation.bundle.
        .library(
            name: "ActionUIDocumentation",
            targets: ["ActionUIDocumentation"]
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

        // MARK: - ActionUIMenuBar
        // Lifecycle-free menu-bar construction.
        .target(
            name: "ActionUIMenuBar",
            dependencies: ["ActionUI"],
            path: "ActionUIMenuBar",
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

        // MARK: - ActionUIViewer (moved out of core)
        // The viewer now lives in its own aggregator package at Apps/ActionUIViewer so it can link
        // the optional add-on packages and register their element types - a core target cannot,
        // because the add-ons depend on core (that would be a circular package dependency). Build it
        // with: swift build --package-path Apps/ActionUIViewer --product ActionUIViewer.

        // MARK: - ActionUIDocumentation
        // Resource-only target. Bundles the Documentation/ folder so consumers
        // can access schemas, JSON templates, and the element index at runtime.
        // Not linked into any framework — meant to be copied into app bundles.
        .target(
            name: "ActionUIDocumentation",
            path: "Documentation",
            exclude: [
            	"Comparison-vs-ReactNative.md",
            	"Comparison-vs-tkinter.md",
            	"Architecture.md"
            ],
            sources: ["ActionUIDocumentation.swift"],
            resources: [
                .copy("ActionUI-JSON-Guide.md"),
                .copy("ActionUI-MenuBar-JSON-Guide.md"),
                .copy("ActionUI-Elements.md"),
                .copy("Schemas"),
                .copy("Elements"),
            ]
        ),

        // MARK: - Unit tests for ActionUI core
        .testTarget(
            name: "ActionUITests",
            dependencies: ["ActionUI"],
            path: "ActionUITests"
        ),

        // MARK: - ActionUIRemote
        // Remote binding: JSON-RPC 2.0 codec, Unix domain socket server, and the method table
        // over ActionUIModel. Pure Swift over Foundation and Darwin; the socket parts are
        // guarded with #if os(macOS) in source rather than through platform conditions here.
        // Non-Swift files under ActionUIRemote/ (Python client, protocol docs) are listed in
        // `exclude` as they are added, so SPM does not warn about unhandled files.
        .target(
            name: "ActionUIRemote",
            dependencies: ["ActionUI"],
            path: "ActionUIRemote",
            exclude: [
                "PROTOCOL.md",
                "README.md",
            ],
        ),

        // MARK: - Unit tests for ActionUIRemote
        .testTarget(
            name: "ActionUIRemoteTests",
            dependencies: ["ActionUIRemote", "ActionUI"],
            path: "ActionUIRemoteTests"
        ),
    ]
)
