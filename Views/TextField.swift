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

struct TextField: ActionUIViewElement {
    // Validates properties specific to TextField; baseline properties are validated by ActionUIRegistry.getValidatedProperties
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = properties
        
        // Default to empty string if placeholder is not provided
        if validatedProperties["placeholder"] == nil {
            validatedProperties["placeholder"] = ""
        }
        
        return validatedProperties
    }
        
    // Builds the SwiftUI.TextField view, binding its text to state and triggering actionID on submit.
    static func buildElement(_ element: ActionUIElement, _ state: Binding<[Int: Any]>, _ windowUUID: String, validatedProperties: [String: Any]) -> AnyView {
        let placeholder = validatedProperties["placeholder"] as? String ?? ""
        let actionID = validatedProperties["actionID"] as? String
        
        // Initialize state with empty text if not present
        if state.wrappedValue[element.id] == nil {
            state.wrappedValue[element.id] = [
                "value": "",
                "validatedProperties": validatedProperties
            ]
        }
        
        // Bind text to state[element.id]["value"]
        let textBinding = Binding(
            get: { (state.wrappedValue[element.id] as? [String: Any])?["value"] as? String ?? "" },
            set: { newValue in
                var newState = (state.wrappedValue[element.id] as? [String: Any]) ?? [:]
                newState["value"] = newValue
                state.wrappedValue[element.id] = newState
            }
        )
        
        return AnyView(
            SwiftUI.TextField(placeholder, text: textBinding)
                .onSubmit {
                    // Trigger actionID only on submit (e.g., Return key)
                    if let actionID = actionID {
                        // Use singleton ActionUIModel.shared for action handling
                        ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, controlPartID: 0)
                    }
                }
        )
    }
        
    // Apply no specific modifiers; rely on ActionUIRegistry for baseline View properties
    static func applyModifiers(_ view: AnyView, _ properties: [String: Any]) -> AnyView {
        return view
    }
}
