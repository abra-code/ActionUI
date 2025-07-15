
/*
 Sample JSON for List:
 {
   "type": "List",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "items": ["Item1", "Item2"], // Optional: Array of strings, defaults to []
     "commandID": "list.select",  // Optional: String for selection action identifier
     "doubleClickCommandID": "list.doubleClick", // Optional: String for double-click action (macOS only)
     "padding": 10.0,            // Optional: CGFloat for padding
     "font": "body",             // Optional: SwiftUI font (e.g., "title", "body")
     "foregroundColor": "blue",  // Optional: SwiftUI color (e.g., "red", "blue")
     "hidden": false             // Optional: Boolean to hide the view
   }
 }
*/

import SwiftUI

struct List: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        let supportedProperties = ["items", "commandID", "doubleClickCommandID", "padding", "font", "foregroundColor", "hidden"]
        var validatedProperties = properties
        
        validatedProperties["items"] = properties["items"] as? [String] ?? []
        
        return validatedProperties.filter { key, _ in
            if supportedProperties.contains(key) {
                return true
            } else {
                print("Warning: Property '\(key)' is not supported for List; ignoring")
                return false
            }
        }
    }
    
    static func register(in registry: ViewBuilderRegistry) {
        registry.register("List") { element, state, dialogGUID in
            let properties = validateProperties(element.properties)
            let items = (properties["items"] as? [String]) ?? []
            if state.wrappedValue[element.id] == nil {
                state.wrappedValue[element.id] = ["value": ""]
            }
            var list = SwiftUI.List(items, id: \.self, selection: Binding(
                get: { (state.wrappedValue[element.id] as? [String: Any])?["value"] as? String },
                set: { newValue in
                    state.wrappedValue[element.id] = ["value": newValue ?? ""]
                    if let commandID = properties["commandID"] as? String {
                        commandHandler(commandID, dialogGUID: dialogGUID, controlID: element.id, controlPartID: 0, model: UIModel.shared)
                    }
                }
            )) { item in
                SwiftUI.Text(item)
            }
            .onChange(of: state.wrappedValue[element.id]?["value"]) { newValue in
                if let commandID = properties["commandID"] as? String, newValue != nil {
                    commandHandler(commandID, dialogGUID: dialogGUID, controlID: element.id, controlPartID: 0, model: UIModel.shared)
                }
            }
            #if os(macOS)
            list = list.onTapGesture(count: 2) {
                if let commandID = properties["doubleClickCommandID"] as? String,
                   let selectedItem = (state.wrappedValue[element.id] as? [String: Any])?["value"] as? String {
                    commandHandler(commandID, dialogGUID: dialogGUID, controlID: element.id, controlPartID: 0, model: UIModel.shared)
                }
            }
            #endif
            return AnyView(list)
        }
    }
}
