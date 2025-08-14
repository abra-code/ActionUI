/*
 Sample JSON for Toggle:
 {
   "type": "Toggle",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "title": "Enable Feature", // Optional: String, defaults to "Toggle"
     "style": "switch",        // Optional: "switch" (iOS/macOS/visionOS), "checkbox" (macOS only), "button" (iOS/macOS/visionOS); defaults to "switch"
   }
   // Note: These properties are specific to Toggle. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct Toggle: ActionUIViewConstruction {
    static var valueType: Any.Type { Bool.self } // Value is the toggle's on/off state
    
    static var validateProperties: ([String: Any]) -> [String: Any] = { properties in
        var validatedProperties = properties
        
        // Validate style based on platform
        #if os(macOS)
        let validStyles = ["switch", "button", "checkbox"]
        #else
        let validStyles = ["switch", "button"]
        #endif
        if let style = validatedProperties["style"] as? String, !validStyles.contains(style) {
            print("Warning: Toggle style '\(style)' invalid on \(ProcessInfo.processInfo.operatingSystemVersionString); defaulting to 'switch'")
            validatedProperties["style"] = "switch"
        }
        if validatedProperties["style"] == nil {
            validatedProperties["style"] = "switch"
        }
        
        return validatedProperties
    }
    
    // Builds the Toggle view, binding isOn to state
    // Design decision: Initializes value as false if not set, preserving shared state (validatedProperties) from ActionUIRegistry.build
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any]) -> any SwiftUI.View = { element, state, windowUUID, properties in
        // Initialize Toggle-specific state only if not set
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
                newState["validatedProperties"] = properties // Include validated properties per ActionUI guidelines
                state.wrappedValue[element.id] = newState
                if let actionID = properties["actionID"] as? String {
                    Task { @MainActor in
                        ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                    }
                }
            }
        )
        
        let title = properties["title"] as? String ?? "Toggle"
        
        return SwiftUI.Toggle(title, isOn: toggleBinding)
    }
    
    static var applyModifiers: (any SwiftUI.View, [String: Any]) -> any SwiftUI.View = { view, properties in
        var modifiedView = view
        if let style = properties["style"] as? String {
            switch style {
            case "checkbox":
                #if os(macOS)
                modifiedView = modifiedView.toggleStyle(CheckboxToggleStyle())
                #else
                print("Warning: CheckboxToggleStyle unavailable on iOS/visionOS/MacCatalyst; using SwitchToggleStyle")
                modifiedView = modifiedView.toggleStyle(SwitchToggleStyle())
                #endif
            case "button":
                modifiedView = modifiedView.toggleStyle(ButtonToggleStyle())
            default:
                modifiedView = modifiedView.toggleStyle(SwitchToggleStyle())
            }
        }
        return modifiedView
    }
}
