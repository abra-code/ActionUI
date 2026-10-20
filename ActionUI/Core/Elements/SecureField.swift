/*
 Sample JSON for SecureField:
 {
   "type": "SecureField",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "title": "Password",            // Optional: String label for the field, defaults to "" (shown in Form/LabeledContent contexts)
     "text": "secret",               // Optional: String initial value, defaults to ""
     "prompt": "Enter password",     // Optional: String prompt (placeholder) shown inside the field when empty, defaults to nil
     "textContentType": "password",  // Optional: String for content type, must be one of: "password", "newPassword", "oneTimeCode"; defaults to nil, ignored on macOS
     "actionID": "secure.submit"     // Optional: String for action triggered on submit (e.g., Return key)
                                     //   On macOS, actionID is also triggered when the field loses focus (tab away, click elsewhere),
                                     //   matching classic AppKit text field behavior where ending editing commits the value.
   }
   // Note: The SecureField view triggers an action via 'actionID' when the user submits input (e.g., Return key or "Done" on iOS). On macOS, actionID is also triggered on focus loss (tab, click away) to match classic AppKit behavior. Supported values for "textContentType": "password", "newPassword", "oneTimeCode" (ignored on macOS). Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties). On macOS, the default text field style (likely rounded) is used.
 }
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension SecureField {
    /// SecureField's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        /// Only the secure content types; the renderer applies it on iOS.
        enum TextContentType: String, Sendable, CaseIterable {
            case password, newPassword, oneTimeCode
        }

        var title = ""
        var prompt: String?
        /// The initial text.
        var text = ""
        var textContentType: TextContentType?
        var actionID: String?
        var valueChangeActionID: String?

        init(_ properties: [String: Any]) {
            title = properties["title"] as? String ?? ""
            prompt = properties["prompt"] as? String
            text = properties["text"] as? String ?? ""
            textContentType = (properties["textContentType"] as? String).flatMap(TextContentType.init(rawValue:))
            actionID = properties["actionID"] as? String
            valueChangeActionID = properties["valueChangeActionID"] as? String
        }
    }
}

struct SecureField: ActionUIElementSpec {
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil

    // Design decision: Defines valueType as String to reflect secure text input for type-safe string parsing in ActionUIModel
    static var valueType: Any.Type = String.self

    static var initialValue: (ViewModel) -> Any? = { model in
        if let initialValue = model.value as? String {
            return initialValue
        }
        return Props(model.properties).text
    }
}
