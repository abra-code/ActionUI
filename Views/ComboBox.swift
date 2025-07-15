/*
 CURRENTLY DISABLED - two part control presents a challenge which properties apply to which part
 
 Sample JSON for ComboBox (macOS, iOS, iPadOS only):
 {
   "type": "ComboBox",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "placeholder": "Select an option", // Optional: String, defaults to ""
     "options": ["Option1", "Option2"], // Optional: Array of strings, defaults to []
     "commandID": "combo.select",      // Optional: String for action identifier
     "padding": 10.0,                 // Optional: CGFloat for padding
     "font": "body",                  // Optional: SwiftUI font (e.g., "title", "body")
     "foregroundColor": "blue",       // Optional: SwiftUI color (e.g., "red", "blue")
     "hidden": false                  // Optional: Boolean to hide the view
     "pickerStyle": "menu"            // Optional: String ("menu", "wheel", "segmented") for Picker style
   }
 }
*/

import SwiftUI

struct ComboBox: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        let supportedProperties = ["placeholder", "options", "commandID", "padding", "font", "foregroundColor", "hidden", "pickerStyle"]
        var validatedProperties = properties
        
        #if os(watchOS) || os(tvOS)
        print("Warning: ComboBox is not supported on watchOS/tvOS; defaulting to empty properties")
        validatedProperties = [:]
        #else
        if let options = properties["options"] as? [String], options.isEmpty {
            print("Warning: ComboBox options is empty; initializing with empty array")
            validatedProperties["options"] = []
        }
        if validatedProperties["placeholder"] == nil {
            validatedProperties["placeholder"] = ""
        }
        if let pickerStyle = properties["pickerStyle"] as? String, !["menu", "wheel", "segmented"].contains(pickerStyle) {
            print("Warning: ComboBox pickerStyle '\(pickerStyle)' invalid; defaulting to 'menu'")
            validatedProperties["pickerStyle"] = "menu"
        }
        #endif
        
        return validatedProperties.filter { key, _ in
            if supportedProperties.contains(key) {
                return true
            } else {
                print("Warning: Property '\(key)' is not supported for ComboBox; ignoring")
                return false
            }
        }
    }
    
    static func register(in registry: ViewBuilderRegistry) {
        #if os(macOS) || os(iOS) || os(iPadOS)
        registry.register("ComboBox") { element, state, dialogGUID in
            let properties = StaticElement.getValidatedProperties(element: element, state: state)
            let placeholder = properties["placeholder"] as? String ?? ""
            let items = (properties["options"] as? [String]) ?? []
            if state.wrappedValue[element.id] == nil {
                state.wrappedValue[element.id] = ["value": ""]
            }
            
            let binding = Binding(
                get: { (state.wrappedValue[element.id] as? [String: Any])?["value"] as? String ?? "" },
                set: { newValue in
                    state.wrappedValue[element.id] = ["value": newValue]
                    if let commandID = properties["commandID"] as? String {
                        commandHandler(commandID, dialogGUID: dialogGUID, controlID: element.id, controlPartID: 0, model: UIModel.shared)
                    }
                }
            )
            
            return AnyView(
                HStack {
                    TextField(placeholder, text: binding)
                    Picker("", selection: binding) {
                        Text(placeholder).tag("")
                        ForEach(items, id: \.self) { item in
                            Text(item).tag(item)
                        }
                    }
                    .pickerStyle((properties["pickerStyle"] as? String).flatMap {
                        switch $0 {
                        case "menu": return MenuPickerStyle()
                        case "wheel": return WheelPickerStyle()
                        case "segmented": return SegmentedPickerStyle()
                        default: return MenuPickerStyle()
                        }
                    } ?? MenuPickerStyle())
                }
            )
        }
        #else
        registry.register("ComboBox") { _, _, _ in
            print("Warning: ComboBox is not supported on this platform")
            return AnyView(EmptyView())
        }
        #endif
    }
}
