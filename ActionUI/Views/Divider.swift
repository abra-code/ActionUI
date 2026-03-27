// Sources/Views/Divider.swift
/*
 Sample JSON for Divider:
 {
   "type": "Divider",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
   }
   // Note: These properties are specific to Divider. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct Divider: ActionUIViewConstruction {
    static var valueType: Any.Type = Void.self
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }

    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        return properties
    }
    
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { _, _, _, _, _ in
        return SwiftUI.Divider()
    }
}
