// SwiftUI rendering of Rectangle; its portable part is in Core/Elements/Rectangle.swift.

import SwiftUI

extension Rectangle: ActionUISwiftUIRenderer {
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { _, _, _, properties, _ in
        let props = Props(properties)
        if let fillStr = props.fill, let style = ColorHelper.resolveShapeStyle(fillStr) {
            return SwiftUI.Rectangle().fill(style)
        }
        if let strokeStr = props.stroke, let style = ColorHelper.resolveShapeStyle(strokeStr) {
            let lineWidth = CGFloat(props.strokeLineWidth)
            return SwiftUI.Rectangle().stroke(style, lineWidth: lineWidth)
        }
        return SwiftUI.Rectangle()
    }

    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in
        return view
    }
}
