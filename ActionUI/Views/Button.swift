/*
 Sample JSON for Button:
 {
   "type": "Button",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "title": "Click Me",    // Optional: String, defaults to "Button"
     "disabled": false,      // Optional: Boolean to disable the button (handled by View)
     "buttonStyle": "plain", // Optional: Button style (e.g., "plain", "bordered", "borderedProminent"), defaults to "plain"
     "role": "destructive"   // Optional: Button role (e.g., "destructive", "cancel")
   }
   // Note: These properties are specific to Button. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct Button: ActionUIViewConstruction {
    // Button has no stateful value, only triggers actions
    
    // Validates properties specific to Button; baseline properties are validated by ActionUIRegistry.getValidatedProperties
    static var validateProperties: ([String: Any]) -> [String: Any] = { properties in
        var validatedProperties = properties
        
        if validatedProperties["title"] == nil {
            validatedProperties["title"] = "Button"
        }
        if let buttonStyle = validatedProperties["buttonStyle"] as? String {
            if !["plain", "bordered", "borderedProminent"].contains(buttonStyle) {
                print("Warning: Button buttonStyle '\(buttonStyle)' invalid; defaulting to 'plain'")
                validatedProperties["buttonStyle"] = "plain"
            }
        } else if validatedProperties["buttonStyle"] != nil {
            print("Warning: Button buttonStyle must be a string; defaulting to 'plain'")
            validatedProperties["buttonStyle"] = "plain"
        } else {
            validatedProperties["buttonStyle"] = "plain"
        }
        if let role = validatedProperties["role"] as? String {
            if !["destructive", "cancel"].contains(role) {
                print("Warning: Button role '\(role)' invalid; ignoring")
                validatedProperties["role"] = nil
            }
        } else if validatedProperties["role"] != nil {
            print("Warning: Button role must be a string; ignoring")
            validatedProperties["role"] = nil
        }
        
        return validatedProperties
    }
    
    // Builds the Button view, relying on ActionUIRegistry.build for state initialization
    // Design decision: No value state is initialized, as Button has no stateful value (valueType is Void)
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any]) -> any SwiftUI.View = { element, state, windowUUID, properties in
        let title = properties["title"] as? String ?? "Button"
        let role = properties["role"] as? String
        let actionID = properties["actionID"] as? String
        
        var buttonRole: ButtonRole?
        if role == "destructive" {
            buttonRole = .destructive
        } else if role == "cancel" {
            buttonRole = .cancel
        }
        
        return SwiftUI.Button(
            role: buttonRole,
            action: {
                if let actionID = actionID {
                    ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                }
            },
            label: {
                SwiftUI.Text(title)
            }
        )
    }
    
    static var applyModifiers: (any SwiftUI.View, [String: Any]) -> any SwiftUI.View = { view, properties in
        if let buttonStyle = properties["buttonStyle"] as? String {
            if var buttonView = view as? SwiftUI.Button<SwiftUI.Text> {
                var modifiedView: any SwiftUI.View
                switch buttonStyle {
                case "bordered":
                    modifiedView = buttonView.buttonStyle(.bordered)
                case "borderedProminent":
                    modifiedView = buttonView.buttonStyle(.borderedProminent)
                default:
                    modifiedView = buttonView.buttonStyle(.plain)
                }
                return modifiedView
            }
        }
        return view
    }
}
