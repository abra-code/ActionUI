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
   // Note: These properties are specific to Stepper. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, disabled, etc.) are inherited and applied via ActionUIRegistry.shared.applyModifiers.
 }
*/

import SwiftUI

extension Stepper {
    /// Stepper's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        var initialValue = 0.0
        /// The limits, when both bounds are numbers in order; otherwise the stepper is unbounded.
        var range: ClosedRange<Double>?
        var step = 1.0
        var label = ""
        /// A format for the current value (the renderer applies it); takes precedence over label.
        var labelFormat: String?
        var actionID: String?

        init(_ properties: [String: Any]) {
            initialValue = properties.double(forKey: "value") ?? 0.0
            if let range = properties["range"] as? [String: Any],
               let lo = range.double(forKey: "min"), let hi = range.double(forKey: "max"), lo <= hi {
                self.range = lo...hi
            }
            // Not a positive number: 1.0.
            step = properties.double(forKey: "step").flatMap { $0 > 0 ? $0 : nil } ?? 1.0
            label = properties["label"] as? String ?? ""
            labelFormat = properties["labelFormat"] as? String
            actionID = properties["actionID"] as? String
        }
    }
}

struct Stepper: ActionUIViewConstruction {
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil

    static var valueType: Any.Type = Double.self

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let initialValue = Self.initialValue(model) as? Double ?? 0.0
        let props = Props(properties)
        let step = props.step

        // labelFormat takes precedence; re-evaluated each body pass so label stays current.
        // This works because ActionUIView.body is re-run whenever model.value (@Published) changes,
        // causing buildView to be called again with the updated value.
        let currentValue = model.value as? Double ?? initialValue
        let label: String
        if let labelFormat = props.labelFormat {
            label = String(format: labelFormat, currentValue)
        } else {
            label = props.label
        }

        // Hoisted out of the binding: its main-actor closures capture only this Sendable String?,
        // not the non-Sendable [String: Any] properties payload.
        let actionID = props.actionID
        let valueBinding = mainActorBinding(
            get: { model.value as? Double ?? initialValue },
            set: { newValue in
                guard model.value as? Double != newValue else { return }
                // DispatchQueue.main.async avoids "publishing changes from within view updates" warning.
                // actionID fires only on user interaction (binding setter), not programmatic updates.
                DispatchQueue.main.async {
                    model.value = newValue
                    if let actionID {
                        ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0, context: newValue)
                    }
                }
            }
        )

        if let range = props.range {
            return SwiftUI.Stepper(label, value: valueBinding, in: range, step: step)
        }
        return SwiftUI.Stepper(label, value: valueBinding, step: step)
    }

    static var initialValue: (ViewModel) -> Any? = { model in
        if let initialValue = model.value as? Double {
            return initialValue
        }
        return Props(model.properties).initialValue
    }
}
