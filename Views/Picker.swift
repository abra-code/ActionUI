/*
 Sample JSON for Picker:
 {
   "type": "Picker",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "title": "Select Option",    // Optional: String, defaults to ""
     "options": ["Option1", "Option2"], // Required: Array of strings
     "pickerStyle": "menu"       // Optional: "menu", "wheel", "segmented"
   }
   // Note: These properties are specific to Picker. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID) and additional View protocol modifiers are inherited and applied via ModifierRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct Picker: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = View.validateProperties(properties)
        
        if let options = validatedProperties["options"] as? [String], options.isEmpty {
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
        
        return validatedProperties
    }
    
    static func register(in registry: ViewBuilderRegistry) {
        registry.register("Picker") { element, state, windowUUID in
            let properties = StaticElement.getValidatedProperties(element: element, state: state)
            let title = properties["title"] as? String ?? ""
            let items = (properties["options"] as? [String]) ?? []
            if state.wrappedValue[element.id] == nil {
                state.wrappedValue[element.id] = ["value": items.first ?? ""]
            }
            var picker = SwiftUI.Picker(title, selection: Binding(
                get: { (state.wrappedValue[element.id] as? [String: Any])?["value"] as? String ?? items.first ?? "" },
                set: { newValue in
                    state.wrappedValue[element.id] = ["value": newValue]
                    if let actionID = properties["actionID"] as? String {
                        actionHandler(actionID, windowUUID: windowUUID, controlID: element.id, controlPartID: 0, model: ActionUIModel.shared)
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
