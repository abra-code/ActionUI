
/*
 Sample JSON for TextField:
 {
   "type": "TextField",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "placeholder": "Enter text", // Optional: String, defaults to ""
     "commandID": "text.changed", // Optional: String for action identifier
     "padding": 10.0,           // Optional: CGFloat for padding
     "font": "body",            // Optional: SwiftUI font (e.g., "title", "body")
     "foregroundColor": "blue", // Optional: SwiftUI color (e.g., "red", "blue")
     "hidden": false            // Optional: Boolean to hide the view
   }
 }
*/

import SwiftUI

struct TextField: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        let supportedProperties = ["placeholder", "commandID", "padding", "font", "foregroundColor", "hidden"]
        var validatedProperties = properties
        
        if validatedProperties["placeholder"] == nil {
            validatedProperties["placeholder"] = ""
        }
        
        return validatedProperties.filter { key, _ in
            if supportedProperties.contains(key) {
                return true
            } else {
                print("Warning: Property '\(key)' is not supported for TextField; ignoring")
                return false
            }
        }
    }
    
    static func register(in registry: ViewBuilderRegistry) {
        registry.register("TextField") { element, state, dialogGUID in
            let properties = validateProperties(element.properties)
            let placeholder = properties["placeholder"] as? String ?? ""
            if state.wrappedValue[element.id] == nil {
                state.wrappedValue[element.id] = ["value": ""]
            }
            return AnyView(
                SwiftUI.TextField(placeholder, text: Binding(
                    get: { (state.wrappedValue[element.id] as? [String: Any])?["value"] as? String ?? "" },
                    set: { newValue in
                        state.wrappedValue[element.id] = ["value": newValue]
                        if let commandID = properties["commandID"] as? String {
                            commandHandler(commandID, dialogGUID: dialogGUID, controlID: element.id, controlPartID: 0, model: UIModel.shared)
                        }
                    }
                ))
            )
        }
    }
}
