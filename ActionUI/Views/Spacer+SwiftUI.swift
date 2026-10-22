// SwiftUI rendering of Spacer; its portable part is in Core/Elements/Spacer.swift.

import SwiftUI

extension Spacer: ActionUISwiftUIRenderer {
    // minLength is the Spacer's own: along its stack's axis (a minimum height in a VStack), not a
    // minimum width. An infinite or negative minLength is ignored.
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let props = Props(properties)
        let minLength = props.minLength.flatMap { $0.isFinite && $0 >= 0 ? CGFloat($0) : nil }
        return SwiftUI.Spacer(minLength: minLength)
    }
    
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in
        view
    }
}
