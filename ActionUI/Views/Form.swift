// Sources/Views/Form.swift
/*
 Sample JSON for Form:
 {
   "type": "Form",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
   },
   "children": [
      { "type": "Text", "properties": { "text": "Field 1" } }
   ] // Required: Array of child views
   // Note: These properties are specific to Form. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct Form: ActionUIViewConstruction {
    static var valueType: Any.Type = Void.self
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }

    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        return properties
    }
    
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        
        let children = element.subviews?["children"] as? [any ActionUIElementBase] ?? []
        
        return SwiftUI.Form {
            let windowModel = ActionUIModel.shared.windowModels[windowUUID]
            ForEach(children, id: \.id) { child in
                if let childModel = windowModel?.viewModels[child.id] {
                    ActionUIView(element: child, model: childModel, windowUUID: windowUUID)
                }
            }
        }
    }
}
