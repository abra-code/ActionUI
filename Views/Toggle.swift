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

struct Toggle: ActionUIViewConstruction {
    static var valueType: Any.Type? { Bool.self } // Value is the toggle's on/off state
    
    static var validateProperties: (([String: Any]) -> [String: Any])? = { properties in
        var validatedProperties = properties
        
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
    
    // Builds the Toggle view, binding isOn to state
    // Design decision: Initializes value as false if not set, preserving shared state (validatedProperties) from ActionUIRegistry.build
    static var buildElement: ((ActionUIElement, Binding<[Int: Any]>, String, [String: Any]) -> AnyView)? = { element, state, windowUUID, validatedProperties in
        // Initialize Toggle-specific state only if not already set
        // Design decision: Merges value (Bool) conditionally to avoid overwriting existing properties
        var newState = (state.wrappedValue[element.id] as? [String: Any]) ?? [:]
        var viewSpecificState: [String: Any] = [:]
        if newState["value"] == nil {
            viewSpecificState["value"] = false
        }
        if !viewSpecificState.isEmpty {
            state.wrappedValue[element.id] = newState.merging(viewSpecificState, uniquingKeysWith: { _, new in new })
        }
        
        let toggleBinding = Binding(
            get: { (state.wrappedValue[element.id] as? [String: Any])?["value"] as? Bool ?? false },
            set: { newValue in
                var newState = (state.wrappedValue[element.id] as? [String: Any]) ?? [:]
                newState["value"] = newValue
                state.wrappedValue[element.id] = newState
                if let actionID = validatedProperties["actionID"] as? String {
                    ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                }
            }
        )
        
        return AnyView(
            SwiftUI.Toggle("", isOn: toggleBinding)
        )
    }
    
    static var applyModifiers: ((AnyView, [String: Any]) -> AnyView)? = { view, properties in
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
