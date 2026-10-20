// SwiftUI rendering of Spacer; its portable part is in Core/Elements/Spacer.swift.

import SwiftUI

extension Spacer: ActionUISwiftUIRenderer {
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        return SwiftUI.Spacer()
    }
    
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, properties, logger in
        let props = Props(properties)
        if let minLength = props.minLength {
            return view.frame(minWidth: CGFloat(minLength))
        }
        return view
    }
}
