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
   // Note: These properties are specific to Slider. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct Slider: ActionUIViewConstruction {
    static var valueType: Any.Type { Double.self } // Value is the slider's position
    
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
                    validatedProperties["step"] = rangeSize
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
    
    static var buildView: (any ActionUIElement, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let initialValue = Self.initialValue(model) as? Double ?? 0.0
        let range = properties["range"] as? [String: Any] ?? ["min": 0.0, "max": 1.0]
        let min = range.double(forKey: "min") ?? 0.0
        let max = range.double(forKey: "max") ?? 1.0
        let step = properties.double(forKey: "step")
        
        let valueBinding = Binding(
            get: { model.value as? Double ?? initialValue },
            set: { newValue in
                if (min...max).contains(newValue) {
                    model.value = newValue
                    if let valueChangeActionID = properties["valueChangeActionID"] as? String {
                        ActionUIModel.shared.actionHandler(valueChangeActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                    }
                }
            }
        )
        
        if let step = step, step > 0 {
            return SwiftUI.Slider(value: valueBinding, in: min...max, step: step)
        }
        return SwiftUI.Slider(value: valueBinding, in: min...max)
    }
    
    static var initialValue: (ViewModel) -> Any? = { model in
        if let initialValue = model.value as? Double {
            return initialValue
        }
        return model.validatedProperties.double(forKey: "value") ?? 0.0
    }
}
