/*
 Sample JSON for Slider:
 {
   "type": "Slider",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "value": 50.0,       // Optional: Initial value (Double), defaults to 0.0
     "range": { "min": 0.0, "max": 100.0 }, // Optional: Dictionary with min/max values, defaults to 0.0 to 1.0. "range" becomes required if you specify "step"
     "step": 1.0          // Optional: Step increment (Double), defaults to continuous sliding if not present
   }
   // Note: These properties are specific to Slider. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

extension Slider {
    /// Slider's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        var initialValue = 0.0
        var min = 0.0
        var max = 1.0
        var step: Double?
        var valueChangeActionID: String?

        init(_ properties: [String: Any]) {
            initialValue = properties.double(forKey: "value") ?? 0.0
            // A range needs both bounds, numeric, in order; anything else is 0...1.
            if let range = properties["range"] as? [String: Any],
               let lo = range.double(forKey: "min"), let hi = range.double(forKey: "max"), lo <= hi {
                min = lo
                max = hi
            }
            if properties["step"] != nil {
                // Not a positive number: 1.0, which is then clamped like a given step.
                let s = properties.double(forKey: "step").flatMap { $0 > 0 ? $0 : nil } ?? 1.0
                if properties["range"] == nil {
                    step = 1.0                           // a step without a range
                } else if max > min {
                    step = Swift.min(s, max - min)       // clamped to the range; min == max: no step
                }
            }
            valueChangeActionID = properties["valueChangeActionID"] as? String
        }

        /// A value the user may set: inside the range.
        func accepts(_ value: Double) -> Bool {
            (min...max).contains(value)
        }
    }
}

struct Slider: ActionUIViewConstruction {
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil

    static var valueType: Any.Type = Double.self // Value is the slider's position
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        // Validate value
        if let value = validatedProperties.double(forKey: "value") {
            validatedProperties["value"] = value
        } else if validatedProperties["value"] != nil {
            logger.log("Slider value must be a number; defaulting to 0.0", .warning)
            validatedProperties["value"] = 0.0
        } else {
            validatedProperties["value"] = 0.0
        }
        
        // Validate range
        if let range = validatedProperties["range"] as? [String: Any] {
            var validatedRange: [String: Double] = [:]
            if let min = range.double(forKey: "min"), let max = range.double(forKey: "max"), min <= max {
                validatedRange["min"] = min
                validatedRange["max"] = max
                validatedProperties["range"] = validatedRange
            } else {
                logger.log("Slider range must have valid min/max numbers with min <= max; defaulting to 0.0...1.0", .warning)
                validatedProperties["range"] = ["min": 0.0, "max": 1.0]
            }
        } else if validatedProperties["range"] != nil {
            logger.log("Slider range must be a dictionary with min/max numbers; defaulting to 0.0...1.0", .warning)
            validatedProperties["range"] = ["min": 0.0, "max": 1.0]
        }
        
        // Validate step and ensure it doesn't exceed range
        if let step = validatedProperties.double(forKey: "step"), step > 0 {
            if let range = validatedProperties["range"] as? [String: Any],
               let min = range.double(forKey: "min"),
               let max = range.double(forKey: "max") {
                let rangeSize = max - min
                if step > rangeSize {
                    logger.log("Slider step must not exceed range (max - min); clamping to \(rangeSize)", .warning)
                    // An empty range (min == max) has no step: removed rather than stored as 0.
                    validatedProperties["step"] = rangeSize > 0 ? rangeSize : nil
                } else {
                    validatedProperties["step"] = step
                }
            } else if validatedProperties["step"] != nil {
                logger.log("Slider step requires a valid range; defaulting to 1.0", .warning)
                validatedProperties["step"] = 1.0
            }
        } else if validatedProperties["step"] != nil {
            logger.log("Slider step must be a positive number; defaulting to 1.0", .warning)
            validatedProperties["step"] = 1.0
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let props = Props(properties)
        let initialValue = Self.initialValue(model) as? Double ?? props.initialValue

        // The binding's main-actor closures capture the Sendable props, not the non-Sendable
        // [String: Any] properties payload.
        let valueBinding = mainActorBinding(
            get: { model.value as? Double ?? initialValue },
            set: { newValue in
                guard model.value as? Double != newValue else {
                    return
                }
                if props.accepts(newValue) {
                    // Use DispatchQueue.main.async to guarantee deferred execution and avoid
                    // "publishing changes from within view updates" warning
                    DispatchQueue.main.async {
                        model.value = newValue
                        if let valueChangeActionID = props.valueChangeActionID {
                            ActionUIModel.shared.actionHandler(valueChangeActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                        }
                    }
                }
            }
        )

        if let step = props.step {
            return SwiftUI.Slider(value: valueBinding, in: props.min...props.max, step: step)
        }
        return SwiftUI.Slider(value: valueBinding, in: props.min...props.max)
    }

    static var initialValue: (ViewModel) -> Any? = { model in
        if let initialValue = model.value as? Double {
            return initialValue
        }
        return Props(model.validatedProperties).initialValue
    }
}
