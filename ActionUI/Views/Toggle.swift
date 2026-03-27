/*
 Sample JSON for Toggle:
 {
   "type": "Toggle",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "isOn": true,              // Optional: Boolean initial state, defaults to false
     "title": "Enable Feature", // Optional: String, defaults to "Toggle"
     "style": "switch",        // Optional: "switch" (iOS/macOS/visionOS), "checkbox" (macOS only), "button" (iOS/macOS/visionOS); defaults to "switch"
     "actionID": "toggle.changed", // Optional: String for action triggered on value change
   }
   // Note: These properties are specific to Toggle. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct Toggle: ActionUIViewConstruction {
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }

    static var valueType: Any.Type = Bool.self // Value is the toggle's on/off state
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        // Validate isOn (initial value)
        if properties["isOn"] != nil && !(properties["isOn"] is Bool) {
            logger.log("Toggle isOn must be a Bool; ignoring", .warning)
            validatedProperties["isOn"] = nil
        }

        // Validate style based on platform
        #if os(macOS)
        let validStyles = ["switch", "button", "checkbox"]
        #else
        let validStyles = ["switch", "button"]
        #endif
        if let style = validatedProperties["style"] as? String, !validStyles.contains(style) {
            logger.log("Toggle style '\(style)' invalid on \(ProcessInfo.processInfo.operatingSystemVersionString); falling back to default", .warning)
            validatedProperties["style"] = nil
        }

        return validatedProperties
    }
    
    // Builds the Toggle view, binding isOn to state
    // Design decision: Initializes value as false if not set, preserving shared state (validatedProperties) from ActionUIRegistry.build
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        
        let initialValue = Self.initialValue(model) as? Bool ?? false
        
        let toggleBinding = Binding(
            get: { model.value as? Bool ?? initialValue },
            set: { newValue in
                guard model.value as? Bool != newValue else {
                    return
                }
                // DispatchQueue.main.async avoids "publishing changes from within view updates" warning.
                // actionID is fired here in the binding setter (not via .onChange) so it only triggers
                // on user interaction. .onChange would also fire on programmatic value changes,
                // which can cause cascading actions and unexpected behavior.
                DispatchQueue.main.async {
                    model.value = newValue
                    if let actionID = properties["actionID"] as? String {
                        ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0, context: newValue)
                    }
                }
            }
        )

        let title = properties["title"] as? String ?? "Toggle"

        return SwiftUI.Toggle(title, isOn: toggleBinding)
    }
    
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, properties, logger in
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
    
    static var initialValue: (ViewModel) -> Any? = { model in
        if let initialValue = model.value as? Bool {
            return initialValue
        }
        if let isOn = model.validatedProperties["isOn"] as? Bool {
            return isOn
        }
        return false
    }
}
