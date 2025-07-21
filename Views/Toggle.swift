/*
 Sample JSON for Toggle:
 {
   "type": "Toggle",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "label": "Enable Feature", // Optional: String, defaults to "Toggle"
     "style": "switch",        // Optional: "switch", "checkbox", "button"; defaults to "switch"
   }
   // Note: These properties are specific to Toggle. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct Toggle: ActionUIViewElement {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = View.validateProperties(properties)
        
        if let style = validatedProperties["style"] as? String, !["switch", "checkbox", "button"].contains(style) {
            print("Warning: Toggle style '\(style)' invalid; defaulting to switch")
            validatedProperties["style"] = "switch"
        }
        if validatedProperties["style"] == nil {
            validatedProperties["style"] = "switch"
        }
        if validatedProperties["label"] == nil {
            validatedProperties["label"] = "Toggle"
        }
        
        return validatedProperties
    }
    
    static func buildElement(_ element: ActionUIElement, _ state: Binding<[Int: Any]>, _ windowUUID: String, validatedProperties: [String: Any]) -> AnyView {
        if state.wrappedValue[element.id] == nil {
            state.wrappedValue[element.id] = ["value": false]
        }
        let toggleBinding = Binding(
            get: { (state.wrappedValue[element.id] as? [String: Any])?["value"] as? Bool ?? false },
            set: { newValue in
                state.wrappedValue[element.id] = ["value": newValue]
                if let actionID = validatedProperties["actionID"] as? String {
                    ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, controlPartID: 0)
                }
            }
        )
        
        return AnyView(
            SwiftUI.Toggle("", isOn: toggleBinding)
        )
    }
    
    static func applyModifiers(_ view: AnyView, _ properties: [String: Any]) -> AnyView {
        var modifiedView = view
        if let label = properties["label"] as? String {
            modifiedView = AnyView(modifiedView.toggleLabel(Text(label)))
        }
        if let style = properties["style"] as? String {
            let toggleStyle = {
                switch style {
                case "checkbox": return ToggleStyle.checkbox
                case "button": return ToggleStyle.button
                default: return ToggleStyle.switch
                }
            }()
            modifiedView = AnyView(modifiedView.toggleStyle(toggleStyle))
        }
        return modifiedView
    }
}
