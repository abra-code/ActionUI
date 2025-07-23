/*
 Sample JSON for StepSlider (macOS 13.0+):
 {
   "type": "StepSlider",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "value": 2,          // Optional: Initial value (Int), defaults to 0
     "range": { "min": 0, "max": 5 }, // Optional: Dictionary with min/max values
     "stepCount": 5       // Optional: Number of steps (Int), defaults to 5
   }
   // Note: These properties are specific to StepSlider. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct StepSlider: ActionUIViewConstruction {
    // Design decision: Defines valueType as Int to reflect value state for type-safe string parsing in ActionUIModel
    static var valueType: Any.Type? { Int.self }
    
    static var validateProperties: (([String: Any]) -> [String: Any])? = { properties in
        var validatedProperties = View.validateProperties(properties)
        
        #if os(macOS)
        if #available(macOS 13.0, *) {
            if let value = validatedProperties["value"] as? Int {
                validatedProperties["value"] = value
            }
            if let range = validatedProperties["range"] as? [String: Int] {
                var validatedRange: [String: Int] = [:]
                if let min = range["min"] { validatedRange["min"] = min }
                if let max = range["max"] { validatedRange["max"] = max }
                if validatedRange["min"] != nil || validatedRange["max"] != nil {
                    validatedProperties["range"] = validatedRange
                }
            }
            if let stepCount = validatedProperties["stepCount"] as? Int, stepCount > 0 {
                validatedProperties["stepCount"] = stepCount
            } else if validatedProperties["stepCount"] != nil {
                print("Warning: StepSlider stepCount must be a positive Int; defaulting to 5")
                validatedProperties["stepCount"] = 5
            }
        } else {
            print("Warning: StepSlider requires macOS 13.0 or later; defaulting to empty properties")
            validatedProperties = [:]
        }
        #else
        print("Warning: StepSlider is macOS-only; defaulting to empty properties")
        validatedProperties = [:]
        #endif
        
        return validatedProperties
    }
    
    static var buildElement: ((ActionUIElement, Binding<[Int: Any]>, String, [String: Any]) -> AnyView)? = { element, state, windowUUID, validatedProperties in
        #if os(macOS)
        if #available(macOS 13.0, *) {
            let initialValue = (validatedProperties["value"] as? Int) ?? 0
            if state.wrappedValue[element.id] == nil {
                state.wrappedValue[element.id] = ["value": initialValue]
            }
            let valueBinding = Binding(
                get: { (state.wrappedValue[element.id] as? [String: Any])?["value"] as? Int ?? initialValue },
                set: { newValue in
                    state.wrappedValue[element.id] = ["value": newValue]
                    if let actionID = validatedProperties["actionID"] as? String {
                        ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                    }
                }
            )
            return AnyView(
                SwiftUI.StepSlider(value: valueBinding)
            )
        } else {
            print("Warning: StepSlider requires macOS 13.0 or later")
            return AnyView(SwiftUI.EmptyView())
        }
        #else
        print("Warning: StepSlider is macOS-only")
        return AnyView(SwiftUI.EmptyView())
        #endif
    }
    
    static var applyModifiers: ((AnyView, [String: Any]) -> AnyView)? = { view, properties in
        #if os(macOS)
        if #available(macOS 13.0, *) {
            var modifiedView = view
            if let range = properties["range"] as? [String: Int] {
                modifiedView = AnyView(modifiedView.stepSliderRange(range["min"]!...range["max"]!))
            }
            if let stepCount = properties["stepCount"] as? Int {
                modifiedView = AnyView(modifiedView.stepSliderStepCount(stepCount))
            }
            return modifiedView
        }
        #endif
        return view
    }
}
