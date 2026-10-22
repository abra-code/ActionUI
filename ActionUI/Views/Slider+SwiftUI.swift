// SwiftUI rendering of Slider; its portable part is in Core/Elements/Slider.swift.

import SwiftUI

extension Slider: ActionUISwiftUIRenderer {
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }

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
                // Use DispatchQueue.main.async to guarantee deferred execution and avoid
                // "publishing changes from within view updates" warning
                DispatchQueue.main.async {
                    Slider.userSetValue(newValue, element: element, model: model, windowUUID: windowUUID, props: props)
                }
            }
        )

        if let step = props.step {
            return SwiftUI.Slider(value: valueBinding, in: props.min...props.max, step: step)
        }
        return SwiftUI.Slider(value: valueBinding, in: props.min...props.max)
    }
}
