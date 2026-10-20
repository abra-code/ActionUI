/*
 Sample JSON for Menu:
 {
   "type": "Menu",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "title": "Options", // Optional: String for title, defaults to empty
   },
   "label": {            // Optional: a single child view to display instead of title for the control
     "type": "Image", "properties": { "systemName": "ellipsis.circle" }
   },
   "children": [
     { "type": "Button", "properties": { "title": "Option 1" } }
   ] // Required: Array of child views (typically Buttons)
   // Note: These properties are specific to Menu. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
   // Children can include Divider and Section to organize menu items:
   //   { "type": "Divider" }                                                          — visual separator line
   //   { "type": "Section", "properties": { "header": "Group" }, "children": [...] }  — named group with header
 }
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Menu {
    /// Menu's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        var title = ""

        init(_ properties: [String: Any]) {
            title = properties["title"] as? String ?? ""
        }
    }
}

struct Menu: ActionUIElementSpec {
    static var valueType: Any.Type = Void.self
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = ["children": .flat]
}
