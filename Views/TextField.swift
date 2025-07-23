/*
 Sample JSON for TextField:
 {
   "type": "TextField",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "placeholder": "Enter text", // Optional: String for placeholder, defaults to ""
     "actionID": "text.submit"   // Optional: String for action triggered on submit (e.g., Return key)
   }
   // Note: The TextField view triggers an action via 'actionID' when the user submits input (e.g., Return key or "Done" on iOS). Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct TextField: ActionUIViewConstruction {
    static var valueType: Any.Type? { String.self } // Value is the text input
    
    // Validates properties specific to TextField; baseline properties are validated by ActionUIRegistry.getValidatedProperties
    static var validateProperties: (([String: Any]) -> [String: Any])? = { properties in
        var validatedProperties = properties
        
        // Default to empty string if placeholder is not provided
        if validatedProperties["placeholder"] == nil {
            validatedProperties["placeholder"] = ""
        }
        
        return validatedProperties
    }
    
    // Builds the SwiftUI.TextField view, binding its text to state and triggering actionID on submit
    // Design decision: Initializes value as "" if not set, preserving shared state (validatedProperties) from ActionUIRegistry.build
    static var buildElement: ((ActionUIElement, Binding<[Int: Any]>, String, [String: Any]) -> AnyView)? = { element, state, windowUUID, validatedProperties in
        let placeholder = validatedProperties["placeholder"] as? String ?? ""
        
        // Initialize TextField-specific state only if not already set
        // Design decision: Merges value (String) conditionally to avoid overwriting existing properties
        var newState = (state.wrappedValue[element.id] as? [String: Any]) ?? [:]
        var viewSpecificState: [String: Any] = [:]
        if newState["value"] == nil {
            viewSpecificState["value"] = ""
        }
        if !viewSpecificState.isEmpty {
            state.wrappedValue[element.id] = newState.merging(viewSpecificState, uniquingKeysWith: { _, new in new })
        }
        
        let textBinding = Binding(
            get: { (state.wrappedValue[element.id] as? [String: Any])?["value"] as? String ?? "" },
            set: { newValue in
                var newState = (state.wrappedValue[element.id] as? [String: Any]) ?? [:]
                newState["value"] = newValue
                state.wrappedValue[element.id] = newState
            }
        )
        
        let actionID = validatedProperties["actionID"] as? String
        
        return AnyView(
            SwiftUI.TextField(placeholder, text: textBinding)
                .onSubmit {
                    // Trigger actionID only on submit (e.g., Return key)
                    if let actionID = actionID {
                        ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                    }
                }
        )
    }
}
