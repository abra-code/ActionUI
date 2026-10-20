// SwiftUI rendering of Label; its portable part is in Core/Elements/Label.swift.

import SwiftUI

extension Label: ActionUISwiftUIRenderer {
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, _ in
        
        let props = Props(properties)
        let initialValue = Self.initialValue(model) as? String ?? ""
        
        if let systemImage = props.systemImage {
            return SwiftUI.Label(initialValue, systemImage: systemImage)
        } else if let imageName = props.imageName {
            return SwiftUI.Label(initialValue, image: imageName)
        }
        
        return SwiftUI.Label(initialValue, systemImage: "").labelStyle(.titleOnly)
    }
    
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, properties, logger in
        var modifiedView = view
        return modifiedView
    }
}
