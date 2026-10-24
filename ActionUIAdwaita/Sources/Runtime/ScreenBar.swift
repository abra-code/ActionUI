// Sources/Runtime/ScreenBar.swift
/*
 A screen's header bar, where the toolbars of the views on that screen show (NodeToolbar), as
 SwiftUI puts a view's toolbar items in its navigation bar or window toolbar. A screen is a
 window's document, a NavigationStack page, a NavigationSplitView column or a dialog; whoever makes
 its header bar attaches a ScreenBar to the screen's root node (RenderNode.screenBar), and a view's
 toolbar goes to the nearest one above it.

 Each view's items are a contribution, kept in the order the views first contributed: the leading
 items in a box at the start of the bar, the trailing ones in a box at its end, the principal ones
 in place of the title. A slot with no items takes no room; without principal items the bar shows
 its title again. A navigation container's persistent items are an outer contribution: at the outer
 edge of the bar, before the leading items and after the trailing ones, as ToolbarHelper orders
 them against the screen's own.

 Two more slots, as the web renderer has them:
 - overflow: a "more" menu button at the end of the header bar, outside the trailing items, whose
   popover lists the secondaryAction items, as iOS collapses secondary actions into its "..."
   menu; a click on an item, or Return or Space on one, closes it. One menu for the screen's items
   and the persistent ones, as on Apple.
 - search: the search field of a view with searchable (NodeToolbar), between the trailing items and
   the menu button, as macOS puts it at the trailing end of the window toolbar.
 - bottom: a bar below the screen's content, the items centered 8 points apart, for bottomBar. A
   screen without a toolbar view to put it in (none is known) shows those items as trailing ones.
*/

import CAdwaita

@MainActor
final class ScreenBar {
    enum Slot: CaseIterable {
        case leading, principal, trailing, search, overflow, bottom
    }

    /// The overflow popover's items: flat, the width of the menu. Hovered, pressed and checked
    /// buttons keep the theme's look (these rules outrank the theme's), so a toggle button still
    /// shows that it is on.
    static let overflowRules = """
        .actionui-overflow button:not(:hover):not(:active):not(:checked) { background: none; box-shadow: none; }
        """

    private let header: OwnedObject
    private let start: OwnedObject
    private let end: OwnedObject
    private let principal: OwnedObject
    private let search: OwnedObject
    private let moreButton: OwnedObject
    private let overflow: OwnedObject
    /// The toolbar view (AdwToolbarView) the bottom bar goes in, and the bar, each with a reference
    /// of the bar's own (released in deinit); nil without one. Plain pointers: an optional OwnedObject
    /// cannot be read in a class without consuming it.
    private let toolbarView: OpaquePointer?
    private let bottom: WidgetPointer?
    /// Each contributing view's items by slot, in the order the views first contributed, and whether
    /// they go at the outer edge.
    private var contributions: [(owner: ObjectIdentifier, outer: Bool, items: [Slot: [WidgetPointer]])] = []
    /// Called when the principal items come or go, instead of setting the header bar's title widget:
    /// for a header bar whose title widget a renderer sets itself (a split view column's).
    private let principalChanged: (() -> Void)?

    /// The bar on `header` (an AdwHeaderBar), with its bottom bar in `toolbarView` (the AdwToolbarView
    /// holding the header bar and the screen). With `principalChanged`, the caller shows
    /// `principalWidget` as the title widget itself.
    init(header: WidgetPointer, toolbarView: WidgetPointer?, principalChanged: (() -> Void)? = nil) {
        StyleSheet.shared.installFixedRules("actionui-overflow", Self.overflowRules)
        self.header = OwnedObject(retaining: header)
        start = OwnedObject(retaining: gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6)!)
        end = OwnedObject(retaining: gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6)!)
        principal = OwnedObject(retaining: gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6)!)
        search = OwnedObject(retaining: gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6)!)
        moreButton = OwnedObject(retaining: gtk_menu_button_new()!)
        overflow = OwnedObject(retaining: gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!)
        self.principalChanged = principalChanged
        if let toolbarView {
            g_object_ref(UnsafeMutableRawPointer(toolbarView))
            let bar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8)!
            g_object_ref_sink(UnsafeMutableRawPointer(bar))
            self.toolbarView = OpaquePointer(toolbarView)
            bottom = bar
        } else {
            self.toolbarView = nil
            bottom = nil
        }
        Gtk.Widget(start.widget).isVisible = false
        Gtk.Widget(end.widget).isVisible = false
        Gtk.Widget(search.widget).isVisible = false

        gtk_menu_button_set_icon_name(moreButton.opaquePointer, "view-more-symbolic")
        gtk_widget_set_tooltip_text(moreButton.widget, "More")
        setAccessibleLabel(moreButton.widget, "More")
        Gtk.Widget(overflow.widget).setCSSClass("actionui-overflow", true)
        let popover = gtk_popover_new()!
        gtk_popover_set_child(typed(popover), overflow.widget)
        gtk_menu_button_set_popover(moreButton.opaquePointer, popover)
        // A click on an item, or Return or Space on one, closes the menu after the item has handled
        // it, unless the item opened a popover of its own (a Menu, a Picker), which closing the menu
        // would close with it.
        let click = gtk_gesture_click_new()!
        gtk_event_controller_set_propagation_phase(click, GTK_PHASE_CAPTURE)
        connectSignal(UnsafeMutableRawPointer(click), "released", .press) { [weak self] in
            self?.closeMenuAfterItem()
        }
        gtk_widget_add_controller(overflow.widget, click)
        let keys = gtk_event_controller_key_new()!
        gtk_event_controller_set_propagation_phase(keys, GTK_PHASE_CAPTURE)
        connectKeyPressed(UnsafeMutableRawPointer(keys)) { [weak self] keyval in
            let activating: Set<guint> = [guint(GDK_KEY_Return), guint(GDK_KEY_KP_Enter), guint(GDK_KEY_ISO_Enter),
                                          guint(GDK_KEY_space), guint(GDK_KEY_KP_Space)]
            if activating.contains(keyval) {
                self?.closeMenuAfterItem()
            }
            return false
        }
        gtk_widget_add_controller(overflow.widget, keys)
        Gtk.Widget(moreButton.widget).isVisible = false

        // The end of the bar from the outside in: the menu button, the search field, then the
        // trailing items.
        adw_header_bar_pack_start(OpaquePointer(header), start.widget)
        adw_header_bar_pack_end(OpaquePointer(header), moreButton.widget)
        adw_header_bar_pack_end(OpaquePointer(header), search.widget)
        adw_header_bar_pack_end(OpaquePointer(header), end.widget)

        if let view = self.toolbarView, let bottom {
            gtk_widget_set_halign(bottom, GTK_ALIGN_CENTER)
            Gtk.Widget(bottom).setCSSClass("toolbar", true)
            Gtk.Widget(bottom).isVisible = false
            adw_toolbar_view_add_bottom_bar(view, bottom)
        }
    }

    isolated deinit {
        // The header bar may outlive the bar (a page's content replaced): its widgets go.
        let bar = header.opaquePointer
        adw_header_bar_remove(bar, start.widget)
        adw_header_bar_remove(bar, end.widget)
        adw_header_bar_remove(bar, search.widget)
        adw_header_bar_remove(bar, moreButton.widget)
        if adw_header_bar_get_title_widget(bar) == principal.widget {
            adw_header_bar_set_title_widget(bar, nil)
        }
        if let toolbarView, let bottom {
            adw_toolbar_view_remove(toolbarView, bottom)
            g_object_unref(UnsafeMutableRawPointer(bottom))
            g_object_unref(UnsafeMutableRawPointer(toolbarView))
        }
    }

    /// The principal items' box when there are any (the title widget to show), else nil.
    var principalWidget: WidgetPointer? {
        Gtk.Widget(principal.widget).firstChild == nil ? nil : principal.widget
    }

    /// The overflow menu's button (shown while it has items).
    var overflowButton: WidgetPointer { moreButton.widget }

    /// The bottom bar (shown while it has items), nil without a toolbar view.
    var bottomBar: WidgetPointer? { bottom }

    /// The widgets shown in `slot`, in order.
    func widgets(_ slot: Slot) -> [WidgetPointer] {
        box(slot).map { Gtk.Widget($0).children.map(\.pointer) } ?? []
    }

    /// Shows `items` as `owner`'s contribution, replacing its earlier one; `outer` puts them at the
    /// outer edge of the bar.
    func set(owner: AnyObject, items: [(slot: Slot, widget: WidgetPointer)], outer: Bool = false) {
        var bySlot: [Slot: [WidgetPointer]] = [:]
        for item in items {
            // Without a bottom bar, its items trail.
            let slot = item.slot == .bottom && bottom == nil ? .trailing : item.slot
            bySlot[slot, default: []].append(item.widget)
        }
        let id = ObjectIdentifier(owner)
        if let index = contributions.firstIndex(where: { $0.owner == id }) {
            guard contributions[index].items != bySlot else { return }
            contributions[index].items = bySlot
        } else {
            guard !items.isEmpty else { return }
            contributions.append((id, outer, bySlot))
        }
        show()
    }

    /// Takes `owner`'s contribution out.
    func remove(owner: AnyObject) {
        let id = ObjectIdentifier(owner)
        guard let index = contributions.firstIndex(where: { $0.owner == id }) else { return }
        contributions.remove(at: index)
        show()
    }

    /// Puts each slot's widgets in its box, in contribution order; a box already holding them in
    /// that order is left alone. The boxes' visibility and the title follow once every slot is
    /// done: an item that moves to an earlier slot leaves a later one empty before it is looked at.
    private func show() {
        let hadPrincipal = principalWidget != nil
        for slot in Slot.allCases {
            guard let box = self.box(slot) else { continue }
            let inner = contributions.filter { !$0.outer }.flatMap { $0.items[slot] ?? [] }
            let outer = contributions.filter(\.outer).flatMap { $0.items[slot] ?? [] }
            let wanted = slot == .leading ? outer + inner : inner + outer
            let current = Gtk.Widget(box).children.map(\.pointer)
            guard current != wanted else { continue }
            for child in current {
                gtk_box_remove(typed(box), child)
            }
            for widget in wanted {
                if gtk_widget_get_parent(widget) != nil {
                    gtk_widget_unparent(widget)
                }
                gtk_box_append(typed(box), widget)
            }
        }
        for box in [start.widget, end.widget, search.widget] + (bottom.map { [$0] } ?? []) {
            let widget = Gtk.Widget(box)
            widget.isVisible = widget.firstChild != nil
        }
        Gtk.Widget(moreButton.widget).isVisible = Gtk.Widget(overflow.widget).firstChild != nil
        if hadPrincipal != (principalWidget != nil) {
            showPrincipal()
        }
    }

    /// The principal items came or went: the title widget follows.
    private func showPrincipal() {
        if let principalChanged {
            principalChanged()
            return
        }
        let bar = header.opaquePointer
        let title = principalWidget
        if adw_header_bar_get_title_widget(bar) != title {
            adw_header_bar_set_title_widget(bar, title)
        }
    }

    /// Closes the "more" menu once the item has handled the click or key, unless it opened a popover.
    private func closeMenuAfterItem() {
        runAfter(milliseconds: 0) { [weak self] in
            guard let self, !Self.hasOpenPopover(Gtk.Widget(self.overflow.widget)) else { return }
            gtk_menu_button_popdown(self.moreButton.opaquePointer)
        }
    }

    /// Whether a popover among `widget`'s descendants is shown.
    private static func hasOpenPopover(_ widget: Gtk.Widget) -> Bool {
        widget.children.contains { child in
            (child.isA(gtk_popover_get_type()) && child.isVisible) || hasOpenPopover(child)
        }
    }

    /// A slot's box; none for the bottom slot without a bottom bar (set moves its items to the
    /// trailing one).
    private func box(_ slot: Slot) -> WidgetPointer? {
        switch slot {
        case .leading: return start.widget
        case .principal: return principal.widget
        case .trailing: return end.widget
        case .search: return search.widget
        case .overflow: return overflow.widget
        case .bottom: return bottom
        }
    }
}
