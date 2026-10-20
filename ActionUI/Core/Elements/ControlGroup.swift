/*
 Sample JSON for ControlGroup:
 {
   "type": "ControlGroup",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "title": "Options"  // Optional: String for the control group title; defaults to nil
   },
   "children": [
     { "type": "Button", "properties": { "title": "Option 1", "actionID": "option1" } }
   ]
   // Note: These properties are specific to ControlGroup. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
 */

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension ControlGroup {
    /// ControlGroup's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        var title: String?

        init(_ properties: [String: Any]) {
            title = properties["title"] as? String
        }
    }
}

struct ControlGroup: ActionUIElementSpec {
    static var valueType: Any.Type = Void.self
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = ["children": .flat]
}
