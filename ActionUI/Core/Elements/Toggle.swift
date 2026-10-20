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

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

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

struct Toggle: ActionUIElementSpec {
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil
    static var valueType: Any.Type = Bool.self // Value is the toggle's on/off state
    static var initialValue: (ViewModel) -> Any? = { model in
        if let initialValue = model.value as? Bool {
            return initialValue
        }
        return Props(model.properties).isOn ?? false
    }
}
