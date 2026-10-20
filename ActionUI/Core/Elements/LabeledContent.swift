/*
 Sample JSON for LabeledContent:
 {
   "type": "LabeledContent",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "title": "Username"  // Required: String for the label displayed before the content
   },
   "children": [
     { "type": "TextField", "id": 2, "properties": { "prompt": "Enter username" } }
   ]
   // Note: LabeledContent pairs a title label with one or more child views. It renders consistently
   // across all container contexts (Form, VStack, etc.), making labels visible where SwiftUI's built-in
   // view labels (e.g., TextField's title) would otherwise be hidden. Baseline View properties (padding,
   // hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, actionID, disabled) and
   // additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers.
 }
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension LabeledContent {
    /// LabeledContent's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        var title = ""

        init(_ properties: [String: Any]) {
            title = properties["title"] as? String ?? ""
        }
    }
}

struct LabeledContent: ActionUIElementSpec {
    static var valueType: Any.Type = Void.self
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = ["children": .flat]
}
