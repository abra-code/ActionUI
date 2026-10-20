/*
 Sample JSON for Slider:
 {
   "type": "Slider",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "value": 50.0,       // Optional: Initial value (Double), defaults to 0.0
     "range": { "min": 0.0, "max": 100.0 }, // Optional: Dictionary with min/max values, defaults to 0.0 to 1.0. "range" becomes required if you specify "step"
     "step": 1.0          // Optional: Step increment (Double), defaults to continuous sliding if not present; a step that makes more than a million steps is ignored
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

        /// The most steps a range may have; a million steps take about 16 MB.
        static let maxSteps = 1_000_000.0

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
                // SwiftUI keeps every step of the range in memory, 16 bytes each, and stops the app
                // when there are too many (or the range is infinite): past the limit, no step. An
                // infinite step over an infinite range gives NaN, which counts as too many.
                if let given = step, !((max - min) / given <= Self.maxSteps) {
                    step = nil
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
        return Props(model.properties).initialValue
    }
}
