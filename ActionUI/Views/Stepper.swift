/*
 Sample JSON for Stepper:
 {
   "type": "Stepper",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "value": 5.0,        // Optional: Initial value (Double), defaults to 0.0
     "range": { "min": 0.0, "max": 10.0 }, // Optional: Dictionary with min/max values; no range clamping if omitted
     "step": 1.0,         // Optional: Step increment (Double), defaults to 1.0
     "label": "Quantity", // Optional: Static string label; ignored when labelFormat is set
     "labelFormat": "Quantity: %.0f", // Optional: printf-style format string embedding the current value; use float
                          // specifiers (%g, %f, %.0f, %.1f, etc.) since the value is always a Double.
                          // Examples: "Count: %.0f" → "Count: 5", "Rating: %.1f" → "Rating: 2.5",
                          //           "Volume: %g%%" → "Volume: 50%"
                          // Takes precedence over "label" when both are present.
     "actionID": "stepper.changed", // Optional: String for action triggered on user-initiated value change
   }
   // Note: These properties are specific to Stepper. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, disabled, etc.) are inherited and applied via ActionUIRegistry.shared.applyModifiers.
 }
*/

import SwiftUI

struct Stepper: ActionUIViewConstruction {
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil

    static var valueType: Any.Type = Double.self

    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties

        // Validate value
        if let value = validatedProperties.double(forKey: "value") {
            validatedProperties["value"] = value
        } else if validatedProperties["value"] != nil {
            logger.log("Stepper value must be a number; defaulting to 0.0", .warning)
            validatedProperties["value"] = 0.0
        } else {
            validatedProperties["value"] = 0.0
        }

        // Validate range
        if let range = validatedProperties["range"] as? [String: Any] {
            if let min = range.double(forKey: "min"), let max = range.double(forKey: "max"), min <= max {
                validatedProperties["range"] = ["min": min, "max": max]
            } else {
                logger.log("Stepper range must have valid min/max numbers with min <= max; ignoring range", .warning)
                validatedProperties["range"] = nil
            }
        } else if validatedProperties["range"] != nil {
            logger.log("Stepper range must be a dictionary with min/max numbers; ignoring range", .warning)
            validatedProperties["range"] = nil
        }

        // Validate step
        if let step = validatedProperties.double(forKey: "step"), step > 0 {
            validatedProperties["step"] = step
        } else if validatedProperties["step"] != nil {
            logger.log("Stepper step must be a positive number; defaulting to 1.0", .warning)
            validatedProperties["step"] = 1.0
        } else {
            validatedProperties["step"] = 1.0
        }

        // Validate label
        if let label = validatedProperties["label"], !(label is String) {
            logger.log("Stepper label must be a String; ignoring", .warning)
            validatedProperties["label"] = nil
        }

        // Validate labelFormat
        if let labelFormat = validatedProperties["labelFormat"], !(labelFormat is String) {
            logger.log("Stepper labelFormat must be a String; ignoring", .warning)
            validatedProperties["labelFormat"] = nil
        }

        return validatedProperties
    }

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let initialValue = Self.initialValue(model) as? Double ?? 0.0
        let step = properties.double(forKey: "step") ?? 1.0

        // labelFormat takes precedence; re-evaluated each body pass so label stays current.
        // This works because ActionUIView.body is re-run whenever model.value (@Published) changes,
        // causing buildView to be called again with the updated value.
        let currentValue = model.value as? Double ?? initialValue
        let label: String
        if let labelFormat = properties["labelFormat"] as? String {
            label = String(format: labelFormat, currentValue)
        } else {
            label = properties["label"] as? String ?? ""
        }

        let valueBinding = Binding(
            get: { model.value as? Double ?? initialValue },
            set: { newValue in
                guard model.value as? Double != newValue else { return }
                // DispatchQueue.main.async avoids "publishing changes from within view updates" warning.
                // actionID fires only on user interaction (binding setter), not programmatic updates.
                DispatchQueue.main.async {
                    model.value = newValue
                    if let actionID = properties["actionID"] as? String {
                        ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0, context: newValue)
                    }
                }
            }
        )

        if let range = properties["range"] as? [String: Any],
           let min = range.double(forKey: "min"),
           let max = range.double(forKey: "max") {
            return SwiftUI.Stepper(label, value: valueBinding, in: min...max, step: step)
        }
        return SwiftUI.Stepper(label, value: valueBinding, step: step)
    }

    static var initialValue: (ViewModel) -> Any? = { model in
        if let initialValue = model.value as? Double {
            return initialValue
        }
        return model.validatedProperties.double(forKey: "value") ?? 0.0
    }
}
