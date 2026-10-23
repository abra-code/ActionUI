// SwiftUI rendering of ColorPicker; its portable part is in Core/Elements/ColorPicker.swift.

import SwiftUI

extension ColorPicker: ActionUISwiftUIRenderer {
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }

    // Builds the ColorPicker view, binding selection to the view model's ColorSpec value
    // Design decision: Initializes value as the "selectedColor" property or clear if not set, preserving shared state (the view model) from ActionUIRegistry.buildView
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let initialSpec = Self.initialValue(model) as? ColorSpec ?? .named(.clear)
        let props = Props(properties)
        let title = props.title

        // The binding's main-actor closures capture the Sendable Props, not the non-Sendable
        // [String: Any] properties payload.
        let colorBinding = mainActorBinding(
            get: { ColorHelper.color(for: model.value as? ColorSpec ?? initialSpec) },
            set: { newValue in
                // The picked color as sRGB components; a color with none to read is ignored.
                guard let picked = ColorHelper.spec(from: newValue), model.value as? ColorSpec != picked else {
                    return
                }
                // Use DispatchQueue.main.async to guarantee deferred execution and avoid
                // "publishing changes from within view updates" warning
                DispatchQueue.main.async {
                    ColorPicker.userPicked(picked, element: element, model: model, windowUUID: windowUUID, props: props)
                }
            }
        )

        return SwiftUI.ColorPicker(title, selection: colorBinding)
    }
}
