/*
 Sample JSON for SecureField:
 {
   "type": "SecureField",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "placeholder": "Enter password", // Optional: String for placeholder, defaults to ""
     "textContentType": "password",  // Optional: String for content type, must be one of: "password", "newPassword", "oneTimeCode"; defaults to nil, ignored on macOS
     "actionID": "secure.submit"     // Optional: String for action triggered on submit (e.g., Return key)
   }
   // Note: The SecureField view triggers an action via 'actionID' when the user submits input (e.g., Return key or "Done" on iOS). Supported values for "textContentType": "password", "newPassword", "oneTimeCode" (ignored on macOS). Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties). On macOS, the default text field style (likely rounded) is used.
 }
*/

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct SecureField: ActionUIViewConstruction {
    // Design decision: Defines valueType as String to reflect secure text input for type-safe string parsing in ActionUIModel
    static var valueType: Any.Type { String.self }
    
    // Validates properties specific to SecureField; baseline properties are validated by ActionUIRegistry.getValidatedProperties
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        // Default to empty string if placeholder is not provided
        if validatedProperties["placeholder"] == nil {
            validatedProperties["placeholder"] = ""
        }
        // Validate textContentType, allow only secure types
        if let textContentType = validatedProperties["textContentType"] as? String,
           ["password", "newPassword", "oneTimeCode"].contains(textContentType) {
            validatedProperties["textContentType"] = textContentType
        } else if validatedProperties["textContentType"] != nil {
            logger.log("SecureField textContentType must be 'password', 'newPassword', or 'oneTimeCode'; defaulting to nil", .warning)
            validatedProperties["textContentType"] = nil
        }
        
        return validatedProperties
    }
    
    // Builds the SwiftUI.SecureField view, binding its text to state and triggering actionID on submit
    // Design decision: Initializes value as "" if not set, preserving shared state (validatedProperties)
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, state, windowUUID, properties, logger in
        let placeholder = properties["placeholder"] as? String ?? ""
        let actionID = properties["actionID"] as? String
        
        // Initialize value if not set
        var newState = (state.wrappedValue[element.id] as? [String: Any]) ?? [:]
        if newState["value"] == nil {
            newState["value"] = ""
            state.wrappedValue[element.id] = newState
        }
        
        let textBinding = Binding(
            get: { (state.wrappedValue[element.id] as? [String: Any])?["value"] as? String ?? "" },
            set: { newValue in
                var newState = (state.wrappedValue[element.id] as? [String: Any]) ?? [:]
                newState["value"] = newValue
                state.wrappedValue[element.id] = newState
            }
        )
        
        return SwiftUI.SecureField(placeholder, text: textBinding)
            .onSubmit {
                // Trigger actionID only on submit (e.g., Return key or "Done" on iOS)
                if let actionID = actionID {
                    Task { @MainActor in
                        ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                    }
                }
            }
    }
    
    // Applies modifiers specific to SecureField, such as textContentType
    // Design decision: Relies on default macOS text field style (likely rounded) for HIG compliance; textContentType is iOS-only
    static var applyModifiers: (any SwiftUI.View, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, properties, logger in
        var modifiedView = view
        #if canImport(UIKit)
        if let textContentType = properties["textContentType"] as? String {
            switch textContentType {
            case "password":
                modifiedView = modifiedView.textContentType(.password)
            case "newPassword":
                modifiedView = modifiedView.textContentType(.newPassword)
            case "oneTimeCode":
                modifiedView = modifiedView.textContentType(.oneTimeCode)
            default:
                break // Already validated to nil in validateProperties
            }
        }
        #endif
        return modifiedView
    }
}
