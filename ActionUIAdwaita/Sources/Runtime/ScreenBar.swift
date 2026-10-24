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
 its title again.
*/

import CAdwaita

@MainActor
final class ScreenBar {
    enum Slot: CaseIterable {
        case leading, principal, trailing
    }

    private let header: OwnedObject
    private let start: OwnedObject
    private let end: OwnedObject
    private let principal: OwnedObject
    /// Each contributing view's items by slot, in the order the views first contributed.
    private var contributions: [(owner: ObjectIdentifier, items: [Slot: [WidgetPointer]])] = []
    /// Called when the principal items come or go, instead of setting the header bar's title widget:
    /// for a header bar whose title widget a renderer sets itself (a split view column's).
    private let principalChanged: (() -> Void)?

    /// The bar on `header` (an AdwHeaderBar). With `principalChanged`, the caller shows
    /// `principalWidget` as the title widget itself.
    init(header: WidgetPointer, principalChanged: (() -> Void)? = nil) {
        self.header = OwnedObject(retaining: header)
        start = OwnedObject(retaining: gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6)!)
        end = OwnedObject(retaining: gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6)!)
        principal = OwnedObject(retaining: gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6)!)
        self.principalChanged = principalChanged
        Gtk.Widget(start.widget).isVisible = false
        Gtk.Widget(end.widget).isVisible = false
        adw_header_bar_pack_start(OpaquePointer(header), start.widget)
        adw_header_bar_pack_end(OpaquePointer(header), end.widget)
    }

    isolated deinit {
        // The header bar may outlive the bar (a page's content replaced): its boxes go.
        let bar = header.opaquePointer
        adw_header_bar_remove(bar, start.widget)
        adw_header_bar_remove(bar, end.widget)
        if adw_header_bar_get_title_widget(bar) == principal.widget {
            adw_header_bar_set_title_widget(bar, nil)
        }
    }

    /// The principal items' box when there are any (the title widget to show), else nil.
    var principalWidget: WidgetPointer? {
        Gtk.Widget(principal.widget).firstChild == nil ? nil : principal.widget
    }

    /// The widgets shown in `slot`, in order.
    func widgets(_ slot: Slot) -> [WidgetPointer] {
        Gtk.Widget(box(slot)).children.map(\.pointer)
    }

    /// Shows `items` as `owner`'s contribution, replacing its earlier one.
    func set(owner: AnyObject, items: [(slot: Slot, widget: WidgetPointer)]) {
        var bySlot: [Slot: [WidgetPointer]] = [:]
        for item in items {
            bySlot[item.slot, default: []].append(item.widget)
        }
        let id = ObjectIdentifier(owner)
        if let index = contributions.firstIndex(where: { $0.owner == id }) {
            guard contributions[index].items != bySlot else { return }
            contributions[index].items = bySlot
        } else {
            guard !items.isEmpty else { return }
            contributions.append((id, bySlot))
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
            let box = self.box(slot)
            let wanted = contributions.flatMap { $0.items[slot] ?? [] }
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
        Gtk.Widget(start.widget).isVisible = Gtk.Widget(start.widget).firstChild != nil
        Gtk.Widget(end.widget).isVisible = Gtk.Widget(end.widget).firstChild != nil
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

    private func box(_ slot: Slot) -> WidgetPointer {
        switch slot {
        case .leading: return start.widget
        case .principal: return principal.widget
        case .trailing: return end.widget
        }
    }
}
