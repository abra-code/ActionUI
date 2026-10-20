// SwiftUI rendering of Ellipse; its portable part is in Core/Elements/Ellipse.swift.

import SwiftUI

extension Ellipse: ActionUISwiftUIRenderer {
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { _, _, _, properties, _ in
        let props = Props(properties)
        if let fillStr = props.fill, let style = ColorHelper.resolveShapeStyle(fillStr) {
            return SwiftUI.Ellipse().fill(style)
        }
        if let strokeStr = props.stroke, let style = ColorHelper.resolveShapeStyle(strokeStr) {
            let lineWidth = CGFloat(props.strokeLineWidth)
            return SwiftUI.Ellipse().stroke(style, lineWidth: lineWidth)
        }
        return SwiftUI.Ellipse()
    }

    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in
        return view
    }
}
