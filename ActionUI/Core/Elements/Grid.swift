// Core/Elements/Grid.swift
/*
 Sample JSON for Grid:
 {
   "type": "Grid",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "rows": [             // Required: Array of arrays of ActionUIElementBase objects. Note: Declared as a top-level key in JSON but stored in subviews["rows"] by ActionUIElement.init(from:).
     [
       { "type": "Text", "properties": { "text": "Cell1" } },
       { "type": "Button", "properties": { "title": "Click" } }
     ],
     [
       { "type": "Image", "properties": { "systemName": "star" } }
     ]
   ],
   "properties": {
     "alignment": "center",        // Optional: "topLeading", "top", "topTrailing", "leading", "center", "trailing", "bottomLeading", "bottom", "bottomTrailing"
     "horizontalSpacing": 8.0,    // Optional: Double for horizontal spacing between columns
     "verticalSpacing": 8.0       // Optional: Double for vertical spacing between rows
   }
   // Note: These properties (alignment, horizontalSpacing, verticalSpacing) are specific to Grid. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
   // Performance: Child ActionUIView instances leverage Equatable conformance to optimize rendering, reducing re-renders for unchanged cells in large grids.
 }
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Grid {
    /// Grid's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        enum Alignment: String, Sendable, CaseIterable {
            case topLeading, top, topTrailing, leading, center, trailing, bottomLeading, bottom, bottomTrailing
        }

        /// nil for either spacing: the system's default.
        var horizontalSpacing: Double?
        var verticalSpacing: Double?
        var alignment = Alignment.center

        init(_ properties: [String: Any]) {
            horizontalSpacing = properties.double(forKey: "horizontalSpacing")
            verticalSpacing = properties.double(forKey: "verticalSpacing")
            alignment = (properties["alignment"] as? String).flatMap(Alignment.init(rawValue:)) ?? .center
        }
    }
}

struct Grid: ActionUIElementSpec {
    static var valueType: Any.Type = Void.self
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = ["rows": .rows]
}
