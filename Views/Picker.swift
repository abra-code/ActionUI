
/*
 Sample JSON for Picker:
 {
   "type": "Picker",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "title": "Select Option",    // Optional: String, defaults to ""
     "options": ["Option1", "Option2"], // Required: Array of strings
     "pickerStyle": "menu",       // Optional: "menu", "wheel", "segmented"
     "commandID": "picker.select", // Optional: String for action identifier
     "padding": 10.0,            // Optional: CGFloat for padding
     "font": "body",             // Optional: SwiftUI font (e.g., "title", "body")
     "foregroundColor": "blue",  // Optional: SwiftUI color (e.g., "red", "blue")
     "hidden": false             // Optional: Boolean to hide the view
   }
 }
*/

import SwiftUI

struct Picker: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        let supportedProperties = ["title", "options", "pickerStyle", "commandID", "padding", "font", "foregroundColor", "hidden"]
        var validatedProperties = properties
        
        if let options = properties["options"] as? [String], options.isEmpty {
            print("Warning: Picker options is empty; initializing with empty array")
            validatedProperties["options"] = []
        }
        if validatedProperties["title"] == nil {
            validatedProperties["title"] = ""
        }
        if let style = validatedProperties["pickerStyle"] as? String, !["menu", "wheel", "segmented"].contains(style) {
            print("Warning: Picker style '\(style)' invalid; ignoring")
            validatedProperties["pickerStyle"] = nil
        }
        
        return validatedProperties.filter { key, _ in
            if supportedProperties.contains(key) {
                return true
            } else {
                print("Warning: Property '\(key)' is not supported for Picker; ignoring")
                return false
            }
        }
    }
    
    static func register(in registry: ViewBuilderRegistry) {
        registry.register("Picker") { element, state, dialogGUID in
            let properties = validateProperties(element.properties)
            let title = properties["title"] as? String ?? ""
            let items = (properties["options"] as? [String]) ?? []
            if state.wrappedValue[element.id] == nil {
                state.wrappedValue[element.id] = ["value": items.first ?? ""]
            }
            var picker = SwiftUI.Picker(title, selection: Binding(
                get: { (state.wrappedValue[element.id] as? [String: Any])?["value"] as? String ?? items.first ?? "" },
                set: { newValue in
                    state.wrappedValue[element.id] = ["value": newValue]
                    if let commandID = properties["commandID"] as? String {
                        commandHandler(commandID, dialogGUID: dialogGUID, controlID: element.id, controlPartID: 0, model: UIModel.shared)
                    }
                }
            )) {
                ForEach(items, id: \.self) { item in
                    SwiftUI.Text(item).tag(item)
                }
            }
            if let style = properties["pickerStyle"] as? String {
                switch style {
                case "menu": picker = picker.pickerStyle(.menu)
                case "wheel": picker = picker.pickerStyle(.wheel)
                case "segmented": picker = picker.pickerStyle(.segmented)
                default: break
                }
            }
            return AnyView(picker)
        }
    }
}
