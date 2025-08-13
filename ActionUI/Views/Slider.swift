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
    
    static var validateProperties: ([String: Any]) -> [String: Any] = { properties in
        var validatedProperties = properties
        
        if let value = validatedProperties["value"] as? Double {
            validatedProperties["value"] = value
        } else if validatedProperties["value"] != nil {
            print("Warning: Slider value must be a Double; defaulting to 0.0")
            validatedProperties["value"] = 0.0
        }
        if let range = validatedProperties["range"] as? [String: Double] {
            var validatedRange: [String: Double] = [:]
            if let min = range["min"], let max = range["max"], min <= max {
                validatedRange["min"] = min
                validatedRange["max"] = max
                validatedProperties["range"] = validatedRange
            } else {
                print("Warning: Slider range must have valid min/max Doubles with min <= max; defaulting to 0.0...1.0")
                validatedProperties["range"] = ["min": 0.0, "max": 1.0]
            }
        } else if validatedProperties["range"] != nil {
            print("Warning: Slider range must be a dictionary with min/max Doubles; defaulting to 0.0...1.0")
            validatedProperties["range"] = ["min": 0.0, "max": 1.0]
        }
        if let step = validatedProperties["step"] as? Double, step > 0 {
            validatedProperties["step"] = step
        } else if validatedProperties["step"] != nil {
            print("Warning: Slider step must be a positive Double; defaulting to 1.0")
            validatedProperties["step"] = 1.0
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any]) -> any SwiftUI.View = { element, state, windowUUID, properties in
        let initialValue = (properties["value"] as? Double) ?? 0.0
        let value = (state.wrappedValue[element.id] as? [String: Any])?["value"] as? Double ?? initialValue
        let range = properties["range"] as? [String: Double] ?? ["min": 0.0, "max": 1.0]
        let min = range["min"] ?? 0.0
        let max = range["max"] ?? 1.0
        let step = properties["step"] as? Double
        
        let valueBinding = Binding(
            get: { (state.wrappedValue[element.id] as? [String: Any])?["value"] as? Double ?? initialValue },
            set: { newValue in
                if (min...max).contains(newValue) {
                    state.wrappedValue[element.id] = (state.wrappedValue[element.id] as? [String: Any] ?? [:]).merging(
                        ["value": newValue, "validatedProperties": properties],
                        uniquingKeysWith: { _, new in new }
                    )
                    if let actionID = properties["actionID"] as? String {
                        Task { @MainActor in
                            ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                        }
                    }
                }
            }
        )
        
        if let step = step, step > 0 {
            return SwiftUI.Slider(value: valueBinding, in: min...max, step: step)
        }
        return SwiftUI.Slider(value: valueBinding, in: min...max)
    }
}
