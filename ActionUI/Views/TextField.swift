// Sources/Views/TextField.swift
/*
 Sample JSON for TextField:
 {
   "type": "TextField",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "placeholder": "Enter text", // Optional: String for placeholder, defaults to "" in buildView
     "textContentType": "username", // Optional: String for content type (e.g., "username", "password"), defaults to nil, ignored on macOS
     "actionID": "text.submit"   // Optional: String for action triggered on submit (e.g., Return key)
   }
   // Note: The TextField view triggers an action via 'actionID' when the user submits input (e.g., Return key or "Done" on iOS).
   Supported values for "textContentType": "name", "namePrefix", "givenName", "middleName", "familyName", "nameSuffix", "nickname", "jobTitle", "organizationName", "location", "fullStreetAddress", "streetAddressLine1", "streetAddressLine2", "addressCity", "addressState", "addressCityAndState", "sublocality", "countryName", "postalCode", "telephoneNumber", "emailAddress", "url", "creditCardNumber", "creditCardSecurityCode", "creditCardName", "creditCardExpiration", "creditCardType", "username", "password", "newPassword", "oneTimeCode", "shipmentTrackingNumber", "flightNumber", "dateTime", "birthdate", "birthdateDay", "birthdateMonth", "birthdateYear", "paymentMethod" (ignored on macOS). Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties). On macOS, the default text field style (likely rounded) is used.
 }
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
        
        // Validate textContentType as String or nil
        if let textContentType = validatedProperties["textContentType"], !(textContentType is String) {
            logger.log("Invalid type for textContentType: expected String, got \(type(of: textContentType)), defaulting to nil", .warning)
            validatedProperties["textContentType"] = nil
        }
        
        return validatedProperties
    }
    
    // Builds the SwiftUI.TextField view, binding its text to state and triggering actionID on submit
    // Design decision: Initializes value as "" if not set, preserving shared state (validatedProperties) from ActionUIRegistry.build
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, state, windowUUID, properties, logger in
        let placeholder = properties["placeholder"] as? String ?? ""
        
        // Initialize TextField-specific state only if not set
        var newState = (state.wrappedValue[element.id] as? [String: Any]) ?? [:]
        var viewSpecificState: [String: Any] = [:]
        if newState["value"] == nil {
            viewSpecificState["value"] = ""
        }
        if !viewSpecificState.isEmpty {
            state.wrappedValue[element.id] = newState.merging(viewSpecificState, uniquingKeysWith: { _, new in new })
        }
        
        let textBinding = Binding(
            get: { (state.wrappedValue[element.id] as? [String: Any])?["value"] as? String ?? "" },
            set: { newValue in
                var newState = (state.wrappedValue[element.id] as? [String: Any]) ?? [:]
                newState["value"] = newValue
                newState["validatedProperties"] = properties // Preserve validated properties
                state.wrappedValue[element.id] = newState
            }
        )
        
        let actionID = properties["actionID"] as? String
        
        return SwiftUI.TextField(placeholder, text: textBinding)
            .onSubmit {
                // Trigger actionID only on submit (e.g., Return key)
                if let actionID = actionID {
                    Task { @MainActor in
                        ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                    }
                }
            }
    }
    
    // Applies TextField-specific modifiers (e.g., textContentType)
    // Design decision: Relies on default macOS text field style (likely rounded) for HIG compliance; textContentType is iOS-only
    static var applyModifiers: (any SwiftUI.View, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, properties, logger in
        var modifiedView = view
        #if canImport(UIKit)
        if let textContentType = properties["textContentType"] as? String {
            modifiedView = modifiedView.textContentType(UITextContentType(rawValue: textContentType))
        }
        #endif
        return modifiedView
    }
}
