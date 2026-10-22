// Core/Elements/TextField.swift
/*
 Sample JSON for TextField:
 {
   "type": "TextField",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "title": "Username",            // Optional: String label for the field, defaults to "" (shown in Form/LabeledContent contexts)
     "text": "Hello",                // Optional: String initial value for the field, defaults to ""
     "prompt": "Enter text",         // Optional: String prompt (placeholder) shown inside the field when empty, defaults to nil
     "axis": "vertical",            // Optional: "vertical" for multi-line text field that grows with content. Defaults to horizontal (single-line).
                                     //   Use with lineLimit to control height. Preferred over TextEditor when placeholder text is needed.
     "lineLimit": 5,                 // Optional: Int (exact) or {"min": N} or {"min": N, "max": N} for range. Controls visible line count.
                                     //   Especially useful with axis "vertical" (e.g., lineLimit {"min": 3} for minimum 3 lines).
     "format": "decimal",            // Optional: "integer", "decimal", "percent", "currency". When set, uses SwiftUI value:format: constructor. Value is stored as String internally
     "currencyCode": "USD",          // Optional: ISO 4217 currency code, defaults to "USD". Only used with format "currency"
     "fractionLength": {"min": 0, "max": 2}, // Optional: Int (exact) or {"min": N, "max": N} (range). Controls decimal places for decimal/percent/currency
     "value": 9.99,                  // Optional: Initial numeric value (Int, Double, or String). Used instead of "text" when format is set. Defaults to 0
     "textContentType": "username",  // Optional: String for content type (e.g., "username", "password"), defaults to nil, ignored on macOS
     "actionID": "text.submit",      // Optional: String for action triggered on submit (e.g., Return key, inherited from View)
                                     //   On macOS, actionID is also triggered when the field loses focus (tab away, click elsewhere),
                                     //   matching classic AppKit text field behavior where ending editing commits the value.
                                     //   Without an actionID the field has no submit handler, so on macOS Return falls through
                                     //   to the window's default button (a Button with keyboardShortcut return and modifiers []).
     "valueChangeActionID": "text.valueChanged" // Optional: String for action triggered on any value change (user or programmatic, inherited from View)
   }
 }

 Multi-line TextField example (preferred over TextEditor when placeholder text is needed):
 {
   "type": "TextField",
   "id": 3,
   "properties": {
     "prompt": "Enter description...",
     "axis": "vertical",
     "lineLimit": {"min": 3, "max": 10}
   }
 }

 Formatted numeric TextField example (value stored as String, converted internally):
 {
   "type": "TextField",
   "id": 2,
   "properties": {
     "title": "Price",
     "format": "currency",          // Optional: "integer", "decimal", "percent", "currency". When set, uses SwiftUI value:format: constructor
     "currencyCode": "USD",         // Optional: ISO 4217 currency code, defaults to "USD". Only used with format "currency"
     "fractionLength": {"min": 0, "max": 2}, // Optional: Int (exact) or {"min": N, "max": N} (range). Controls decimal places for decimal/percent/currency
     "value": 9.99                  // Optional: Initial numeric value (Int, Double, or String). Used instead of "text" when format is set. Defaults to 0
   }
 }

   // Note: The TextField view triggers an action via 'actionID' when the user submits input (e.g., Return key or "Done" on iOS). On macOS, actionID is also triggered on focus loss (tab, click away) to match classic AppKit behavior. valueChangeActionID is triggered continously on each change via the binding's set closure.
   Supported values for "textContentType": "name", "namePrefix", "givenName", "middleName", "familyName", "nameSuffix", "nickname", "jobTitle", "organizationName", "location", "fullStreetAddress", "streetAddressLine1", "streetAddressLine2", "addressCity", "addressState", "addressCityAndState", "sublocality", "countryName", "postalCode", "telephoneNumber", "emailAddress", "url", "creditCardNumber", "creditCardSecurityCode", "creditCardName", "creditCardExpiration", "creditCardType", "username", "password", "newPassword", "oneTimeCode", "shipmentTrackingNumber", "flightNumber", "dateTime", "birthdate", "birthdateDay", "birthdateMonth", "birthdateYear", "paymentMethod" (ignored on macOS). Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties). On macOS, the default text field style (likely rounded) is used.

   // Note: actionID is triggered via onSubmit for user-initiated submits (e.g., Return key).  Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, disabled, etc.) are inherited and applied via ActionUIRegistry.shared.applyModifiers. On macOS, the default text field style (likely rounded) is used.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension TextField {
    /// TextField's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        enum Axis: String, Sendable, CaseIterable {
            case horizontal, vertical
        }

        enum LineLimit: Equatable, Sendable {
            case exact(Int)
            /// At least one bound is set.
            case range(min: Int?, max: Int?)
        }

        var title = ""
        var prompt: String?
        /// The initial text of a field without a format.
        var text: String?
        var textContentType: String?
        /// The number format; nil for a plain text field.
        var format: NumberFormatSpec?
        /// The initial value of a field with a format, as text ("value", else "text", else "0").
        var formattedInitialValue: String
        var axis: Axis?
        var lineLimit: LineLimit?
        var actionID: String?
        var valueChangeActionID: String?

        init(_ properties: [String: Any]) {
            title = properties["title"] as? String ?? ""
            prompt = properties["prompt"] as? String
            text = properties["text"] as? String
            textContentType = properties["textContentType"] as? String
            format = NumberFormatSpec.resolve(from: properties)
            formattedInitialValue = NumberFormatSpec.initialValueString(from: properties)
            axis = (properties["axis"] as? String).flatMap(Axis.init(rawValue:))
            if let exact = properties["lineLimit"] as? Int {
                lineLimit = .exact(exact)
            } else if let dict = properties["lineLimit"] as? [String: Any] {
                let min = dict["min"] as? Int
                var max = dict["max"] as? Int
                // A max below the min is raised to it: a reversed range would stop the app.
                if let lo = min, let hi = max, hi < lo { max = lo }
                lineLimit = (min != nil || max != nil) ? .range(min: min, max: max) : nil
            }
            actionID = properties["actionID"] as? String
            valueChangeActionID = properties["valueChangeActionID"] as? String
        }

        /// The value the field starts with when the model has none.
        var initialValue: String {
            format != nil ? formattedInitialValue : (text ?? "")
        }
    }
}

extension TextField {
    /// The user changed the text of a field without a format: stores it as the value and fires
    /// valueChangeActionID, only when it differs from the value.
    @MainActor
    static func userEditedText(_ newValue: String, element: any ActionUIElementBase, model: ViewModel, windowUUID: String, props: Props) {
        guard model.value as? String != newValue else { return }
        model.value = newValue
        if let valueChangeActionID = props.valueChangeActionID {
            ActionUIModel.shared.actionHandler(valueChangeActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
        }
    }

    /// The user submitted the field (Return, or on macOS and Linux, leaving it): fires actionID.
    @MainActor
    static func userSubmitted(element: any ActionUIElementBase, windowUUID: String, props: Props) {
        guard let actionID = props.actionID else { return }
        // actionHandler logs the call.
        ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
    }
}

struct TextField: ActionUIElementSpec {
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil
    static var valueType: Any.Type = String.self // Value is always String, even for formatted numeric fields
    static var initialValue: (ViewModel) -> Any? = { model in
        if let initialValue = model.value as? String {
            return initialValue
        }
        // A formatted field starts from "value" (may be numeric from JSON); a plain one from "text".
        return Props(model.properties).initialValue
    }
}
