// SwiftUI rendering of SecureField; its portable part is in Core/Elements/SecureField.swift.

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension SecureField: ActionUISwiftUIRenderer {
    // Builds the SwiftUI.SecureField view, binding its text to state and triggering actionID on submit
    // Design decision: Initializes value as "" if not set, preserving shared state (the view model's properties)
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let props = Props(properties)
        let title = props.title
        let prompt = props.prompt.map { SwiftUI.Text($0) }
        let initialValue = Self.initialValue(model) as? String ?? ""

        let onSubmit = {
            TextField.userSubmitted(actionID: props.actionID, viewID: element.id, windowUUID: windowUUID)
        }

        let textBinding = mainActorBinding(
            get: { model.value as? String ?? initialValue },
            set: { newValue in
                guard model.value as? String != newValue else {
                    return
                }
                // Use DispatchQueue.main.async to guarantee deferred execution and avoid
                // "publishing changes from within view updates" warning
                DispatchQueue.main.async {
                    TextField.userEditedText(newValue, valueChangeActionID: props.valueChangeActionID, viewID: element.id, model: model, windowUUID: windowUUID)
                }
            }
        )

        return TextFieldFocusContainer(onSubmit: onSubmit) {
            SwiftUI.SecureField(title, text: textBinding, prompt: prompt)
                .onSubmit(onSubmit)
        }
    }

    // Applies modifiers specific to SecureField, such as textContentType
    // Design decision: Relies on default macOS text field style (likely rounded) for HIG compliance; textContentType is iOS-only
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, properties, logger in
        var modifiedView = view
        #if canImport(UIKit)
        if let textContentType = Props(properties).textContentType {
            switch textContentType {
            case .password:
                modifiedView = modifiedView.textContentType(.password)
            case .newPassword:
                modifiedView = modifiedView.textContentType(.newPassword)
            case .oneTimeCode:
                modifiedView = modifiedView.textContentType(.oneTimeCode)
            }
        }
        #endif
        return modifiedView
    }
}
