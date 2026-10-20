/*
 Sample JSON for Section:
 {
   "type": "Section",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "header": "Details", // Optional: String for header, defaults to nil
   },
   "children": [
     { "type": "Text", "properties": { "text": "Item 1" } }
   ], // Required: Array of child views
   // OR data-driven mode (children replaced by template)
   "template": {      // Presence of "template" activates data-driven rendering; "id" required for setElementRows
     "type": "Text",
     "properties": { "text": "$1" }
   }
   //
   // Column reference syntax in template string properties:
   //   $1  — column 0 (first column, 1-based)
   //   $2  — column 1 (second column, 1-based)
   //   $N  — column N-1
   //   $0  — all columns joined with ", "
   //
   // Data is set at runtime via setElementRows(windowUUID:viewID:rows:).
   // states["content"] ([[String]]) holds the current rows.
   //
   // Note: These properties are specific to Section. Baseline View properties (padding, hidden,
   // foregroundStyle, font, background, frame, opacity, cornerRadius, actionID, disabled) and
   // additional View protocol modifiers are inherited and applied via
   // ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Section {
    /// Section's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        var header: String?

        init(_ properties: [String: Any]) {
            header = properties["header"] as? String
        }
    }
}

struct Section: ActionUIElementSpec {
    static var valueType: Any.Type = Void.self
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = ["children": .flat]
}
