// Sources/Elements/TabView+Adwaita.swift
/*
 TabView on GTK: an AdwViewStack under an AdwViewSwitcher, libadwaita's tabs (the switcher above
 the pages, where macOS draws its tab buttons). Each child is a Tab: its title, its systemImage
 (SymbolNames) and its badge label the switcher's button; its "content" is the page.

 - The value, as on Apple, is the selected tab's index (initially the selection property); the
   user's choice stores it and fires actionID with the index as context; a host's write switches.
 - A badge: an Int above 0 is the button's badge number (libadwaita shows 999+ for more); a
   non-empty String marks the button as needing attention, as libadwaita has no text badge.
 - style: the sidebarAdaptable, grouped and page styles look the same here.
*/

import CAdwaita

/// The widgets of a TabView, kept on its box.
@MainActor
final class TabViewParts {
    let stack: OpaquePointer
    let switcher: WidgetPointer
    /// The page of each tab's content, by the content's element id.
    var pages: [Int: OpaquePointer] = [:]
    /// The content element id of each tab, in order: the page names follow the index.
    var contentIDs: [Int] = []

    init(stack: OpaquePointer, switcher: WidgetPointer) {
        self.stack = stack
        self.switcher = switcher
    }
}

let tabViewPartsKey = AttachKey<TabViewParts>("actionui-tab-view")

extension TabView: ActionUIAdwaitaRenderer {
    static var defaultExpansion: Expansion { .both }

    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        let stack = adw_view_stack_new()!
        // Fills what it is offered, as SwiftUI's does.
        gtk_widget_set_hexpand(box, 1)
        gtk_widget_set_vexpand(box, 1)
        let switcher = adw_view_switcher_new()!
        adw_view_switcher_set_policy(OpaquePointer(switcher), ADW_VIEW_SWITCHER_POLICY_WIDE)
        adw_view_switcher_set_stack(OpaquePointer(switcher), OpaquePointer(stack))
        gtk_widget_set_halign(switcher, GTK_ALIGN_CENTER)
        gtk_widget_set_margin_top(switcher, 6)
        gtk_widget_set_margin_bottom(switcher, 6)
        gtk_widget_set_vexpand(stack, 1)
        gtk_box_append(typed(box), switcher)
        gtk_box_append(typed(box), stack)
        let parts = TabViewParts(stack: OpaquePointer(stack), switcher: switcher)
        attach(parts, to: box, key: tabViewPartsKey)
        connectUserSignal(stack, "notify::visible-child-name", .instanceAndArgument) { [weak node] in
            guard let node else { return }
            userChose(node)
        }
        return box
    }

    /// The page name of the tab at `index`.
    static func pageName(_ index: Int) -> String { "tab-\(index)" }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        guard let parts = attached(on: widget, key: tabViewPartsKey) else { return }
        let tabs = node.effectiveElement.subviews?["children"] as? [any ActionUIElementBase] ?? []
        // Each tab's page is its content; a tab without one shows nothing.
        let contents = tabs.compactMap { $0.subviews?["content"] as? any ActionUIElementBase }
        let order = contents.map(\.id)
        if order != parts.contentIDs {
            // The names follow the index, so a changed list of tabs rebuilds the pages.
            for page in parts.pages.values {
                adw_view_stack_remove(parts.stack, adw_view_stack_page_get_child(page))
            }
            parts.pages = [:]
            parts.contentIDs = order
        }
        node.syncChildren(contents, insert: { child, index in
            guard parts.pages[child.element.id] == nil else { return }
            parts.pages[child.element.id] = adw_view_stack_add_named(parts.stack, child.outerWidget, pageName(index))
        }, remove: { child in
            if let page = parts.pages.removeValue(forKey: child.element.id) {
                adw_view_stack_remove(parts.stack, adw_view_stack_page_get_child(page))
            }
        })

        // The switcher's buttons: each Tab's title, symbol and badge.
        for tab in tabs {
            guard let content = tab.subviews?["content"] as? any ActionUIElementBase,
                  let page = parts.pages[content.id] else { continue }
            let properties = node.windowModel.viewModels[tab.id].map { ActionUIRegistry.shared.currentProperties(element: tab, model: $0) } ?? tab.properties
            let index = parts.contentIDs.firstIndex(of: content.id) ?? 0
            let title = properties["title"] as? String ?? "Tab \(index + 1)"
            if swiftString(adw_view_stack_page_get_title(page)) != title {
                adw_view_stack_page_set_title(page, title)
            }
            // Without a symbol, a question mark, as Apple's placeholder (libadwaita would show its
            // full-color broken-image icon); assetImage has no Linux image.
            let icon = (properties["systemImage"] as? String).map { SymbolNames.iconName($0) } ?? "dialog-question-symbolic"
            if swiftString(adw_view_stack_page_get_icon_name(page)) != icon {
                adw_view_stack_page_set_icon_name(page, icon)
            }
            let badge = properties["badge"]
            let number = UInt32(clamping: max(0, badge as? Int ?? 0))
            if adw_view_stack_page_get_badge_number(page) != number {
                adw_view_stack_page_set_badge_number(page, number)
            }
            let attention: gboolean = (badge as? String).map { $0.isEmpty ? 0 : 1 } ?? 0
            if adw_view_stack_page_get_needs_attention(page) != attention {
                adw_view_stack_page_set_needs_attention(page, attention)
            }
        }

        // The selected tab: the value, else the selection property; out of range, the first.
        let selected = initialValue(node.model) as? Int ?? 0
        let index = parts.contentIDs.indices.contains(selected) ? selected : 0
        if !parts.contentIDs.isEmpty, swiftString(adw_view_stack_get_visible_child_name(parts.stack)) != pageName(index) {
            adw_view_stack_set_visible_child_name(parts.stack, pageName(index))
        }
    }

    /// The user chose a tab: its index is the value, and actionID fires with it.
    private static func userChose(_ node: RenderNode) {
        guard let parts = attached(on: node.widget, key: tabViewPartsKey),
              let name = swiftString(adw_view_stack_get_visible_child_name(parts.stack)),
              name.hasPrefix("tab-"), let index = Int(name.dropFirst(4)),
              initialValue(node.model) as? Int != index else { return }
        node.model.value = index
        if let actionID = Props(node.properties).actionID {
            ActionUIModel.shared.actionHandler(actionID, windowUUID: node.windowUUID, viewID: node.element.id, viewPartID: 0, context: index)
        }
    }
}
