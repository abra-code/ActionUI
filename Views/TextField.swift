/*
 Sample JSON for TextField:
 {
   "type": "TextField",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "placeholder": "Enter text", // Optional: String, defaults to ""
   }
   // Note: These properties are specific to TextField. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ModifierRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct TextField: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = View.validateProperties(properties)
        
        if validatedProperties["placeholder"] == nil {
            validatedProperties["placeholder"] = ""
        }
        
        return validatedProperties
    }
    
    static func register(in registry: ViewBuilderRegistry) {
        registry.register("TextField") { element, state, windowUUID in
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
                SwiftUI.TextField(placeholder, text: textBinding)
            )
        }
    }
    
    static func registerModifiers() {
        // No specific modifiers beyond base View properties
    }
}
