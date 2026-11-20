// Sources/Layout/FillLayout.swift
/*
 The layout of the elements that fill whatever room they get, as SwiftUI's Color and shapes do: a
 LayoutPanel that asks for all of a finite offer and, offered unbounded room, for SwiftUI's ideal
 size of 10 in that axis (measured on macOS; the GTK renderer's Color.idealLength). Its one child
 (a shape, or none for a Color, which paints the panel's background) fills the panel.

 Divider uses it too, with a thickness of 1 along its parent stack's axis instead of the ideal. A
 Circle's ellipse is placed in the largest square of the panel, centered (squareChild). A Canvas's
 image of its drawing fills it, drawn again for each new size (arranged).

 For a shape, two of SwiftUI's rules WinUI does not have: a stroke is centered on the outline, half
 of it outside the frame, where a WinUI shape draws it inside its bounds (so the shape reaches half
 the stroke past the panel on every side: childOutset); and a corner radius is at most half the
 shorter side, where WinUI clamps each axis on its own, which turns a large radius into an ellipse
 (cornerRadius, set at each arrange; a Capsule's is infinite).
*/

import CWinUI

@MainActor
final class FillLayout {
    /// SwiftUI's ideal size of a Color and of the shapes, in each axis.
    static let idealLength = 10.0

    let panel: LayoutPanel
    /// A fixed length per axis instead of filling it (a Divider's thickness); nil fills.
    var fixedWidth: Double?
    var fixedHeight: Double?
    /// Whether the child is placed in the largest square of the panel, centered (a Circle).
    var squareChild = false
    /// How far the child reaches past its place on every side: half a shape's stroke.
    var childOutset = 0.0
    /// The child rectangle's corner radius before clamping: nil leaves it alone; infinite for a
    /// Capsule. Arrange sets it to at most half the shorter side of the shape's frame.
    var cornerRadius: Double?
    /// Called at the end of each arrange with the panel's final size (a Canvas draws for it).
    var arranged: ((ActionUIWinUISize) -> Void)?

    init(child: WinUIObject? = nil) throws(WinUIError) {
        panel = try LayoutPanel()
        if let child {
            try panel.append(child)
        }
        panel.measure = { [unowned self] available in measure(available) }
        panel.arrange = { [unowned self] finalSize in arrange(finalSize) }
    }

    private func length(_ offer: Double, fixed: Double?) -> Double {
        if let fixed { return fixed }
        return offer.isFinite ? offer : Self.idealLength
    }

    private func measure(_ available: ActionUIWinUISize) -> ActionUIWinUISize {
        let size = ActionUIWinUISize(width: length(available.width, fixed: fixedWidth),
                                     height: length(available.height, fixed: fixedHeight))
        let childSize = ActionUIWinUISize(width: size.width + 2 * childOutset, height: size.height + 2 * childOutset)
        for child in panel.children {
            _ = child.measure(childSize)
        }
        return size
    }

    private func arrange(_ finalSize: ActionUIWinUISize) {
        var rect = ActionUIWinUIRect(x: 0, y: 0, width: finalSize.width, height: finalSize.height)
        if squareChild {
            let side = min(finalSize.width, finalSize.height)
            rect = ActionUIWinUIRect(x: (finalSize.width - side) / 2, y: (finalSize.height - side) / 2, width: side, height: side)
        }
        for child in panel.children {
            // The shim sets it only when it changed, so the layout this asks for settles.
            if let cornerRadius,
               !actionUIWinUIShapeSetCornerRadius(child.pointer, min(cornerRadius, min(rect.width, rect.height) / 2)) {
                ActionUIModel.shared.logger.log("FillLayout: \(WinUIError.last("rounding a shape"))", .error)
            }
            child.arrange(ActionUIWinUIRect(x: rect.x - childOutset, y: rect.y - childOutset,
                                            width: rect.width + 2 * childOutset, height: rect.height + 2 * childOutset))
        }
        arranged?(finalSize)
    }
}
