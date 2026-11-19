// Sources/Elements/ScrollView+WinUI.swift
/*
 ScrollView on WinUI: a ScrollViewer holding the element's content, laid out as SwiftUI does (the
 GTK renderer's measurements, ScrollView+Adwaita.swift):
 - it expands along its scroll axes (axis vertical, horizontal or both) and takes its content's
   size across them (all of it when the content expands there); in a stack it can be made as small
   as nothing along a scroll axis, so two of them share the space (StackLayout.Item.compressible),
   and asked for its ideal size it asks for its content's;
 - along a scroll axis the content has its own size, at the start (top, leading); across, it is
   offered the ScrollView's size and placed in it as in any box (centered).
 showsIndicators false keeps scrolling without scroll bars. WinUI shows its scroll bars only while
 the pointer is over the view, as macOS and libadwaita draw overlay scrollers.

 Not yet: onRefreshActionID (pull to refresh, which desktops do not have), ScrollViewReader.
*/

import CWinUI

extension ScrollView: ActionUIWinUIRenderer {
    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        guard let scroll = WinUIObject(adopting: actionUIWinUIScrollViewerCreate()) else {
            throw WinUIError.last("creating a ScrollViewer")
        }
        node.state = ScrollState()
        return scroll
    }

    /// The axes a ScrollView of `axis` scrolls along.
    static func scrollAxes(_ axis: Props.Axis) -> Expansion {
        switch axis {
        case .vertical: return .vertical
        case .horizontal: return .horizontal
        case .both: return .both
        }
    }

    static func expansion(_ node: RenderNode) -> Expansion {
        var expansion = scrollAxes(Props(node.properties).axis)
        // Across, as its content when that expands without a limit (a TextField: the ScrollView takes
        // the width it is offered, as on Linux). Content with a frame's finite maximum keeps the
        // ScrollView at its measured size, which that maximum already bounds. The content's node
        // exists from the first sync on, and marks this one dirty when its expansion changes.
        if let content = node.orderedChildren.first {
            if content.expansion.contains(.horizontal) && content.caps.horizontal == nil { expansion.insert(.horizontal) }
            if content.expansion.contains(.vertical) && content.caps.vertical == nil { expansion.insert(.vertical) }
        }
        return expansion
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        guard let state = node.state as? ScrollState else { return }
        let props = Props(node.properties)
        let horizontal = props.axis != .vertical
        let vertical = props.axis != .horizontal
        if !actionUIWinUIScrollViewerSetAxes(view.pointer, horizontal, vertical, props.showsIndicators) {
            ActionUIModel.shared.logger.log("ScrollView: \(WinUIError.last("setting the scroll axes"))", .error)
        }
        let content = node.effectiveElement.subviews?["content"] as? any ActionUIElementBase
        let child = node.syncChildren(content.map { [$0] } ?? []).first
        let childView = child?.outerView
        if state.content !== childView {
            state.content = childView
            if !actionUIWinUIScrollViewerSetContent(view.pointer, childView?.pointer) {
                ActionUIModel.shared.logger.log("ScrollView: \(WinUIError.last("setting the content"))", .error)
            }
        }
        // Along a scroll axis at the start, at its own size; across, given the whole width or height.
        if let childView {
            let placed = actionUIWinUIElementSetAlignment(childView.pointer,
                                                          horizontal ? ActionUIWinUIAlignStart : ActionUIWinUIAlignStretch,
                                                          vertical ? ActionUIWinUIAlignStart : ActionUIWinUIAlignStretch)
            if !placed {
                ActionUIModel.shared.logger.log("ScrollView: \(WinUIError.last("placing the content"))", .error)
            }
        }
    }
}

/// What a ScrollView node keeps: the content's box now in the ScrollViewer.
@MainActor final class ScrollState {
    var content: WinUIObject?
}
