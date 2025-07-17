/*
 Sample JSON for Button:
 {
   "type": "Button",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "title": "Click Me",    // Optional: String, defaults to "Button"
     "disabled": false,      // Optional: Boolean to disable the button
     "style": "plain",       // Optional: Button style (e.g., "plain", "bordered", "borderedProminent"), defaults to "plain"
     "role": "destructive"   // Optional: Button role (e.g., "destructive", "cancel")
   }
   // Note: These properties are specific to Button. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID) and additional View protocol modifiers are inherited and applied via ModifierRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct Button: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = View.validateProperties(properties)
        
        if validatedProperties["title"] == nil {
            validatedProperties["title"] = "Button"
        }
        if let disabled = validatedProperties["disabled"] as? Bool {
            validatedProperties["disabled"] = disabled
        } else if validatedProperties["disabled"] != nil {
            print("Warning: Button disabled must be a boolean; ignoring")
            validatedProperties["disabled"] = nil
        }
        if let style = validatedProperties["style"] as? String {
            if !["plain", "bordered", "borderedProminent"].contains(style) {
                print("Warning: Button style '\(style)' invalid; defaulting to 'plain'")
                validatedProperties["style"] = "plain"
            }
        } else if validatedProperties["style"] != nil {
            print("Warning: Button style must be a string; defaulting to 'plain'")
            validatedProperties["style"] = "plain"
        } else {
            validatedProperties["style"] = "plain"
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
    
    static func register(in registry: ViewBuilderRegistry) {
        registry.register("Button") { element, state, windowUUID in
            let properties = StaticElement.getValidatedProperties(element: element, state: state)
            
            let title = properties["title"] as? String ?? "Button"
            let role = properties["role"] as? String
            
            var buttonRole: ButtonRole?
            if role == "destructive" {
                buttonRole = .destructive
            } else if role == "cancel" {
                buttonRole = .cancel
            }
            
            let actionID = properties["actionID"] as? String
            
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
    
    static func registerModifiers(registry: ModifierRegistry) {
        registry.register("style") { view, properties in
            if let style = properties["style"] as? String {
                switch style {
                case "bordered": return AnyView(view.buttonStyle(.bordered))
                case "borderedProminent": return AnyView(view.buttonStyle(.borderedProminent))
                default: return AnyView(view.buttonStyle(.plain))
                }
            }
            return view
        }
    }
}
