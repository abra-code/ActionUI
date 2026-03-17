/*
 Sample JSON for SecureField:
 {
   "type": "SecureField",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "title": "Password",            // Optional: String label for the field, defaults to "" (shown in Form/LabeledContent contexts)
     "text": "secret",               // Optional: String initial value, defaults to ""
     "prompt": "Enter password",     // Optional: String prompt (placeholder) shown inside the field when empty, defaults to nil
     "textContentType": "password",  // Optional: String for content type, must be one of: "password", "newPassword", "oneTimeCode"; defaults to nil, ignored on macOS
     "actionID": "secure.submit"     // Optional: String for action triggered on submit (e.g., Return key)
                                     //   On macOS, actionID is also triggered when the field loses focus (tab away, click elsewhere),
                                     //   matching classic AppKit text field behavior where ending editing commits the value.
   }
   // Note: The SecureField view triggers an action via 'actionID' when the user submits input (e.g., Return key or "Done" on iOS). On macOS, actionID is also triggered on focus loss (tab, click away) to match classic AppKit behavior. Supported values for "textContentType": "password", "newPassword", "oneTimeCode" (ignored on macOS). Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties). On macOS, the default text field style (likely rounded) is used.
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

        // Validate text (initial value)
        if properties["text"] != nil && !(properties["text"] is String) {
            logger.log("SecureField text must be a String; ignoring", .warning)
            validatedProperties["text"] = nil
        }

        // Validate title
        if properties["title"] != nil && !(properties["title"] is String) {
            logger.log("SecureField title must be a String; defaulting to empty string", .warning)
            validatedProperties["title"] = nil
        }

        // Validate prompt
        if !(properties["prompt"] is String?), properties["prompt"] != nil {
            logger.log("SecureField prompt must be a String; defaulting to nil", .warning)
            validatedProperties["prompt"] = nil
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
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let title = properties["title"] as? String ?? ""
        let prompt = (properties["prompt"] as? String).map { SwiftUI.Text($0) }
        let actionID = properties["actionID"] as? String
        let initialValue = Self.initialValue(model) as? String ?? ""

        let onSubmit = {
            if let actionID = actionID {
                ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
            }
        }

        let textBinding = Binding(
            get: { model.value as? String ?? initialValue },
            set: { newValue in
                guard model.value as? String != newValue else {
                    return
                }
                // Use DispatchQueue.main.async to guarantee deferred execution and avoid
                // "publishing changes from within view updates" warning
                DispatchQueue.main.async {
                    model.value = newValue
                    if let valueChangeActionID = properties["valueChangeActionID"] as? String {
                        ActionUIModel.shared.actionHandler(valueChangeActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                    }
                }
            }
        )

        return TextFieldFocusContainer(onSubmit: onSubmit) {
            SwiftUI.SecureField(title, text: textBinding, prompt: prompt)
                .onSubmit(onSubmit)
        }
    }

    // Applies modifiers specific to SecureField, such as textContentType
    // Design decision: Relies on default macOS text field style (likely rounded) for HIG compliance; textContentType is iOS-only
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, properties, logger in
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

    static var initialValue: (ViewModel) -> Any? = { model in
        if let initialValue = model.value as? String {
            return initialValue
        }
        if let text = model.validatedProperties["text"] as? String {
            return text
        }
        return ""
    }
}
