/*
 Sample JSON for LazyHGrid (ActionUI):
 {
   "type": "LazyHGrid",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "rows": [
       { "minimum": 100.0 },
       { "flexible": true }
     ], // Array of row definitions (minimum: CGFloat, flexible: Bool)
     "spacing": 10.0,     // Optional: CGFloat for spacing between elements
     "alignment": "center" // Optional: Vertical alignment (e.g., "top", "center", "bottom")
   },
   "children": [
     { "type": "Text", "properties": { "text": "Item 1" } },
     { "type": "Text", "properties": { "text": "Item 2" } }
   ],
   // OR data-driven mode
   "template": {      // Presence of "template" activates data-driven rendering; "id" required for setElementRows
     "type": "Text",
     "properties": { "text": "$1" }
   }
   //
   // Column reference syntax in template string properties:
   //   $1  - column 0 (first column, 1-based)
   //   $N  - column N-1
   //   $0  - all columns joined with ", "
   //
   // Data is set at runtime via setElementRows(windowUUID:viewID:rows:).
   // states["content"] ([[String]]) holds the current rows; each data row becomes
   // one grid cell, flowing into the declared rows.
   //
   // Note: These properties are specific to LazyHGrid. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension LazyHGrid {
    /// LazyHGrid's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        enum Alignment: String, Sendable, CaseIterable {
            case top, center, bottom
        }

        /// One row: a fixed height, or a flexible one.
        enum Track: Sendable, Equatable {
            case fixed(Double)
            case flexible
        }

        var spacing = 0.0
        var alignment = Alignment.center
        /// No usable row definition gives one flexible row. Empty when the only definitions with a
        /// usable value say "flexible": false: the grid then has no rows and shows nothing.
        var rows = [Track.flexible]

        init(_ properties: [String: Any]) {
            spacing = properties.double(forKey: "spacing") ?? 0.0
            alignment = (properties["alignment"] as? String).flatMap(Alignment.init(rawValue:)) ?? .center
            // A definition with a numeric "minimum" is fixed; one with "flexible": true is flexible;
            // anything else is skipped.
            if let definitions = properties["rows"] as? [[String: Any]] {
                let tracks = definitions.compactMap { row -> Track? in
                    if let minimum = row.double(forKey: "minimum") {
                        return .fixed(minimum)
                    } else if let flexible = row["flexible"] as? Bool, flexible {
                        return .flexible
                    }
                    return nil
                }
                // A "flexible": false definition counts as a definition though it gives no row.
                if !tracks.isEmpty || definitions.contains(where: { $0["flexible"] as? Bool != nil }) {
                    rows = tracks
                }
            }
        }
    }
}

struct LazyHGrid: ActionUIElementSpec {
    static var valueType: Any.Type = Void.self
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = ["children": .flat]
}
