/*
 Sample JSON for SecureField:
 {
   "type": "SecureField",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "placeholder": "Enter password", // Optional: String for placeholder, defaults to ""
     "textContentType": "password",  // Optional: String for content type (e.g., "password", "newPassword"), defaults to nil
     "actionID": "secure.submit"     // Optional: String for action triggered on submit (e.g., Return key), validated by View.validateProperties
   }
   // Note: These properties are specific to SecureField. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct SecureField: ActionUIViewConstruction {
    // Validates properties specific to SecureField; baseline properties are validated by ActionUIRegistry.getValidatedProperties
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = properties
        
        // Default to empty string if placeholder is not provided
        if validatedProperties["placeholder"] == nil {
            validatedProperties["placeholder"] = ""
        }
        // Validate textContentType, ignore if invalid
        if let textContentType = validatedProperties["textContentType"] as? String,
           ["password", "newPassword"].contains(textContentType) {
            validatedProperties["textContentType"] = textContentType
        } else if validatedProperties["textContentType"] != nil {
            print("Warning: SecureField textContentType must be 'password' or 'newPassword'; ignoring")
            validatedProperties["textContentType"] = nil
        }
        
        return validatedProperties
    }
        
    // Builds the SwiftUI.SecureField view, binding its text to state and triggering actionID on submit
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
            SwiftUI.SecureField(placeholder, text: textBinding)
                .onSubmit {
                    // Trigger actionID only on submit (e.g., Return key or "Done" on iOS)
                    if let actionID = actionID {
                        // Use singleton ActionUIModel.shared for action handling
                        ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                    }
                }
        )
    }
    
    // Applies modifiers specific to SecureField, such as textContentType
    static func applyModifiers(_ view: AnyView, _ properties: [String: Any]) -> AnyView {
        var modifiedView = view
        if let textContentType = properties["textContentType"] as? String {
            // Apply textContentType for password autofill or new password suggestions
            if textContentType == "password" {
                modifiedView = AnyView(modifiedView.textContentType(.password))
            } else if textContentType == "newPassword" {
                modifiedView = AnyView(modifiedView.textContentType(.newPassword))
            }
        }
        return modifiedView
    }
}
