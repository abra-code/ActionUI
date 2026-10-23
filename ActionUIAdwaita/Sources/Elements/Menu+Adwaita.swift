// Sources/Elements/Menu+Adwaita.swift
/*
 Menu on GTK: a GtkMenuButton showing the title, or the label element, with a down arrow, which
 opens GTK's own menu built from the children, as macOS shows a pop-up button that opens a menu. As
 large as it is (it does not grow).

 The children become menu items, not widgets (a GMenu model with one action per item, in an action
 group on the button):
 - A Button is an item with its title; choosing it runs Core's Button.userTapped (actionID). A
   disabled Button is a disabled item, a hidden one is left out.
 - A Divider starts a new section (GTK draws a line between sections); a Section is a section with
   its header; a nested Menu is a submenu.
 - The menu is rebuilt only when what it shows changes (a title, an item disabled, children added
   or removed); while it is open, items are enabled or disabled at once and the rest waits until it
   closes (a new model makes a new popover, which would close it).
 - A disabled Section or nested Menu disables its items, as in SwiftUI; an empty Section header is
   none.

 Assistive technologies read the button, named after the title, and the open menu's items, which
 GTK 4.18 exposes without their text (its menu items have no accessible name).

 Not yet: other children (Toggle as a check item, Picker as choices, Text); each type is logged
 once. A Button's systemImage and its destructive role are not shown.
*/

import CAdwaita

@MainActor private var reportedItemTypes: Set<String> = []

/// What a Menu shows, built from its children; compared to skip rebuilding an unchanged menu.
indirect enum MenuEntry: Equatable {
    case item(id: Int, title: String, enabled: Bool)
    case divider
    case section(header: String?, entries: [MenuEntry])
    case submenu(title: String, entries: [MenuEntry])
}

/// A Menu's action group and what it was built from, attached to its button.
@MainActor
final class MenuState {
    let actions: OpaquePointer
    var entries: [MenuEntry]?
    /// What the menu should show once the open menu closes: rebuilding the model makes a new
    /// popover, which would close the menu under the user.
    var pending: [MenuEntry]?
    /// The Button elements the items stand for, by id.
    var items: [Int: any ActionUIElementBase] = [:]

    init() {
        actions = OpaquePointer(g_simple_action_group_new()!)
    }

    isolated deinit {
        g_object_unref(UnsafeMutableRawPointer(actions))
    }
}

let menuStateKey = "actionui-menu"

extension Menu: ActionUIAdwaitaRenderer {
    /// The prefix of the items' actions (the button's action group).
    static let actionPrefix = "menu"

    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        let button = gtk_menu_button_new()!
        gtk_menu_button_set_always_show_arrow(OpaquePointer(button), 1)
        let state = MenuState()
        gtk_widget_insert_action_group(button, actionPrefix, state.actions)
        attach(state, to: button, key: menuStateKey)
        // Closed: build what changed while it was open, on the next turn of the main loop (not
        // inside the closing popover's own signal).
        connectSignal(button, "notify::active", .instanceAndArgument) {
            guard gtk_menu_button_get_active(OpaquePointer(button)) == 0, state.pending != nil else { return }
            // Held until the callback ran: the node can drop the button before then (a window
            // closed, the Menu removed), and a freed address must not be read.
            g_object_ref(UnsafeMutableRawPointer(button))
            runAfter(milliseconds: 0) {
                defer { g_object_unref(UnsafeMutableRawPointer(button)) }
                guard let entries = state.pending, gtk_menu_button_get_active(OpaquePointer(button)) == 0 else { return }
                setMenu(OpaquePointer(button), state, entries)
            }
        }
        return button
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        let button = OpaquePointer(widget)
        updateLabel(button, node)
        guard let state = attached(MenuState.self, on: widget, key: menuStateKey) else { return }
        var items: [Int: any ActionUIElementBase] = [:]
        let entries = self.entries(node.subviews("children"), node, &items)
        state.items = items
        syncActions(state, entries, node)
        guard state.entries != entries else {
            state.pending = nil
            return
        }
        // Open: the actions (enabled, removed) changed at once; the items wait until it closes.
        if gtk_menu_button_get_active(button) != 0 {
            state.pending = entries
            return
        }
        setMenu(button, state, entries)
    }

    private static func setMenu(_ button: OpaquePointer, _ state: MenuState, _ entries: [MenuEntry]) {
        state.pending = nil
        state.entries = entries
        let model = makeMenu(entries)
        gtk_menu_button_set_menu_model(button, typed(model))
        g_object_unref(UnsafeMutableRawPointer(model))
    }

    /// The title, or the label element rendered as the button's child.
    private static func updateLabel(_ button: OpaquePointer, _ node: RenderNode) {
        // A single element, not a list.
        let label = node.effectiveElement.subviews?["label"] as? any ActionUIElementBase
        node.syncChildren(label.map { [$0] } ?? [], insert: { child, _ in
            if gtk_menu_button_get_child(button) != child.outerWidget {
                gtk_menu_button_set_child(button, child.outerWidget)
            }
        }, remove: { _ in
            gtk_menu_button_set_child(button, nil)
        })
        if label == nil {
            let title = Props(node.properties).title
            if swiftString(gtk_menu_button_get_label(button)) != title {
                gtk_menu_button_set_label(button, title)
            }
        }
    }

    /// What `elements` show as menu entries; the Button elements among them go into `items`.
    /// `disabled`: a Section or Menu around them is disabled, which disables them, as in SwiftUI.
    static func entries(_ elements: [any ActionUIElementBase], _ node: RenderNode,
                        _ items: inout [Int: any ActionUIElementBase], disabled: Bool = false) -> [MenuEntry] {
        var result: [MenuEntry] = []
        for element in elements {
            let model = node.windowModel.viewModels[element.id] ?? ViewModel()
            let properties = ActionUIRegistry.shared.currentProperties(element: element, model: model)
            let modifiers = BaseModifiers(properties)
            if modifiers.hidden { continue }
            let isDisabled = disabled || modifiers.disabled == true
            // With the elements inserted or removed at run time (a nested Section or Menu keeps
            // them in its own view model). A tracked read.
            let children = ActionUIRegistry.shared.applyDynamicSubviews(to: element, model: model)
                .subviews?["children"] as? [any ActionUIElementBase] ?? []
            switch element.type {
            case "Button":
                items[element.id] = element
                result.append(.item(id: element.id, title: Button.Props(properties).title, enabled: !isDisabled))
            case "Divider":
                result.append(.divider)
            case "Section":
                // An empty header is none (no empty title row).
                let header = Section.Props(properties).header.flatMap { $0.isEmpty ? nil : $0 }
                result.append(.section(header: header, entries: entries(children, node, &items, disabled: isDisabled)))
            case "Menu":
                result.append(.submenu(title: Props(properties).title, entries: entries(children, node, &items, disabled: isDisabled)))
            default:
                if !reportedItemTypes.contains(element.type) {
                    reportedItemTypes.insert(element.type)
                    ActionUIModel.shared.logger.log("Menu: a \(element.type) is not shown as a menu item on Linux yet", .warning)
                }
            }
        }
        return result
    }

    /// One action per item, enabled as the item is; actions of items that left are removed.
    private static func syncActions(_ state: MenuState, _ entries: [MenuEntry], _ node: RenderNode) {
        var enabled: [Int: Bool] = [:]
        func collect(_ entries: [MenuEntry]) {
            for entry in entries {
                switch entry {
                case let .item(id, _, isEnabled): enabled[id] = isEnabled
                case let .section(_, children), let .submenu(_, children): collect(children)
                case .divider: break
                }
            }
        }
        collect(entries)
        let map = state.actions
        // A set: a search of the ids per action is quadratic in a long menu.
        let kept = Set(enabled.keys.map(actionName))
        for name in actionNames(map) where !kept.contains(name) {
            g_action_map_remove_action(map, name)
        }
        for (id, isEnabled) in enabled {
            let name = actionName(id)
            let action: OpaquePointer
            if let existing = g_action_map_lookup_action(map, name) {
                action = existing
            } else {
                action = g_simple_action_new(name, nil)!
                g_action_map_add_action(map, action)
                g_object_unref(UnsafeMutableRawPointer(action))
                connectUserSignal(UnsafeMutableRawPointer(action), "activate", .instanceAndArgument) { [weak node] in
                    guard let node, let state = attached(MenuState.self, on: node.widget, key: menuStateKey),
                          let element = state.items[id], let model = node.windowModel.viewModels[id] else { return }
                    Button.userTapped(element: element, model: model, windowUUID: node.windowUUID,
                                      props: Button.Props(ActionUIRegistry.shared.currentProperties(element: element, model: model)))
                }
            }
            if (g_action_get_enabled(action) != 0) != isEnabled {
                g_simple_action_set_enabled(action, isEnabled ? 1 : 0)
            }
        }
    }

    static func actionName(_ id: Int) -> String {
        "item-\(id)"
    }

    private static func actionNames(_ map: OpaquePointer) -> [String] {
        guard let names = g_action_group_list_actions(map) else { return [] }
        defer { g_strfreev(names) }
        var result: [String] = []
        var index = 0
        while let name = names[index] {
            result.append(String(cString: name))
            index += 1
        }
        return result
    }

    /// The GMenu for `entries`: items in sections, a Divider closing one section and starting the
    /// next. The caller owns the returned reference.
    static func makeMenu(_ entries: [MenuEntry]) -> OpaquePointer {
        let menu = g_menu_new()!
        var section = g_menu_new()!
        func closeSection() {
            if g_menu_model_get_n_items(typed(section)) > 0 {
                g_menu_append_section(menu, nil, typed(section))
            }
            g_object_unref(UnsafeMutableRawPointer(section))
            section = g_menu_new()!
        }
        for entry in entries {
            switch entry {
            case let .item(id, title, _):
                g_menu_append(section, mnemonicEscaped(title), "\(actionPrefix).\(actionName(id))")
            case .divider:
                closeSection()
            case let .section(header, children):
                closeSection()
                let inner = makeMenu(children)
                g_menu_append_section(menu, header, typed(inner))
                g_object_unref(UnsafeMutableRawPointer(inner))
            case let .submenu(title, children):
                let inner = makeMenu(children)
                g_menu_append_submenu(section, mnemonicEscaped(title), typed(inner))
                g_object_unref(UnsafeMutableRawPointer(inner))
            }
        }
        closeSection()
        g_object_unref(UnsafeMutableRawPointer(section))
        return menu
    }

    /// `text` with each underscore doubled: GTK reads an item's or a submenu's label as a mnemonic,
    /// so "Save_As" would show as "SaveAs". Section headers are shown as given. By scalar, as GTK
    /// parses it (a Character holding "_" and a combining mark would not match "_").
    static func mnemonicEscaped(_ text: String) -> String {
        var result = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            result.append(scalar)
            if scalar == "_" {
                result.append(scalar)
            }
        }
        return String(result)
    }

    /// Named after its title, as SwiftUI names a menu.
    static func defaultAccessibleLabel(_ node: RenderNode) -> String? {
        let title = Props(node.properties).title
        return title.isEmpty ? nil : title
    }
}
