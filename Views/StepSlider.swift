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
   // Note: These properties are specific to StepSlider. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ModifierRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct StepSlider: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
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
    
    static func register(in registry: ViewBuilderRegistry) {
        #if os(macOS)
        if #available(macOS 13.0, *) {
            registry.register("StepSlider") { element, state, windowUUID in
                let properties = StaticElement.getValidatedProperties(element: element, state: state)
                let initialValue = (properties["value"] as? Int) ?? 0
                let range = properties["range"] as? [String: Int] ?? ["min": 0, "max": 5]
                if state.wrappedValue[element.id] == nil {
                    state.wrappedValue[element.id] = ["value": initialValue]
                }
                let valueBinding = Binding(
                    get: { (state.wrappedValue[element.id] as? [String: Any])?["value"] as? Int ?? initialValue },
                    set: { newValue in
                        state.wrappedValue[element.id] = ["value": newValue]
                        if let actionID = properties["actionID"] as? String {
                            actionHandler(actionID, windowUUID: windowUUID, controlID: element.id, controlPartID: 0, model: ActionUIModel.shared)
                        }
                    }
                )
                return AnyView(
                    StepSlider(value: valueBinding, in: range["min"]!...range["max"]!)
                )
            }
        } else {
            registry.register("StepSlider") { _, _, _ in
                print("Warning: StepSlider requires macOS 13.0 or later")
                return AnyView(EmptyView())
            }
        }
        #else
        registry.register("StepSlider") { _, _, _ in
            print("Warning: StepSlider is macOS-only")
            return AnyView(EmptyView())
        }
        #endif
    }
    
    static func registerModifiers(registry: ModifierRegistry) {
        registry.register("stepCount") { view, properties in
            guard let stepCount = properties["stepCount"] as? Int else { return view }
            return AnyView(view.stepperStyle(DefaultStepperStyle()).onChange(of: stepCount) { _ in
                // Note: Step count is set during construction; this is a placeholder for dynamic updates if needed
            })
        }
    }
}
