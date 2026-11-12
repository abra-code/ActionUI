// Sources/Runtime/AppCommands.swift
/*
 The application's commands on Linux: the CommandMenu and CommandGroup elements a host loads
 (actionUIAppLoadMenuBar, AdwaitaApplication.loadMenuBar), which macOS puts in its menu bar, shown
 in GNOME's primary menu instead (the owner's choice, 2026-10-24): one menu button at the end of
 a window's header bar, opening a menu shared by every window.

 The menu, top to bottom, each part a section:
 - the CommandGroup items placed at the targets of the File, Edit, View and Window menus (newItem,
   saveItem, importExport, printItem, undoRedo, pasteboard, textEditing, textFormatting, toolbar,
   sidebar, windowSize, windowArrangement, windowList, singleWindowList, systemServices,
   appVisibility), in that order;
 - each CommandMenu, a submenu titled with its name, in the order loaded;
 - the items at appSettings and help, then "About <name>" (appInfo), as GNOME's primary menu ends,
   then any items a group puts at appTermination.
 A group's items come before ("before") or after ("after") the target's own; "replacing" puts
 them in its place, and without children takes the target's own away. Only appInfo (About) and
 appTermination (Ctrl+Q quits, as in GNOME apps, with no menu item) have items of their own; the
 macOS identifiers of those two items, "about" and "quit", name their targets too. Any other
 target is help, as Core reads a missing one. A Divider (or Separator) starts a new section.
 A Menu is a submenu titled with its title, holding its own Buttons, Dividers and Menus, as a Menu
 in a SwiftUI CommandMenu and in ActionUIMenuBar's.
 Button is the one action item, as on macOS: its title, its keyboardShortcut as the action's
 accelerator (command and control are Ctrl, option Alt, shift Shift; no modifiers given, or none
 known, is Ctrl), disabled or no actionID greying it out, as AppKit does. Choosing one fires its
 actionID for the active window's document, with the element's id as viewID.

 Each item is an action of the application, so its shortcut works in every window, as a menu bar
 shortcut does. The application is the one start() gave (ActionUI's own, AdwaitaApplication), else
 the process's default GApplication once it is registered: a host that runs its own application
 gets the menu on it with no call, as AppKit code finds NSApp. The actions go on the application
 when the menu is loaded or a menu button is made, whichever first finds one. Ctrl+Q and its
 quit action are ActionUI's own application's only (it runs the quit handler, AdwaitaApplication's
 terminate, which asks its shouldTerminate handler): a host's application quits by its own rules,
 so the host binds Quit itself, or puts an item at appTermination, as NSApp's terminate goes
 through the host's own delegate on macOS.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CAdwaita

@MainActor
package final class AppCommands {
    package static let shared = AppCommands()

    /// The primary menu every window's menu button shows, rebuilt in place.
    let menu = OwnedObject(adopting: g_menu_new()!)
    /// The CommandMenu and CommandGroup elements loaded, in order.
    private var commands: [[String: Any]] = []
    /// The application start() gave, until stop().
    private var startedApplication: OpaquePointer?
    private var startedName: String?
    /// The application the actions were installed on, held weakly (GLib clears it when the
    /// application goes away, so a rebuild never touches a freed one), and the actions' names,
    /// removed before a rebuild. nonisolated(unsafe) only so deinit can free it: it is used on the
    /// main thread alone, where GLib also clears it.
    private nonisolated(unsafe) let installedBox: UnsafeMutablePointer<gpointer?> = {
        let box = UnsafeMutablePointer<gpointer?>.allocate(capacity: 1)
        box.initialize(to: nil)
        return box
    }()
    private var installedApplication: OpaquePointer? {
        get { installedBox.pointee.map(OpaquePointer.init) }
        set {
            if let old = installedBox.pointee {
                g_object_remove_weak_pointer(old.assumingMemoryBound(to: GObject.self), installedBox)
            }
            installedBox.pointee = newValue.map { UnsafeMutableRawPointer($0) }
            if let new = installedBox.pointee {
                g_object_add_weak_pointer(new.assumingMemoryBound(to: GObject.self), installedBox)
            }
        }
    }
    private var actionNames: [String] = []
    /// What Ctrl+Q does; nil quits the application.
    package var quitHandler: (@MainActor () -> Void)?

    /// The application the actions go on: start()'s, else the default GApplication once it is
    /// registered and is a GtkApplication (see the header).
    private var application: OpaquePointer? {
        if let startedApplication {
            return startedApplication
        }
        guard let candidate = g_application_get_default(), g_application_get_is_registered(candidate) != 0,
              g_type_check_instance_is_a(UnsafeMutableRawPointer(candidate).assumingMemoryBound(to: GTypeInstance.self),
                                         gtk_application_get_type()) != 0 else { return nil }
        return OpaquePointer(candidate)
    }

    /// The name About shows: start()'s, else GLib's application name.
    var appName: String {
        startedName ?? swiftString(g_get_application_name()) ?? ProcessInfo.processInfo.processName
    }

    /// The UUID of the active window of the application in use, "" when it shows no document.
    func activeWindowUUID() -> String {
        WindowRegistry.shared.activeWindowUUID(of: application)
    }

    static let topTargets = ["newItem", "saveItem", "importExport", "printItem", "undoRedo", "pasteboard",
                             "textEditing", "textFormatting", "toolbar", "sidebar", "windowSize",
                             "windowArrangement", "windowList", "singleWindowList", "systemServices",
                             "appVisibility"]
    /// appTermination's own item has no place in the menu (Ctrl+Q only), but the items a group
    /// puts there do.
    static let bottomTargets = ["appSettings", "help", "appInfo", "appTermination"]

    /// The target a placementTarget names: one of the menu's, or the macOS menu bar's identifier of
    /// a default item Linux also has ("about" is appInfo's item, "quit" appTermination's); any
    /// other is help, as Core reads a missing one.
    static func target(_ name: String?) -> String {
        switch name {
        case "about": return "appInfo"
        case "quit": return "appTermination"
        case let name? where (topTargets + bottomTargets).contains(name): return name
        default: return "help"
        }
    }

    /// A separate instance for tests; the application uses `shared`.
    init() {}

    deinit {
        if let application = installedBox.pointee {
            g_object_remove_weak_pointer(application.assumingMemoryBound(to: GObject.self), installedBox)
        }
        installedBox.deallocate()
    }

    /// Adds the CommandMenu and CommandGroup elements in `json` (an array of them) to the menu;
    /// nil only makes sure the menu is there. Returns false, logging why, for JSON that is not
    /// such an array.
    @discardableResult
    package func load(json: String?) -> Bool {
        if let json {
            guard let parsed = try? ActionUIJSON.value(from: json), let array = parsed as? [Any] else {
                ActionUIModel.shared.logger.log("Menu commands: the JSON is not an array", .error)
                return false
            }
            commands += array.compactMap { $0 as? [String: Any] }
        }
        rebuild()
        return true
    }

    /// The keys of the command sets loaded with `once`.
    private var loadedKeys: Set<String> = []

    /// As load(json:), unless commands with `key` were loaded already (a WindowGroup's, for each
    /// window of the group).
    @discardableResult
    package func load(json: String, once key: String) -> Bool {
        guard loadedKeys.insert(key).inserted else { return true }
        return load(json: json)
    }

    /// ActionUI's own application started: its actions can be installed.
    package func start(_ application: UnsafeMutablePointer<AdwApplication>, name: String) {
        startedApplication = OpaquePointer(application)
        startedName = name
        rebuild()
    }

    /// ActionUI's own application ended: its actions went with it.
    package func stop() {
        startedApplication = nil
        startedName = nil
        installedApplication = nil
        actionNames = []
    }

    /// A new menu button showing the menu: the window's primary menu, which F10 also opens. The
    /// actions go on the application now if they are not on it yet.
    package func makeMenuButton() -> WidgetPointer {
        if application != installedApplication {
            rebuild()
        }
        let button = gtk_menu_button_new()!
        gtk_menu_button_set_icon_name(OpaquePointer(button), "open-menu-symbolic")
        gtk_menu_button_set_menu_model(OpaquePointer(button), typed(menu.opaquePointer))
        gtk_menu_button_set_primary(OpaquePointer(button), 1)
        gtk_widget_set_tooltip_text(button, "Main Menu")
        setAccessibleLabel(button, "Main Menu")
        return button
    }

    // MARK: Building

    /// One menu item: a Button's title, the action it fires and its shortcut, a Menu's title and
    /// items, or a Divider.
    private enum Entry {
        case item(title: String, actionID: String?, viewID: Int, accelerator: String?, disabled: Bool)
        case submenu(title: String, entries: [Entry])
        /// The default appInfo item.
        case about
        case divider
    }

    private func rebuild() {
        let root = menu.opaquePointer
        g_menu_remove_all(root)
        if let installedApplication {
            for name in actionNames {
                g_action_map_remove_action(installedApplication, name)
                Self.setAccelerators(installedApplication, "app." + name, [])
            }
        }
        actionNames = []
        installedApplication = application

        // The groups at each target, in the order loaded.
        var groups: [String: [(placement: String, entries: [Entry])]] = [:]
        var menus: [(name: String, entries: [Entry])] = []
        for command in commands {
            let properties = command["properties"] as? [String: Any] ?? [:]
            let entries = (command["children"] as? [[String: Any]] ?? []).compactMap(Self.entry)
            switch command["type"] as? String {
            case "CommandMenu":
                guard let name = properties["name"] as? String, !name.isEmpty else { continue }
                menus.append((name, entries))
            case "CommandGroup":
                let target = Self.target(properties["placementTarget"] as? String)
                let placement = (properties["placement"] as? String).flatMap { ["before", "after", "replacing"].contains($0) ? $0 : nil } ?? "after"
                groups[target, default: []].append((placement, entries))
            default:
                continue
            }
        }

        for target in Self.topTargets {
            appendSections(root, target: target, groups[target] ?? [], defaults: [])
        }
        if !menus.isEmpty {
            let section = OwnedObject(adopting: g_menu_new()!)
            for command in menus {
                let submenu = OwnedObject(adopting: g_menu_new()!)
                appendEntries(submenu.opaquePointer, command.entries)
                g_menu_append_submenu(section.opaquePointer, command.name, typed(submenu.opaquePointer))
            }
            g_menu_append_section(root, nil, typed(section.opaquePointer))
        }
        for target in Self.bottomTargets {
            let defaults: [Entry] = target == "appInfo" ? [.about] : []
            appendSections(root, target: target, groups[target] ?? [], defaults: defaults)
        }
        installQuit(replaced: groups["appTermination"]?.contains { $0.placement == "replacing" } ?? false)
    }

    /// The sections of one target: the "before" groups, the target's own items (or what replaces
    /// them), the "after" groups, split at Dividers.
    private func appendSections(_ root: OpaquePointer, target: String, _ groups: [(placement: String, entries: [Entry])],
                                defaults: [Entry]) {
        let replacing = groups.filter { $0.placement == "replacing" }
        var entries = groups.filter { $0.placement == "before" }.flatMap(\.entries)
        entries += replacing.isEmpty ? defaults : replacing.flatMap(\.entries)
        entries += groups.filter { $0.placement == "after" }.flatMap(\.entries)
        for chunk in Self.sections(entries) {
            let model = OwnedObject(adopting: g_menu_new()!)
            appendItems(model.opaquePointer, chunk)
            g_menu_append_section(root, nil, typed(model.opaquePointer))
        }
    }

    /// `entries` split at Dividers, without empty parts.
    private static func sections(_ entries: [Entry]) -> [[Entry]] {
        var sections: [[Entry]] = [[]]
        for entry in entries {
            if case .divider = entry {
                sections.append([])
            } else {
                sections[sections.count - 1].append(entry)
            }
        }
        return sections.filter { !$0.isEmpty }
    }

    /// Appends `entries` to `model` (a submenu): its items, or a section for each part between
    /// Dividers when there are several.
    private func appendEntries(_ model: OpaquePointer, _ entries: [Entry]) {
        let parts = Self.sections(entries)
        guard parts.count > 1 else {
            appendItems(model, parts.first ?? [])
            return
        }
        for part in parts {
            let section = OwnedObject(adopting: g_menu_new()!)
            appendItems(section.opaquePointer, part)
            g_menu_append_section(model, nil, typed(section.opaquePointer))
        }
    }

    /// Appends one item per entry (no Dividers) to `model`, each with its action.
    private func appendItems(_ model: OpaquePointer, _ entries: [Entry]) {
        for entry in entries {
            switch entry {
            case .item(let title, let actionID, let viewID, let accelerator, let disabled):
                // An item with no action is greyed out, as AppKit shows a menu item without one.
                let name = addAction(actionID: actionID, viewID: viewID, accelerator: accelerator,
                                     disabled: disabled || actionID == nil, about: false)
                g_menu_append(model, title, "app." + name)
            case .submenu(let title, let entries):
                let submenu = OwnedObject(adopting: g_menu_new()!)
                appendEntries(submenu.opaquePointer, entries)
                g_menu_append_submenu(model, title, typed(submenu.opaquePointer))
            case .about:
                let name = addAction(actionID: nil, viewID: 0, accelerator: nil, disabled: false, about: true)
                g_menu_append(model, "About \(appName)", "app." + name)
            case .divider:
                break
            }
        }
    }

    /// A Button, Menu or Divider element as an entry; nil for anything else (logged).
    private static func entry(_ element: [String: Any]) -> Entry? {
        switch element["type"] as? String {
        case "Divider", "Separator":
            return .divider
        case "Button":
            let properties = element["properties"] as? [String: Any] ?? [:]
            return .item(title: properties["title"] as? String ?? "",
                         actionID: properties["actionID"] as? String,
                         viewID: element["id"] as? Int ?? 0,
                         accelerator: (properties["keyboardShortcut"] as? [String: Any]).flatMap(accelerator),
                         disabled: properties["disabled"] as? Bool ?? false)
        case "Menu":
            let properties = element["properties"] as? [String: Any] ?? [:]
            return .submenu(title: properties["title"] as? String ?? "",
                            entries: (element["children"] as? [[String: Any]] ?? []).compactMap(entry))
        default:
            ActionUIModel.shared.logger.log("Commands: a \(element["type"] as? String ?? "?") is not a menu item on Linux; it is left out", .warning)
            return nil
        }
    }

    // MARK: Actions

    /// Installs an action for an item (or the About item) and its accelerator; returns its name.
    private func addAction(actionID: String?, viewID: Int, accelerator: String?, disabled: Bool, about: Bool) -> String {
        let name = "actionui-command-\(actionNames.count)"
        actionNames.append(name)
        guard let application = installedApplication else { return name }
        let action = OwnedObject(adopting: g_simple_action_new(name, nil)!)
        connectSignal(action.pointer, "activate", .instanceAndArgument) { [weak self] in
            if about {
                AppCommands.showAbout()
            } else if let actionID {
                ActionUIModel.shared.actionHandler(actionID, windowUUID: self?.activeWindowUUID() ?? "",
                                                   viewID: viewID, viewPartID: 0, context: nil)
            }
        }
        g_simple_action_set_enabled(action.opaquePointer, disabled ? 0 : 1)
        g_action_map_add_action(application, action.opaquePointer)
        if let accelerator {
            Self.setAccelerators(application, "app." + name, [accelerator])
        }
        return name
    }

    /// Ctrl+Q quits ActionUI's own application, unless appTermination is replaced. Not on a host's:
    /// see the header.
    private func installQuit(replaced: Bool) {
        guard let application = installedApplication, startedApplication != nil, !replaced else { return }
        let name = "actionui-quit"
        actionNames.append(name)
        let action = OwnedObject(adopting: g_simple_action_new(name, nil)!)
        connectSignal(action.pointer, "activate", .instanceAndArgument) { [weak self] in
            if let quitHandler = self?.quitHandler {
                quitHandler()
            } else {
                g_application_quit(typed(application))
            }
        }
        g_action_map_add_action(application, action.opaquePointer)
        Self.setAccelerators(application, "app." + name, ["<Control>q"])
    }

    private static func setAccelerators(_ application: OpaquePointer, _ action: String, _ accelerators: [String]) {
        var pointers = accelerators.map { strdup($0) }
        pointers.append(nil)
        pointers.withUnsafeBufferPointer { buffer in
            buffer.baseAddress!.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: buffer.count) { list in
                gtk_application_set_accels_for_action(typed(application), action, list)
            }
        }
        for pointer in pointers {
            free(pointer)
        }
    }

    /// The About dialog: the application's name and icon, over the active window.
    private static func showAbout() {
        let dialog = adw_about_dialog_new()!
        adw_about_dialog_set_application_name(OpaquePointer(dialog), AppCommands.shared.appName)
        if let icon = swiftString(gtk_window_get_default_icon_name()) {
            adw_about_dialog_set_application_icon(OpaquePointer(dialog), icon)
        }
        // The active window, whether or not it shows a document (a host's own window may not)
        let parent = WindowRegistry.activeWindow(of: AppCommands.shared.application)
        adw_dialog_present(typed(OpaquePointer(dialog)), parent.map { WidgetPointer(OpaquePointer($0)) })
    }

    // MARK: Shortcuts

    /// A keyboardShortcut as a GTK accelerator ("<Control><Shift>n"): command and control are
    /// Ctrl (Linux has no Command key), option is Alt; modifiers missing are Ctrl, an empty list
    /// none. nil for a missing or unknown key.
    static func accelerator(_ shortcut: [String: Any]) -> String? {
        guard let key = shortcut["key"] as? String else { return nil }
        return accelerator(key: key, modifiers: ModifierParsing.keyboardShortcutModifiers(shortcut["modifiers"]))
    }

    /// The accelerator of `key` with `modifiers` as Core resolves them (BaseModifiers'
    /// keyboardShortcut: an empty set is the bare key). Caps Lock alone, which GTK cannot hold down
    /// as a modifier, keeps the default: not the bare key.
    static func accelerator(key: String, modifiers: Set<BaseModifiers.ModifierKey>) -> String? {
        guard let keyName = keyName(key) else { return nil }
        var control = modifiers.contains(.command) || modifiers.contains(.control)
        let alt = modifiers.contains(.option)
        let shift = modifiers.contains(.shift)
        if !modifiers.isEmpty && !control && !alt && !shift { control = true }
        return (control ? "<Control>" : "") + (alt ? "<Alt>" : "") + (shift ? "<Shift>" : "") + keyName
    }

    /// A key's GDK name, as the macOS menu bar reads ActionUI's key names.
    private static func keyName(_ key: String) -> String? {
        switch key.lowercased() {
        case "return", "enter": return "Return"
        case "tab": return "Tab"
        case "space": return "space"
        case "escape": return "Escape"
        case "delete", "backspace": return "BackSpace"
        case "deleteforward": return "Delete"
        case "uparrow": return "Up"
        case "downarrow": return "Down"
        case "leftarrow": return "Left"
        case "rightarrow": return "Right"
        case "home": return "Home"
        case "end": return "End"
        case "clear": return "Clear"
        case "pageup": return "Page_Up"
        case "pagedown": return "Page_Down"
        case let name where name.count >= 2 && name.hasPrefix("f") && Int(name.dropFirst()).map({ (1...12).contains($0) }) == true:
            return name.uppercased()
        default:
            // One character: its key's name ("n", "comma").
            guard key.unicodeScalars.count == 1, let scalar = key.lowercased().unicodeScalars.first else { return nil }
            let keyval = gdk_unicode_to_keyval(scalar.value)
            return swiftString(gdk_keyval_name(keyval))
        }
    }
}
