// Sources/Runtime/AppCommands+WinUI.swift
/*
 The application's commands on Windows: the CommandMenu and CommandGroup elements a host loads
 (actionUIAppLoadMenuBar, WinUIApplication.loadMenuBar), which macOS puts in its menu bar and Linux in
 GNOME's primary menu, shown in a menu bar across the top of each window, as Windows desktop programs
 show theirs (Notepad, Paint). A window shows one once the host has loaded commands, even none; until
 then a window has no menu bar, as most WinUI programs have none.

 The menus, left to right, each shown only when it has an item:
 - File: the items at newItem, saveItem, importExport and printItem, then Exit (appTermination).
 - Edit: undoRedo, pasteboard, textEditing. Format: textFormatting. View: toolbar, sidebar.
 - Each CommandMenu, a menu titled with its name, in the order loaded (where macOS puts them).
 - Tools: appSettings (where Windows programs keep their options).
 - Window: windowSize, windowArrangement, windowList, singleWindowList, and what Windows has no place
   for (systemServices, appVisibility).
 - Help: help, then "About <name>" (appInfo).
 A target's items are a section of their menu, between separators. A group's items come before
 ("before") or after ("after") the target's own; "replacing" puts them in its place, and without
 children takes the target's own away. Only appInfo (About) and appTermination (Exit, which asks the
 shouldTerminate handler, as closing the last window does) have items of their own; Exit has no
 shortcut, as on Windows Alt+F4 closes a window. A target may also be what macOS's menu bar names, read
 as on Linux (AppCommands on Linux: "new" is newItem, the menu "Edit" undoRedo, and so on); any other
 target is help, as Core reads a missing one. A Divider (or Separator) starts a new section; a Menu is a
 submenu holding its own Buttons, Dividers and Menus.
 Button is the one action item, as on macOS and Linux: its title, its keyboardShortcut as the item's
 keyboard accelerator (read as a view's keyboardShortcut is on WinUI: command and control are Ctrl,
 option Alt), which works while its menu is closed and which the menu shows beside the title; disabled
 or no actionID grays it out. Choosing one fires its actionID for the JSON of the window whose menu bar
 it is, with the element's id as viewID.

 Not yet on Windows: a WindowGroup's own commands (WindowGroup roots are not read yet), and the
 version and copyright line Linux's About shows.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CWinUI

@MainActor
package final class AppCommands {
    package static let shared = AppCommands()

    /// The CommandMenu and CommandGroup elements loaded, in order.
    private var commands: [[String: Any]] = []
    /// Whether the host has loaded commands (even none): then every window shows a menu bar.
    package private(set) var isLoaded = false
    /// The name About shows.
    package var appName: @MainActor () -> String = { ProcessInfo.processInfo.processName }
    /// What Exit does (the application's terminate, which asks shouldTerminate).
    package var exitHandler: (@MainActor () -> Void)?
    /// What About does (the application's alert naming it).
    package var aboutHandler: (@MainActor (_ name: String) -> Void)?
    /// Called after the commands change, so each window's menu bar is made again.
    package var changed: (@MainActor () -> Void)?

    /// A separate instance for tests; the application uses `shared`.
    package init() {}

    // MARK: Loading

    /// Adds the CommandMenu and CommandGroup elements in `json` (an array of them); nil only makes the
    /// menu bar show. Returns false, logging why and changing nothing, for JSON that is not such an array.
    @discardableResult
    package func load(json: String?) -> Bool {
        if let json {
            guard let parsed = try? ActionUIJSON.value(from: json), let array = parsed as? [Any] else {
                ActionUIModel.shared.logger.log("Menu commands: the JSON is not an array", .error)
                return false
            }
            commands += array.compactMap { $0 as? [String: Any] }
        }
        isLoaded = true
        changed?()
        return true
    }

    // MARK: Targets

    static let fileTargets = ["newItem", "saveItem", "importExport", "printItem", "appTermination"]
    static let editTargets = ["undoRedo", "pasteboard", "textEditing"]
    static let formatTargets = ["textFormatting"]
    static let viewTargets = ["toolbar", "sidebar"]
    static let toolsTargets = ["appSettings"]
    static let windowTargets = ["windowSize", "windowArrangement", "windowList", "singleWindowList",
                                "systemServices", "appVisibility"]
    static let helpTargets = ["help", "appInfo"]

    /// The SwiftUI group a macOS menu bar name stands for (as on Linux).
    static let macOSNames: [String: String] = [
        "new": "newItem", "open": "newItem", "close": "saveItem",
        "undo": "undoRedo", "redo": "undoRedo",
        "cut": "pasteboard", "copy": "pasteboard", "paste": "pasteboard", "delete": "pasteboard", "selectAll": "pasteboard",
        "minimize": "windowSize", "zoom": "windowSize", "bringAllToFront": "windowArrangement",
        "services": "systemServices", "hide": "appVisibility", "hideOthers": "appVisibility", "showAll": "appVisibility",
        "about": "appInfo", "quit": "appTermination",
        "File": "newItem", "Edit": "undoRedo", "Format": "textFormatting", "View": "toolbar", "Window": "windowSize", "Help": "help",
    ]

    /// The target a placementTarget names: one of the menus', or a macOS menu bar name for the target
    /// where that kind of item is kept; any other is help, as Core reads a missing one.
    static func target(_ name: String?) -> String {
        guard let name else { return "help" }
        let all = fileTargets + editTargets + formatTargets + viewTargets + toolsTargets + windowTargets + helpTargets
        if all.contains(name) {
            return name
        }
        return macOSNames[name] ?? "help"
    }

    // MARK: The menus

    /// One menu entry: a Button, a Menu, a Divider, or one of the two items of ActionUI's own.
    enum Entry {
        case item(title: String, actionID: String?, viewID: Int, shortcut: BaseModifiers.KeyboardShortcut?, disabled: Bool)
        case submenu(title: String, entries: [Entry])
        case about
        case exit
        case divider
    }

    /// The menu bar's menus as titles and entries, in order, each with at least one item. Internal, for
    /// tests.
    func menus() -> [(title: String, entries: [Entry])] {
        var groups: [String: [(placement: String, entries: [Entry])]] = [:]
        var commandMenus: [(title: String, entries: [Entry])] = []
        for command in commands {
            let properties = command["properties"] as? [String: Any] ?? [:]
            let entries = (command["children"] as? [[String: Any]] ?? []).compactMap(Self.entry)
            switch command["type"] as? String {
            case "CommandMenu":
                guard let name = properties["name"] as? String, !name.isEmpty else { continue }
                commandMenus.append((name, entries))
            case "CommandGroup":
                let target = Self.target(properties["placementTarget"] as? String)
                let placement = (properties["placement"] as? String).flatMap { ["before", "after", "replacing"].contains($0) ? $0 : nil } ?? "after"
                groups[target, default: []].append((placement, entries))
            default:
                continue
            }
        }
        func menu(_ targets: [String]) -> [Entry] {
            var entries: [Entry] = []
            for target in targets {
                let defaults: [Entry] = target == "appInfo" ? [.about] : target == "appTermination" ? [.exit] : []
                let placed = groups[target] ?? []
                let replacing = placed.filter { $0.placement == "replacing" }
                var section = placed.filter { $0.placement == "before" }.flatMap(\.entries)
                section += replacing.isEmpty ? defaults : replacing.flatMap(\.entries)
                section += placed.filter { $0.placement == "after" }.flatMap(\.entries)
                entries += [.divider] + section
            }
            return Self.tidied(entries)
        }
        var result: [(title: String, entries: [Entry])] = [
            ("File", menu(Self.fileTargets)), ("Edit", menu(Self.editTargets)),
            ("Format", menu(Self.formatTargets)), ("View", menu(Self.viewTargets)),
        ]
        result += commandMenus.map { ($0.title, Self.tidied($0.entries)) }
        result += [("Tools", menu(Self.toolsTargets)), ("Window", menu(Self.windowTargets)), ("Help", menu(Self.helpTargets))]
        return result.filter { !$0.entries.isEmpty }
    }

    /// `entries` without dividers at the start or end or next to each other (each section once, with no
    /// empty ones), and with each submenu's entries tidied too.
    static func tidied(_ entries: [Entry]) -> [Entry] {
        var result: [Entry] = []
        for entry in entries {
            switch entry {
            case .divider:
                if let last = result.last, case .divider = last { continue }
                if result.isEmpty { continue }
                result.append(.divider)
            case .submenu(let title, let children):
                result.append(.submenu(title: title, entries: tidied(children)))
            default:
                result.append(entry)
            }
        }
        if let last = result.last, case .divider = last {
            result.removeLast()
        }
        return result
    }

    /// A Button, Menu or Divider element as an entry; nil for anything else (logged).
    static func entry(_ element: [String: Any]) -> Entry? {
        switch element["type"] as? String {
        case "Divider", "Separator":
            return .divider
        case "Button":
            let properties = element["properties"] as? [String: Any] ?? [:]
            return .item(title: properties["title"] as? String ?? "", actionID: properties["actionID"] as? String,
                         viewID: element["id"] as? Int ?? 0, shortcut: ModifierParsing.keyboardShortcut(properties["keyboardShortcut"]),
                         disabled: properties["disabled"] as? Bool ?? false)
        case "Menu":
            let properties = element["properties"] as? [String: Any] ?? [:]
            return .submenu(title: properties["title"] as? String ?? "",
                            entries: (element["children"] as? [[String: Any]] ?? []).compactMap(entry))
        default:
            ActionUIModel.shared.logger.log("Commands: a \(element["type"] as? String ?? "?") is not a menu item on Windows; it is left out", .warning)
            return nil
        }
    }

    // MARK: A window's menu bar

    /// A new menu bar for the window showing `windowUUID`, nil when the host has loaded no commands or the
    /// bar could not be made (logged).
    package func makeMenuBar(windowUUID: String) -> WinUIObject? {
        guard isLoaded else { return nil }
        guard let bar = WinUIObject(adopting: actionUIWinUIMenuBarCreate()) else {
            ActionUIModel.shared.logger.log("Commands: \(WinUIError.last("making a menu bar"))", .error)
            return nil
        }
        for (title, entries) in menus() {
            guard let menu = WinUIObject(adopting: actionUIWinUIMenuBarAppendMenu(bar.pointer, title)) else {
                ActionUIModel.shared.logger.log("Commands: \(WinUIError.last("adding the menu \(title)"))", .error)
                continue
            }
            append(entries, to: menu, windowUUID: windowUUID)
        }
        return bar
    }

    private func append(_ entries: [Entry], to menu: WinUIObject, windowUUID: String) {
        let logger = ActionUIModel.shared.logger
        for entry in entries {
            switch entry {
            case .divider:
                _ = WinUIObject(adopting: actionUIWinUIMenuAppend(menu.pointer, ActionUIWinUIMenuItemSeparator, nil, true, false, nil))
            case .submenu(let title, let children):
                guard let submenu = WinUIObject(adopting: actionUIWinUIMenuAppend(menu.pointer, ActionUIWinUIMenuItemSubmenu,
                                                                                  title, true, false, nil)) else {
                    logger.log("Commands: \(WinUIError.last("adding the submenu \(title)"))", .error)
                    continue
                }
                append(children, to: submenu, windowUUID: windowUUID)
            case .item(let title, let actionID, let viewID, let shortcut, let disabled):
                // An item with no action is grayed out, as AppKit shows a menu item without one.
                guard let item = WinUIObject(adopting: actionUIWinUIMenuAppend(menu.pointer, ActionUIWinUIMenuItem, title,
                                                                               !disabled && actionID != nil, false, nil)) else {
                    logger.log("Commands: \(WinUIError.last("adding the item \(title)"))", .error)
                    continue
                }
                if shortcut != nil {
                    _ = RenderNode.applyShortcut(shortcut, to: item, applied: nil)
                }
                if let actionID {
                    WinUIEvents.connect(item, actionUIWinUIMenuItemOnClick, "a menu bar item's click") {
                        // The menu is the host's: its items are in no window's model.
                        ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: viewID,
                                                           viewPartID: 0, context: nil, origin: .host)
                    }
                }
            case .about:
                let name = appName()
                guard let item = WinUIObject(adopting: actionUIWinUIMenuAppend(menu.pointer, ActionUIWinUIMenuItem,
                                                                               "About \(name)", true, false, nil)) else { continue }
                WinUIEvents.connect(item, actionUIWinUIMenuItemOnClick, "the About item's click") { [weak self] in
                    // The name as it is now: the host may have set it after the bar was made.
                    guard let self else { return }
                    self.aboutHandler?(self.appName())
                }
            case .exit:
                guard let item = WinUIObject(adopting: actionUIWinUIMenuAppend(menu.pointer, ActionUIWinUIMenuItem,
                                                                               "Exit", true, false, nil)) else { continue }
                WinUIEvents.connect(item, actionUIWinUIMenuItemOnClick, "the Exit item's click") { [weak self] in
                    self?.exitHandler?()
                }
            }
        }
    }
}
