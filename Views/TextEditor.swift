
/*
 Sample JSON for TextEditor:
 {
   "type": "TextEditor",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "placeholder": "Enter text here", // Optional: String, defaults to "Enter text"
     "actionID": "editor.changed",    // Optional: String for action identifier
     "padding": 10.0,                 // Optional: CGFloat for padding
     "font": "body",                  // Optional: SwiftUI font (e.g., "title", "body")
     "foregroundColor": "blue",       // Optional: SwiftUI color (e.g., "red", "blue")
     "hidden": false                  // Optional: Boolean to hide the view
   }
 }
*/

import SwiftUI

struct TextEditor: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        let supportedProperties = ["placeholder", "actionID", "padding", "font", "foregroundColor", "hidden"]
        var validatedProperties = properties
        
        if validatedProperties["placeholder"] == nil {
            validatedProperties["placeholder"] = "Enter text"
        }
        
        return validatedProperties.filter { key, _ in
            if supportedProperties.contains(key) {
                return true
            } else {
                print("Warning: Property '\(key)' is not supported for TextEditor; ignoring")
                return false
            }
        }
    }
    
    static func register(in registry: ViewBuilderRegistry) {
        registry.register("TextEditor") { element, state, windowUUID in
            let properties = validateProperties(element.properties)
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
