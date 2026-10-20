// SwiftUI rendering of RoundedRectangle; its portable part is in Core/Elements/RoundedRectangle.swift.

import SwiftUI

extension RoundedRectangle: ActionUISwiftUIRenderer {
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { _, _, _, properties, _ in
        let props = Props(properties)
        let cornerRadius = CGFloat(props.cornerRadius)
        let style: RoundedCornerStyle = {
            switch props.cornerStyle {
            case .circular: return .circular
            case .continuous: return .continuous
            }
        }()
        let shape = SwiftUI.RoundedRectangle(cornerRadius: cornerRadius, style: style)

        if let fillStr = props.fill, let fillStyle = ColorHelper.resolveShapeStyle(fillStr) {
            return shape.fill(fillStyle)
        }
        if let strokeStr = props.stroke, let strokeStyle = ColorHelper.resolveShapeStyle(strokeStr) {
            let lineWidth = CGFloat(props.strokeLineWidth)
            return shape.stroke(strokeStyle, lineWidth: lineWidth)
        }
        return shape
    }

    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in
        return view
    }
}
