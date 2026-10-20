// SwiftUI rendering of Capsule; its portable part is in Core/Elements/Capsule.swift.

import SwiftUI

extension Capsule: ActionUISwiftUIRenderer {
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { _, _, _, properties, _ in
        let props = Props(properties)
        let style: RoundedCornerStyle = {
            switch props.style {
            case .circular: return .circular
            case .continuous: return .continuous
            }
        }()
        let shape = SwiftUI.Capsule(style: style)

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
