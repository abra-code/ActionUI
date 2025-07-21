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
   // Note: These properties are specific to ComboBox. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct ComboBox: ActionUIViewElement {
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
    
    static func buildElement(_ element: ActionUIElement, _ state: Binding<[Int: Any]>, _ windowUUID: String, validatedProperties: [String: Any]) -> AnyView {
        #if os(macOS) || os(iOS) || os(iPadOS)
        let items = (validatedProperties["options"] as? [String]) ?? []
        let placeholder = validatedProperties["placeholder"] as? String ?? ""
        let pickerStyle = validatedProperties["pickerStyle"] as? String ?? "menu"
        if state.wrappedValue[element.id] == nil {
            state.wrappedValue[element.id] = ["value": ""]
        }
        let binding = Binding(
            get: { (state.wrappedValue[element.id] as? [String: Any])?["value"] as? String ?? "" },
            set: { newValue in
                state.wrappedValue[element.id] = ["value": newValue]
                if let actionID = validatedProperties["actionID"] as? String {
                    ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, controlID: element.id, controlPartID: 0)
                }
            }
        )
        
        return AnyView(
            HStack {
                TextField(placeholder, text: binding)
                Picker("", selection: binding) {
                    ForEach(items, id: \.self) { item in
                        Text(item).tag(item)
                    }
                }
                .pickerStyle({
                    switch pickerStyle {
                    case "wheel": return WheelPickerStyle()
                    case "segmented": return SegmentedPickerStyle()
                    default: return MenuPickerStyle()
                    }
                }())
            }
        )
        #else
        print("Warning: ComboBox is not supported on this platform")
        return AnyView(SwiftUI.EmptyView())
        #endif
    }
    
    static func applyModifiers(_ view: AnyView, _ properties: [String: Any]) -> AnyView {
        return view // No view-specific modifiers; base modifiers handled by ActionUIRegistry
    }
}
