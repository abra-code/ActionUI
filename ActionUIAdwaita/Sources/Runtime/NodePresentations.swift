// Sources/Runtime/NodePresentations.swift
/*
 The presentations an element declares as subview keys: "sheet", "fullScreenCover" and "popover",
 shown while the element's view model state "sheetVisible", "fullScreenCoverVisible" or
 "popoverVisible" is true, as SheetHelper and PopoverHelper do on Apple. A Button's click sets the
 states (Core's Button.userTapped); a host sets them with setElementState.

 - sheet and fullScreenCover: an AdwDialog over the window, a header bar with a close button above
   the subview's element, as a window-level modal (WindowPresenter). fullScreenCover is a dialog
   too, as macOS makes it a sheet. Closing it sets the state false; any dismissal, by the user or by
   the host's state, fires sheetOnDismissActionID or fullScreenCoverOnDismissActionID.
 - popover: a GtkPopover on the element's box, on the side popoverArrowEdge names (measured on
   macOS 27: top puts it above the element, leading before it). Closing it (a click outside,
   Escape) sets the state false. An element other than a Button shows or hides it on a click,
   firing popoverActionID when it shows, as PopoverHelper's tap gesture does. Content with nothing
   to focus takes the focus itself, so the keyboard is in the popover and Escape closes it.

 The node reads the states while it syncs (so a change re-syncs it) and applies them after, when
 the subview nodes it makes can sync outside its observation. The subview's element is shown in a
 tree of its own, its root without a parent node, as a presentation is its own context on Apple.
 When the node leaves the tree its presentations come down, the states left as they are.
*/

import CAdwaita
import Dispatch
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@MainActor
final class NodePresentations {
    /// A presentation an element can declare: its subview key and its visibility state.
    enum Kind: CaseIterable {
        case sheet, fullScreenCover, popover

        var subviewKey: String {
            switch self {
            case .sheet: return "sheet"
            case .fullScreenCover: return "fullScreenCover"
            case .popover: return "popover"
            }
        }

        var stateKey: String {
            switch self {
            case .sheet: return "sheetVisible"
            case .fullScreenCover: return "fullScreenCoverVisible"
            case .popover: return "popoverVisible"
            }
        }
    }

    private weak var node: RenderNode?
    /// The kinds the element declares.
    let kinds: [Kind]
    private var shown: [Kind: Shown] = [:]

    /// One presentation on screen: its GTK object (an AdwDialog or a GtkPopover) and its tree.
    private final class Shown {
        let widget: OwnedObject
        let root: RenderNode

        init(widget: consuming OwnedObject, root: RenderNode) {
            self.widget = widget
            self.root = root
        }
    }

    /// The presentations `node`'s element declares; nil when it declares none.
    static func make(for node: RenderNode) -> NodePresentations? {
        let kinds = Kind.allCases.filter { node.element.subviews?[$0.subviewKey] is any ActionUIElementBase }
        return kinds.isEmpty ? nil : NodePresentations(node: node, kinds: kinds)
    }

    private init(node: RenderNode, kinds: [Kind]) {
        self.node = node
        self.kinds = kinds
        if kinds.contains(.popover), node.element.type != "Button" {
            addClickToggle(node)
        }
    }

    /// Which presentations the states ask for: a tracked read, made in the node's sync.
    func requested() -> Set<Kind> {
        guard let node else { return [] }
        return Set(kinds.filter { node.model.states[$0.stateKey] as? Bool ?? false })
    }

    /// Shows what `requested` holds and takes down the rest (after the node's sync).
    func apply(_ requested: Set<Kind>) {
        for kind in kinds {
            if requested.contains(kind), shown[kind] == nil {
                show(kind)
            } else if !requested.contains(kind), shown[kind] != nil {
                close(kind, fireDismiss: true)
            }
        }
    }

    /// The node left the tree: everything shown comes down, no action fires, the states stay.
    func detach() {
        for kind in Array(shown.keys) {
            close(kind, fireDismiss: false)
        }
    }

    /// The root of `kind`'s tree while it is shown.
    func root(_ kind: Kind) -> RenderNode? { shown[kind]?.root }
    /// The AdwDialog or GtkPopover of `kind` while it is shown.
    func widget(_ kind: Kind) -> WidgetPointer? { shown[kind]?.widget.widget }

    // MARK: Showing

    private func show(_ kind: Kind) {
        // Attached: an action fired earlier in the same apply may have taken the node out.
        guard let node, node.isAttached,
              let element = node.element.subviews?[kind.subviewKey] as? any ActionUIElementBase else { return }
        guard gtk_widget_get_root(node.outerWidget) != nil else {
            ActionUIModel.shared.logger.log("NodePresentations: element \(node.element.id) is not in a window; its \(kind.subviewKey) is not shown", .warning)
            return
        }
        guard let model = node.windowModel.viewModels[element.id] else {
            ActionUIModel.shared.logger.log("NodePresentations: no view model for the \(kind.subviewKey) element \(element.id) in window \(node.windowUUID)", .error)
            return
        }
        let root = RenderNode(element: element, model: model, windowModel: node.windowModel, parent: nil)
        // A NavigationStack in a sheet brings the dialog's header bars itself (its pages').
        root.isWindowRoot = kind != .popover && AdwaitaWindow.headerBarTypes.contains(element.type)
        root.sync()

        let widget: OwnedObject
        if kind == .popover {
            widget = OwnedObject(retaining: gtk_popover_new()!)
            let popover: UnsafeMutablePointer<GtkPopover> = widget.typed()
            gtk_popover_set_child(popover, root.outerWidget)
            // Content with nothing to focus (text, an image) takes the focus itself, as a popover
            // does on macOS: the keyboard is in the popover, so Escape closes it, and GTK's focus
            // code, which expects a widget to focus, logs no critical.
            if !Self.hasFocusableWidget(root.outerWidget) {
                gtk_widget_set_focusable(root.outerWidget, 1)
            }
            gtk_popover_set_position(popover, Self.position(BaseModifiers(node.properties).popoverArrowEdge))
            gtk_widget_set_parent(widget.widget, node.outerWidget)
            connectSignal(widget.pointer, "closed", .instanceOnly) { [weak self] in
                self?.closedByUser(kind, root: root)
            }
            shown[kind] = Shown(widget: widget, root: root)
            gtk_popover_popup(popover)
        } else {
            // Sized by its content's natural size (the header bar's included), as AdwDialog does.
            widget = OwnedObject(retaining: UnsafeMutableRawPointer(adw_dialog_new()!))
            let dialog: UnsafeMutablePointer<AdwDialog> = widget.typed()
            let toolbar = adw_toolbar_view_new()!
            if !root.isWindowRoot {
                let header = adw_header_bar_new()!
                adw_toolbar_view_add_top_bar(OpaquePointer(toolbar), header)
                // The presented view's toolbars show in it.
                root.screenBar = ScreenBar(header: header, toolbarView: toolbar)
            }
            adw_toolbar_view_set_content(OpaquePointer(toolbar), root.outerWidget)
            adw_dialog_set_child(dialog, toolbar)
            connectSignal(widget.pointer, "closed", .instanceOnly) { [weak self] in
                self?.closedByUser(kind, root: root)
            }
            shown[kind] = Shown(widget: widget, root: root)
            adw_dialog_present(dialog, node.outerWidget)
        }
    }

    /// Whether `widget` or a widget in it can take the keyboard focus. An invisible or insensitive
    /// widget, or one with can-focus false (a hidden or disabled element's), keeps it from all of
    /// its descendants.
    static func hasFocusableWidget(_ widget: WidgetPointer) -> Bool {
        guard gtk_widget_get_visible(widget) != 0, gtk_widget_get_sensitive(widget) != 0,
              gtk_widget_get_can_focus(widget) != 0 else { return false }
        if gtk_widget_get_focusable(widget) != 0 {
            return true
        }
        return Gtk.Widget(widget).children.contains { hasFocusableWidget($0.pointer) }
    }

    /// The GtkPopover position for SwiftUI's arrow edge, the edge of the element the arrow is at:
    /// the popover is on that side (measured on macOS 27: top above the element, bottom below,
    /// leading before it, trailing after).
    static func position(_ arrowEdge: BaseModifiers.EdgeName) -> GtkPositionType {
        let rightToLeft = gtk_widget_get_default_direction() == GTK_TEXT_DIR_RTL
        switch arrowEdge {
        case .top: return GTK_POS_TOP
        case .bottom: return GTK_POS_BOTTOM
        case .leading: return rightToLeft ? GTK_POS_RIGHT : GTK_POS_LEFT
        case .trailing: return rightToLeft ? GTK_POS_LEFT : GTK_POS_RIGHT
        }
    }

    // MARK: Closing

    /// "closed": the user closed it (a presentation the node closed itself is no longer in `shown`).
    private func closedByUser(_ kind: Kind, root: RenderNode) {
        guard let current = shown[kind], current.root === root else { return }
        takeDown(kind, current)
        guard let node else { return }
        node.model.states[kind.stateKey] = false
        fireDismiss(kind, node)
    }

    private func close(_ kind: Kind, fireDismiss: Bool) {
        guard let current = shown[kind] else { return }
        takeDown(kind, current)
        if kind == .popover {
            gtk_popover_popdown(current.widget.typed())
        } else {
            adw_dialog_force_close(current.widget.typed())
        }
        if fireDismiss, let node {
            self.fireDismiss(kind, node)
        }
    }

    /// Forgets the presentation (so its "closed" changes nothing) and detaches its tree.
    private func takeDown(_ kind: Kind, _ current: Shown) {
        shown[kind] = nil
        current.root.detach()
        if kind == .popover {
            // Unparented once closed; a popover keeps its parent's reference until then. Held until
            // then too: a box disposed meanwhile (its node released) unparents and frees it.
            let popover = current.widget.widget
            g_object_ref(popover)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if gtk_widget_get_parent(popover) != nil {
                        gtk_widget_unparent(popover)
                    }
                    g_object_unref(popover)
                }
            }
        }
    }

    private func fireDismiss(_ kind: Kind, _ node: RenderNode) {
        let modifiers = BaseModifiers(node.properties)
        let actionID: String?
        switch kind {
        case .sheet: actionID = modifiers.sheetOnDismissActionID
        case .fullScreenCover: actionID = modifiers.fullScreenCoverOnDismissActionID
        case .popover: actionID = nil
        }
        guard let actionID, !actionID.isEmpty else { return }
        ActionUIModel.shared.actionHandler(actionID, windowUUID: node.windowUUID, viewID: node.element.id, viewPartID: 0)
    }

    // MARK: A click on an element other than a Button

    private func addClickToggle(_ node: RenderNode) {
        let click = gtk_gesture_click_new()!
        connectUserSignal(UnsafeMutableRawPointer(click), "released", .press) { [weak node] in
            guard let node else { return }
            let willShow = !(node.model.states[Kind.popover.stateKey] as? Bool ?? false)
            node.model.states[Kind.popover.stateKey] = willShow
            if willShow, let actionID = BaseModifiers(node.properties).popoverActionID, !actionID.isEmpty {
                ActionUIModel.shared.actionHandler(actionID, windowUUID: node.windowUUID, viewID: node.element.id, viewPartID: 0)
            }
        }
        gtk_widget_add_controller(node.outerWidget, click)
    }
}
