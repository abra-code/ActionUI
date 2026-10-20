/*
 Sample JSON for Toggle:
 {
   "type": "Toggle",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "isOn": true,              // Optional: Boolean initial state, defaults to false
     "title": "Enable Feature", // Optional: String, defaults to "Toggle"
     "style": "switch",        // Optional: "switch" (iOS/macOS/visionOS), "checkbox" (macOS only), "button" (iOS/macOS/visionOS); defaults to "switch"
     "actionID": "toggle.changed", // Optional: String for action triggered on value change
   }
   // In a data-driven template (a List, VStack, HStack, ... with a "template"), the row data is the
   // source of truth:
   //   "isOn": "$1"   a string is read from the row: "true" or "1" is on, "false", "0" or empty is
   //                  off, in any letter case; any other text is off, with one warning.
   //   When "isOn" is exactly one column reference, a user toggle writes "true" or "false" into
   //   that column of that row in the container's states["content"], then fires actionID with
   //   viewID = the container's id, viewPartID = the 0-based row index and context = the new Bool.
   //   Any other "isOn" in a template (a literal, "$0", text around a reference) is display-only.
   //   setElementRows / appendElementRows / clearElementRows change what the toggles show and
   //   fire nothing. Outside a template a string "isOn" is invalid, as before.
   // Note: These properties are specific to Toggle. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

extension Toggle {
    /// Toggle's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        /// "checkbox" exists on macOS only; elsewhere the renderer applies no style for it.
        enum Style: String, Sendable, CaseIterable {
            case `switch`, button, checkbox
        }

        /// The initial state; nil when not given (or not a Bool).
        var isOn: Bool?
        var title = "Toggle"
        var style: Style?
        var actionID: String?

        init(_ properties: [String: Any]) {
            isOn = properties["isOn"] as? Bool
            title = properties["title"] as? String ?? "Toggle"
            style = (properties["style"] as? String).flatMap(Style.init(rawValue:))
            actionID = properties["actionID"] as? String
        }
    }
}

struct Toggle: ActionUIViewConstruction {
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil

    static var valueType: Any.Type = Bool.self // Value is the toggle's on/off state
    
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

    static var initialValue: (ViewModel) -> Any? = { model in
        if let initialValue = model.value as? Bool {
            return initialValue
        }
        return Props(model.properties).isOn ?? false
    }
}
