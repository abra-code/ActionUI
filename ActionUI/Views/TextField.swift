// Sources/Views/TextField.swift
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

import SwiftUI
#if canImport(UIKit)
import UIKit
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
        var format: NumberFormatHelper?
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
            format = NumberFormatHelper.resolve(from: properties)
            formattedInitialValue = NumberFormatHelper.initialValueString(from: properties)
            axis = (properties["axis"] as? String).flatMap(Axis.init(rawValue:))
            if let exact = properties["lineLimit"] as? Int {
                lineLimit = .exact(exact)
            } else if let dict = properties["lineLimit"] as? [String: Any] {
                let min = dict["min"] as? Int
                let max = dict["max"] as? Int
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

struct TextField: ActionUIViewConstruction {
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil

    static var valueType: Any.Type = String.self // Value is always String, even for formatted numeric fields

    // Validates properties specific to TextField; baseline properties are validated by ActionUIRegistry.validateProperties
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties

        // Validate title
        if properties["title"] != nil && !(properties["title"] is String) {
            logger.log("TextField title must be a String; defaulting to empty string", .warning)
            validatedProperties["title"] = nil
        }

        // Validate prompt
        if !(properties["prompt"] is String?), properties["prompt"] != nil {
            logger.log("TextField prompt must be a String; defaulting to nil", .warning)
            validatedProperties["prompt"] = nil
        }

        // Validate text (initial value for text mode)
        if properties["text"] != nil && !(properties["text"] is String) {
            logger.log("TextField text must be a String; ignoring", .warning)
            validatedProperties["text"] = nil
        }

        // Validate textContentType
        if !(properties["textContentType"] is String?), properties["textContentType"] != nil {
            logger.log("TextField textContentType must be a String; defaulting to nil", .warning)
            validatedProperties["textContentType"] = nil
        }

        // Validate format-related properties (format, fractionLength, currencyCode, value)
        if let format = properties["format"] {
            if let formatStr = format as? String {
                let validFormats = ["integer", "decimal", "percent", "currency"]
                if !validFormats.contains(formatStr) {
                    logger.log("TextField format must be one of \(validFormats); ignoring", .warning)
                    validatedProperties["format"] = nil
                }
            } else {
                logger.log("TextField format must be a String; ignoring", .warning)
                validatedProperties["format"] = nil
            }
        }

        if let fractionLength = properties["fractionLength"] {
            if fractionLength is Int {
                // Valid: exact fraction length
            } else if let dict = fractionLength as? [String: Any] {
                if dict["min"] == nil && dict["max"] == nil {
                    logger.log("TextField fractionLength dict must have 'min' and/or 'max'; ignoring", .warning)
                    validatedProperties["fractionLength"] = nil
                }
            } else {
                logger.log("TextField fractionLength must be Int or {min, max} dict; ignoring", .warning)
                validatedProperties["fractionLength"] = nil
            }
        }

        if properties["currencyCode"] != nil && !(properties["currencyCode"] is String) {
            logger.log("TextField currencyCode must be a String; defaulting to USD", .warning)
            validatedProperties["currencyCode"] = nil
        }

        // Validate axis
        if let axis = properties["axis"] {
            if let axisStr = axis as? String {
                if axisStr != "vertical" && axisStr != "horizontal" {
                    logger.log("TextField axis must be \"vertical\" or \"horizontal\"; ignoring", .warning)
                    validatedProperties["axis"] = nil
                }
            } else {
                logger.log("TextField axis must be a String; ignoring", .warning)
                validatedProperties["axis"] = nil
            }
        }

        // Validate lineLimit
        if let lineLimit = properties["lineLimit"] {
            if lineLimit is Int {
                // Valid: exact line limit
            } else if let dict = lineLimit as? [String: Any] {
                if dict["min"] == nil && dict["max"] == nil {
                    logger.log("TextField lineLimit dict must have 'min' and/or 'max'; ignoring", .warning)
                    validatedProperties["lineLimit"] = nil
                }
            } else {
                logger.log("TextField lineLimit must be Int or {min, max} dict; ignoring", .warning)
                validatedProperties["lineLimit"] = nil
            }
        }

        // Validate "value" — accept Int, Double, or String (numeric)
        if let value = properties["value"] {
            if !(value is Int) && !(value is Double) && !(value is String) {
                logger.log("TextField value must be a number or String; ignoring", .warning)
                validatedProperties["value"] = nil
            }
        }

        return validatedProperties
    }

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let props = Props(properties)
        let title = props.title
        let prompt = props.prompt.map { SwiftUI.Text($0) }
        let initialValue = Self.initialValue(model) as? String ?? ""
        let actionID = props.actionID
        let valueChangeActionID = props.valueChangeActionID

        let onSubmit = {
            if let actionID = actionID {
                logger.log("Executing handler for actionID: \(actionID), viewID: \(element.id)", .debug)
                ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
            }
        }

        // Formatted numeric TextField
        if let format = props.format {
            let onValueChange: (String) -> Void = { newValue in
                DispatchQueue.main.async {
                    model.value = newValue
                    if let valueChangeActionID {
                        ActionUIModel.shared.actionHandler(valueChangeActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                    }
                }
            }

            let formatted = AnyView(
                NumberFormatHelper.buildFormattedTextField(
                    title: title,
                    prompt: prompt,
                    format: format,
                    model: model,
                    defaultValue: initialValue,
                    onValueChange: onValueChange
                )
            )
            return TextFieldFocusContainer(onSubmit: onSubmit) {
                // A submit handler makes the field consume Return on macOS. Without an actionID
                // there is nothing to run, so leave Return to the window's default button.
                if actionID != nil {
                    formatted.onSubmit(onSubmit)
                } else {
                    formatted
                }
            }
        }

        // Standard text TextField
        let textBinding = mainActorBinding(
            get: { model.value as? String ?? initialValue },
            set: { newValue in
                guard model.value as? String != newValue else {
                    return
                }
                // Use DispatchQueue.main.async to guarantee deferred execution and avoid
                // "publishing changes from within view updates" warning
                DispatchQueue.main.async {
                    model.value = newValue
                    if let valueChangeActionID {
                        ActionUIModel.shared.actionHandler(valueChangeActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                    }
                }
            }
        )

        let isVertical = props.axis == .vertical

        let field = isVertical
            ? AnyView(SwiftUI.TextField(title, text: textBinding, prompt: prompt, axis: .vertical))
            : AnyView(SwiftUI.TextField(title, text: textBinding, prompt: prompt))
        return TextFieldFocusContainer(onSubmit: onSubmit) {
            // A submit handler makes the field consume Return on macOS. Without an actionID
            // there is nothing to run, so leave Return to the window's default button.
            if actionID != nil {
                field.onSubmit(onSubmit)
            } else {
                field
            }
        }
    }

    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, properties, logger in
        var modifiedView = view
        let props = Props(properties)
        #if canImport(UIKit)
        if let textContentType = props.textContentType {
            modifiedView = modifiedView.textContentType(UITextContentType(rawValue: textContentType))
        }
        #endif

        // Apply lineLimit: exact Int, or range via {min, max}
        switch props.lineLimit {
        case .exact(let exact):
            modifiedView = modifiedView.lineLimit(exact)
        case .range(let min?, let max?):
            modifiedView = modifiedView.lineLimit(min...max)
        case .range(let min?, nil):
            modifiedView = modifiedView.lineLimit(min...)
        case .range(nil, let max?):
            modifiedView = modifiedView.lineLimit(...max)
        case .range(nil, nil), nil:
            break
        }

        return modifiedView
    }

    static var initialValue: (ViewModel) -> Any? = { model in
        if let initialValue = model.value as? String {
            return initialValue
        }
        // A formatted field starts from "value" (may be numeric from JSON); a plain one from "text".
        return Props(model.validatedProperties).initialValue
    }
}
