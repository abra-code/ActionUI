/*
 Sample JSON for Slider:
 {
   "type": "Slider",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "value": 50.0,       // Optional: Initial value (Double), defaults to 0.0
     "range": { "min": 0.0, "max": 100.0 }, // Optional: Dictionary with min/max values
     "step": 1.0          // Optional: Step increment (Double), defaults to 1.0
   }
   // Note: These properties are specific to Slider. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ModifierRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct Slider: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = View.validateProperties(properties)
        
        if let value = validatedProperties["value"] as? Double {
            validatedProperties["value"] = value
        }
        if let range = validatedProperties["range"] as? [String: Double] {
            var validatedRange: [String: Double] = [:]
            if let min = range["min"] { validatedRange["min"] = min }
            if let max = range["max"] { validatedRange["max"] = max }
            if validatedRange["min"] != nil || validatedRange["max"] != nil {
                validatedProperties["range"] = validatedRange
            }
        }
        if let step = validatedProperties["step"] as? Double, step > 0 {
            validatedProperties["step"] = step
        } else if validatedProperties["step"] != nil {
            print("Warning: Slider step must be a positive Double; defaulting to 1.0")
            validatedProperties["step"] = 1.0
        }
        
        return validatedProperties
    }
    
    static func register(in registry: ViewBuilderRegistry) {
        registry.register("Slider") { element, state, windowUUID in
            let properties = StaticElement.getValidatedProperties(element: element, state: state)
            let initialValue = (properties["value"] as? Double) ?? 0.0
            let range = properties["range"] as? [String: Double] ?? ["min": 0.0, "max": 100.0]
            if state.wrappedValue[element.id] == nil {
                state.wrappedValue[element.id] = ["value": initialValue]
            }
            let valueBinding = Binding(
                get: { (state.wrappedValue[element.id] as? [String: Any])?["value"] as? Double ?? initialValue },
                set: { newValue in
                    state.wrappedValue[element.id] = ["value": newValue]
                    if let actionID = properties["actionID"] as? String {
                        actionHandler(actionID, windowUUID: windowUUID, controlID: element.id, controlPartID: 0, model: ActionUIModel.shared)
                    }
                }
            )
            return AnyView(
                Slider(value: valueBinding, in: range["min"]!...range["max"]!)
            )
        }
    }
    
    static func registerModifiers(registry: ModifierRegistry) {
        registry.register("step") { view, properties in
            guard let step = properties["step"] as? Double else { return view }
            return AnyView(view.sliderStyle(DefaultSliderStyle()).onChange(of: step) { _ in
                // Note: Step is set during construction; this is a placeholder for dynamic updates if needed
            })
        }
    }
}
