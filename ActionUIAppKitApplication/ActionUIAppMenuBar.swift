// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

//
//  ActionUIAppMenuBar.swift
//  ActionUIAppKitApplication
//
//  Programmatic replacement for MainMenu.nib.
//
//  Builds the standard macOS menu bar (App, File, Edit, Window, Help)
//  with all default items wired to their standard first-responder selectors.
//
//  Supports loading additional CommandMenu / CommandGroup items from ActionUI
//  JSON to customise the menu bar at startup.
//

import AppKit
import Foundation
import ActionUI

// MARK: - Main-actor dispatch helper (file-private copy)
//
// Each file in ActionUIAppKitApplication keeps its own private copy to avoid
// exposing a module-internal symbol that could collide with the identically
// named private function in ActionUICAdapter when both static libraries are
// linked into the same binary.

@inline(__always)
private func runOnMainActorSync<T>(_ operation: @MainActor () -> T) -> T {
    if Thread.isMainThread {
        return MainActor.assumeIsolated { operation() }
    } else {
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated { operation() }
        }
    }
}

// MARK: - Default menu bar construction

/// Builds and installs the standard macOS menu bar on NSApp.
/// Call once, before `NSApplication.run()`.
@MainActor
func installDefaultMenuBar(appName: String? = nil) {
    let name = appName ?? ProcessInfo.processInfo.processName

    let mainMenu = NSMenu()

    // App menu (title is ignored by macOS; the system uses CFBundleName / processName)
    mainMenu.addItem(buildAppMenu(appName: name))

    // File menu
    mainMenu.addItem(buildFileMenu())

    // Edit menu
    mainMenu.addItem(buildEditMenu())

    // Window menu
    let (windowMenuItem, windowMenu) = buildWindowMenu()
    mainMenu.addItem(windowMenuItem)

    // Help menu
    let (helpMenuItem, helpMenu) = buildHelpMenu(appName: name)
    mainMenu.addItem(helpMenuItem)

    NSApp.mainMenu = mainMenu
    NSApp.windowsMenu = windowMenu
    NSApp.helpMenu = helpMenu

    // Force the app menu's bold title in the menu bar.
    // macOS normally derives this from the bundle's CFBundleName, which
    // for unbundled processes (e.g. Python) is wrong.  Setting the first
    // menu item's title directly is the only known workaround.
    if let appMenuItem = mainMenu.items.first {
        appMenuItem.title = name
        appMenuItem.submenu?.title = name
    }
}

// MARK: - Individual default menus

private func buildAppMenu(appName: String) -> NSMenuItem {
    let menu = NSMenu()   // title ignored for app menu

    menu.addItem(withTitle: "About \(appName)",
                 action: #selector(ActionUIApplicationDelegate.showAboutPanel(_:)),
                 keyEquivalent: "")

    menu.addItem(.separator())

    let servicesMenu = NSMenu(title: "Services")
    let servicesItem = menu.addItem(withTitle: "Services", action: nil, keyEquivalent: "")
    servicesItem.submenu = servicesMenu
    NSApp.servicesMenu = servicesMenu

    menu.addItem(.separator())

    menu.addItem(withTitle: "Hide \(appName)",
                 action: #selector(NSApplication.hide(_:)),
                 keyEquivalent: "h")

    let hideOthers = menu.addItem(withTitle: "Hide Others",
                                  action: #selector(NSApplication.hideOtherApplications(_:)),
                                  keyEquivalent: "h")
    hideOthers.keyEquivalentModifierMask = [.command, .option]

    menu.addItem(withTitle: "Show All",
                 action: #selector(NSApplication.unhideAllApplications(_:)),
                 keyEquivalent: "")

    menu.addItem(.separator())

    menu.addItem(withTitle: "Quit \(appName)",
                 action: #selector(NSApplication.terminate(_:)),
                 keyEquivalent: "q")

    let item = NSMenuItem()
    item.submenu = menu
    return item
}

private func buildFileMenu() -> NSMenuItem {
    let menu = NSMenu(title: "File")

    menu.addItem(withTitle: "Close",
                 action: #selector(NSWindow.performClose(_:)),
                 keyEquivalent: "w")

    let item = NSMenuItem()
    item.submenu = menu
    return item
}

private func buildEditMenu() -> NSMenuItem {
    let menu = NSMenu(title: "Edit")

    menu.addItem(withTitle: "Undo",
                 action: Selector(("undo:")),
                 keyEquivalent: "z")

    let redo = menu.addItem(withTitle: "Redo",
                            action: Selector(("redo:")),
                            keyEquivalent: "z")
    redo.keyEquivalentModifierMask = [.command, .shift]

    menu.addItem(.separator())

    menu.addItem(withTitle: "Cut",
                 action: #selector(NSText.cut(_:)),
                 keyEquivalent: "x")

    menu.addItem(withTitle: "Copy",
                 action: #selector(NSText.copy(_:)),
                 keyEquivalent: "c")

    menu.addItem(withTitle: "Paste",
                 action: #selector(NSText.paste(_:)),
                 keyEquivalent: "v")

    menu.addItem(withTitle: "Delete",
                 action: #selector(NSText.delete(_:)),
                 keyEquivalent: "")

    menu.addItem(withTitle: "Select All",
                 action: #selector(NSText.selectAll(_:)),
                 keyEquivalent: "a")

    let item = NSMenuItem()
    item.submenu = menu
    return item
}

private func buildWindowMenu() -> (NSMenuItem, NSMenu) {
    let menu = NSMenu(title: "Window")

    menu.addItem(withTitle: "Minimize",
                 action: #selector(NSWindow.performMiniaturize(_:)),
                 keyEquivalent: "m")

    menu.addItem(withTitle: "Zoom",
                 action: #selector(NSWindow.performZoom(_:)),
                 keyEquivalent: "")

    menu.addItem(.separator())

    menu.addItem(withTitle: "Bring All to Front",
                 action: #selector(NSApplication.arrangeInFront(_:)),
                 keyEquivalent: "")

    let item = NSMenuItem()
    item.submenu = menu
    return (item, menu)
}

private func buildHelpMenu(appName: String) -> (NSMenuItem, NSMenu) {
    let menu = NSMenu(title: "Help")

    menu.addItem(withTitle: "\(appName) Help",
                 action: #selector(NSApplication.showHelp(_:)),
                 keyEquivalent: "?")

    let item = NSMenuItem()
    item.submenu = menu
    return (item, menu)
}

// MARK: - Tag-based placement target system
//
// Each default menu and "region" within a menu is assigned a tag so that
// CommandGroup's placementTarget can locate the right insertion point.
// Tags are internal-only and never exposed to the caller.

/// Maps CommandGroup `placementTarget` strings to an NSMenuItem tag.
/// The tag is set on a sentinel separator in each region of the default menus.
private enum MenuPlacementTag: Int {
    // App menu regions
    case appInfo         = 1001
    case appSettings     = 1002
    case systemServices  = 1003
    case appVisibility   = 1004
    case appTermination  = 1005

    // File menu regions
    case newItem         = 2001
    case saveItem        = 2002
    case importExport    = 2003
    case printItem       = 2004

    // Edit menu regions
    case undoRedo        = 3001
    case pasteboard      = 3002
    case textEditing     = 3003
    case textFormatting  = 3004

    // View menu regions
    case toolbar         = 4001
    case sidebar         = 4002

    // Window menu regions
    case windowSize        = 5001
    case windowList        = 5002
    case singleWindowList  = 5003
    case windowArrangement = 5004

    // Help menu
    case help            = 6001

    static func from(_ target: String) -> MenuPlacementTag? {
        switch target {
        case "appInfo":           return .appInfo
        case "appSettings":       return .appSettings
        case "systemServices":    return .systemServices
        case "appVisibility":     return .appVisibility
        case "appTermination":    return .appTermination
        case "newItem":           return .newItem
        case "saveItem":          return .saveItem
        case "importExport":      return .importExport
        case "printItem":         return .printItem
        case "undoRedo":          return .undoRedo
        case "pasteboard":        return .pasteboard
        case "textEditing":       return .textEditing
        case "textFormatting":    return .textFormatting
        case "toolbar":           return .toolbar
        case "sidebar":           return .sidebar
        case "windowSize":        return .windowSize
        case "windowList":        return .windowList
        case "singleWindowList":  return .singleWindowList
        case "windowArrangement": return .windowArrangement
        case "help":              return .help
        default:                  return nil
        }
    }
}

// MARK: - CommandMenu / CommandGroup to NSMenu adapter

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
        ActionUIModel.shared.actionHandler(
            actionID,
            windowUUID: "",        // menu actions are not window-scoped
            viewID: sender.tag,
            viewPartID: 0,
            context: nil
        )
    }
}

/// Load an array of CommandMenu / CommandGroup elements from a JSON string
/// and apply them to the current main menu.
///
/// The JSON must be an array of elements:
/// ```json
/// [
///   { "type": "CommandMenu", "id": 100, "properties": { "name": "Tools" }, "children": [...] },
///   { "type": "CommandGroup", "id": 200, "properties": { "placement": "after", "placementTarget": "newItem" }, "children": [...] }
/// ]
/// ```
@MainActor
func loadMenuBarCommands(from jsonString: String) {
    let logger = ActionUIModel.shared.logger

    guard let data = jsonString.data(using: .utf8) else {
        logger.log("loadMenuBarCommands: invalid UTF-8 string", .error)
        return
    }

    guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
        logger.log("loadMenuBarCommands: JSON must be an array of command elements", .error)
        return
    }

    guard let mainMenu = NSApp.mainMenu else {
        logger.log("loadMenuBarCommands: no main menu installed; call actionUIAppRun first", .error)
        return
    }

    for element in jsonArray {
        guard let type = element["type"] as? String else {
            logger.log("loadMenuBarCommands: element missing 'type'", .warning)
            continue
        }

        let properties = element["properties"] as? [String: Any] ?? [:]
        let children = element["children"] as? [[String: Any]] ?? []

        switch type {
        case "CommandMenu":
            applyCommandMenu(properties: properties, children: children,
                             to: mainMenu, logger: logger)

        case "CommandGroup":
            applyCommandGroup(properties: properties, children: children,
                              to: mainMenu, logger: logger)

        default:
            logger.log("loadMenuBarCommands: unsupported command type '\(type)'", .warning)
        }
    }
}

// MARK: - CommandMenu application

@MainActor
private func applyCommandMenu(properties: [String: Any],
                               children: [[String: Any]],
                               to mainMenu: NSMenu,
                               logger: any ActionUILogger) {
    var name = properties["name"] as? String ?? "Menu"
    if name.isEmpty {
        logger.log("CommandMenu name must be a non-empty string; defaulting to 'Menu'", .warning)
        name = "Menu"
    }

    let menu = NSMenu(title: name)

    for child in children {
        if let item = buildMenuItem(from: child, logger: logger) {
            menu.addItem(item)
        }
    }

    let menuItem = NSMenuItem()
    menuItem.submenu = menu

    // Insert before the Help menu (last item), or append if no items
    let helpIndex = mainMenu.items.count > 0 ? mainMenu.items.count - 1 : 0
    mainMenu.insertItem(menuItem, at: helpIndex)
}

// MARK: - CommandGroup application

@MainActor
private func applyCommandGroup(properties: [String: Any],
                                children: [[String: Any]],
                                to mainMenu: NSMenu,
                                logger: any ActionUILogger) {
    let placement = properties["placement"] as? String ?? "after"
    let placementTarget = properties["placementTarget"] as? String ?? "help"

    guard let targetTag = MenuPlacementTag.from(placementTarget) else {
        logger.log("CommandGroup: unknown placementTarget '\(placementTarget)'", .warning)
        return
    }

    // Find the menu and index of the tagged sentinel item
    guard let (menu, sentinelIndex) = findSentinelItem(tag: targetTag.rawValue, in: mainMenu) else {
        // No sentinel found — fall back to positional heuristic
        applyCommandGroupByHeuristic(placement: placement, placementTarget: placementTarget,
                                     children: children, to: mainMenu, logger: logger)
        return
    }

    let newItems = children.compactMap { buildMenuItem(from: $0, logger: logger) }
    guard !newItems.isEmpty else { return }

    switch placement {
    case "replacing":
        // Replace the sentinel item with the new items
        menu.removeItem(at: sentinelIndex)
        for (offset, item) in newItems.enumerated() {
            menu.insertItem(item, at: sentinelIndex + offset)
        }

    case "before":
        for (offset, item) in newItems.enumerated() {
            menu.insertItem(item, at: sentinelIndex + offset)
        }

    default: // "after"
        let insertAt = sentinelIndex + 1
        for (offset, item) in newItems.enumerated() {
            menu.insertItem(item, at: min(insertAt + offset, menu.items.count))
        }
    }
}

/// Heuristic fallback: find the right menu by placementTarget name and append at end.
@MainActor
private func applyCommandGroupByHeuristic(placement: String,
                                           placementTarget: String,
                                           children: [[String: Any]],
                                           to mainMenu: NSMenu,
                                           logger: any ActionUILogger) {
    // Determine which top-level menu to target
    let menuTitle: String
    switch placementTarget {
    case "appInfo", "appSettings", "systemServices", "appVisibility", "appTermination":
        // App menu is the first item
        if let appMenu = mainMenu.items.first?.submenu {
            appendItems(children, to: appMenu, logger: logger)
        }
        return
    case "newItem", "saveItem", "importExport", "printItem":
        menuTitle = "File"
    case "undoRedo", "pasteboard", "textEditing", "textFormatting":
        menuTitle = "Edit"
    case "toolbar", "sidebar":
        menuTitle = "View"
    case "windowSize", "windowList", "singleWindowList", "windowArrangement":
        menuTitle = "Window"
    case "help":
        menuTitle = "Help"
    default:
        logger.log("CommandGroup: cannot locate menu for placementTarget '\(placementTarget)'", .warning)
        return
    }

    if let targetMenu = mainMenu.items.first(where: { $0.submenu?.title == menuTitle })?.submenu {
        appendItems(children, to: targetMenu, logger: logger)
    } else {
        logger.log("CommandGroup: menu '\(menuTitle)' not found in main menu", .warning)
    }
}

@MainActor
private func appendItems(_ children: [[String: Any]], to menu: NSMenu, logger: any ActionUILogger) {
    for child in children {
        if let item = buildMenuItem(from: child, logger: logger) {
            menu.addItem(item)
        }
    }
}

// MARK: - Sentinel finding

/// Recursively search all submenus of `mainMenu` for an item with the given tag.
/// Returns the submenu and the index of the tagged item within it.
private func findSentinelItem(tag: Int, in mainMenu: NSMenu) -> (NSMenu, Int)? {
    for topLevelItem in mainMenu.items {
        guard let submenu = topLevelItem.submenu else { continue }
        if let index = submenu.items.firstIndex(where: { $0.tag == tag }) {
            return (submenu, index)
        }
    }
    return nil
}

// MARK: - NSMenuItem construction from JSON child elements

@MainActor
private func buildMenuItem(from element: [String: Any], logger: any ActionUILogger) -> NSMenuItem? {
    guard let type = element["type"] as? String else {
        logger.log("Menu child element missing 'type'", .warning)
        return nil
    }

    switch type {
    case "Divider", "Separator":
        return .separator()

    case "Button":
        let properties = element["properties"] as? [String: Any] ?? [:]
        return buildButtonMenuItem(properties: properties, logger: logger)

    default:
        logger.log("Unsupported menu child type '\(type)'; only Button and Divider are supported", .warning)
        return nil
    }
}

@MainActor
private func buildButtonMenuItem(properties: [String: Any], logger: any ActionUILogger) -> NSMenuItem {
    let title = properties["title"] as? String ?? "Untitled"
    let actionID = properties["actionID"] as? String

    // Parse keyboard shortcut
    var keyEquivalent = ""
    var modifierMask: NSEvent.ModifierFlags = []

    if let shortcut = properties["keyboardShortcut"] as? [String: Any],
       let key = shortcut["key"] as? String {
        keyEquivalent = resolveKeyEquivalent(key)
        modifierMask = resolveModifierMask(shortcut["modifiers"] as? [String] ?? ["command"])
    }

    let item: NSMenuItem
    if actionID != nil {
        // Custom action — route through our action target
        item = NSMenuItem(title: title,
                          action: #selector(MenuActionTarget.performAction(_:)),
                          keyEquivalent: keyEquivalent)
        item.target = MenuActionTarget.shared
        item.tag = MenuActionTarget.shared.registerActionID(actionID!)
    } else {
        // No actionID — just a menu item with no action (could be a submenu header, etc.)
        item = NSMenuItem(title: title, action: nil, keyEquivalent: keyEquivalent)
    }

    if !modifierMask.isEmpty {
        item.keyEquivalentModifierMask = modifierMask
    }

    return item
}

// MARK: - Key equivalent and modifier resolution

/// Convert an ActionUI key string to an AppKit key equivalent string.
private func resolveKeyEquivalent(_ key: String) -> String {
    switch key.lowercased() {
    case "return", "enter":       return "\r"
    case "tab":                   return "\t"
    case "space":                 return " "
    case "escape":                return "\u{1B}"
    case "delete", "backspace":   return "\u{08}"
    case "deleteforward":         return "\u{7F}"
    case "uparrow":               return String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))
    case "downarrow":             return String(Character(UnicodeScalar(NSDownArrowFunctionKey)!))
    case "leftarrow":             return String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!))
    case "rightarrow":            return String(Character(UnicodeScalar(NSRightArrowFunctionKey)!))
    case "home":                  return String(Character(UnicodeScalar(NSHomeFunctionKey)!))
    case "end":                   return String(Character(UnicodeScalar(NSEndFunctionKey)!))
    case "pageup":                return String(Character(UnicodeScalar(NSPageUpFunctionKey)!))
    case "pagedown":              return String(Character(UnicodeScalar(NSPageDownFunctionKey)!))
    case "f1":                    return String(Character(UnicodeScalar(NSF1FunctionKey)!))
    case "f2":                    return String(Character(UnicodeScalar(NSF2FunctionKey)!))
    case "f3":                    return String(Character(UnicodeScalar(NSF3FunctionKey)!))
    case "f4":                    return String(Character(UnicodeScalar(NSF4FunctionKey)!))
    case "f5":                    return String(Character(UnicodeScalar(NSF5FunctionKey)!))
    case "f6":                    return String(Character(UnicodeScalar(NSF6FunctionKey)!))
    case "f7":                    return String(Character(UnicodeScalar(NSF7FunctionKey)!))
    case "f8":                    return String(Character(UnicodeScalar(NSF8FunctionKey)!))
    case "f9":                    return String(Character(UnicodeScalar(NSF9FunctionKey)!))
    case "f10":                   return String(Character(UnicodeScalar(NSF10FunctionKey)!))
    case "f11":                   return String(Character(UnicodeScalar(NSF11FunctionKey)!))
    case "f12":                   return String(Character(UnicodeScalar(NSF12FunctionKey)!))
    default:
        // Single character — return as-is (lowercased for AppKit convention)
        return key.lowercased()
    }
}

/// Convert an ActionUI modifiers array to AppKit modifier flags.
private func resolveModifierMask(_ modifiers: [String]) -> NSEvent.ModifierFlags {
    var mask: NSEvent.ModifierFlags = []
    for mod in modifiers {
        switch mod.lowercased() {
        case "command":  mask.insert(.command)
        case "shift":    mask.insert(.shift)
        case "option":   mask.insert(.option)
        case "control":  mask.insert(.control)
        case "capslock": mask.insert(.capsLock)
        default: break
        }
    }
    return mask
}

// MARK: - C API

/// Install the default menu bar and optionally apply commands from a JSON string.
///
/// - Parameter jsonString: Optional JSON array of CommandMenu / CommandGroup elements.
///   Pass NULL to install only the default menu bar.
@_cdecl("actionUIAppLoadMenuBar")
public func actionUIAppLoadMenuBar(_ jsonString: UnsafePointer<CChar>?) {
    // Copy the C string into a Swift String before entering the
    // @MainActor-isolated closure to avoid capturing a non-Sendable pointer.
    let swiftJSON: String? = jsonString.map { String(cString: $0) }

    runOnMainActorSync {
        // NSApp is nil before NSApplication.shared has been accessed
        // (i.e. before actionUIAppRun).  Guard against that.
        let app = NSApplication.shared

        // Ensure default menu bar is installed
        if app.mainMenu == nil || app.mainMenu?.items.isEmpty == true {
            installDefaultMenuBar()
        }

        // Apply custom commands if provided
        if let json = swiftJSON {
            loadMenuBarCommands(from: json)
        }
    }
}
