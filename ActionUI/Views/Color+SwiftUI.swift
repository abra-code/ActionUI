// SwiftUI rendering of Color; its portable part is in Core/Elements/Color.swift.
// SwiftUI's own `Color` is itself a View, so the element renders as one.

import SwiftUI

extension Color: ActionUISwiftUIRenderer {
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { _, model, _, properties, logger in
        // Runtime override takes precedence (ActionUIView re-builds this when model.value changes).
        if let spec = model.value as? ColorSpec {
            return ColorHelper.color(for: spec)
        }
        let props = Props(properties)
        if let colorStr = props.color, !colorStr.isEmpty {
            if let resolved = ColorHelper.resolveColor(colorStr) {
                return resolved
            }
            logger.log("Unknown color \"\(colorStr)\" for Color view; rendering clear", .warning)
        } else {
            logger.log("Color view requires a 'color' string; rendering clear", .warning)
        }
        return SwiftUI.Color.clear
    }

    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in
        return view
    }
}
