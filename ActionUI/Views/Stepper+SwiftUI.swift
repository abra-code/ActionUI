// SwiftUI rendering of Stepper; its portable part is in Core/Elements/Stepper.swift.

import SwiftUI

extension Stepper: ActionUISwiftUIRenderer {
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let initialValue = Self.initialValue(model) as? Double ?? 0.0
        let props = Props(properties)
        let step = props.step

        // labelFormat takes precedence; re-evaluated each body pass so label stays current.
        // This works because ActionUIView.body is re-run whenever model.value changes,
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
}
