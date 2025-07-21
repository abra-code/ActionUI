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
   // Note: These properties are specific to Slider. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct Slider: ActionUIViewElement {
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
    
    static func buildElement(_ element: ActionUIElement, _ state: Binding<[Int: Any]>, _ windowUUID: String, validatedProperties: [String: Any]) -> AnyView {
        let initialValue = (validatedProperties["value"] as? Double) ?? 0.0
        if state.wrappedValue[element.id] == nil {
            state.wrappedValue[element.id] = ["value": initialValue]
        }
        let valueBinding = Binding(
            get: { (state.wrappedValue[element.id] as? [String: Any])?["value"] as? Double ?? initialValue },
            set: { newValue in
                state.wrappedValue[element.id] = ["value": newValue]
                if let actionID = validatedProperties["actionID"] as? String {
                    ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, controlPartID: 0)
                }
            }
        )
        
        return AnyView(
            SwiftUI.Slider(value: valueBinding)
        )
    }
    
    static func applyModifiers(_ view: AnyView, _ properties: [String: Any]) -> AnyView {
        var modifiedView = view
        if let range = properties["range"] as? [String: Double] {
            modifiedView = AnyView(modifiedView.sliderRange(range["min"]!...range["max"]!))
        }
        if let step = properties["step"] as? Double {
            modifiedView = AnyView(modifiedView.sliderStep(step))
        }
        return modifiedView
    }
}
