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
   // Note: These properties are specific to Picker. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct Picker: ActionUIViewConstruction {
    // Design decision: Defines valueType as String to reflect selected option for type-safe string parsing in ActionUIModel
    static var valueType: Any.Type? { String.self }
    
    static var validateProperties: (([String: Any]) -> [String: Any])? = { properties in
        var validatedProperties = properties
        
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
    
    static var buildElement: ((ActionUIElement, Binding<[Int: Any]>, String, [String: Any]) -> AnyView)? = { element, state, windowUUID, validatedProperties in
        let items = (validatedProperties["options"] as? [String]) ?? []
        let initialValue = items.first ?? ""
        if state.wrappedValue[element.id] == nil {
            state.wrappedValue[element.id] = ["value": initialValue]
        }
        let selectionBinding = Binding(
            get: { (state.wrappedValue[element.id] as? [String: Any])?["value"] as? String ?? initialValue },
            set: { newValue in
                state.wrappedValue[element.id] = ["value": newValue]
                if let actionID = validatedProperties["actionID"] as? String {
                   ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                }
            }
        )
        
        return AnyView(
            SwiftUI.Picker("", selection: selectionBinding) {
                ForEach(items, id: \.self) { item in
                    SwiftUI.Text(item).tag(item)
                }
            }
        )
    }
    
    static var applyModifiers: ((AnyView, [String: Any]) -> AnyView)? = { view, properties in
        var modifiedView = view
        if let title = properties["title"] as? String {
            modifiedView = AnyView(modifiedView.pickerLabel(Text(title)))
        }
        if let style = properties["pickerStyle"] as? String {
            switch style {
            case "menu": modifiedView = AnyView(modifiedView.pickerStyle(.menu))
            case "wheel": modifiedView = AnyView(modifiedView.pickerStyle(.wheel))
            case "segmented": modifiedView = AnyView(modifiedView.pickerStyle(.segmented))
            default: break
            }
        }
        return modifiedView
    }
}
