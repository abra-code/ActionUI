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

struct TextEditor: ActionUIViewElement {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = properties
        
        if let placeholder = validatedProperties["placeholder"] as? String {
            validatedProperties["placeholder"] = placeholder
        } else if validatedProperties["placeholder"] != nil {
            print("Warning: TextEditor placeholder must be a string; ignoring")
            validatedProperties["placeholder"] = nil
        }
        
        return validatedProperties
    }
    
    static func buildElement(_ element: ActionUIElement, _ state: Binding<[Int: Any]>, _ windowUUID: String, validatedProperties: [String: Any]) -> AnyView {
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
        
        if let placeholder = validatedProperties["placeholder"] as? String, !placeholder.isEmpty {
            return AnyView(
                SwiftUI.TextEditor(text: textBinding)
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
        } else {
            return AnyView(
                SwiftUI.TextEditor(text: textBinding)
            )
        }
    }
    
    static func applyModifiers(_ view: AnyView, _ properties: [String: Any]) -> AnyView {
        return view // No specific modifiers beyond base View properties
    }
}
