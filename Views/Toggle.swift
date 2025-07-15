
/*
 Sample JSON for Toggle:
 {
   "type": "Toggle",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "label": "Enable Feature", // Optional: String, defaults to "Toggle"
     "style": "switch",        // Optional: "switch", "checkbox", "button"; defaults to "switch"
     "commandID": "toggle.changed", // Optional: String for action identifier
     "padding": 10.0,          // Optional: CGFloat for padding
     "font": "body",           // Optional: SwiftUI font (e.g., "title", "body")
     "foregroundColor": "blue", // Optional: SwiftUI color (e.g., "red", "blue")
     "hidden": false           // Optional: Boolean to hide the view
   }
 }
*/

import SwiftUI

struct Toggle: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        let supportedProperties = ["label", "style", "commandID", "padding", "font", "foregroundColor", "hidden"]
        var validatedProperties = properties
        
        if let style = properties["style"] as? String, !["switch", "checkbox", "button"].contains(style) {
            print("Warning: Toggle style '\(style)' invalid; defaulting to switch")
            validatedProperties["style"] = "switch"
        }
        if validatedProperties["style"] == nil {
            validatedProperties["style"] = "switch"
        }
        if validatedProperties["label"] == nil {
            validatedProperties["label"] = "Toggle"
        }
        
        return validatedProperties.filter { key, _ in
            if supportedProperties.contains(key) {
                return true
            } else {
                print("Warning: Property '\(key)' is not supported for Toggle; ignoring")
                return false
            }
        }
    }
    
    static func register(in registry: ViewBuilderRegistry) {
        registry.register("Toggle") { element, state, dialogGUID in
            let properties = validateProperties(element.properties)
            let label = properties["label"] as? String ?? "Toggle"
            let style = properties["style"] as? String ?? "switch"
            if state.wrappedValue[element.id] == nil {
                state.wrappedValue[element.id] = ["value": false]
            }
            return AnyView(
                SwiftUI.Toggle(label, isOn: Binding(
                    get: { (state.wrappedValue[element.id] as? [String: Any])?["value"] as? Bool ?? false },
                    set: { newValue in
                        state.wrappedValue[element.id] = ["value": newValue]
                        if let commandID = properties["commandID"] as? String {
                            commandHandler(commandID, dialogGUID: dialogGUID, controlID: element.id, controlPartID: 0, model: UIModel.shared)
                        }
                    }
                ))
                .toggleStyle({
                    switch style {
                    case "checkbox": return .checkbox
                    case "button": return .button
                    default: return .switch
                    }
                }())
            )
        }
    }
}
