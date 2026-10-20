/*
 Sample JSON for LazyVGrid (ActionUI):
 {
   "type": "LazyVGrid",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "columns": [
       { "minimum": 100.0 },
       { "flexible": true }
     ], // Array of column definitions (minimum: CGFloat, flexible: Bool)
     "spacing": 10.0,     // Optional: CGFloat for spacing between elements
     "alignment": "center" // Optional: Horizontal alignment (e.g., "leading", "center", "trailing")
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
   // one grid cell, flowing into the declared columns.
   //
   // Note: The columns, spacing, and alignment properties are specific to LazyVGrid. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension LazyVGrid {
    /// LazyVGrid's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        enum Alignment: String, Sendable, CaseIterable {
            case leading, center, trailing
        }

        /// One column: a fixed width, or a flexible one.
        enum Track: Sendable, Equatable {
            case fixed(Double)
            case flexible
        }

        var spacing = 0.0
        var alignment = Alignment.center
        /// No usable column definition gives one flexible column. Empty when the only definitions
        /// with a usable value say "flexible": false: the grid then has no columns and shows nothing.
        var columns = [Track.flexible]

        init(_ properties: [String: Any]) {
            spacing = properties.double(forKey: "spacing") ?? 0.0
            alignment = (properties["alignment"] as? String).flatMap(Alignment.init(rawValue:)) ?? .center
            // A definition with a numeric "minimum" is fixed; one with "flexible": true is flexible;
            // anything else is skipped.
            if let definitions = properties["columns"] as? [[String: Any]] {
                let tracks = definitions.compactMap { column -> Track? in
                    if let minimum = column.double(forKey: "minimum") {
                        return .fixed(minimum)
                    } else if let flexible = column["flexible"] as? Bool, flexible {
                        return .flexible
                    }
                    return nil
                }
                // A "flexible": false definition counts as a definition though it gives no column.
                if !tracks.isEmpty || definitions.contains(where: { $0["flexible"] as? Bool != nil }) {
                    columns = tracks
                }
            }
        }
    }
}

struct LazyVGrid: ActionUIElementSpec {
    static var valueType: Any.Type = Void.self
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = ["children": .flat]
}
