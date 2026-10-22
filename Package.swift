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
//   • ActionUIVerifier               – Document verifier against the element schemas, Foundation only
//
// The ActionUIViewer preview tool moved to its own aggregator package at Apps/ActionUIViewer so it
// can link the optional add-ons and register their element types (a core target cannot depend on the
// add-ons, which depend on core - that would be circular).
//
// Excluded adapters:
//   • ActionUICppAdapter             – not included in this distribution

import Foundation
import PackageDescription

// Three packages, one chosen at the end. applePackage() is the full package for Apple platforms,
// linuxPackage() the one for Linux: the same module ActionUI, made of the portable code in
// ActionUI/Core and the GTK renderer in ActionUIAdwaita. coreCheckPackage() builds only
// ActionUI/Core, as the module ActionUI; set ACTIONUI_CORE_ONLY=1 to select it on either host,
// which Scripts/check-core.sh does on a Mac to cross-build Core for Linux.
let coreOnly = Context.environment["ACTIONUI_CORE_ONLY"] == "1"

// Every path in a target's folder (`target`, relative to the repository; "" for the root) that is
// neither one of `kept` nor a folder on the way to one, for the target's `exclude`: that leaves
// the target holding only the kept folders. Paths are relative to the target's folder, as
// `exclude` and `sources` are. Without it SwiftPM scans the whole folder of a target with
// `sources`: for path "." it takes every app's asset catalog as one of its resources, and in a
// test folder it warns about every other test file. SwiftPM caches a manifest's result by its
// text, not by the folder listing, so a build of such a package passes --manifest-cache none.
func excludingAllBut(_ kept: [String], in target: String = "") -> [String] {
    let root = target.isEmpty ? Context.packageDirectory : Context.packageDirectory + "/" + target
    func walk(_ relative: String) -> [String] {
        let folder = relative.isEmpty ? root : root + "/" + relative
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
        var excluded: [String] = []
        for entry in entries.sorted() {
            let path = relative.isEmpty ? entry : relative + "/" + entry
            if kept.contains(path) {
                continue
            }
            if kept.contains(where: { $0.hasPrefix(path + "/") }) {
                excluded += walk(path)
            } else {
                excluded.append(path)
            }
        }
        return excluded
    }
    return walk("")
}

func applePackage() -> Package {
Package(
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

        // MARK: - Document verifier
        // Checks ActionUI JSON documents against the element schemas: unknown property names,
        // wrong value types, unknown enum values, missing required properties, platform issues.
        // Swift twin of the Python verifier in Tools/verifier (both read ActionUIVerifier/Schemas),
        // Foundation only; it does not depend on ActionUI. The command-line tool is in
        // Apps/ActionUIVerifier.
        .library(
            name: "ActionUIVerifier",
            targets: ["ActionUIVerifier"]
        ),
    ],
    targets: [
        // MARK: - ActionUI (core)
        // Pure Swift target. Contains all view types, ActionUIModel, ActionUIRegistry,
        // ActionUIView, and related infrastructure.
        .target(
            name: "ActionUI",
            path: "ActionUI",
            // VideoPlayer.swift imports AVKit, but the code only references the SwiftUI overlay
            // (_AVKit_SwiftUI), so the linker records no dependency on AVKit.framework itself and
            // the overlay's VideoPlayerView then fails at runtime: "failed to demangle superclass of
            // VideoPlayerView from mangled name 'So12AVPlayerViewC'" (AVPlayerView is not loaded).
            // The Xcode project links AVKit.framework explicitly for the same reason (de12140);
            // this is the SwiftPM equivalent, so the viewer and any other package client get it.
            // Unconditional: AVKit exists on every platform this package declares.
            linkerSettings: [
                .linkedFramework("AVKit"),
                .linkedFramework("Charts"),
            ],
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
        //     ActionUIC.swift, ActionUIC+Apple.swift - compiled by ActionUICAdapter target below
        //     ActionUIC+Linux.swift                   - compiled by linuxPackage's ActionUICAdapter
        .target(
            name: "ActionUICAdapterHeaders",
            path: "ActionUICAdapter",
            exclude: [
                "ActionUIC.swift",
                "ActionUIC+Apple.swift",
                "ActionUIC+Linux.swift",
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
                "ActionUIC+Linux.swift",
            ],
            sources: ["ActionUIC.swift", "ActionUIC+Apple.swift"],
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
                "Python",
                "README.md",
                "Shell",
            ],
        ),

        // MARK: - ActionUIVerifier
        // Swift sources in ActionUIVerifier/, and ActionUIVerifier/Schemas - the element schemas,
        // shared with the Python verifier in Tools/verifier - bundled as a resource (reached
        // through Bundle.module).
        .target(
            name: "ActionUIVerifier",
            path: "ActionUIVerifier",
            resources: [
                .copy("Schemas"),
            ]
        ),

        // MARK: - Unit tests for ActionUIVerifier
        // Parity/ holds the script that compares this verifier with the Python one; it is run
        // with python3, not by `swift test`.
        .testTarget(
            name: "ActionUIVerifierTests",
            dependencies: ["ActionUIVerifier"],
            path: "ActionUIVerifierTests",
            exclude: [
                "Parity",
            ]
        ),

        // MARK: - Unit tests for ActionUIRemote
        .testTarget(
            name: "ActionUIRemoteTests",
            dependencies: ["ActionUIRemote", "ActionUI"],
            path: "ActionUIRemoteTests"
        ),
    ]
)
}

func coreCheckPackage() -> Package {
Package(
    name: "ActionUI",
    products: [
        .library(name: "ActionUI", targets: ["ActionUI"]),
    ],
    targets: [
        // The portable code, and a renderer half with no renderers (ActionUICoreCheck).
        .target(
            name: "ActionUI",
            path: ".",
            exclude: excludingAllBut(["ActionUI/Core", "ActionUICoreCheck"]),
            sources: ["ActionUI/Core", "ActionUICoreCheck"]
        ),
        // The Core tests: ActionUITests/Core, portable like the code they test.
        .testTarget(
            name: "ActionUITests",
            dependencies: ["ActionUI"],
            path: "ActionUITests",
            exclude: excludingAllBut(["Core"], in: "ActionUITests"),
            sources: ["Core"]
        ),
    ]
)
}

// Linux: GTK 4 and libadwaita from the system (libgtk-4-dev, libadwaita-1-dev and pkg-config to
// build), never bundled; the version floor is in ActionUIAdwaita/CAdwaita/CAdwaita.h.
func linuxPackage() -> Package {
Package(
    name: "ActionUI",
    products: [
        // A shared library, so programs in other languages load it and call its C functions.
        .library(name: "ActionUI", type: .dynamic, targets: ["ActionUI", "ActionUICAdapter", "ActionUIAdwaitaApplication"]),
    ],
    targets: [
        // libadwaita's C API (and GTK's, which it includes), found through pkg-config.
        .systemLibrary(
            name: "CAdwaita",
            path: "ActionUIAdwaita/CAdwaita",
            pkgConfig: "libadwaita-1"
        ),
        // The portable code and the GTK renderer: one module, as ActionUI is on Apple platforms.
        .target(
            name: "ActionUI",
            dependencies: ["CAdwaita"],
            path: ".",
            exclude: excludingAllBut(["ActionUI/Core", "ActionUIAdwaita/Sources"]),
            sources: ["ActionUI/Core", "ActionUIAdwaita/Sources"]
        ),
        // The C interface: its C header as a module (only ActionUIC.h: the folder's umbrella
        // header is Objective-C), and the functions that work with values and JSON text
        // (ActionUIC.swift; the Apple-only ones, which hand out native views, are not built).
        .systemLibrary(
            name: "ActionUICAdapterHeaders",
            path: "ActionUIAdwaita/CAdapterHeaders"
        ),
        .target(
            name: "ActionUICAdapter",
            dependencies: ["ActionUI", "ActionUICAdapterHeaders"],
            path: "ActionUICAdapter",
            exclude: [
                "dummy.c",
                "include",
                "ActionUIC+Apple.swift",
            ],
            sources: ["ActionUIC.swift", "ActionUIC+Linux.swift"]
        ),
        // The application functions (actionUIApp*), over AdwaitaApplication; their C header's
        // handler types come from ActionUIApp.h as a module (only that header: its folder's
        // umbrella header is Objective-C).
        .systemLibrary(
            name: "ActionUIAppHeaders",
            path: "ActionUIAdwaita/AppHeaders"
        ),
        .target(
            name: "ActionUIAdwaitaApplication",
            dependencies: ["ActionUI", "ActionUIAppHeaders"],
            path: "ActionUIAdwaitaApplication"
        ),
        // The Core tests, as in coreCheckPackage.
        .testTarget(
            name: "ActionUITests",
            dependencies: ["ActionUI"],
            path: "ActionUITests",
            exclude: excludingAllBut(["Core"], in: "ActionUITests"),
            sources: ["Core"]
        ),
        // The renderer tests. They need a display and skip themselves without one.
        .testTarget(
            name: "ActionUIAdwaitaTests",
            dependencies: ["ActionUI", "CAdwaita", "ActionUIAdwaitaApplication"],
            path: "ActionUIAdwaita/Tests"
        ),
    ]
)
}

// Only the chosen package may be constructed: PackageDescription takes the last Package created as
// the manifest.
#if os(Linux)
let package = coreOnly ? coreCheckPackage() : linuxPackage()
#else
let package = coreOnly ? coreCheckPackage() : applePackage()
#endif
