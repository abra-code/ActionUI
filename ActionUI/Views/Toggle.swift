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
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        // Validate style based on platform
        #if os(macOS)
        let validStyles = ["switch", "button", "checkbox"]
        #else
        let validStyles = ["switch", "button"]
        #endif
        if let style = validatedProperties["style"] as? String, !validStyles.contains(style) {
            logger.log("Toggle style '\(style)' invalid on \(ProcessInfo.processInfo.operatingSystemVersionString); defaulting to 'switch'", .warning)
            validatedProperties["style"] = "switch"
        }
        if validatedProperties["style"] == nil {
            validatedProperties["style"] = "switch"
        }
        
        return validatedProperties
    }
    
    // Builds the Toggle view, binding isOn to state
    // Design decision: Initializes value as false if not set, preserving shared state (validatedProperties) from ActionUIRegistry.build
    static var buildView: (any ActionUIElement, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        
        // Initialize Toggle-specific state only if not set
        if model.value == nil {
            model.value = false
        }
        
        let toggleBinding = Binding(
            get: { model.value as? Bool ?? false },
            set: { newValue in
                model.value = newValue
                if let valueChangeActionID = properties["valueChangeActionID"] as? String {
                    Task { @MainActor in
                    	ActionUIModel.shared.actionHandler(valueChangeActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                    }
                }
            }
        )
        
        let title = properties["title"] as? String ?? "Toggle"
        
        return SwiftUI.Toggle(title, isOn: toggleBinding)
    }
    
    static var applyModifiers: (any SwiftUI.View, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, properties, logger in
        var modifiedView = view
        if let style = properties["style"] as? String {
            switch style {
            case "checkbox":
                #if os(macOS)
                modifiedView = modifiedView.toggleStyle(CheckboxToggleStyle())
                #else
                logger.log("CheckboxToggleStyle unavailable on iOS/visionOS/MacCatalyst; using SwitchToggleStyle", .warning)
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
