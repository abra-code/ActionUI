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

struct Button: ActionUIViewElement {
    // Validates properties specific to Button; baseline properties are validated by ActionUIRegistry.getValidatedProperties
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
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
            
    static func buildElement(_ element: ActionUIElement, _ state: Binding<[Int: Any]>, _ windowUUID: String, validatedProperties: [String: Any]) -> AnyView {
        let title = validatedProperties["title"] as? String ?? "Button"
        let role = validatedProperties["role"] as? String
        
        var buttonRole: ButtonRole?
        if role == "destructive" {
            buttonRole = .destructive
        } else if role == "cancel" {
            buttonRole = .cancel
        }
        
        let actionID = validatedProperties["actionID"] as? String
        
        return AnyView(
            SwiftUI.Button(
                role: buttonRole,
                action: {
                    if let actionID = actionID {
                        // Use singleton ActionUIModel.shared for action handling
                        ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                    }
                },
                label: {
                    Text(title)
                }
            )
        )
    }
        
    static func applyModifiers(_ view: AnyView, _ properties: [String: Any]) -> AnyView {
        var modifiedView = view
        
        if let buttonStyle = properties["buttonStyle"] as? String {
            switch buttonStyle {
            case "bordered": modifiedView = AnyView(modifiedView.buttonStyle(.bordered))
            case "borderedProminent": modifiedView = AnyView(modifiedView.buttonStyle(.borderedProminent))
            default: modifiedView = AnyView(modifiedView.buttonStyle(.plain))
            }
        }
        
        return modifiedView
    }
}
