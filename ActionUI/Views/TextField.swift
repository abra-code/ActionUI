// Sources/Views/TextField.swift
/*
 Sample JSON for TextField:
 {
   "type": "TextField",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "text": "Hello",              // Optional: String initial value for the field, defaults to ""
     "placeholder": "Enter text", // Optional: String for placeholder, defaults to "" in buildView
     "textContentType": "username", // Optional: String for content type (e.g., "username", "password"), defaults to nil, ignored on macOS
     "actionID": "text.submit",   // Optional: String for action triggered on submit (e.g., Return key, inherited from View)
     "valueChangeActionID": "text.valueChanged" // Optional: String for action triggered on any value change (user or programmatic, inherited from View)
   }
 }
   // Note: The TextField view triggers an action via 'actionID' when the user submits input (e.g., Return key or "Done" on iOS). valueChangeActionID is triggered continously on each change via the binding's set closure.
   Supported values for "textContentType": "name", "namePrefix", "givenName", "middleName", "familyName", "nameSuffix", "nickname", "jobTitle", "organizationName", "location", "fullStreetAddress", "streetAddressLine1", "streetAddressLine2", "addressCity", "addressState", "addressCityAndState", "sublocality", "countryName", "postalCode", "telephoneNumber", "emailAddress", "url", "creditCardNumber", "creditCardSecurityCode", "creditCardName", "creditCardExpiration", "creditCardType", "username", "password", "newPassword", "oneTimeCode", "shipmentTrackingNumber", "flightNumber", "dateTime", "birthdate", "birthdateDay", "birthdateMonth", "birthdateYear", "paymentMethod" (ignored on macOS). Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties). On macOS, the default text field style (likely rounded) is used.

   // Note: actionID is triggered via onSubmit for user-initiated submits (e.g., Return key).  Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, disabled, etc.) are inherited and applied via ActionUIRegistry.shared.applyModifiers. On macOS, the default text field style (likely rounded) is used.
*/

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct TextField: ActionUIViewConstruction {
    static var valueType: Any.Type { String.self } // Value is the text input
    
    // Validates properties specific to TextField; baseline properties are validated by ActionUIRegistry.validateProperties
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        // Validate placeholder
        if !(properties["placeholder"] is String?), properties["placeholder"] != nil {
            logger.log("TextField placeholder must be a String; defaulting to nil", .warning)
            validatedProperties["placeholder"] = nil
        }
        
        // Validate text (initial value)
        if properties["text"] != nil && !(properties["text"] is String) {
            logger.log("TextField text must be a String; ignoring", .warning)
            validatedProperties["text"] = nil
        }

        // Validate textContentType
        if !(properties["textContentType"] is String?), properties["textContentType"] != nil {
            logger.log("TextField textContentType must be a String; defaulting to nil", .warning)
            validatedProperties["textContentType"] = nil
        }

        return validatedProperties
    }
    
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let placeholder = properties["placeholder"] as? String ?? ""
        let initialValue = Self.initialValue(model) as? String ?? ""

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
        
        let actionID = properties["actionID"] as? String
        
        return SwiftUI.TextField(placeholder, text: textBinding)
            .onSubmit {
                // Trigger actionID only on submit (e.g., Return key)
                if let actionID = actionID {
                    logger.log("Executing handler for actionID: \(actionID), viewID: \(element.id)", .debug)
                    ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                }
            }
    }
    
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, properties, logger in
        var modifiedView = view
        #if canImport(UIKit)
        if let textContentType = properties["textContentType"] as? String {
            modifiedView = modifiedView.textContentType(UITextContentType(rawValue: textContentType))
        }
        #endif
        return modifiedView
    }
    
    static var initialValue: (ViewModel) -> Any? = { model in
        if let initialValue = model.value as? String {
            return initialValue
        }
        // Fall back to "text" property if set in JSON (e.g., for pre-populated fields)
        if let text = model.validatedProperties["text"] as? String {
            return text
        }
        return ""
    }
}
