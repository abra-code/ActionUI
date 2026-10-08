// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

//
//  ActionUIAppMenuBar.swift
//  ActionUIAppKitApplication
//
//  ActionUI app-host glue over the shared ActionUIMenuBar engine.
//
//  Menu-bar construction (the default bar + CommandMenu / CommandGroup, with
//  deletion expressed as a childless "replacing" CommandGroup) lives in the
//  lifecycle-free ActionUIMenuBar library.
//  This file supplies only the host-specific parts: dispatch of custom menu
//  items through ActionUIModel, the custom About handler, and the C entry
//  point `actionUIAppLoadMenuBar`.
//

import AppKit
import Foundation
import ActionUI
import ActionUIMenuBar

// MARK: - Main-actor dispatch helper (file-private copy)
//
// Each file in ActionUIAppKitApplication keeps its own private copy to avoid
// exposing a module-internal symbol that could collide with the identically
// named private function in ActionUICAdapter when both static libraries are
// linked into the same binary.

@inline(__always)
private func runOnMainActorSync<T>(_ operation: @MainActor () -> T) -> T {
    // Both branches are fully synchronous and run entirely on the main thread,
    // so the result is produced and consumed without any cross-thread transfer.
    // Moving it back out through a nonisolated(unsafe) box avoids the spurious
    // T: Sendable requirement Swift 6 would otherwise impose on the closure's
    // return value.
    nonisolated(unsafe) var result: T!
    if Thread.isMainThread {
        MainActor.assumeIsolated { result = operation() }
    } else {
        DispatchQueue.main.sync {
            MainActor.assumeIsolated { result = operation() }
        }
    }
    return result
}

// MARK: - ActionUIModel menu dispatch

/// Target object for custom menu items that dispatch through ActionUIModel.
@MainActor
private final class MenuActionTarget: NSObject {
    static let shared = MenuActionTarget()

    /// Maps the menu item's tag to its actionID string.
    var actionIDsByTag: [Int: String] = [:]

    /// Monotonic counter for assigning unique tags.
    private var nextTag: Int = 10_000

    func registerActionID(_ actionID: String) -> Int {
        let tag = nextTag
        nextTag += 1
        actionIDsByTag[tag] = actionID
        return tag
    }

    @objc func performAction(_ sender: NSMenuItem) {
        guard let actionID = actionIDsByTag[sender.tag] else { return }
        // Resolve the front window's UUID so menu actions target the key window.
        let windowUUID = keyWindowUUID()
        ActionUIModel.shared.actionHandler(
            actionID,
            windowUUID: windowUUID,
            viewID: sender.tag,
            viewPartID: 0,
            context: nil
        )
    }
}

/// `itemBuilder` for the shared engine: wires a Button element's `actionID` to
/// ActionUIModel.  The engine fills in the item's title and keyboard shortcut.
@MainActor
private func actionUIModelMenuItem(_ properties: [String: Any]) -> NSMenuItem? {
    let item = NSMenuItem()
    if let actionID = properties["actionID"] as? String {
        item.action = #selector(MenuActionTarget.performAction(_:))
        item.target = MenuActionTarget.shared
        item.tag = MenuActionTarget.shared.registerActionID(actionID)
    }
    return item
}

// MARK: - Default menu bar + commands (host convenience wrappers)

/// Builds and installs the standard macOS menu bar on NSApp, using the host's
/// custom About handler.  Call once, before `NSApplication.run()`.
@MainActor
func installDefaultMenuBar(appName: String? = nil) {
    ActionUIMenuBarBuilder.installDefaultMenuBar(
        appName: appName,
        aboutTarget: nil,
        aboutAction: #selector(ActionUIApplicationDelegate.showAboutPanel(_:))
    )
}

/// Load an array of CommandMenu / CommandGroup elements from a JSON string and
/// apply them to the current main menu, dispatching custom items through
/// ActionUIModel.
@MainActor
func loadMenuBarCommands(from jsonString: String) {
    ActionUIMenuBarBuilder.loadMenuBarCommands(json: jsonString,
                                               itemBuilder: actionUIModelMenuItem)
}

/// Every commands JSON given to `actionUIAppLoadMenuBar`, in call order, so the
/// commands can be applied again when the default menu bar is rebuilt at launch.
/// Mutated and read only on the main thread.
private nonisolated(unsafe) var loadedMenuBarCommands: [String] = []

/// Rebuilds the default menu bar with `appName` and applies again the commands
/// loaded so far.  Used at launch, when a menu bar built before the application
/// name was set carries stale titles.
@MainActor
func reinstallMenuBar(appName: String?) {
    installDefaultMenuBar(appName: appName)
    for json in loadedMenuBarCommands {
        loadMenuBarCommands(from: json)
    }
}

// MARK: - C API

/// Install the default menu bar and optionally apply commands from a JSON string.
///
/// - Parameter jsonString: Optional JSON array of CommandMenu / CommandGroup
///   elements.  Pass NULL to install only the default menu bar.
///
/// May be called before or after `actionUIAppRun`, and more than once: each
/// call adds to the menu bar.  Commands loaded before launch survive the
/// rebuild of the default menu bar that `actionUIAppSetName` causes at launch.
@_cdecl("actionUIAppLoadMenuBar")
public func actionUIAppLoadMenuBar(_ jsonString: UnsafePointer<CChar>?) {
    // Copy the C string into a Swift String before entering the
    // @MainActor-isolated closure to avoid capturing a non-Sendable pointer.
    let swiftJSON: String? = jsonString.map { String(cString: $0) }

    runOnMainActorSync {
        // NSApp is nil before NSApplication.shared has been accessed
        // (i.e. before actionUIAppRun).  Guard against that.
        let app = NSApplication.shared

        // Ensure default menu bar is installed.
        if app.mainMenu == nil || app.mainMenu?.items.isEmpty == true {
            installDefaultMenuBar()
        }

        // Apply custom commands if provided.
        if let json = swiftJSON {
            loadMenuBarCommands(from: json)
            loadedMenuBarCommands.append(json)
        }
    }
}
