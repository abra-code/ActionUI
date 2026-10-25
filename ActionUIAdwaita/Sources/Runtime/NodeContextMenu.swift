// Sources/Runtime/NodeContextMenu.swift
/*
 A view's contextMenu on GTK: a right click on the element's frame (or a long press on a touch
 screen, or the Menu key while focus is inside it) opens a menu at the pointer, built from the
 contextMenu elements as a Menu's children are (Menu.entries, the same items, actions and
 sections: a Button runs its action, a Toggle toggles, a Picker picks, a Divider separates, a
 Section or nested Menu groups), as macOS opens a view's context menu on a right click.
 contextMenuPreview is iOS's and is not shown, as on macOS.

 A List row's swipeActions are in the same menu: GTK has no swipe-to-reveal row actions (GNOME
 offers a row's actions in its context menu), so the leading edge's Buttons and then the trailing
 edge's follow the row's own contextMenu items, each group after a separator, in the order
 declared. As in SwiftUI, only a List's row (its child, or its template's row) has them; tint,
 role and allowsFullSwipe are not shown. A List row's menu, its swipe actions or its own
 contextMenu, opens anywhere on the row, not only on its content's frame (watchRows).

 - The click is claimed, so the innermost view with a context menu opens its own, and an
   enclosing List row is not selected.
 - The menu is rebuilt when what it shows changes, while it is closed (a new model would close it
   under the user); items are enabled or disabled at once.
 - A disabled view opens nothing, and its click is left to the views around it. Its widget is
   insensitive, but the box holding the gestures is not, and GTK picks the box when the widget
   cannot be picked, so the click checks the widget.
*/

import CAdwaita

@MainActor
final class NodeContextMenu {
    private weak var node: RenderNode?
    /// The items' actions and what the menu was built from (as a Menu's), the action group on the
    /// element's box.
    private let state = MenuState()
    /// The popover menu, made on the first opening, parented to the box (which holds it).
    private var popover: WidgetPointer?

    /// A node's context menu, or nil when its element declares none (no contextMenu, and no
    /// swipeActions on a List's row).
    static func make(for node: RenderNode) -> NodeContextMenu? {
        let items = node.element.subviews?["contextMenu"] as? [any ActionUIElementBase] ?? []
        guard !items.isEmpty || !swipeActions(node.element, node).isEmpty else { return nil }
        return NodeContextMenu(node)
    }

    /// `element`'s swipeActions when `node` is a List's row: the leading edge's, then the trailing
    /// edge's (an action declares no edge: trailing, as in SwiftUI). An action declaring another
    /// edge is on neither, as on Apple (View+SwiftUI's swipeActions).
    private static func swipeActions(_ element: any ActionUIElementBase, _ node: RenderNode) -> [[any ActionUIElementBase]] {
        guard isListRow(node),
              let actions = element.subviews?["swipeActions"] as? [any ActionUIElementBase], !actions.isEmpty else { return [] }
        let edges = ["leading", "trailing"]
        return edges.map { edge in actions.filter { ($0.properties["edge"] as? String ?? "trailing") == edge } }.filter { !$0.isEmpty }
    }

    private init(_ node: RenderNode) {
        self.node = node
        let box = Self.area(node)
        gtk_widget_insert_action_group(box, Menu.actionPrefix, state.actions)
        // A right click.
        let click = gtk_gesture_click_new()!
        gtk_gesture_single_set_button(click, guint(GDK_BUTTON_SECONDARY))
        connectClick(UnsafeMutableRawPointer(click), "pressed") { [weak self] _, x, y in
            guard let self, self.isEnabled else { return }
            gtk_gesture_set_state(click, GTK_EVENT_SEQUENCE_CLAIMED)
            self.open(x: x, y: y)
        }
        gtk_widget_add_controller(box, click)
        // A long press on a touch screen.
        let press = gtk_gesture_long_press_new()!
        gtk_gesture_single_set_touch_only(press, 1)
        connectPoint(UnsafeMutableRawPointer(press), "pressed") { [weak self] x, y in
            guard let self, self.isEnabled else { return }
            gtk_gesture_set_state(press, GTK_EVENT_SEQUENCE_CLAIMED)
            self.open(x: x, y: y)
        }
        gtk_widget_add_controller(box, press)
        // The Menu key while focus is inside the view: at its middle.
        let keys = gtk_event_controller_key_new()!
        connectKeyPressed(UnsafeMutableRawPointer(keys)) { [weak self] keyval in
            guard let self, keyval == guint(GDK_KEY_Menu), self.isEnabled else { return false }
            self.open(x: Double(gtk_widget_get_width(box)) / 2, y: Double(gtk_widget_get_height(box)) / 2)
            return true
        }
        gtk_widget_add_controller(box, keys)
    }

    /// False while the view is disabled (its widget insensitive): a click is then left to the views
    /// around it, as if it had no context menu.
    private var isEnabled: Bool {
        guard let node else { return false }
        return gtk_widget_is_sensitive(node.widget) != 0
    }

    /// Builds the items from the contextMenu elements (a tracked read in the node's sync, so a
    /// changed item updates the menu) and syncs their actions; the model waits while the menu is
    /// open.
    func update() {
        guard let node else { return }
        let element = node.effectiveElement
        let elements = element.subviews?["contextMenu"] as? [any ActionUIElementBase] ?? []
        var items: [Int: any ActionUIElementBase] = [:]
        var entries = Menu.entries(elements, node, &items)
        for group in Self.swipeActions(element, node) {
            let groupEntries = Menu.entries(group, node, &items)
            if !entries.isEmpty, !groupEntries.isEmpty {
                entries.append(.divider)
            }
            entries += groupEntries
        }
        state.items = items
        Menu.syncActions(state, entries, node)
        guard state.entries != entries else {
            state.pending = nil
            return
        }
        if let popover, gtk_widget_get_visible(popover) != 0 {
            state.pending = entries
            return
        }
        setModel(entries)
    }

    private func setModel(_ entries: [MenuEntry]) {
        state.pending = nil
        state.entries = entries
        guard let popover else { return }
        let model = Menu.makeMenu(entries)
        gtk_popover_menu_set_menu_model(OpaquePointer(popover), model.typed())
    }

    /// Opens the menu at (x, y) in the box.
    private func open(x: Double, y: Double) {
        guard let node, node.isAttached else { return }
        let box = Self.area(node)
        // What changed while it was closed and its deferred update has not run yet.
        if let entries = state.pending {
            setModel(entries)
        }
        if popover == nil {
            let model = Menu.makeMenu(state.entries ?? [])
            let menu = gtk_popover_menu_new_from_model(model.typed())!
            gtk_popover_set_has_arrow(typed(menu), 0)
            gtk_widget_set_halign(menu, GTK_ALIGN_START)
            gtk_widget_set_parent(menu, box)
            // Closed: build what changed while it was open, on the next turn.
            connectSignal(UnsafeMutableRawPointer(menu), "closed", .instanceOnly) { [weak self] in
                runAfter(milliseconds: 0) {
                    // Not if it opened again meanwhile: a new model would close it.
                    guard let self, let entries = self.state.pending,
                          let popover = self.popover, gtk_widget_get_visible(popover) == 0 else { return }
                    self.setModel(entries)
                }
            }
            popover = menu
        }
        guard let popover else { return }
        var point = GdkRectangle(x: Int32(x), y: Int32(y), width: 1, height: 1)
        gtk_popover_set_pointing_to(typed(popover), &point)
        gtk_popover_popup(typed(popover))
    }

    /// Opens the menu at (x, y) in `widget` (a List's row beside its content); false when the view
    /// is disabled or the point cannot be placed.
    func open(from widget: WidgetPointer, x: Double, y: Double) -> Bool {
        guard let node, isEnabled else { return false }
        var point = graphene_point_t(x: Float(x), y: Float(y))
        var inArea = graphene_point_t()
        guard gtk_widget_compute_point(widget, Self.area(node), &point, &inArea) != 0 else { return false }
        open(x: Double(inArea.x), y: Double(inArea.y))
        return true
    }

    /// A right click or a long press on a List's row outside its content (the content's own
    /// gestures take one on it first) opens the menu of the row's node: the whole row has the menu,
    /// as a row's swipe and its context menu cover the row in SwiftUI. `rowNode` finds the node of
    /// the row at a y in `listBox`.
    static func watchRows(of listBox: WidgetPointer, rowNode: @escaping @MainActor (Double) -> RenderNode?) {
        let click = gtk_gesture_click_new()!
        gtk_gesture_single_set_button(click, guint(GDK_BUTTON_SECONDARY))
        connectClick(UnsafeMutableRawPointer(click), "pressed") { _, x, y in
            guard let menu = rowNode(y)?.contextMenu, menu.open(from: listBox, x: x, y: y) else { return }
            gtk_gesture_set_state(click, GTK_EVENT_SEQUENCE_CLAIMED)
        }
        gtk_widget_add_controller(listBox, click)
        let press = gtk_gesture_long_press_new()!
        gtk_gesture_single_set_touch_only(press, 1)
        connectPoint(UnsafeMutableRawPointer(press), "pressed") { x, y in
            guard let menu = rowNode(y)?.contextMenu, menu.open(from: listBox, x: x, y: y) else { return }
            gtk_gesture_set_state(press, GTK_EVENT_SEQUENCE_CLAIMED)
        }
        gtk_widget_add_controller(listBox, press)
    }

    /// Where the menu answers clicks and opens: the box's content group, exactly the element's frame
    /// (padding and background included); the box itself can be given more (a window's root fills
    /// the window), where a right click must not open the element's menu. A List's row beside its
    /// content is the List's (watchRows).
    private static func area(_ node: RenderNode) -> WidgetPointer {
        ModifierBox.content(of: node.outerWidget) ?? node.outerWidget
    }

    /// True for a List's row: its child, or its template's row.
    private static func isListRow(_ node: RenderNode) -> Bool {
        node.parent?.element.type == "List"
    }

    /// The node left the tree: the menu comes down and leaves the box.
    func detach() {
        guard let popover else { return }
        gtk_popover_popdown(typed(popover))
        if gtk_widget_get_parent(popover) != nil {
            gtk_widget_unparent(popover)
        }
        self.popover = nil
    }

    /// The popover menu, nil before the first opening (for tests).
    var menuWidget: WidgetPointer? { popover }
}
