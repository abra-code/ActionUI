/*
 Sample JSON for TextEditor:
 {
   "type": "TextEditor",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "placeholder": "Enter text here" // Optional: String, no default value if omitted or empty
   }
   // Note: These properties are specific to TextEditor. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct TextEditor: ActionUIViewConstruction {
    // Design decision: Defines valueType as String to reflect text input for type-safe string parsing in ActionUIModel
    static var valueType: Any.Type { String.self }
    
    static var validateProperties: ([String: Any]) -> [String: Any] = { properties in
        var validatedProperties = properties
        
        // Validate placeholder
        if let placeholder = validatedProperties["placeholder"] as? String {
            validatedProperties["placeholder"] = placeholder
        } else if validatedProperties["placeholder"] != nil {
            print("Warning: TextEditor placeholder must be a string; ignoring")
            validatedProperties["placeholder"] = nil
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any]) -> any SwiftUI.View = { element, state, windowUUID, properties in
        // Initialize TextEditor-specific state
        var newState = (state.wrappedValue[element.id] as? [String: Any]) ?? [:]
        var viewSpecificState: [String: Any] = [:]
        if newState["value"] == nil {
            viewSpecificState["value"] = ""
        }
        viewSpecificState["validatedProperties"] = properties
        if !viewSpecificState.isEmpty {
            state.wrappedValue[element.id] = newState.merging(viewSpecificState, uniquingKeysWith: { _, new in new })
        }
        
        let textBinding = Binding(
            get: { (state.wrappedValue[element.id] as? [String: Any])?["value"] as? String ?? "" },
            set: { newValue in
                var newState = (state.wrappedValue[element.id] as? [String: Any]) ?? [:]
                newState["value"] = newValue
                newState["validatedProperties"] = properties // Include validated properties per ActionUI guidelines
                state.wrappedValue[element.id] = newState
                if let actionID = properties["actionID"] as? String {
                    Task { @MainActor in
                        ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                    }
                }
            }
        )
        
        if let placeholder = properties["placeholder"] as? String, !placeholder.isEmpty {
            return SwiftUI.TextEditor(text: textBinding)
                .overlay(
                    SwiftUI.Group {
                        if (state.wrappedValue[element.id] as? [String: Any])?["value"] as? String == "" {
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
}
