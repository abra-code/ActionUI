// Sources/Elements/Divider+WinUI.swift
/*
 Divider on WinUI: a line 1 thick across its parent stack's axis, as SwiftUI's Divider and the GTK
 renderer's: vertical in an HStack or a LabeledContent's row (spanning its height), horizontal anywhere else (spanning the
 width), with the stack's spacing on both sides. It is drawn in the WinUI theme's divider color
 (DividerStrokeColorDefaultBrush), as a WinUI app draws its separators.
*/

import CWinUI

extension Divider: ActionUIWinUIRenderer {
    /// Whether the element's parent lays it out in a row (an HStack, a LabeledContent's content),
    /// where it is a vertical line.
    static func inRow(_ node: RenderNode) -> Bool {
        StackViews.parentAxis(node) == .horizontal
    }

    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        let fill = try FillLayout()
        node.state = fill
        return fill.panel.object
    }

    static func expansion(_ node: RenderNode) -> Expansion {
        inRow(node) ? .vertical : .horizontal
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        guard let fill = node.state as? FillLayout else { return }
        let row = inRow(node)
        let width: Double? = row ? 1 : nil
        let height: Double? = row ? nil : 1
        if fill.fixedWidth != width || fill.fixedHeight != height {
            fill.fixedWidth = width
            fill.fixedHeight = height
            fill.panel.invalidateLayout()
        }
        Paint.apply(.theme("DividerStrokeColorDefaultBrush"), ActionUIWinUIBrushBackground, to: view, what: "a Divider")
    }
}
