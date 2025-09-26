// Sources/Views/Button.swift
/*
 Sample JSON for Button:
 {
   "type": "Button",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "title": "Click Me",    // Optional: String, defaults to "Button" in buildView
     "disabled": false,      // Optional: Boolean to disable the button (handled by View)
     "buttonStyle": "plain", // Optional: Button style (e.g., "plain", "bordered", "borderedProminent"), defaults to "plain" in applyModifiers
     "role": "destructive"   // Optional: Button role (e.g., "destructive", "cancel")
   }
   // Note: These properties are specific to Button. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct Button: ActionUIViewConstruction {
    // Button has no stateful value, only triggers actions
    static var valueType: Any.Type { Void.self }
    
    // Validates properties specific to Button; baseline properties are validated by ActionUIRegistry.getValidatedProperties
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        // Validate title
        if let title = validatedProperties["title"], !(title is String) {
            logger.log("Invalid type for Button title: expected String, got \(type(of: title)), ignoring", .warning)
            validatedProperties["title"] = nil
        }
        
        // Validate buttonStyle
        if let buttonStyle = validatedProperties["buttonStyle"] as? String {
            if !["plain", "bordered", "borderedProminent"].contains(buttonStyle) {
                logger.log("Invalid Button buttonStyle '\(buttonStyle)', ignoring", .warning)
                validatedProperties["buttonStyle"] = nil
            }
        } else if validatedProperties["buttonStyle"] != nil {
            logger.log("Invalid type for Button buttonStyle: expected String, got \(type(of: validatedProperties["buttonStyle"]!)), ignoring", .warning)
            validatedProperties["buttonStyle"] = nil
        }
        
        // Validate role
        if let role = validatedProperties["role"] as? String {
            if !["destructive", "cancel"].contains(role) {
                logger.log("Invalid Button role '\(role)', ignoring", .warning)
                validatedProperties["role"] = nil
            }
        } else if validatedProperties["role"] != nil {
            logger.log("Invalid type for Button role: expected String, got \(type(of: validatedProperties["role"]!)), ignoring", .warning)
            validatedProperties["role"] = nil
        }
        
        return validatedProperties
    }
    
    // Builds the Button view, relying on ActionUIRegistry.build for state initialization
    // Design decision: No value state is initialized, as Button has no stateful value (valueType is Void)
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
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
    
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, properties, logger in
        if var buttonView = view as? SwiftUI.Button<SwiftUI.Text> {
            let buttonStyle = properties["buttonStyle"] as? String ?? "plain"
            switch buttonStyle {
            case "bordered":
                return buttonView.buttonStyle(.bordered)
            case "borderedProminent":
                return buttonView.buttonStyle(.borderedProminent)
            default:
                return buttonView.buttonStyle(.plain)
            }
        } else {
            logger.log("Invalid view type.Expected SwiftUI.Button<SwiftUI.Text>", .error)
        }
        return view
    }
}
