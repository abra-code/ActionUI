// SwiftUI rendering of Circle; its portable part is in Core/Elements/Circle.swift.

import SwiftUI

extension Circle: ActionUISwiftUIRenderer {
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { _, _, _, properties, _ in
        let props = Props(properties)
        if let fillStr = props.fill, let style = ColorHelper.resolveShapeStyle(fillStr) {
            return SwiftUI.Circle().fill(style)
        }
        if let strokeStr = props.stroke, let style = ColorHelper.resolveShapeStyle(strokeStr) {
            let lineWidth = CGFloat(props.strokeLineWidth)
            return SwiftUI.Circle().stroke(style, lineWidth: lineWidth)
        }
        return SwiftUI.Circle()
    }

    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in
        return view
    }
}
