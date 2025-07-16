/*
 Sample JSON for Button:
 {
   "type": "Button",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "title": "Click Me",    // Optional: String, defaults to "Button"
     "disabled": false,      // Optional: Boolean to disable the button
     "actionID": "button.click", // Optional: String for action identifier
     "padding": 10.0,        // Optional: CGFloat for padding
     "font": "body",         // Optional: SwiftUI font role (e.g., "largeTitle", "title", "title2", "title3", "headline", "subheadline", "body", "callout", "caption", "caption2", "footnote") or custom font name (e.g., "Helvetica", "Times New Roman"), defaults to "body"
     "foregroundColor": "blue", // Optional: SwiftUI color (e.g., "red", "blue", "green", "yellow", "purple", "pink", "mint", "teal", "cyan", "indigo", "brown", "gray", "black", "white", "primary", "secondary") or hex RGBA (e.g., "#FF0000" for red, "#FF0000FF" for red with full opacity), defaults to primary
     "hidden": false,        // Optional: Boolean to hide the view
     "style": "plain",       // Optional: Button style (e.g., "plain", "bordered", "borderedProminent"), defaults to "plain"
     "role": "destructive"   // Optional: Button role (e.g., "destructive", "cancel")
   }
 }
*/

import SwiftUI

struct Button: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        let supportedProperties = ["title", "disabled", "actionID", "padding", "font", "foregroundColor", "hidden", "style", "role"]
        var validatedProperties = properties
        
        if validatedProperties["title"] == nil {
            validatedProperties["title"] = "Button"
        }
        if let disabled = validatedProperties["disabled"] as? Bool {
            validatedProperties["disabled"] = disabled
        } else if validatedProperties["disabled"] != nil {
            print("Warning: Button disabled must be a boolean; ignoring")
            validatedProperties["disabled"] = nil
        }
        if let style = properties["style"] as? String {
            if !["plain", "bordered", "borderedProminent"].contains(style) {
                print("Warning: Button style '\(style)' invalid; defaulting to 'plain'")
                validatedProperties["style"] = "plain"
            }
        } else if properties["style"] != nil {
            print("Warning: Button style must be a string; defaulting to 'plain'")
            validatedProperties["style"] = "plain"
        } else {
            validatedProperties["style"] = "plain"
        }
        if let role = properties["role"] as? String {
            if !["destructive", "cancel"].contains(role) {
                print("Warning: Button role '\(role)' invalid; ignoring")
                validatedProperties["role"] = nil
            }
        } else if properties["role"] != nil {
            print("Warning: Button role must be a string; ignoring")
            validatedProperties["role"] = nil
        }
        
        return validatedProperties.filter { key, _ in
            if supportedProperties.contains(key) {
                return true
            } else {
                print("Warning: Property '\(key)' is not supported for Button; ignoring")
                return false
            }
        }
    }
    
    static func register(in registry: ViewBuilderRegistry) {
        registry.register("Button") { element, state, windowUUID in
            let validatedProperties = StaticElement.getValidatedProperties(element: element, state: state)
            
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
                            actionHandler(actionID, windowUUID: windowUUID, controlID: element.id, controlPartID: 0, model: ActionUIModel.shared)
                        }
                    },
                    label: {
                        Text(title)
                    }
                )
            )
        }
    }
}