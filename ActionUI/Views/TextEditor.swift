/*
 Sample JSON for TextEditor:
 {
   "type": "TextEditor",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "placeholder": "Enter text here" // Optional: String, no default value if omitted or empty
   }
   // Note: These properties are specific to TextEditor. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct TextEditor: ActionUIViewConstruction {
    // Design decision: Defines valueType as String to reflect text input for type-safe string parsing in ActionUIModel
    static var valueType: Any.Type { String.self }
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        // Validate placeholder
        if !(properties["placeholder"] is String?), properties["placeholder"] != nil {
            logger.log("TextEditor placeholder must be a String; defaulting to nil", .warning)
            validatedProperties["placeholder"] = nil
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let initialValue = Self.initialValue(model) as? String ?? ""
        
        let textBinding = Binding(
            get: { model.value as? String ?? initialValue },
            set: { newValue in
                guard model.value as? String != newValue else {
                    return
                }
                // Use DispatchQueue.main.async to guarantee deferred execution and avoid
                // "publishing changes from within view updates" warning
                DispatchQueue.main.async {
                    model.value = newValue
                    if let valueChangeActionID = properties["valueChangeActionID"] as? String {
                        ActionUIModel.shared.actionHandler(valueChangeActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                    }
                }
            }
        )
        
        if let placeholder = properties["placeholder"] as? String, !placeholder.isEmpty {
            return SwiftUI.TextEditor(text: textBinding)
                .overlay(
                    SwiftUI.Group {
                        if model.value as? String == "" {
                            SwiftUI.Text(placeholder)
                                .foregroundColor(.gray)
                                .allowsHitTesting(false)
                        } else {
                            SwiftUI.EmptyView()
                        }
                    },
                    alignment: .topLeading
                )
        } else {
            return SwiftUI.TextEditor(text: textBinding)
        }
    }
    
    static var initialValue: (ViewModel) -> Any? = { model in
        if let initialValue = model.value as? String {
            return initialValue
        }
        return ""
    }
}
