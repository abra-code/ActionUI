// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

//
//  ActionUIAppMenuBar.swift
//  ActionUIMenuBar
//
//  Programmatic replacement for MainMenu.nib.
//
//  Builds the standard macOS menu bar (App, File, Edit, Format, Window, Help)
//  with all default items wired to their standard first-responder selectors,
//  and applies additional CommandMenu / CommandGroup items described in
//  ActionUI JSON.  JSON may also remove default items via RemoveMenu /
//  RemoveItem, so a host can pare the standard bar down to what it needs.
//
//  This library is lifecycle-free: it does NOT own the NSApplication, an app
//  delegate, or a run loop.  The two host-specific concerns — how a custom
//  menu item dispatches, and what the "About" item does — are injected by the
//  caller:
//
//    • Action items are produced by an `itemBuilder` closure.  The engine
//      handles all structure (placement, separators, titles, keyboard
//      shortcuts); the host returns a wired NSMenuItem for each Button element.
//    • The "About" item defaults to the standard
//      `NSApplication.orderFrontStandardAboutPanel(_:)` selector; a host may
//      supply its own target/action.
//
//  The host supplies the per-item action wiring through an injected item
//  builder, so this library has no knowledge of any particular host's command
//  or action model.
//

import AppKit
import Foundation
import ActionUI

/// Builds a wired NSMenuItem for a single "Button" element's `properties`
/// dictionary.  Return `nil` to skip the element.  The engine sets the item's
/// title and keyboard shortcut afterwards, so the builder only needs to handle
/// host-specific identity and action wiring (the host's own action identifier,
/// target, and action).
public typealias ActionUIMenuItemBuilder = (_ properties: [String: Any]) -> NSMenuItem?

// MARK: - Public facade

/// Lifecycle-free menu-bar construction shared by ActionUI hosts.
///
/// The Swift type name deliberately differs from the module name
/// `ActionUIMenuBar` to avoid the class-shadows-module problem
/// (Swift issue #56573), which otherwise breaks `.swiftinterface` emission in
/// library-evolution (framework) builds.  The Objective-C runtime name is
/// pinned to `ActionUIMenuBar` via `@objc(ActionUIMenuBar)` so existing ObjC
/// callers — e.g. `[ActionUIMenuBar installDefaultMenuBarWithAppName:]` — and the
/// generated `-Swift.h` are unaffected.
@objc(ActionUIMenuBar) public final class ActionUIMenuBarBuilder: NSObject {

    /// Builds and installs the standard macOS menu bar on NSApp, using the
    /// standard About panel.  Call once, before the run loop starts.
    @MainActor
    @objc(installDefaultMenuBarWithAppName:)
    public static func installDefaultMenuBar(appName: String?) {
        installDefaultMenuBar(appName: appName, aboutTarget: nil, aboutAction: nil)
    }

    /// Builds and installs the standard macOS menu bar on NSApp.
    ///
    /// - Parameters:
    ///   - appName: Title used for "About <app>", "Quit <app>", etc.  Defaults
    ///     to the process name.
    ///   - aboutTarget/aboutAction: Optional custom handler for the About item.
    ///     When `aboutAction` is nil the standard
    ///     `NSApplication.orderFrontStandardAboutPanel(_:)` is used.
    @MainActor
    @objc(installDefaultMenuBarWithAppName:aboutTarget:aboutAction:)
    public static func installDefaultMenuBar(appName: String?,
                                             aboutTarget: AnyObject?,
                                             aboutAction: Selector?) {
        let name = appName ?? ProcessInfo.processInfo.processName

        let mainMenu = NSMenu()

        // App menu (title is ignored by macOS; the system uses CFBundleName / processName)
        mainMenu.addItem(buildAppMenu(appName: name, aboutTarget: aboutTarget, aboutAction: aboutAction))

        // File menu
        mainMenu.addItem(buildFileMenu())

        // Edit menu
        mainMenu.addItem(buildEditMenu())

        // Format menu
        mainMenu.addItem(buildFormatMenu())

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

    /// Parse an array of CommandMenu / CommandGroup elements from a JSON string
    /// and apply them to the current main menu.  Requires that a main menu is
    /// already installed (call `installDefaultMenuBar` first).
    ///
    /// ```json
    /// [
    ///   { "type": "CommandMenu", "properties": { "name": "Tools" }, "children": [...] },
    ///   { "type": "CommandGroup", "properties": { "placement": "after", "placementTarget": "newItem" }, "children": [...] },
    ///   { "type": "RemoveMenu", "properties": { "name": "Format" } },
    ///   { "type": "RemoveItem", "properties": { "menu": "File", "title": "New" } }
    /// ]
    /// ```
    ///
    /// `RemoveMenu` deletes a whole top-level menu by its title; `RemoveItem`
    /// deletes a single item by title (optionally scoped to one menu via
    /// `menu`).  Both let a host pare the default bar down to what it needs.
    ///
    /// - Parameter itemBuilder: Produces a wired NSMenuItem for each Button
    ///   element; see `ActionUIMenuItemBuilder`.
    @MainActor
    @objc(loadMenuBarCommandsWithJSON:itemBuilder:)
    public static func loadMenuBarCommands(json jsonString: String,
                                           itemBuilder: @escaping ActionUIMenuItemBuilder) {
        let logger = ActionUIModel.shared.logger

        guard let data = jsonString.data(using: .utf8) else {
            logger.log("ActionUIMenuBar: invalid UTF-8 string", .error)
            return
        }

        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            logger.log("ActionUIMenuBar: JSON must be an array of command elements", .error)
            return
        }

        guard let mainMenu = NSApp.mainMenu else {
            logger.log("ActionUIMenuBar: no main menu installed; call installDefaultMenuBar first", .error)
            return
        }

        for element in jsonArray {
            guard let type = element["type"] as? String else {
                logger.log("ActionUIMenuBar: element missing 'type'", .warning)
                continue
            }

            let properties = element["properties"] as? [String: Any] ?? [:]
            let children = element["children"] as? [[String: Any]] ?? []

            switch type {
            case "CommandMenu":
                applyCommandMenu(properties: properties, children: children,
                                 to: mainMenu, itemBuilder: itemBuilder, logger: logger)

            case "CommandGroup":
                applyCommandGroup(properties: properties, children: children,
                                  to: mainMenu, itemBuilder: itemBuilder, logger: logger)

            case "RemoveMenu":
                applyRemoveMenu(properties: properties, from: mainMenu, logger: logger)

            case "RemoveItem":
                applyRemoveItem(properties: properties, from: mainMenu, logger: logger)

            default:
                logger.log("ActionUIMenuBar: unsupported command type '\(type)'", .warning)
            }
        }
    }
}

// MARK: - Individual default menus

@MainActor
private func buildAppMenu(appName: String, aboutTarget: AnyObject?, aboutAction: Selector?) -> NSMenuItem {
    let menu = NSMenu()   // title ignored for app menu

    // --- appInfo ---
    let appInfoSentinel = NSMenuItem.separator()
    appInfoSentinel.tag = MenuPlacementTag.appInfo.rawValue
    menu.addItem(appInfoSentinel)

    // About — standard panel by default, host override optional.
    let aboutItem = menu.addItem(withTitle: "About \(appName)",
                                 action: aboutAction ?? #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                                 keyEquivalent: "")
    aboutItem.target = aboutTarget

    // --- appSettings ---
    let appSettingsSentinel = NSMenuItem.separator()
    appSettingsSentinel.tag = MenuPlacementTag.appSettings.rawValue
    menu.addItem(appSettingsSentinel)

    // --- systemServices ---
    let systemServicesSentinel = NSMenuItem.separator()
    systemServicesSentinel.tag = MenuPlacementTag.systemServices.rawValue
    menu.addItem(systemServicesSentinel)

    let servicesMenu = NSMenu(title: "Services")
    let servicesItem = menu.addItem(withTitle: "Services", action: nil, keyEquivalent: "")
    servicesItem.submenu = servicesMenu
    NSApp.servicesMenu = servicesMenu

    // --- appVisibility ---
    let appVisibilitySentinel = NSMenuItem.separator()
    appVisibilitySentinel.tag = MenuPlacementTag.appVisibility.rawValue
    menu.addItem(appVisibilitySentinel)

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

    // --- appTermination ---
    let appTerminationSentinel = NSMenuItem.separator()
    appTerminationSentinel.tag = MenuPlacementTag.appTermination.rawValue
    menu.addItem(appTerminationSentinel)

    menu.addItem(withTitle: "Quit \(appName)",
                 action: #selector(NSApplication.terminate(_:)),
                 keyEquivalent: "q")

    let item = NSMenuItem()
    item.submenu = menu
    return item
}

@MainActor
private func buildFileMenu() -> NSMenuItem {
    let menu = NSMenu(title: "File")

    // --- New / Open group ---
    // Standard first-responder document actions: active when something in the
    // responder chain (or NSDocumentController) handles them, disabled otherwise.
    addStandardItem(menu, "New", NSSelectorFromString("newDocument:"), key: "n")
    addStandardItem(menu, "Open…", NSSelectorFromString("openDocument:"), key: "o")

    // Note: no "Open Recent" submenu is built here. AppKit only auto-populates an
    // Open Recent submenu for nib-based menus; a programmatic submenu stays empty
    // unless a host drives it explicitly, so hosts that want it add their own.

    // Sentinel marking the end of the New/Open group (CommandGroup target).
    let newItemSentinel = NSMenuItem.separator()
    newItemSentinel.tag = MenuPlacementTag.newItem.rawValue
    menu.addItem(newItemSentinel)

    // --- Close / Save group ---
    menu.addItem(withTitle: "Close",
                 action: #selector(NSWindow.performClose(_:)),
                 keyEquivalent: "w")

    let saveItemSentinel = NSMenuItem.separator()
    saveItemSentinel.tag = MenuPlacementTag.saveItem.rawValue
    menu.addItem(saveItemSentinel)

    // --- Import / Export group ---
    let importExportSentinel = NSMenuItem.separator()
    importExportSentinel.tag = MenuPlacementTag.importExport.rawValue
    menu.addItem(importExportSentinel)

    // --- Print group ---
    let printItemSentinel = NSMenuItem.separator()
    printItemSentinel.tag = MenuPlacementTag.printItem.rawValue
    menu.addItem(printItemSentinel)

    let item = NSMenuItem()
    item.submenu = menu
    return item
}

@MainActor
private func buildEditMenu() -> NSMenuItem {
    let menu = NSMenu(title: "Edit")

    // --- undoRedo ---
    let undoRedoSentinel = NSMenuItem.separator()
    undoRedoSentinel.tag = MenuPlacementTag.undoRedo.rawValue
    menu.addItem(undoRedoSentinel)

    menu.addItem(withTitle: "Undo",
                 action: NSSelectorFromString("undo:"),
                 keyEquivalent: "z")

    let redo = menu.addItem(withTitle: "Redo",
                            action: NSSelectorFromString("redo:"),
                            keyEquivalent: "z")
    redo.keyEquivalentModifierMask = [.command, .shift]

    // --- pasteboard ---
    let pasteboardSentinel = NSMenuItem.separator()
    pasteboardSentinel.tag = MenuPlacementTag.pasteboard.rawValue
    menu.addItem(pasteboardSentinel)

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

    // --- textEditing ---
    let textEditingSentinel = NSMenuItem.separator()
    textEditingSentinel.tag = MenuPlacementTag.textEditing.rawValue
    menu.addItem(textEditingSentinel)

    // --- textFormatting ---
    let textFormattingSentinel = NSMenuItem.separator()
    textFormattingSentinel.tag = MenuPlacementTag.textFormatting.rawValue
    menu.addItem(textFormattingSentinel)

    let item = NSMenuItem()
    item.submenu = menu
    return item
}

/// Add a default-menu item, optionally with a target, modifier mask, and tag,
/// in a single call.  A nil target leaves the item targeting the first
/// responder (the standard menu-action mechanism).
@MainActor
@discardableResult
private func addStandardItem(_ menu: NSMenu, _ title: String, _ action: Selector?,
                            key: String = "",
                            modifiers: NSEvent.ModifierFlags = .command,
                            target: AnyObject? = nil,
                            tag: Int = 0) -> NSMenuItem {
    let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
    if !key.isEmpty {
        item.keyEquivalentModifierMask = modifiers
    }
    if let target = target {
        item.target = target
    }
    item.tag = tag
    return item
}

/// Add a disabled label item that acts as a section header inside a submenu
/// (used for the Writing Direction "Paragraph"/"Selection" groups).
@MainActor
private func addSectionLabel(_ menu: NSMenu, _ title: String) {
    let item = menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
    item.isEnabled = false
}

@MainActor
private func buildFormatMenu() -> NSMenuItem {
    let menu = NSMenu(title: "Format")
    let fontManager = NSFontManager.shared

    // --- Font submenu ---
    // Bold/Italic/Bigger/Smaller and Show Fonts target the shared font manager;
    // its tag encodes the trait (bold = 2, italic = 1) or size action
    // (NSSizeUpFontAction = 3, NSSizeDownFontAction = 4).
    let fontMenu = NSMenu(title: "Font")
    addStandardItem(fontMenu, "Show Fonts", NSSelectorFromString("orderFrontFontPanel:"),
                    key: "t", target: fontManager)
    addStandardItem(fontMenu, "Bold", NSSelectorFromString("addFontTrait:"),
                    key: "b", target: fontManager, tag: 2)
    addStandardItem(fontMenu, "Italic", NSSelectorFromString("addFontTrait:"),
                    key: "i", target: fontManager, tag: 1)
    addStandardItem(fontMenu, "Underline", NSSelectorFromString("underline:"), key: "u")

    fontMenu.addItem(.separator())
    addStandardItem(fontMenu, "Bigger", NSSelectorFromString("modifyFont:"),
                    key: "+", target: fontManager, tag: 3)
    addStandardItem(fontMenu, "Smaller", NSSelectorFromString("modifyFont:"),
                    key: "-", target: fontManager, tag: 4)

    fontMenu.addItem(.separator())
    let kernMenu = NSMenu(title: "Kern")
    addStandardItem(kernMenu, "Use Default", NSSelectorFromString("useStandardKerning:"))
    addStandardItem(kernMenu, "Use None", NSSelectorFromString("turnOffKerning:"))
    addStandardItem(kernMenu, "Tighten", NSSelectorFromString("tightenKerning:"))
    addStandardItem(kernMenu, "Loosen", NSSelectorFromString("loosenKerning:"))
    fontMenu.addItem(withTitle: "Kern", action: nil, keyEquivalent: "").submenu = kernMenu

    let ligatureMenu = NSMenu(title: "Ligatures")
    addStandardItem(ligatureMenu, "Use Default", NSSelectorFromString("useStandardLigatures:"))
    addStandardItem(ligatureMenu, "Use None", NSSelectorFromString("turnOffLigatures:"))
    addStandardItem(ligatureMenu, "Use All", NSSelectorFromString("useAllLigatures:"))
    fontMenu.addItem(withTitle: "Ligatures", action: nil, keyEquivalent: "").submenu = ligatureMenu

    let baselineMenu = NSMenu(title: "Baseline")
    addStandardItem(baselineMenu, "Use Default", NSSelectorFromString("unscript:"))
    addStandardItem(baselineMenu, "Superscript", NSSelectorFromString("superscript:"))
    addStandardItem(baselineMenu, "Subscript", NSSelectorFromString("subscript:"))
    addStandardItem(baselineMenu, "Raise", NSSelectorFromString("raiseBaseline:"))
    addStandardItem(baselineMenu, "Lower", NSSelectorFromString("lowerBaseline:"))
    fontMenu.addItem(withTitle: "Baseline", action: nil, keyEquivalent: "").submenu = baselineMenu

    fontMenu.addItem(.separator())
    addStandardItem(fontMenu, "Show Colors", NSSelectorFromString("orderFrontColorPanel:"),
                    key: "c", modifiers: [.command, .shift])

    fontMenu.addItem(.separator())
    addStandardItem(fontMenu, "Copy Style", NSSelectorFromString("copyFont:"),
                    key: "c", modifiers: [.command, .option])
    addStandardItem(fontMenu, "Paste Style", NSSelectorFromString("pasteFont:"),
                    key: "v", modifiers: [.command, .option])

    menu.addItem(withTitle: "Font", action: nil, keyEquivalent: "").submenu = fontMenu

    // --- Text submenu ---
    let textMenu = NSMenu(title: "Text")
    addStandardItem(textMenu, "Align Left", NSSelectorFromString("alignLeft:"), key: "{")
    addStandardItem(textMenu, "Center", NSSelectorFromString("alignCenter:"), key: "|")
    addStandardItem(textMenu, "Justify", NSSelectorFromString("alignJustified:"))
    addStandardItem(textMenu, "Align Right", NSSelectorFromString("alignRight:"), key: "}")

    textMenu.addItem(.separator())
    let writingMenu = NSMenu(title: "Writing Direction")
    addSectionLabel(writingMenu, "Paragraph")
    addStandardItem(writingMenu, "Default", NSSelectorFromString("makeBaseWritingDirectionNatural:"))
    addStandardItem(writingMenu, "Left to Right", NSSelectorFromString("makeBaseWritingDirectionLeftToRight:"))
    addStandardItem(writingMenu, "Right to Left", NSSelectorFromString("makeBaseWritingDirectionRightToLeft:"))
    writingMenu.addItem(.separator())
    addSectionLabel(writingMenu, "Selection")
    addStandardItem(writingMenu, "Default", NSSelectorFromString("makeTextWritingDirectionNatural:"))
    addStandardItem(writingMenu, "Left to Right", NSSelectorFromString("makeTextWritingDirectionLeftToRight:"))
    addStandardItem(writingMenu, "Right to Left", NSSelectorFromString("makeTextWritingDirectionRightToLeft:"))
    textMenu.addItem(withTitle: "Writing Direction", action: nil, keyEquivalent: "").submenu = writingMenu

    textMenu.addItem(.separator())
    addStandardItem(textMenu, "Show Ruler", NSSelectorFromString("toggleRuler:"))
    addStandardItem(textMenu, "Copy Ruler", NSSelectorFromString("copyRuler:"),
                    key: "c", modifiers: [.command, .control])
    addStandardItem(textMenu, "Paste Ruler", NSSelectorFromString("pasteRuler:"),
                    key: "v", modifiers: [.command, .control])

    menu.addItem(withTitle: "Text", action: nil, keyEquivalent: "").submenu = textMenu

    let item = NSMenuItem()
    item.submenu = menu
    return item
}

@MainActor
private func buildWindowMenu() -> (NSMenuItem, NSMenu) {
    let menu = NSMenu(title: "Window")

    // --- windowSize ---
    let windowSizeSentinel = NSMenuItem.separator()
    windowSizeSentinel.tag = MenuPlacementTag.windowSize.rawValue
    menu.addItem(windowSizeSentinel)

    menu.addItem(withTitle: "Minimize",
                 action: #selector(NSWindow.performMiniaturize(_:)),
                 keyEquivalent: "m")

    menu.addItem(withTitle: "Zoom",
                 action: #selector(NSWindow.performZoom(_:)),
                 keyEquivalent: "")

    // --- windowArrangement ---
    let windowArrangementSentinel = NSMenuItem.separator()
    windowArrangementSentinel.tag = MenuPlacementTag.windowArrangement.rawValue
    menu.addItem(windowArrangementSentinel)

    menu.addItem(withTitle: "Bring All to Front",
                 action: #selector(NSApplication.arrangeInFront(_:)),
                 keyEquivalent: "")

    // --- windowList / singleWindowList ---
    let windowListSentinel = NSMenuItem.separator()
    windowListSentinel.tag = MenuPlacementTag.windowList.rawValue
    menu.addItem(windowListSentinel)

    let singleWindowListSentinel = NSMenuItem.separator()
    singleWindowListSentinel.tag = MenuPlacementTag.singleWindowList.rawValue
    menu.addItem(singleWindowListSentinel)

    let item = NSMenuItem()
    item.submenu = menu
    return (item, menu)
}

@MainActor
private func buildHelpMenu(appName: String) -> (NSMenuItem, NSMenu) {
    let menu = NSMenu(title: "Help")

    // --- help ---
    let helpSentinel = NSMenuItem.separator()
    helpSentinel.tag = MenuPlacementTag.help.rawValue
    menu.addItem(helpSentinel)

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

// MARK: - CommandMenu application

@MainActor
private func applyCommandMenu(properties: [String: Any],
                              children: [[String: Any]],
                              to mainMenu: NSMenu,
                              itemBuilder: ActionUIMenuItemBuilder,
                              logger: any ActionUILogger) {
    var name = properties["name"] as? String ?? "Menu"
    if name.isEmpty {
        logger.log("CommandMenu name must be a non-empty string; defaulting to 'Menu'", .warning)
        name = "Menu"
    }

    let menu = NSMenu(title: name)

    for child in children {
        if let item = buildMenuItem(from: child, itemBuilder: itemBuilder, logger: logger) {
            menu.addItem(item)
        }
    }

    let menuItem = NSMenuItem()
    menuItem.submenu = menu

    // Insert before Window menu (or Help if no Window menu found).
    // This keeps Window and Help as the rightmost menus per macOS convention.
    var insertIndex = mainMenu.items.count
    if let windowIndex = mainMenu.items.firstIndex(where: { $0.submenu?.title == "Window" }) {
        insertIndex = windowIndex
    } else if let helpIndex = mainMenu.items.firstIndex(where: { $0.submenu?.title == "Help" }) {
        insertIndex = helpIndex
    }
    mainMenu.insertItem(menuItem, at: insertIndex)
}

// MARK: - CommandGroup application

@MainActor
private func applyCommandGroup(properties: [String: Any],
                               children: [[String: Any]],
                               to mainMenu: NSMenu,
                               itemBuilder: ActionUIMenuItemBuilder,
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
                                     children: children, to: mainMenu,
                                     itemBuilder: itemBuilder, logger: logger)
        return
    }

    let newItems = children.compactMap { buildMenuItem(from: $0, itemBuilder: itemBuilder, logger: logger) }
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
                                          itemBuilder: ActionUIMenuItemBuilder,
                                          logger: any ActionUILogger) {
    // Determine which top-level menu to target
    let menuTitle: String
    switch placementTarget {
    case "appInfo", "appSettings", "systemServices", "appVisibility", "appTermination":
        // App menu is the first item
        if let appMenu = mainMenu.items.first?.submenu {
            appendItems(children, to: appMenu, itemBuilder: itemBuilder, logger: logger)
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
        appendItems(children, to: targetMenu, itemBuilder: itemBuilder, logger: logger)
    } else {
        logger.log("CommandGroup: menu '\(menuTitle)' not found in main menu", .warning)
    }
}

@MainActor
private func appendItems(_ children: [[String: Any]],
                         to menu: NSMenu,
                         itemBuilder: ActionUIMenuItemBuilder,
                         logger: any ActionUILogger) {
    for child in children {
        if let item = buildMenuItem(from: child, itemBuilder: itemBuilder, logger: logger) {
            menu.addItem(item)
        }
    }
}

// MARK: - Default item removal

/// Remove a whole top-level menu (e.g. "Format") from the main menu by title.
@MainActor
private func applyRemoveMenu(properties: [String: Any],
                             from mainMenu: NSMenu,
                             logger: any ActionUILogger) {
    guard let name = properties["name"] as? String, !name.isEmpty else {
        logger.log("RemoveMenu: missing 'name'", .warning)
        return
    }

    if let index = mainMenu.items.firstIndex(where: { $0.submenu?.title == name }) {
        mainMenu.removeItem(at: index)
    } else {
        logger.log("RemoveMenu: top-level menu '\(name)' not found", .warning)
    }
}

/// Remove a single item by title.  When `menu` is given the search is scoped to
/// that top-level menu; otherwise the first match across all menus is removed.
@MainActor
private func applyRemoveItem(properties: [String: Any],
                             from mainMenu: NSMenu,
                             logger: any ActionUILogger) {
    guard let title = properties["title"] as? String, !title.isEmpty else {
        logger.log("RemoveItem: missing 'title'", .warning)
        return
    }
    let menuName = properties["menu"] as? String

    for topLevelItem in mainMenu.items {
        guard let submenu = topLevelItem.submenu else { continue }
        if let menuName = menuName, submenu.title != menuName { continue }
        if let index = submenu.items.firstIndex(where: { $0.title == title }) {
            submenu.removeItem(at: index)
            return
        }
        if menuName != nil { break }
    }

    let scope = menuName.map { " in menu '\($0)'" } ?? ""
    logger.log("RemoveItem: '\(title)'\(scope) not found", .warning)
}

// MARK: - Sentinel finding

/// Recursively search all submenus of `mainMenu` for an item with the given tag.
/// Returns the submenu and the index of the tagged item within it.
@MainActor
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
private func buildMenuItem(from element: [String: Any],
                           itemBuilder: ActionUIMenuItemBuilder,
                           logger: any ActionUILogger) -> NSMenuItem? {
    guard let type = element["type"] as? String else {
        logger.log("Menu child element missing 'type'", .warning)
        return nil
    }

    switch type {
    case "Divider", "Separator":
        return .separator()

    case "Button":
        let properties = element["properties"] as? [String: Any] ?? [:]
        guard let item = itemBuilder(properties) else {
            return nil
        }
        configureActionItem(item, properties: properties)
        return item

    default:
        logger.log("Unsupported menu child type '\(type)'; only Button and Divider are supported", .warning)
        return nil
    }
}

/// Apply the engine-owned structure (title + keyboard shortcut) onto an item
/// produced by the host's `itemBuilder`.
@MainActor
private func configureActionItem(_ item: NSMenuItem, properties: [String: Any]) {
    if let title = properties["title"] as? String {
        item.title = title
    }

    if let shortcut = properties["keyboardShortcut"] as? [String: Any],
       let key = shortcut["key"] as? String {
        item.keyEquivalent = resolveKeyEquivalent(key)
        let mask = resolveModifierMask(shortcut["modifiers"] as? [String] ?? ["command"])
        if !mask.isEmpty {
            item.keyEquivalentModifierMask = mask
        }
    }
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
