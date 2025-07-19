/*
 Sample JSON for SecureField:
 {
   "type": "SecureField",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "placeholder": "Enter password", // Optional: String, defaults to ""
     "textContentType": "password"   // Optional: String for content type (e.g., "password", "newPassword"), defaults to nil
   }
   // Note: These properties are specific to SecureField. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct SecureField: ActionUIViewElement {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = View.validateProperties(properties)
        
        if validatedProperties["placeholder"] == nil {
            validatedProperties["placeholder"] = ""
        }
        if let textContentType = validatedProperties["textContentType"] as? String,
           ["password", "newPassword"].contains(textContentType) {
            validatedProperties["textContentType"] = textContentType
        } else if validatedProperties["textContentType"] != nil {
            print("Warning: SecureField textContentType must be 'password' or 'newPassword'; ignoring")
            validatedProperties["textContentType"] = nil
        }
        
        return validatedProperties
    }
    
    static func buildElement(_ element: ActionUIElement, _ state: Binding<[Int: Any]>, _ windowUUID: String, validatedProperties: [String: Any]) -> AnyView {
        let placeholder = validatedProperties["placeholder"] as? String ?? ""
        if state.wrappedValue[element.id] == nil {
            state.wrappedValue[element.id] = ["value": ""]
        }
        let textBinding = Binding(
            get: { (state.wrappedValue[element.id] as? [String: Any])?["value"] as? String ?? "" },
            set: { newValue in
                state.wrappedValue[element.id] = ["value": newValue]
                if let actionID = validatedProperties["actionID"] as? String {
                    actionHandler(actionID, windowUUID: windowUUID, controlID: element.id, controlPartID: 0, model: ActionUIModel.shared)
                }
            }
        )
        
        return AnyView(
            SwiftUI.SecureField(placeholder, text: textBinding)
        )
    }
    
    static func applyModifiers(_ view: AnyView, _ properties: [String: Any]) -> AnyView {
        var modifiedView = view
        if let textContentType = properties["textContentType"] as? String {
            modifiedView = AnyView(modifiedView.textContentType(textContentType))
        }
        return modifiedView
    }
}
