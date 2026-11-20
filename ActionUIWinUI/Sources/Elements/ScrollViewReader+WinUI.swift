// Sources/Elements/ScrollViewReader+WinUI.swift
/*
 ScrollViewReader on WinUI, as on Apple and Linux: the reader scrolls the ScrollViews inside it so the
 element whose id is `scrollTo` shows at `anchor` (top, center or bottom; centered horizontally, as
 SwiftUI's UnitPoint.top and .bottom are), when it first shows and again, animated, after every write
 to the reader (setElementProperty, setElementValue, setElementState: its view model's
 mutationToken), so writing the same id again brings the element back after the user scrolled away;
 shown again (a tab or a page returning: WinUI loads it again), it scrolls back without animation,
 as SwiftUI's onAppear does. Each ScrollView between the element and the reader scrolls, the innermost
 first; an outer one scrolls to where the element will be once the inner ones have scrolled.

 The reader holds its content as a one-child ZStack does (ZStackLayout). A request waits for the
 layout of what the write changed: it runs on the next turn of the main loop, lays the reader out
 (UpdateLayout) and finds the element in each ScrollViewer's content; one whose ScrollViewer is not
 laid out yet (not in the window, or collapsed: in a closed DisclosureGroup, hidden) waits for the
 reader's loading or its next size change. A request for an element the reader does not hold, or one
 in no ScrollView, is dropped.

 Not yet: WinUI loads the reader again when a container re-adds it (a sibling inserted into a stack
 around it), which scrolls back to scrollTo as a reader shown again does, where SwiftUI's onAppear
 does not run (not checked on Windows); an element in a lazy row not made yet is not found (as on
 Linux).
*/

import Dispatch
import CWinUI

/// What a reader keeps: its layout, its last write acted on, and the scroll waiting for a layout.
@MainActor final class ScrollReaderState {
    struct Request {
        let target: Int
        let anchor: ScrollViewReader.Props.Anchor
        let animated: Bool
    }

    let stack: ZStackLayout
    weak var node: RenderNode?
    /// The reader's mutationToken when it last asked to scroll; nil before its first sync.
    var handledWrite: Int?
    var pending: Request?
    /// A turn of the main loop is already asked for.
    var scheduled = false

    init(stack: ZStackLayout, node: RenderNode) {
        self.stack = stack
        self.node = node
    }
}

extension ScrollViewReader: ActionUIWinUIRenderer {
    static func expansion(_ node: RenderNode) -> Expansion { StackViews.childrenExpansion(node) }

    static func compression(_ node: RenderNode) -> Expansion { StackViews.childrenCompression(node) }

    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        let stack = try ZStackLayout()
        let state = ScrollReaderState(stack: stack, node: node)
        node.state = state
        // Loaded: in the window (again). The first time a request from the first sync may be waiting
        // for it; a later time (a tab or a page returning) scrolls back without animation.
        WinUIEvents.connect(stack.panel.object, actionUIWinUIElementOnLoaded, "a ScrollViewReader's loading") { [weak state] in
            guard let state else { return }
            if state.pending == nil {
                shownAgain(state)
            } else {
                schedule(state)
            }
        }
        // Laid out at a new size: a request waiting for a layout (the reader was collapsed, in a closed
        // DisclosureGroup or hidden) runs now.
        WinUIEvents.connect(stack.panel.object, actionUIWinUIElementOnSizeChanged, "a ScrollViewReader's size") { [weak state] in
            guard let state, state.pending != nil else { return }
            schedule(state)
        }
        return stack.panel.object
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        guard let state = node.state as? ScrollReaderState else { return }
        let content = node.effectiveElement.subviews?["content"] as? any ActionUIElementBase
        let children = node.syncChildren(content.map { [$0] } ?? [])
        state.stack.setItems(children.compactMap { child in
            guard !child.takesNoPlace, let view = child.outerView else { return nil }
            return ZStackLayout.Item(view: view, expansion: child.expansion, cap: child.caps)
        })

        let props = Props(node.properties)
        let write = node.model.mutationToken
        guard write != state.handledWrite else { return }
        let animated = state.handledWrite != nil
        state.handledWrite = write
        guard let target = props.scrollTo else {
            state.pending = nil
            return
        }
        state.pending = ScrollReaderState.Request(target: target, anchor: props.anchor, animated: animated)
        // After this sync (the element's node may be made during it).
        schedule(state)
    }

    /// The reader is in the window again: back to scrollTo without animation.
    private static func shownAgain(_ state: ScrollReaderState) {
        guard let node = state.node else { return }
        let props = Props(node.properties)
        guard let target = props.scrollTo else { return }
        state.pending = ScrollReaderState.Request(target: target, anchor: props.anchor, animated: false)
        schedule(state)
    }

    /// Runs the waiting request on the next turn of the main loop, once however often asked.
    private static func schedule(_ state: ScrollReaderState) {
        guard !state.scheduled else { return }
        state.scheduled = true
        DispatchQueue.main.async { [weak state] in
            MainActor.assumeIsolated {
                guard let state else { return }
                state.scheduled = false
                applyPending(state)
            }
        }
    }

    /// Scrolls to the waiting request's element, unless it is not in the window yet (the reader's
    /// loading runs it again).
    private static func applyPending(_ state: ScrollReaderState) {
        guard let request = state.pending, let node = state.node, node.isAttached, let reader = node.view else { return }
        guard let target = descendant(request.target, of: node), let targetView = target.outerView else {
            state.pending = nil
            return
        }
        // The ScrollViews between the element and the reader, innermost first.
        var scrollers: [(viewer: WinUIObject, content: WinUIObject)] = []
        var current = target.parent
        while let scrollNode = current, scrollNode !== node {
            if scrollNode.element.type == "ScrollView", let viewer = scrollNode.view,
               let content = (scrollNode.state as? ScrollState)?.content {
                scrollers.append((viewer, content))
            }
            current = scrollNode.parent
        }
        guard !scrollers.isEmpty else {
            state.pending = nil
            return
        }
        // What the write changed, laid out now.
        if !actionUIWinUIElementUpdateLayout(reader.pointer) {
            ActionUIModel.shared.logger.log("ScrollViewReader: \(WinUIError.last("laying out"))", .error)
        }
        var placed: [(viewer: WinUIObject, bounds: ActionUIWinUIRect, scroll: ActionUIWinUIScrollState)] = []
        for (viewer, content) in scrollers {
            var bounds = ActionUIWinUIRect(x: 0, y: 0, width: 0, height: 0)
            let scroll = actionUIWinUIScrollViewerState(viewer.pointer)
            // Not laid out yet (not in the window, or collapsed): the reader's loading or its next size
            // change tries again.
            guard actionUIWinUIElementBoundsIn(targetView.pointer, content.pointer, &bounds),
                  scroll.viewportHeight > 0 || scroll.viewportWidth > 0 else { return }
            placed.append((viewer, bounds, scroll))
        }
        state.pending = nil
        let anchor: Double
        switch request.anchor {
        case .top: anchor = 0
        case .center: anchor = 0.5
        case .bottom: anchor = 1
        }
        // How far the inner ScrollViews scroll moves the element in the outer ones' content.
        var moved = (x: 0.0, y: 0.0)
        for (viewer, bounds, scroll) in placed {
            let x = offset(start: bounds.x - moved.x, length: bounds.width, anchor: 0.5, page: scroll.viewportWidth,
                           extent: scroll.extentWidth)
            let y = offset(start: bounds.y - moved.y, length: bounds.height, anchor: anchor, page: scroll.viewportHeight,
                           extent: scroll.extentHeight)
            if abs(x - scroll.offsetX) >= 0.5 || abs(y - scroll.offsetY) >= 0.5 {
                if !actionUIWinUIScrollViewerChangeView(viewer.pointer, x, y, request.animated) {
                    ActionUIModel.shared.logger.log("ScrollViewReader: \(WinUIError.last("scrolling"))", .error)
                }
            }
            moved.x += x - scroll.offsetX
            moved.y += y - scroll.offsetY
        }
    }

    /// The offset that puts the span from `start`, `length` long, with its `anchor` point (0 start, 1
    /// end) at the same point of a page `page` long, within the content's `extent`.
    private static func offset(start: Double, length: Double, anchor: Double, page: Double, extent: Double) -> Double {
        let upper = max(extent - page, 0)
        let value = start + length * anchor - page * anchor
        return value.isFinite ? min(max(value, 0), upper) : 0
    }

    /// The node of the element with `id` among `node`'s descendants (its template instances too: the
    /// first made).
    private static func descendant(_ id: Int, of node: RenderNode) -> RenderNode? {
        for child in node.orderedChildren + node.templateNodes {
            if child.element.id == id { return child }
            if let found = descendant(id, of: child) { return found }
        }
        return nil
    }
}
