// SwiftUI rendering of TextField; its portable part is in Core/Elements/TextField.swift.

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension TextField: ActionUISwiftUIRenderer {
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let props = Props(properties)
        let title = props.title
        let prompt = props.prompt.map { SwiftUI.Text($0) }
        let initialValue = Self.initialValue(model) as? String ?? ""
        let actionID = props.actionID
        let valueChangeActionID = props.valueChangeActionID

        let onSubmit = {
            if let actionID = actionID {
                logger.log("Executing handler for actionID: \(actionID), viewID: \(element.id)", .debug)
                ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
            }
        }

        // Formatted numeric TextField
        if let format = props.format {
            let onValueChange: (String) -> Void = { newValue in
                DispatchQueue.main.async {
                    model.value = newValue
                    if let valueChangeActionID {
                        ActionUIModel.shared.actionHandler(valueChangeActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                    }
                }
            }

            let formatted = AnyView(
                NumberFormatHelper.buildFormattedTextField(
                    title: title,
                    prompt: prompt,
                    format: format,
                    model: model,
                    defaultValue: initialValue,
                    onValueChange: onValueChange
                )
            )
            return TextFieldFocusContainer(onSubmit: onSubmit) {
                // A submit handler makes the field consume Return on macOS. Without an actionID
                // there is nothing to run, so leave Return to the window's default button.
                if actionID != nil {
                    formatted.onSubmit(onSubmit)
                } else {
                    formatted
                }
            }
        }

        // Standard text TextField
        let textBinding = mainActorBinding(
            get: { model.value as? String ?? initialValue },
            set: { newValue in
                guard model.value as? String != newValue else {
                    return
                }
                // Use DispatchQueue.main.async to guarantee deferred execution and avoid
                // "publishing changes from within view updates" warning
                DispatchQueue.main.async {
                    model.value = newValue
                    if let valueChangeActionID {
                        ActionUIModel.shared.actionHandler(valueChangeActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                    }
                }
            }
        )

        let isVertical = props.axis == .vertical

        let field = isVertical
            ? AnyView(SwiftUI.TextField(title, text: textBinding, prompt: prompt, axis: .vertical))
            : AnyView(SwiftUI.TextField(title, text: textBinding, prompt: prompt))
        return TextFieldFocusContainer(onSubmit: onSubmit) {
            // A submit handler makes the field consume Return on macOS. Without an actionID
            // there is nothing to run, so leave Return to the window's default button.
            if actionID != nil {
                field.onSubmit(onSubmit)
            } else {
                field
            }
        }
    }

    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, properties, logger in
        var modifiedView = view
        let props = Props(properties)
        #if canImport(UIKit)
        if let textContentType = props.textContentType {
            modifiedView = modifiedView.textContentType(UITextContentType(rawValue: textContentType))
        }
        #endif

        // Apply lineLimit: exact Int, or range via {min, max}
        switch props.lineLimit {
        case .exact(let exact):
            modifiedView = modifiedView.lineLimit(exact)
        case .range(let min?, let max?):
            modifiedView = modifiedView.lineLimit(min...max)
        case .range(let min?, nil):
            modifiedView = modifiedView.lineLimit(min...)
        case .range(nil, let max?):
            modifiedView = modifiedView.lineLimit(...max)
        case .range(nil, nil), nil:
            break
        }

        return modifiedView
    }
}
