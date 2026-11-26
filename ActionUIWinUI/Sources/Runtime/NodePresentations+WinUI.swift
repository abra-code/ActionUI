// Sources/Runtime/NodePresentations+WinUI.swift
/*
 The presentations an element declares as subview keys: "sheet", "fullScreenCover" and "popover",
 shown while the element's view model state "sheetVisible", "fullScreenCoverVisible" or
 "popoverVisible" is true, as SheetHelper and PopoverHelper do on Apple and NodePresentations on
 Linux. A Button's click sets the states (Core's Button.userTapped); a host sets them with
 setElementState.

 - sheet and fullScreenCover: a ContentDialog over the window (WinUI's modal dialog, the window
   dimmed behind it), as large as its content, with no title or buttons, as a macOS sheet shows its
   view alone. fullScreenCover is a dialog too, as macOS makes it a sheet. WinUI shows one dialog at
   a time in a window: a second one, or one asked for while another is still closing, is not shown
   (logged). The dialog keeps WinUI's minimum size (320 by 184) and padding (24). Closing it (Escape) sets the state
   false; any dismissal, by the user or by the host's state, fires sheetOnDismissActionID or
   fullScreenCoverOnDismissActionID.
 - popover: a Flyout on the element's box, in a window of its own that can reach past the window's
   edges as a macOS popover does (inside the window's content when popoversKeptInWindow or for a
   window in windowsKeepingPopovers, for a rendering of the window to include it), on the side
   popoverArrowEdge names (measured on macOS 27
   for Linux: top puts it above the element, leading before it). Closing it (a click outside,
   Escape) sets the state false. An element other than a Button shows or hides it on a tap, firing
   popoverActionID when it shows, as PopoverHelper's tap gesture does.

 Less-trusted content (ActionUI JSON from a server or from a file outside the app's resources, by
 the host's trust policy: .presentModal) presents no sheet, cover or popover of its own, as on Apple
 and Linux, so it cannot cover the window with a dialog that looks like the app's; its states still
 change, nothing is shown, and a tap toggles no popover (as on Apple). Logged once per element.

 The node reads the states while it syncs (so a change re-syncs it) and applies them after, when
 the subview nodes it makes can sync outside its observation. The subview's element is shown in a
 tree of its own, its root without a parent node, as a presentation is its own context on Apple.
 A presentation asked for before the element is in a window (a state true from the start) is
 shown once it is. When the node leaves the tree its presentations come down, the states left as
 they are.
*/

import CWinUI
import Dispatch

@MainActor
package final class NodePresentations {
    /// Whether popovers stay inside their window's content, where a rendering of the window includes
    /// them (the preview tool, which renders windows to PNG files), rather than reaching past the
    /// window's edges as a macOS popover does (the default).
    package static var popoversKeptInWindow = false
    /// The windows (by UUID) whose popovers stay inside their content whatever popoversKeptInWindow says:
    /// a window drawn past every monitor's edge (WinUIApplication's offscreen rendering), where a popover
    /// in a window of its own would show on the user's screen and be left out of the capture.
    package static var windowsKeepingPopovers: Set<String> = []

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
    /// Whether the element's box entering a window (its Loaded) applies the states again: connected
    /// the first time a show finds it in no window, once.
    private var watchesLoaded = false

    /// One presentation on screen: its WinUI object (a ContentDialog or a Flyout) and its tree.
    private final class Shown {
        let host: WinUIObject
        let root: RenderNode

        init(host: WinUIObject, root: RenderNode) {
            self.host = host
            self.root = root
        }
    }

    /// The presentations `node`'s element declares; nil when it declares none, or when its content
    /// may not present them.
    static func make(for node: RenderNode) -> NodePresentations? {
        let kinds = Kind.allCases.filter { node.element.subviews?[$0.subviewKey] is any ActionUIElementBase }
        guard !kinds.isEmpty else { return nil }
        // Less-trusted content presents no sheet, cover or popover of its own over the window, and a
        // tap on it toggles no popover, as on Apple: its states change, nothing is shown.
        guard LinkTrust.allowsLoggingOnce(.presentModal, what: "presenting a sheet, cover or popover", node) else { return nil }
        return NodePresentations(node: node, kinds: kinds)
    }

    private init(node: RenderNode, kinds: [Kind]) {
        self.node = node
        self.kinds = kinds
        if kinds.contains(.popover), node.element.type != "Button", let outer = node.outerView {
            WinUIEvents.connect(outer, actionUIWinUIElementOnTapped, "a popover's tap") { [weak node] in
                guard let node, node.isAttached else { return }
                let willShow = !(node.model.states[Kind.popover.stateKey] as? Bool ?? false)
                node.model.states[Kind.popover.stateKey] = willShow
                if willShow, let actionID = BaseModifiers(node.properties).popoverActionID, !actionID.isEmpty {
                    ActionUIModel.shared.actionHandler(actionID, windowUUID: node.windowModel.windowUUID,
                                                       viewID: node.element.id, viewPartID: 0, origin: LinkTrust.origin(node))
                }
            }
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

    /// The roots of the trees shown now (the preview finds elements in them).
    package var roots: [RenderNode] { Kind.allCases.compactMap { shown[$0]?.root } }

    // MARK: Showing

    private func show(_ kind: Kind) {
        // Attached: an action fired earlier in the same apply may have taken the node out.
        guard let node, node.isAttached, let anchor = node.outerView,
              let element = node.element.subviews?[kind.subviewKey] as? any ActionUIElementBase else { return }
        guard actionUIWinUIElementIsInWindow(anchor.pointer) else {
            // Not in a window yet (the window is being built, its tab not shown): again once it is.
            showWhenLoaded(anchor)
            return
        }
        guard let model = node.windowModel.viewModels[element.id] else {
            ActionUIModel.shared.logger.log("NodePresentations: no view model for the \(kind.subviewKey) element \(element.id) in window \(node.windowModel.windowUUID)", .error)
            return
        }
        let root = RenderNode(element: element, model: model, windowModel: node.windowModel, parent: nil)
        root.sync()
        guard let content = root.outerView else {
            root.detach()
            return
        }
        if kind == .popover {
            guard let flyout = WinUIObject(adopting: actionUIWinUIFlyoutCreate(content.pointer)) else {
                ActionUIModel.shared.logger.log("NodePresentations: \(WinUIError.last("making a popover"))", .error)
                root.detach()
                return
            }
            let kept = Self.popoversKeptInWindow || Self.windowsKeepingPopovers.contains(node.windowModel.windowUUID)
            if kept, !actionUIWinUIFlyoutSetKeptInWindow(flyout.pointer, true) {
                ActionUIModel.shared.logger.log("NodePresentations: \(WinUIError.last("keeping a popover in its window"))", .warning)
            }
            WinUIEvents.connect(flyout, actionUIWinUIFlyoutOnClosed, "a popover's closing") { [weak self, weak root] in
                guard let root else { return }
                self?.closedByUser(kind, root: root)
            }
            shown[kind] = Shown(host: flyout, root: root)
            let placement = Self.placement(BaseModifiers(node.properties).popoverArrowEdge)
            if !actionUIWinUIFlyoutShow(flyout.pointer, anchor.pointer, placement) {
                ActionUIModel.shared.logger.log("NodePresentations: \(WinUIError.last("showing a popover"))", .error)
                takeDown(kind)
            }
        } else {
            guard let dialog = WinUIObject(adopting: actionUIWinUIDialogCreate(content.pointer)) else {
                ActionUIModel.shared.logger.log("NodePresentations: \(WinUIError.last("making a \(kind.subviewKey)"))", .error)
                root.detach()
                return
            }
            WinUIEvents.connect(dialog, actionUIWinUIDialogOnClosed, "a \(kind.subviewKey)'s closing") { [weak self, weak root] in
                guard let root else { return }
                self?.closedByUser(kind, root: root)
            }
            shown[kind] = Shown(host: dialog, root: root)
            if !actionUIWinUIDialogShow(dialog.pointer, anchor.pointer) {
                ActionUIModel.shared.logger.log("NodePresentations: \(WinUIError.last("showing a \(kind.subviewKey)")); it is not shown", .warning)
                takeDown(kind)
            }
        }
    }

    /// Applies the states again each time `anchor` enters a window (WinUI's Loaded), on the main
    /// queue's next turn: a Loaded can come during another node's sync, whose observation would take
    /// the reads. Not a retry each turn, which would spin while the element stays out of a window.
    private func showWhenLoaded(_ anchor: WinUIObject) {
        guard !watchesLoaded else { return }
        watchesLoaded = true
        WinUIEvents.connect(anchor, actionUIWinUIElementOnLoaded, "a presentation's element loading") { [weak self] in
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.apply(self.requested())
                }
            }
        }
    }

    /// The flyout's side for SwiftUI's arrow edge, the edge of the element the arrow is at: the
    /// popover is on that side (top above the element, bottom below, leading before it, trailing
    /// after; left to right).
    static func placement(_ arrowEdge: BaseModifiers.EdgeName) -> ActionUIWinUIFlyoutPlacement {
        switch arrowEdge {
        case .top: return ActionUIWinUIFlyoutPlacementTop
        case .bottom: return ActionUIWinUIFlyoutPlacementBottom
        case .leading: return ActionUIWinUIFlyoutPlacementLeft
        case .trailing: return ActionUIWinUIFlyoutPlacementRight
        }
    }

    // MARK: Closing

    /// Closed: the user closed it (a presentation the node closed itself is no longer in `shown`).
    private func closedByUser(_ kind: Kind, root: RenderNode) {
        guard let current = shown[kind], current.root === root else { return }
        takeDown(kind)
        guard let node else { return }
        node.model.states[kind.stateKey] = false
        fireDismiss(kind, node)
    }

    private func close(_ kind: Kind, fireDismiss: Bool) {
        guard let current = shown[kind] else { return }
        takeDown(kind)
        let hidden = kind == .popover ? actionUIWinUIFlyoutHide(current.host.pointer) : actionUIWinUIDialogHide(current.host.pointer)
        if !hidden {
            ActionUIModel.shared.logger.log("NodePresentations: \(WinUIError.last("closing a \(kind.subviewKey)"))", .error)
        }
        if fireDismiss, let node {
            self.fireDismiss(kind, node)
        }
    }

    /// Forgets the presentation (so its Closed changes nothing) and detaches its tree.
    private func takeDown(_ kind: Kind) {
        guard let current = shown.removeValue(forKey: kind) else { return }
        current.root.detach()
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
        ActionUIModel.shared.actionHandler(actionID, windowUUID: node.windowModel.windowUUID, viewID: node.element.id, viewPartID: 0, origin: LinkTrust.origin(node))
    }
}
