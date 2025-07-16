/*
 Sample JSON for TextEditor:
 {
   "type": "TextEditor",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "placeholder": "Enter text here" // Optional: String, defaults to "Enter text"
   }
   // Note: These properties are specific to TextEditor. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID) and additional View protocol modifiers are inherited and applied via ModifierRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct TextEditor: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = View.validateProperties(properties)
        
        if validatedProperties["placeholder"] == nil {
            validatedProperties["placeholder"] = "Enter text"
        }
        
        return validatedProperties
    }
    
    static func register(in registry: ViewBuilderRegistry) {
        registry.register("TextEditor") { element, state, windowUUID in
            let properties = StaticElement.getValidatedProperties(element: element, state: state)
            let placeholder = properties["placeholder"] as? String ?? "Enter text"
            if state.wrappedValue[element.id] == nil {
                state.wrappedValue[element.id] = ["value": ""]
            }
            return AnyView(
                SwiftUI.TextEditor(text: Binding(
                    get: { (state.wrappedValue[element.id] as? [String: Any])?["value"] as? String ?? "" },
                    set: { newValue in
                        state.wrappedValue[element.id] = ["value": newValue]
                        if let actionID = properties["actionID"] as? String {
                            actionHandler(actionID, windowUUID: windowUUID, controlID: element.id, controlPartID: 0, model: ActionUIModel.shared)
                        }
                    }
                ))
                .overlay(
                    Group {
                        if (state.wrappedValue[element.id] as? [String: Any])?["value"] as? String == "" {
                            SwiftUI.Text(placeholder)
                                .foregroundColor(.gray)
                                .allowsHitTesting(false)
                        } else {
                            EmptyView()
                        }
                    },
                    alignment: .topLeading
                )
            )
        }
    }
}
