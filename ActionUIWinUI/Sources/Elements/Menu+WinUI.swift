// Sources/Elements/Menu+WinUI.swift
/*
 Menu on WinUI: a DropDownButton (a button with a down arrow) showing the title, or the label element,
 which opens a MenuFlyout built from the children: Windows' own menu, as macOS shows a pop-up button
 that opens a menu and Linux a GtkMenuButton. As large as it is (it does not grow).

 The children become menu items, not elements, as on Linux:
 - A Button is an item with its title; choosing it runs Core's Button.userTapped (actionID). A
   disabled Button is a disabled item, a hidden one is left out.
 - A Toggle is a check item (ToggleMenuFlyoutItem); choosing it runs Core's Toggle.userSetValue with
   the other state: the check mark SwiftUI shows for a Toggle in a menu.
 - A Picker is a submenu named after its title, its options radio items of one group; choosing one runs
   Core's Picker.userSelected: the submenu SwiftUI shows for a Picker in a menu.
 - A Text is an item that cannot be chosen (dimmed).
 - A Divider is a separator line; a Section is its items between separators, its header a dimmed
   title above them (Windows menus have no section headers); a nested Menu is a submenu.
 - A disabled Section or nested Menu disables its items, as in SwiftUI; an empty Section header is
   none.
 - The menu is rebuilt only when what it shows changes (a title, an item enabled or disabled,
   children added or removed); a Toggle's state and a Picker's choice are shown on the items as they
   are.

 Not yet: other children (each type is logged once); a Button's systemImage (Windows' items can show an
 icon) and its destructive role; menu items' keyboard shortcuts; an accessible name for a Menu showing
 only a label element (Linux names a Menu after its title; SwiftUI an image label after its symbol);
 controlSize (ControlSizing sizes Buttons and Pickers).
*/

import CWinUI

@MainActor private var reportedItemTypes: Set<String> = []

/// What a Menu shows, built from its children; compared to skip rebuilding an unchanged menu. A
/// Toggle's state and a Picker's choice are not in it: they are set on the items as they change.
indirect enum MenuEntry: Equatable {
    struct Choice: Equatable {
        let title: String
        let tag: String
    }

    case item(id: Int, title: String, enabled: Bool)
    case toggle(id: Int, title: String, enabled: Bool)
    case picker(id: Int, title: String, enabled: Bool, choices: [Choice])
    case text(String)
    case divider
    case section(header: String?, entries: [MenuEntry])
    case submenu(title: String, entries: [MenuEntry])
}

/// A Menu's flyout, what it was built from, and the items that show a state.
@MainActor
final class MenuState {
    let menu: WinUIObject
    var entries: [MenuEntry]?
    /// The Button, Toggle and Picker elements the items stand for, by id.
    var elements: [Int: any ActionUIElementBase] = [:]
    /// Each Toggle's check item and each Picker's radio items (with their tags), by element id.
    var toggleItems: [Int: WinUIObject] = [:]
    var radioItems: [Int: [(tag: String, item: WinUIObject)]] = [:]
    /// Every item made, kept while the menu shows it.
    var items: [WinUIObject] = []
    /// The button's title as last shown (nil: a label element, or nothing yet).
    var shownTitle: String?

    init(menu: WinUIObject) {
        self.menu = menu
    }
}

extension Menu: ActionUIWinUIRenderer {
    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        guard let button = WinUIObject(adopting: actionUIWinUIMenuButtonCreate()) else {
            throw WinUIError.last("creating a Menu's button")
        }
        guard let menu = WinUIObject(adopting: actionUIWinUIMenuButtonCopyMenu(button.pointer)) else {
            throw WinUIError.last("reading a Menu's flyout")
        }
        node.state = MenuState(menu: menu)
        return button
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        guard let state = node.state as? MenuState else { return }
        node.applyTextAppearance(to: view, what: "a Menu")
        updateLabel(view, node)
        var elements: [Int: any ActionUIElementBase] = [:]
        let entries = self.entries(node.subviews("children"), node, &elements)
        state.elements = elements
        if entries != state.entries {
            rebuild(state, entries, node)
        }
        showStates(state, node)
    }

    /// The title, or the label element shown as the button's content.
    private static func updateLabel(_ view: WinUIObject, _ node: RenderNode) {
        // A single element, not a list.
        let label = node.effectiveElement.subviews?["label"] as? any ActionUIElementBase
        let children = node.syncChildren(label.map { [$0] } ?? [])
        guard let state = node.state as? MenuState else { return }
        let shown: Bool
        if let content = children.first?.outerView {
            shown = actionUIWinUIButtonSetContent(view.pointer, content.pointer)
            state.shownTitle = nil
        } else {
            let title = Props(node.properties).title
            guard title != state.shownTitle else { return }
            // No title: the arrow alone (no empty content beside it).
            shown = title.isEmpty ? actionUIWinUIButtonSetContent(view.pointer, nil) : actionUIWinUIButtonSetTitle(view.pointer, title)
            state.shownTitle = shown ? title : nil
        }
        if !shown {
            ActionUIModel.shared.logger.log("Menu: \(WinUIError.last("showing the title"))", .error)
        }
    }

    /// What `elements` show as menu entries; the Button, Toggle and Picker elements among them go
    /// into `found`. `disabled`: a Section or Menu around them is disabled, which disables them, as in
    /// SwiftUI.
    static func entries(_ elements: [any ActionUIElementBase], _ node: RenderNode,
                        _ found: inout [Int: any ActionUIElementBase], disabled: Bool = false) -> [MenuEntry] {
        var result: [MenuEntry] = []
        for element in elements {
            let model = node.windowModel.viewModels[element.id] ?? ViewModel()
            let properties = ActionUIRegistry.shared.currentProperties(element: element, model: model)
            let modifiers = BaseModifiers(properties)
            if modifiers.hidden { continue }
            let isDisabled = disabled || modifiers.disabled == true
            // With the elements inserted or removed at run time (a nested Section or Menu keeps them in
            // its own view model). A tracked read.
            let children = ActionUIRegistry.shared.applyDynamicSubviews(to: element, model: model)
                .subviews?["children"] as? [any ActionUIElementBase] ?? []
            switch element.type {
            case "Button":
                found[element.id] = element
                result.append(.item(id: element.id, title: Button.Props(properties).title, enabled: !isDisabled))
            case "Toggle":
                found[element.id] = element
                result.append(.toggle(id: element.id, title: Toggle.Props(properties).title, enabled: !isDisabled))
            case "Picker":
                found[element.id] = element
                let picker = Picker.Props(properties)
                let choices = picker.sections.flatMap(\.items).map { MenuEntry.Choice(title: $0.title, tag: $0.tag) }
                result.append(.picker(id: element.id, title: picker.title, enabled: !isDisabled, choices: choices))
            case "Text":
                result.append(.text(Text.displayedText(model.value, properties)))
            case "Divider":
                result.append(.divider)
            case "Section":
                // An empty header is none (no empty title row).
                let header = Section.Props(properties).header.flatMap { $0.isEmpty ? nil : $0 }
                result.append(.section(header: header, entries: entries(children, node, &found, disabled: isDisabled)))
            case "Menu":
                result.append(.submenu(title: Props(properties).title, entries: entries(children, node, &found, disabled: isDisabled)))
            default:
                if !reportedItemTypes.contains(element.type) {
                    reportedItemTypes.insert(element.type)
                    ActionUIModel.shared.logger.log("Menu: a \(element.type) is not shown as a menu item on Windows yet", .warning)
                }
            }
        }
        return result
    }

    // MARK: Building

    /// Makes the menu's items `entries` again.
    private static func rebuild(_ state: MenuState, _ entries: [MenuEntry], _ node: RenderNode) {
        state.toggleItems = [:]
        state.radioItems = [:]
        state.items = []
        guard actionUIWinUIMenuClear(state.menu.pointer) else {
            ActionUIModel.shared.logger.log("Menu: \(WinUIError.last("clearing the menu"))", .error)
            return
        }
        var needsSeparator = false
        append(entries, to: state.menu, state, node, needsSeparator: &needsSeparator)
        state.entries = entries
    }

    /// Appends `entries` to `menu`. `needsSeparator`: a Section or Divider before asks for a line before
    /// the next item (none at the start or the end of a menu, none twice).
    private static func append(_ entries: [MenuEntry], to menu: WinUIObject, _ state: MenuState, _ node: RenderNode,
                               needsSeparator: inout Bool) {
        var hasItems = false
        func add(_ kind: ActionUIWinUIMenuItemKind, _ title: String, enabled: Bool = true, checked: Bool = false,
                 group: String = "") -> WinUIObject? {
            if needsSeparator && hasItems && kind != ActionUIWinUIMenuItemSeparator {
                _ = add(ActionUIWinUIMenuItemSeparator, "")
            }
            needsSeparator = false
            guard let item = WinUIObject(adopting: actionUIWinUIMenuAppend(menu.pointer, kind, title, enabled, checked, group)) else {
                ActionUIModel.shared.logger.log("Menu: \(WinUIError.last("adding an item"))", .error)
                return nil
            }
            hasItems = true
            state.items.append(item)
            return item
        }
        for entry in entries {
            switch entry {
            case let .item(id, title, enabled):
                guard let item = add(ActionUIWinUIMenuItem, title, enabled: enabled) else { continue }
                WinUIEvents.connect(item, actionUIWinUIMenuItemOnClick, "a Menu item's click") { [weak node, weak state] in
                    guard let node, let state, node.isAttached, let (element, model) = itemElement(id, state, node) else { return }
                    Button.userTapped(element: element, model: model, windowUUID: node.windowModel.windowUUID,
                                      props: Button.Props(ActionUIRegistry.shared.currentProperties(element: element, model: model)))
                }
            case let .toggle(id, title, enabled):
                guard let item = add(ActionUIWinUIMenuItemToggle, title, enabled: enabled) else { continue }
                state.toggleItems[id] = item
                WinUIEvents.connect(item, actionUIWinUIMenuItemOnClick, "a Menu check item's click") { [weak node, weak state] in
                    guard let node, let state, node.isAttached, let (element, model) = itemElement(id, state, node) else { return }
                    let on = Toggle.initialValue(model) as? Bool ?? false
                    Toggle.userSetValue(!on, element: element, model: model, windowUUID: node.windowModel.windowUUID,
                                        props: Toggle.Props(ActionUIRegistry.shared.currentProperties(element: element, model: model)))
                }
            case let .picker(id, title, enabled, choices):
                guard let submenu = add(ActionUIWinUIMenuItemSubmenu, title, enabled: enabled) else { continue }
                var radios: [(tag: String, item: WinUIObject)] = []
                // WinUI keeps one checked radio item per group name for the whole UI thread, across
                // windows: the window's UUID keeps another window's Picker of the same id out of the group.
                let group = "picker-\(node.windowModel.windowUUID)-\(id)"
                for choice in choices {
                    guard let item = WinUIObject(adopting: actionUIWinUIMenuAppend(submenu.pointer, ActionUIWinUIMenuItemRadio, choice.title,
                                                                                   enabled, false, group)) else {
                        ActionUIModel.shared.logger.log("Menu: \(WinUIError.last("adding a Picker's option"))", .error)
                        continue
                    }
                    state.items.append(item)
                    radios.append((choice.tag, item))
                    let tag = choice.tag
                    WinUIEvents.connect(item, actionUIWinUIMenuItemOnClick, "a Menu option's click") { [weak node, weak state] in
                        guard let node, let state, node.isAttached, let (element, model) = itemElement(id, state, node) else { return }
                        Picker.userSelected(tag, element: element, model: model, windowUUID: node.windowModel.windowUUID,
                                            props: Picker.Props(ActionUIRegistry.shared.currentProperties(element: element, model: model)))
                    }
                }
                state.radioItems[id] = radios
            case let .text(text):
                _ = add(ActionUIWinUIMenuItemHeader, text)
            case .divider:
                needsSeparator = true
            case let .section(header, children):
                needsSeparator = true
                // Empty, without a header: nothing shown, only a line between the items around it (a
                // line added here would be doubled by the next item's, or end the menu).
                guard header != nil || showsItems(children) else { continue }
                if let header {
                    _ = add(ActionUIWinUIMenuItemHeader, header)
                } else if hasItems {
                    _ = add(ActionUIWinUIMenuItemSeparator, "")
                }
                needsSeparator = false
                var inner = false
                // The section's items continue this menu (no line between the header and them).
                let before = state.items.count
                append(children, to: menu, state, node, needsSeparator: &inner)
                hasItems = hasItems || state.items.count > before
                needsSeparator = true
            case let .submenu(title, children):
                guard let submenu = add(ActionUIWinUIMenuItemSubmenu, title) else { continue }
                var inner = false
                append(children, to: submenu, state, node, needsSeparator: &inner)
            }
        }
    }

    /// Whether `entries` add an item to a menu (Dividers and empty Sections without a header add none).
    private static func showsItems(_ entries: [MenuEntry]) -> Bool {
        entries.contains { entry in
            switch entry {
            case .divider: false
            case let .section(header, children): header != nil || showsItems(children)
            case .item, .toggle, .picker, .text, .submenu: true
            }
        }
    }

    /// Shows each Toggle's state on its check item and each Picker's choice on its radio items.
    private static func showStates(_ state: MenuState, _ node: RenderNode) {
        for (id, item) in state.toggleItems {
            guard let model = node.windowModel.viewModels[id] else { continue }
            let on = Toggle.initialValue(model) as? Bool ?? false
            if !actionUIWinUIMenuItemSetChecked(item.pointer, on) {
                ActionUIModel.shared.logger.log("Menu: \(WinUIError.last("showing a check item"))", .error)
            }
        }
        for (id, radios) in state.radioItems {
            guard let model = node.windowModel.viewModels[id], let element = state.elements[id] else { continue }
            let properties = ActionUIRegistry.shared.currentProperties(element: element, model: model)
            let chosen = model.value as? String ?? Picker.Props(properties).options.first?.tag ?? ""
            for radio in radios where !actionUIWinUIMenuItemSetChecked(radio.item.pointer, radio.tag == chosen) {
                ActionUIModel.shared.logger.log("Menu: \(WinUIError.last("showing a Picker's choice"))", .error)
            }
        }
    }

    /// The element item `id` stands for and its view model, while the menu shows it.
    private static func itemElement(_ id: Int, _ state: MenuState, _ node: RenderNode) -> (any ActionUIElementBase, ViewModel)? {
        guard let element = state.elements[id], let model = node.windowModel.viewModels[id] else { return nil }
        return (element, model)
    }
}
