/*
 Sample JSON for TextField:
 {
   "type": "TextField",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "placeholder": "Enter text" // Optional: String, defaults to ""
   }
   // Note: These properties are specific to TextField. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct TextField: ActionUIViewElement {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = properties
        
        if validatedProperties["placeholder"] == nil {
            validatedProperties["placeholder"] = ""
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
            SwiftUI.TextField(placeholder, text: textBinding)
        )
    }
    
    static func applyModifiers(_ view: AnyView, _ properties: [String: Any]) -> AnyView {
        return view // No specific modifiers beyond base View properties
    }
}
