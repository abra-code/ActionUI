/*
 Sample JSON for GroupBox:
 {
   "type": "GroupBox",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "title": "Settings"  // Optional: String for the group box title; defaults to nil
   },
   "children": [
     { "type": "Text", "properties": { "text": "Content" } }
   ],
   // OR data-driven mode
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
   // Note: These properties are specific to GroupBox. Baseline View properties (padding, hidden,
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

extension GroupBox {
    /// GroupBox's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        var title: String?

        init(_ properties: [String: Any]) {
            title = properties["title"] as? String
        }
    }
}

struct GroupBox: ActionUIElementSpec {
    static var valueType: Any.Type = Void.self
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = ["children": .flat]
}
