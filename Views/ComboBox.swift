/*
 Sample JSON for ComboBox (macOS, iOS, iPadOS only):
 {
   "type": "ComboBox",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "placeholder": "Select an option", // Optional: String, defaults to ""
     "options": ["Option1", "Option2"], // Optional: Array of strings, defaults to []
     "pickerStyle": "menu"            // Optional: String ("menu", "wheel", "segmented") for Picker style
   }
   // Note: These properties are specific to ComboBox. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ModifierRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct ComboBox: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = View.validateProperties(properties)
        
        #if os(watchOS) || os(tvOS)
        print("Warning: ComboBox is not supported on watchOS/tvOS; defaulting to empty properties")
        validatedProperties = [:]
        #else
        if let options = validatedProperties["options"] as? [String], options.isEmpty {
            print("Warning: ComboBox options is empty; initializing with empty array")
            validatedProperties["options"] = []
        }
        if validatedProperties["placeholder"] == nil {
            validatedProperties["placeholder"] = ""
        }
        if let pickerStyle = validatedProperties["pickerStyle"] as? String, !["menu", "wheel", "segmented"].contains(pickerStyle) {
            print("Warning: ComboBox pickerStyle '\(pickerStyle)' invalid; defaulting to 'menu'")
            validatedProperties["pickerStyle"] = "menu"
        }
        #endif
        
        return validatedProperties
    }
    
    static func register(in registry: ViewBuilderRegistry) {
        #if os(macOS) || os(iOS) || os(iPadOS)
        registry.register("ComboBox") { element, state, windowUUID in
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
                    if let actionID = properties["actionID"] as? String {
                        actionHandler(actionID, windowUUID: windowUUID, controlID: element.id, controlPartID: 0, model: ActionUIModel.shared)
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
    
    static func registerModifiers(registry: ModifierRegistry) {
        // No specific modifiers beyond base View properties
    }
}
