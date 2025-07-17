/*
 Sample JSON for SecureField:
 {
   "type": "SecureField",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "placeholder": "Enter password", // Optional: String, defaults to ""
     "textContentType": "password"   // Optional: String for content type (e.g., "password", "newPassword"), defaults to nil
   }
   // Note: These properties are specific to SecureField. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ModifierRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct SecureField: StaticElement, ViewBuilder {
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
    
    static func register(in registry: ViewBuilderRegistry) {
        registry.register("SecureField") { element, state, windowUUID in
            let properties = StaticElement.getValidatedProperties(element: element, state: state)
            let placeholder = properties["placeholder"] as? String ?? ""
            if state.wrappedValue[element.id] == nil {
                state.wrappedValue[element.id] = ["value": ""]
            }
            let textBinding = Binding(
                get: { (state.wrappedValue[element.id] as? [String: Any])?["value"] as? String ?? "" },
                set: { newValue in
                    state.wrappedValue[element.id] = ["value": newValue]
                    if let actionID = properties["actionID"] as? String {
                        actionHandler(actionID, windowUUID: windowUUID, controlID: element.id, controlPartID: 0, model: ActionUIModel.shared)
                    }
                }
            )
            return AnyView(
                SecureField(placeholder, text: textBinding)
            )
        }
    }
    
    static func registerModifiers(registry: ModifierRegistry) {
        registry.register("textContentType") { view, properties in
            guard let textContentType = properties["textContentType"] as? String else { return view }
            return AnyView(view.textContentType(textContentType))
        }
    }
}
