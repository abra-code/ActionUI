// SwiftUI rendering of Toggle; its portable part is in Core/Elements/Toggle.swift.

import SwiftUI

extension Toggle: ActionUISwiftUIRenderer {
    // Builds the Toggle view, binding isOn to state
    // Design decision: Initializes value as false if not set, preserving shared state (the view model's properties)
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let props = Props(properties)
        // The bindings' main-actor closures capture these Sendable values, not the non-Sendable
        // [String: Any] properties payload.
        let actionID = props.actionID
        let title = props.title

        // Template row: the row data holds the state (TemplateHelper has already read "isOn"
        // from the row as a Bool), and this instance's ViewModel is thrown away after the render.
        if let templateContext = model.templateContext {
            let shown = props.isOn ?? false
            // The template's own "isOn" (before substitution) names the column that holds the state.
            let column = TemplateHelper.singleColumnIndex(element.properties["isOn"])
            if column == nil {
                TemplateHelper.warnOnce("Toggle isOn in a template must be a single column reference such as \"$1\" to keep its state; this Toggle is display-only", logger: logger)
            }
            let rowBinding = mainActorBinding(
                get: { shown },
                set: { newValue in
                    guard newValue != shown else { return }
                    // After the view update, as below. The container redraws from the row written.
                    DispatchQueue.main.async {
                        TemplateHelper.commitRowToggle(
                            newValue, context: templateContext, column: column,
                            actionID: actionID, windowUUID: windowUUID
                        )
                    }
                }
            )
            return SwiftUI.Toggle(title, isOn: rowBinding)
        }

        let initialValue = Self.initialValue(model) as? Bool ?? false
        
        let toggleBinding = mainActorBinding(
            get: { model.value as? Bool ?? initialValue },
            set: { newValue in
                guard model.value as? Bool != newValue else {
                    return
                }
                // DispatchQueue.main.async avoids "publishing changes from within view updates" warning.
                // actionID is fired here in the binding setter (not via .onChange) so it only triggers
                // on user interaction. .onChange would also fire on programmatic value changes,
                // which can cause cascading actions and unexpected behavior.
                DispatchQueue.main.async {
                    model.value = newValue
                    if let actionID {
                        ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0, context: newValue)
                    }
                }
            }
        )

        return SwiftUI.Toggle(title, isOn: toggleBinding)
    }
    
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, properties, logger in
        var modifiedView = view
        switch Props(properties).style {
        case .checkbox:
            #if os(macOS)
            modifiedView = modifiedView.toggleStyle(CheckboxToggleStyle())
            #else
            // No checkbox style here: apply none, so the platform's default stays.
            break
            #endif
        case .button:
            modifiedView = modifiedView.toggleStyle(ButtonToggleStyle())
        case .switch:
            modifiedView = modifiedView.toggleStyle(SwitchToggleStyle())
        case nil:
            break
        }
        return modifiedView
    }
}
